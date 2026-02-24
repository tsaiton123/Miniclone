import SwiftUI
import Combine
import UIKit

@MainActor
class CanvasViewModel: ObservableObject {
    // Multi-page support
    @Published var pages: [PageData] = [PageData(elements: [])]
    @Published var currentPageIndex: Int = 0
    static let pageGap: CGFloat = 20
    
    // Computed property for all elements with their global vertical offset applied
    var allElementsWithOffsets: [CanvasElementData] {
        var shiftedElements: [CanvasElementData] = []
        for (index, page) in pages.enumerated() {
            let yOffset = CGFloat(index) * (CanvasConstants.a4Height + CanvasViewModel.pageGap)
            let pageElements = page.elements.map { element -> CanvasElementData in
                var newElement = element
                newElement.y += yOffset
                return newElement
            }
            shiftedElements.append(contentsOf: pageElements)
        }
        return shiftedElements
    }

    var selectedElementsWithOffsets: [CanvasElementData] {
        var shiftedElements: [CanvasElementData] = []
        let pageHeight = CanvasConstants.a4Height + CanvasViewModel.pageGap
        for (index, page) in pages.enumerated() {
            let yOffset = CGFloat(index) * pageHeight
            for element in page.elements {
                if selectedElementIds.contains(element.id) {
                    var newElement = element
                    newElement.y += yOffset
                    shiftedElements.append(newElement)
                }
            }
        }
        return shiftedElements
    }

    // Elements for the current page (legacy support/compatibility)
    var elements: [CanvasElementData] {
        get {
            guard currentPageIndex < pages.count else { return [] }
            return pages[currentPageIndex].elements
        }
        set {
            guard currentPageIndex < pages.count else { return }
            pages[currentPageIndex].elements = newValue
        }
    }
    
    @Published var selectedElementIds: Set<UUID> = []
    @Published var scale: CGFloat = 1.0
    @Published var offset: CGSize = .zero
    
    @Published var currentStroke: CanvasElementData?
    @Published var selectionBox: CGRect?
    @Published var editingElementId: UUID?
    @Published var pendingEditedText: String = ""  // Tracks text changes in real-time
    
    // Cache for images to avoid repeated base64 decoding
    @Published var imageCache: [UUID: UIImage] = [:]
    
    // Styling
    @Published var currentStrokeColor: String = "#000000"
    @Published var currentStrokeWidth: CGFloat = 2.0
    @Published var currentBrushType: BrushType = .pen
    @Published var currentEraserWidth: CGFloat = 10.0
    
    // Track when canvas is being touched (for UI collapse behavior)
    @Published var isCanvasTouched: Bool = false
    
    // Global Undo/Redo
    private var undoStack: [[PageData]] = []
    private var redoStack: [[PageData]] = []
    
    // Horizontal constraints and elasticity
    @Published var viewportSize: CGSize = .zero
    private let elasticResistance: CGFloat = 0.3
    private let verticalPadding: CGFloat = 120
    
    private var noteId: UUID
    private var initialPageIndex: Int?
    private var lastOffset: CGSize = .zero
    private var lastScale: CGFloat = 1.0
    private var selectionStartPoint: CGPoint?
    private var cancellables = Set<AnyCancellable>()
    private var hasCenteredInitial = false
    private let saveTrigger = PassthroughSubject<Void, Never>()
    
    // Eraser state tracking
    private var eraserPath: [CGPoint] = []
    @Published var currentEraserPosition: CGPoint? = nil
    private var modifiedImageIds: Set<UUID> = []
    
    // Page management computed properties
    var pageCount: Int { pages.count }
    var canDeletePage: Bool { pages.count > 1 }
    var isFirstPage: Bool { currentPageIndex == 0 }
    var isLastPage: Bool { currentPageIndex >= pages.count - 1 }
    
    var totalCanvasHeight: CGFloat {
        let count = CGFloat(pages.count)
        return count * CanvasConstants.a4Height + (count - 1) * CanvasViewModel.pageGap
    }
    
    init(noteId: UUID, initialPageIndex: Int? = nil) {
        self.noteId = noteId
        self.initialPageIndex = initialPageIndex
        setupDebouncedSave()
        loadCanvas()
        
        // If we have an initial page index, make sure we show it
        if let index = initialPageIndex {
            self.currentPageIndex = min(max(0, index), pages.count - 1)
        }
    }
    
    private func setupDebouncedSave() {
        saveTrigger
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.performSave()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Panning & Zooming
    
    func handleDrag(translation: CGSize) {
        var newX = lastOffset.width + translation.width
        var newY = lastOffset.height + translation.height
        
        // Horizontal Elasticity
        let canvasWidth = CanvasConstants.a4Width * scale
        let minX = viewportSize.width - canvasWidth
        let maxX: CGFloat = 0
        
        if canvasWidth > viewportSize.width {
            if newX > maxX {
                let diff = newX - maxX
                newX = maxX + diff * elasticResistance
            } else if newX < minX {
                let diff = newX - minX
                newX = minX + diff * elasticResistance
            }
        } else {
            let centerX = (viewportSize.width - canvasWidth) / 2
            let limit: CGFloat = 30.0
            if newX > centerX + limit {
                let diff = newX - (centerX + limit)
                newX = (centerX + limit) + diff * elasticResistance
            } else if newX < centerX - limit {
                let diff = newX - (centerX - limit)
                newX = (centerX - limit) + diff * elasticResistance
            }
        }
        
        // Vertical Elasticity
        let canvasHeight = totalCanvasHeight * scale
        let minY = viewportSize.height - canvasHeight - verticalPadding
        let maxY: CGFloat = verticalPadding
        
        if canvasHeight > (viewportSize.height - 2 * verticalPadding) {
            if newY > maxY {
                let diff = newY - maxY
                newY = maxY + diff * elasticResistance
            } else if newY < minY {
                let diff = newY - minY
                newY = minY + diff * elasticResistance
            }
        } else {
            let centerY = (viewportSize.height - canvasHeight) / 2
            let limit: CGFloat = 30.0
            if newY > centerY + limit {
                let diff = newY - (centerY + limit)
                newY = (centerY + limit) + diff * elasticResistance
            } else if newY < centerY - limit {
                let diff = newY - (centerY - limit)
                newY = (centerY - limit) + diff * elasticResistance
            }
        }
        
        offset = CGSize(width: newX, height: newY)
        updateCurrentPageIndex()
    }
    
    func endDrag(translation: CGSize) {
        handleDrag(translation: translation)
        snapToBoundaries(animated: true)
    }
    
    func handleMagnification(value: CGFloat, center: CGPoint) {
        let newScale = lastScale * value
        
        // Calculate offset adjustment to keep the pinch center point stationary
        let canvasPointX = (center.x - lastOffset.width) / lastScale
        let canvasPointY = (center.y - lastOffset.height) / lastScale
        
        scale = newScale
        
        var newOffsetX = center.x - canvasPointX * newScale
        var newOffsetY = center.y - canvasPointY * newScale
        
        // Apply horizontal elasticity during zoom if needed
        let canvasWidth = CanvasConstants.a4Width * newScale
        let minX = viewportSize.width - canvasWidth
        let maxX: CGFloat = 0
        
        if canvasWidth > viewportSize.width {
            if newOffsetX > maxX {
                let diff = newOffsetX - maxX
                newOffsetX = maxX + diff * elasticResistance
            } else if newOffsetX < minX {
                let diff = newOffsetX - minX
                newOffsetX = minX + diff * elasticResistance
            }
        }
        
        // Apply vertical elasticity during zoom if needed
        let canvasHeight = totalCanvasHeight * newScale
        let minY = viewportSize.height - canvasHeight - verticalPadding
        let maxY: CGFloat = verticalPadding
        
        if canvasHeight > (viewportSize.height - 2 * verticalPadding) {
            if newOffsetY > maxY {
                let diff = newOffsetY - maxY
                newOffsetY = maxY + diff * elasticResistance
            } else if newOffsetY < minY {
                let diff = newOffsetY - minY
                newOffsetY = minY + diff * elasticResistance
            }
        }
        
        offset = CGSize(width: newOffsetX, height: newOffsetY)
        updateCurrentPageIndex()
    }
    
    func endMagnification(value: CGFloat, center: CGPoint) {
        handleMagnification(value: value, center: center)
        snapToBoundaries(animated: true)
        saveCanvas()
    }
    
    func snapToBoundaries(animated: Bool) {
        let canvasWidth = CanvasConstants.a4Width * scale
        let canvasHeight = totalCanvasHeight * scale
        
        var finalX = offset.width
        var finalY = offset.height
        
        // Horizontal Snap-back / Centering
        let minX = viewportSize.width - canvasWidth
        let maxX: CGFloat = 0
        
        if canvasWidth > viewportSize.width {
            if finalX > maxX {
                finalX = maxX
            } else if finalX < minX {
                finalX = minX
            }
        } else {
            finalX = (viewportSize.width - canvasWidth) / 2
        }
        
        // Vertical Snap-back / Centering
        let minY = viewportSize.height - canvasHeight - verticalPadding
        let maxY: CGFloat = verticalPadding
        
        if canvasHeight > (viewportSize.height - 2 * verticalPadding) {
            if finalY > maxY {
                finalY = maxY
            } else if finalY < minY {
                finalY = minY
            }
        } else {
            finalY = (viewportSize.height - canvasHeight) / 2
        }
        
        if animated {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                offset = CGSize(width: finalX, height: finalY)
                lastScale = scale
                lastOffset = offset
            }
        } else {
            offset = CGSize(width: finalX, height: finalY)
            lastScale = scale
            lastOffset = offset
        }
        
        updateCurrentPageIndex()
    }
    
    private func updateCurrentPageIndex() {
        let pageHeight = (CanvasConstants.a4Height + CanvasViewModel.pageGap) * scale
        let scrollY = -offset.height
        let index = Int((scrollY + (pageHeight / 3)) / pageHeight) 
        let clampedIndex = min(max(0, index), pages.count - 1)
        
        if currentPageIndex != clampedIndex {
            currentPageIndex = clampedIndex
        }
    }
    
    func zoomIn() {
        scale = min(scale + 0.1, 5.0)
        snapToBoundaries(animated: true)
    }
    
    func zoomOut() {
        scale = max(scale - 0.1, 0.1)
        snapToBoundaries(animated: true)
    }
    
    func centerCanvas(in screenSize: CGSize) {
        // Initial centering logic: center the A4 paper in the available screen space
        // We only do this if we haven't centered yet or if the canvas is empty
        guard screenSize.width > 0 && screenSize.height > 0 else { return }
        viewportSize = screenSize
        
        let initialScale: CGFloat = min(
            (screenSize.width - 40) / CanvasConstants.a4Width,
            (screenSize.height - 40) / CanvasConstants.a4Height,
            1.0
        )
        
        scale = initialScale
        lastScale = initialScale
        
        let offsetX = (screenSize.width - CanvasConstants.a4Width * scale) / 2
        
        // Calculate vertical offset
        let pageHeight = (CanvasConstants.a4Height + CanvasViewModel.pageGap) * scale
        let targetPageIndex = CGFloat(initialPageIndex ?? 0)
        
        // We want to center the target page or at least show it from the top
        var offsetY: CGFloat
        if initialPageIndex != nil {
            // Scroll to the specific page
            offsetY = verticalPadding - (targetPageIndex * pageHeight)
        } else {
            // Standard centering logic
            let totalHeight = totalCanvasHeight * scale
            offsetY = totalHeight > (screenSize.height - 2 * verticalPadding) ? verticalPadding : (screenSize.height - totalHeight) / 2
        }
        
        offset = CGSize(width: offsetX, height: offsetY)
        lastOffset = offset
        hasCenteredInitial = true
        updateCurrentPageIndex()
    }
    
    func updateViewportSize(_ size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }
        let oldSize = viewportSize
        viewportSize = size
        
        // If the size changed significantly (e.g., rotation), re-center or snap
        if abs(oldSize.width - size.width) > 1 || abs(oldSize.height - size.height) > 1 {
            if !hasCenteredInitial {
                centerCanvas(in: size)
            } else {
                snapToBoundaries(animated: true)
            }
        }
    }
    
    func clearCanvas() {
        saveState()
        elements.removeAll()
        saveCanvas()
    }
    
    // MARK: - Selection
    
    func startSelection(at point: CGPoint) {
        let canvasPoint = toCanvasCoordinates(point)
        selectionStartPoint = canvasPoint
        selectionBox = CGRect(origin: canvasPoint, size: .zero)
        clearSelection()
    }
    
    func updateSelection(to point: CGPoint) {
        guard let start = selectionStartPoint else { return }
        let current = toCanvasCoordinates(point)
        
        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)
        
        selectionBox = CGRect(x: x, y: y, width: width, height: height)
        
        // Update selected elements in real-time
        updateSelectedElements()
    }
    
    func endSelection() {
        selectionBox = nil
        selectionStartPoint = nil
    }
    
    var selectedElementsBounds: CGRect? {
        guard !selectedElementIds.isEmpty else { return nil }
        
        // If we are currently dragging a selection box, use that
        if let box = selectionBox {
            return box
        }
        
        // Otherwise, calculate bounds of selected elements using their global offsets
        var minX: CGFloat = .infinity
        var minY: CGFloat = .infinity
        var maxX: CGFloat = -.infinity
        var maxY: CGFloat = -.infinity
        
        var hasElements = false
        let pageHeight = CanvasConstants.a4Height + CanvasViewModel.pageGap
        
        for (index, page) in pages.enumerated() {
            let yOffset = CGFloat(index) * pageHeight
            for element in page.elements {
                if selectedElementIds.contains(element.id) {
                    hasElements = true
                    minX = min(minX, element.x)
                    minY = min(minY, element.y + yOffset)
                    maxX = max(maxX, element.x + element.width)
                    maxY = max(maxY, element.y + yOffset + element.height)
                }
            }
        }
        
        guard hasElements else { return nil }
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    private func updateSelectedElements() {
        guard let box = selectionBox else { return }
        
        let elementsToSearch = allElementsWithOffsets
        
        let selected = elementsToSearch.filter { element in
            let elementRect = CGRect(x: element.x, y: element.y, width: element.width, height: element.height)
            
            // 1. Fast Bounding Box Check
            guard box.intersects(elementRect) else { return false }
            
            // 2. Precise Check for Strokes
            if case .stroke(let data) = element.data {
                return strokeIntersectsRect(stroke: data, elementOrigin: CGPoint(x: element.x, y: element.y), rect: box)
            }
            
            // Default to bounding box for other types
            return true
        }
        
        selectedElementIds = Set(selected.map { $0.id })
    }
    
    private func strokeIntersectsRect(stroke: StrokeData, elementOrigin: CGPoint, rect: CGRect) -> Bool {
        guard !stroke.points.isEmpty else { return false }
        
        // Check if any point is inside the rect (fastest precise check)
        for point in stroke.points {
            let absPoint = CGPoint(x: elementOrigin.x + point.x, y: elementOrigin.y + point.y)
            if rect.contains(absPoint) {
                return true
            }
        }
        
        // Check if any line segment intersects the rect edges
        // This handles cases where the stroke crosses through the rect without having a vertex inside
        guard stroke.points.count > 1 else { return false }
        
        for i in 0..<stroke.points.count - 1 {
            let p1 = stroke.points[i]
            let p2 = stroke.points[i+1]
            
            let absP1 = CGPoint(x: elementOrigin.x + p1.x, y: elementOrigin.y + p1.y)
            let absP2 = CGPoint(x: elementOrigin.x + p2.x, y: elementOrigin.y + p2.y)
            
            if lineSegmentIntersectsRect(p1: absP1, p2: absP2, rect: rect) {
                return true
            }
        }
        
        return false
    }
    
    private func lineSegmentIntersectsRect(p1: CGPoint, p2: CGPoint, rect: CGRect) -> Bool {
        // Cohen-Sutherland algorithm or simple edge intersection
        // Since we already checked if points are inside, we just need to check edge intersections
        
        let tl = CGPoint(x: rect.minX, y: rect.minY)
        let tr = CGPoint(x: rect.maxX, y: rect.minY)
        let bl = CGPoint(x: rect.minX, y: rect.maxY)
        let br = CGPoint(x: rect.maxX, y: rect.maxY)
        
        let edges = [
            (tl, tr), // Top
            (tr, br), // Right
            (br, bl), // Bottom
            (bl, tl)  // Left
        ]
        
        for (e1, e2) in edges {
            if lineSegmentsIntersect(p1: p1, p2: p2, p3: e1, p4: e2) {
                return true
            }
        }
        
        return false
    }
    
    // Helper: Check if line segment (p1,p2) intersects (p3,p4)
    private func lineSegmentsIntersect(p1: CGPoint, p2: CGPoint, p3: CGPoint, p4: CGPoint) -> Bool {
        let d1 = direction(p3, p4, p1)
        let d2 = direction(p3, p4, p2)
        let d3 = direction(p1, p2, p3)
        let d4 = direction(p1, p2, p4)
        
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
           ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }
        
        if d1 == 0 && onSegment(p3, p4, p1) { return true }
        if d2 == 0 && onSegment(p3, p4, p2) { return true }
        if d3 == 0 && onSegment(p1, p2, p3) { return true }
        if d4 == 0 && onSegment(p1, p2, p4) { return true }
        
        return false
    }
    
    private func direction(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> Double {
        return Double((p3.x - p1.x) * (p2.y - p1.y) - (p2.x - p1.x) * (p3.y - p1.y))
    }
    
    private func onSegment(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> Bool {
        return min(p1.x, p2.x) <= p3.x && p3.x <= max(p1.x, p2.x) &&
               min(p1.y, p2.y) <= p3.y && p3.y <= max(p1.y, p2.y)
    }
    
    func isPointInSelectedElement(_ point: CGPoint) -> Bool {
        let canvasPoint = toCanvasCoordinates(point)
        let elementsToSearch = allElementsWithOffsets
        for id in selectedElementIds {
            if let element = elementsToSearch.first(where: { $0.id == id }) {
                let rect = CGRect(x: element.x, y: element.y, width: element.width, height: element.height)
                if rect.contains(canvasPoint) {
                    return true
                }
            }
        }
        return false
    }
    
    func findElement(at point: CGPoint) -> UUID? {
        let canvasPoint = toCanvasCoordinates(point)
        let elementsToSearch = allElementsWithOffsets
        // Search in reverse order (topmost first)
        for element in elementsToSearch.reversed() {
            let rect = CGRect(x: element.x, y: element.y, width: element.width, height: element.height)
            if rect.contains(canvasPoint) {
                return element.id
            }
        }
        return nil
    }
    
    // MARK: - Moving Selection
    
    private var initialElementPositions: [UUID: CGPoint] = [:]
    
    func startMovingSelection() {
        saveState()
        initialElementPositions.removeAll()
        let elementsToSearch = allElementsWithOffsets
        for id in selectedElementIds {
            if let element = elementsToSearch.first(where: { $0.id == id }) {
                initialElementPositions[id] = CGPoint(x: element.x, y: element.y)
            }
        }
    }
    
    func moveSelection(translation: CGSize) {
        let deltaX = translation.width / scale
        let deltaY = translation.height / scale
        
        for (id, initialPos) in initialElementPositions {
            // We need to find which page this element belongs to and update it there
            for pageIndex in 0..<pages.count {
                if let elementIndex = pages[pageIndex].elements.firstIndex(where: { $0.id == id }) {
                    let yOffset = CGFloat(pageIndex) * (CanvasConstants.a4Height + CanvasViewModel.pageGap)
                    let newX = initialPos.x + deltaX
                    let newY = initialPos.y + deltaY - yOffset // Convert back to local
                    
                    pages[pageIndex].elements[elementIndex].x = newX
                    pages[pageIndex].elements[elementIndex].y = newY
                    break
                }
            }
        }
    }
    
    func endMovingSelection() {
        redistributeSelectedElements()
        initialElementPositions.removeAll()
        saveCanvas()
    }
    
    /// Redistribute selected elements to the correct pages based on their global Y position
    private func redistributeSelectedElements() {
        let pageHeight = CanvasConstants.a4Height + CanvasViewModel.pageGap
        
        for id in selectedElementIds {
            // Find current page and index
            var currentSourcePageIndex: Int?
            var elementToMove: CanvasElementData?
            
            for pageIndex in 0..<pages.count {
                if let index = pages[pageIndex].elements.firstIndex(where: { $0.id == id }) {
                    currentSourcePageIndex = pageIndex
                    elementToMove = pages[pageIndex].elements[index]
                    pages[pageIndex].elements.remove(at: index)
                    break
                }
            }
            
            guard var element = elementToMove, let sourceIndex = currentSourcePageIndex else { continue }
            
            // Calculate global Y
            let sourceYOffset = CGFloat(sourceIndex) * pageHeight
            let globalY = element.y + sourceYOffset
            
            // Find target page
            let targetPageIndex = Int(max(0, globalY) / pageHeight)
            let clampedTargetIndex = min(max(0, targetPageIndex), pages.count - 1)
            
            // Normalize for target page
            let targetYOffset = CGFloat(clampedTargetIndex) * pageHeight
            element.y = globalY - targetYOffset
            
            // Add to target page
            pages[clampedTargetIndex].elements.append(element)
        }
    }
    
    // MARK: - Drawing
    
    func startStroke(at point: CGPoint) {
        let canvasPoint = toCanvasCoordinates(point)
        
        // Find which page this point belongs to
        let pageHeight = CanvasConstants.a4Height + CanvasViewModel.pageGap
        let pageIndex = Int(max(0, canvasPoint.y) / pageHeight)
        
        // Ensure page index is valid (clamped to existing pages or allows temporary drawing on "new" space?)
        // For now, let's clamp to existing pages.
        let clampedPageIndex = min(max(0, pageIndex), pages.count - 1)
        
        let yOffset = CGFloat(clampedPageIndex) * pageHeight
        let localPoint = CGPoint(x: canvasPoint.x, y: canvasPoint.y - yOffset)
        
        // Clamp local point to A4 boundaries
        let clampedLocalPoint = CGPoint(
            x: max(0, min(localPoint.x, CanvasConstants.a4Width)),
            y: max(0, min(localPoint.y, CanvasConstants.a4Height))
        )
        
        let strokeData = StrokeData(points: [StrokeData.Point(x: clampedLocalPoint.x, y: clampedLocalPoint.y)], color: currentStrokeColor, width: currentStrokeWidth, brushType: currentBrushType)
        
        currentStroke = CanvasElementData(
            id: UUID(),
            type: .stroke,
            x: 0, y: 0,
            width: 0, height: 0,
            zIndex: 1,
            data: .stroke(strokeData)
        )
        
        // Remember which page we started drawing on
        currentPageIndex = clampedPageIndex
    }
    
    func continueStroke(at point: CGPoint) {
        guard var stroke = currentStroke, case .stroke(var data) = stroke.data else {
            startStroke(at: point) // Safety fallback
            return
        }
        
        let canvasPoint = toCanvasCoordinates(point)
        let pageHeight = CanvasConstants.a4Height + CanvasViewModel.pageGap
        let yOffset = CGFloat(currentPageIndex) * pageHeight
        
        // Map global canvas point to the page we started on
        let localX = canvasPoint.x
        let localY = canvasPoint.y - yOffset
        
        // Clamp to A4 boundaries of that page
        let clampedLocalX = max(0, min(localX, CanvasConstants.a4Width))
        let clampedLocalY = max(0, min(localY, CanvasConstants.a4Height))
        
        data.points.append(StrokeData.Point(x: clampedLocalX, y: clampedLocalY))
        stroke.data = .stroke(data)
        currentStroke = stroke
    }
    
    /// Start erasing - initializes the eraser path
    func startErasing(at point: CGPoint) {
        saveState()
        let canvasPoint = toCanvasCoordinates(point)
        
        // Sync currentPageIndex based on where erasing starts
        let pageHeight = CanvasConstants.a4Height + CanvasViewModel.pageGap
        let pageIndex = Int(max(0, canvasPoint.y) / pageHeight)
        currentPageIndex = min(max(0, pageIndex), pages.count - 1)
        
        eraserPath = [canvasPoint]
        currentEraserPosition = canvasPoint
        // Immediately process the first point
        eraseStrokesAtPoint(canvasPoint)
    }
    
    /// Continue erasing - adds points to path and erases intersecting strokes
    func continueErasing(at point: CGPoint) {
        let canvasPoint = toCanvasCoordinates(point)
        eraserPath.append(canvasPoint)
        currentEraserPosition = canvasPoint
        eraseStrokesAtPoint(canvasPoint)
    }
    
    /// End erasing - cleans up and saves
    func endErasing() {
        eraserPath.removeAll()
        currentEraserPosition = nil
        
        // Persist modified images
        if !modifiedImageIds.isEmpty {
            for id in modifiedImageIds {
               // Find which page this element belongs to
               for pageIndex in 0..<pages.count {
                   if let index = pages[pageIndex].elements.firstIndex(where: { $0.id == id }),
                      let cachedImage = imageCache[id],
                      let pngData = cachedImage.pngData() {
                       
                       let base64 = pngData.base64EncodedString()
                       var element = pages[pageIndex].elements[index]
                       
                       if case .bitmapInk(var data) = element.data {
                           data.src = base64
                           element.data = .bitmapInk(data)
                       } else if case .image(var data) = element.data {
                           data.src = base64
                           element.data = .image(data)
                       }
                       
                       pages[pageIndex].elements[index] = element
                       break
                   }
               }
            }
            modifiedImageIds.removeAll()
        }
        
        saveCanvas()
    }
    
    /// Erase stroke segments or whole elements at a specific point
    private func eraseStrokesAtPoint(_ point: CGPoint) {
        let pageHeight = CanvasConstants.a4Height + CanvasViewModel.pageGap
        
        // Check all pages instead of just current page to be robust
        for pageIndex in 0..<pages.count {
            var elementsToRemove: [UUID] = []
            var elementsToAdd: [CanvasElementData] = []
            let yOffset = CGFloat(pageIndex) * pageHeight
            
            var hasChanges = false
            
            for element in pages[pageIndex].elements {
                // Adjust element for global checks
                let elementRect = CGRect(x: element.x, y: element.y + yOffset, width: element.width, height: element.height)
                
                // Fast check: Eraser must be near bounding box
                let expandedRect = elementRect.insetBy(dx: -currentEraserWidth, dy: -currentEraserWidth)
                guard expandedRect.contains(point) else { continue }
                
                switch element.data {
                case .stroke(let strokeData):
                    // Check if any point of this stroke is within eraser radius
                    let hasIntersection = strokeData.points.contains { strokePoint in
                        let absolutePoint = CGPoint(
                            x: elementRect.minX + strokePoint.x,
                            y: elementRect.minY + strokePoint.y
                        )
                        return distance(from: absolutePoint, to: point) <= currentEraserWidth
                    }
                    
                    guard hasIntersection else { continue }
                    
                    // Split the stroke, removing erased segments
                    var globalElement = element
                    globalElement.y += yOffset
                    let fragments = splitStroke(element: globalElement, strokeData: strokeData, eraserPoint: point)
                    
                    if fragments.isEmpty {
                        elementsToRemove.append(element.id)
                        hasChanges = true
                    } else if fragments.count == 1 && fragments[0].id == element.id {
                        continue
                    } else {
                        elementsToRemove.append(element.id)
                        let localFragments = fragments.map { fragment -> CanvasElementData in
                            var localFrag = fragment
                            localFrag.y -= yOffset
                            return localFrag
                        }
                        elementsToAdd.append(contentsOf: localFragments)
                        hasChanges = true
                    }
                    
                case .bitmapInk, .image:
                    guard let image = imageCache[element.id] else { continue }
                    
                    let renderer = UIGraphicsImageRenderer(size: elementRect.size)
                    let newImage = renderer.image { context in
                        image.draw(in: CGRect(origin: .zero, size: elementRect.size))
                        
                        let cgContext = context.cgContext
                        cgContext.setBlendMode(.clear)
                        cgContext.setFillColor(UIColor.clear.cgColor)
                        
                        let relativePoint = CGPoint(x: point.x - elementRect.minX, y: point.y - elementRect.minY)
                        let eraserRect = CGRect(
                            x: relativePoint.x - currentEraserWidth,
                            y: relativePoint.y - currentEraserWidth,
                            width: currentEraserWidth * 2,
                            height: currentEraserWidth * 2
                        )
                        
                        cgContext.fillEllipse(in: eraserRect)
                    }
                    
                    imageCache[element.id] = newImage
                    modifiedImageIds.insert(element.id)
                    hasChanges = true
                    
                default:
                    continue
                }
            }
            
            if hasChanges {
                if !elementsToRemove.isEmpty || !elementsToAdd.isEmpty {
                    pages[pageIndex].elements.removeAll { elementsToRemove.contains($0.id) }
                    pages[pageIndex].elements.append(contentsOf: elementsToAdd)
                }
            }
        }
    }
    
    /// Split a stroke into fragments, removing points within eraser radius
    private func splitStroke(
        element: CanvasElementData,
        strokeData: StrokeData,
        eraserPoint: CGPoint
    ) -> [CanvasElementData] {
        var fragments: [[StrokeData.Point]] = []
        var currentFragment: [StrokeData.Point] = []
        
        for strokePoint in strokeData.points {
            let absolutePoint = CGPoint(
                x: element.x + strokePoint.x,
                y: element.y + strokePoint.y
            )
            
            if distance(from: absolutePoint, to: eraserPoint) <= currentEraserWidth {
                // This point is erased
                if !currentFragment.isEmpty {
                    fragments.append(currentFragment)
                    currentFragment = []
                }
            } else {
                // Keep absolute coordinates for now, we'll normalize later
                currentFragment.append(StrokeData.Point(x: absolutePoint.x, y: absolutePoint.y))
            }
        }
        
        // Don't forget the last fragment
        if !currentFragment.isEmpty {
            fragments.append(currentFragment)
        }
        
        // Convert fragments to CanvasElementData
        return fragments.compactMap { fragmentPoints in
            guard fragmentPoints.count >= 2 else { return nil }
            
            // Calculate bounding box for this fragment
            let xs = fragmentPoints.map { $0.x }
            let ys = fragmentPoints.map { $0.y }
            
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else {
                return nil
            }
            
            let width = max(maxX - minX, strokeData.width)
            let height = max(maxY - minY, strokeData.width)
            
            // Normalize points relative to new bounding box
            let normalizedPoints = fragmentPoints.map {
                StrokeData.Point(x: $0.x - minX, y: $0.y - minY)
            }
            
            let newStrokeData = StrokeData(
                points: normalizedPoints,
                color: strokeData.color,
                width: strokeData.width,
                brushType: strokeData.brushType
            )
            
            return CanvasElementData(
                id: UUID(),
                type: .stroke,
                x: minX,
                y: minY,
                width: width,
                height: height,
                zIndex: element.zIndex,
                data: .stroke(newStrokeData)
            )
        }
    }
    
    /// Calculate distance between two points
    private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }
    
    func endStroke() {
        guard let stroke = currentStroke, case .stroke(let data) = stroke.data, !data.points.isEmpty else {
            currentStroke = nil
            return
        }
        
        // Calculate bounding box
        let xs = data.points.map { $0.x }
        let ys = data.points.map { $0.y }
        
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else {
            currentStroke = nil
            return
        }
        
        // Ensure minimum dimensions to account for stroke width
        // This prevents straight horizontal/vertical lines from having 0 width/height
        let width = max(maxX - minX, data.width)
        let height = max(maxY - minY, data.width)
        
        // Normalize points relative to bounding box
        let normalizedPoints = data.points.map { StrokeData.Point(x: $0.x - minX, y: $0.y - minY) }
        let newStrokeData = StrokeData(points: normalizedPoints, color: data.color, width: data.width, brushType: data.brushType)
        
        // Create final element
        let newElement = CanvasElementData(
            id: UUID(),
            type: .stroke,
            x: minX,
            y: minY,
            width: width,
            height: height,
            zIndex: elements.count,
            data: .stroke(newStrokeData)
        )
        
        saveState()
        elements.append(newElement)
        currentStroke = nil
        saveCanvas()
    }
    
    private func toCanvasCoordinates(_ point: CGPoint) -> CGPoint {
        return CGPoint(
            x: (point.x - offset.width) / scale,
            y: (point.y - offset.height) / scale
        )
    }
    
    // MARK: - Undo/Redo
    
    func saveState() {
        undoStack.append(pages)
        redoStack.removeAll()
        
        // Limit stack size
        if undoStack.count > 20 {
            undoStack.removeFirst()
        }
    }
    
    func undo() {
        guard let previousState = undoStack.popLast() else { return }
        redoStack.append(pages)
        pages = previousState
        saveCanvas()
    }
    
    func redo() {
        guard let nextState = redoStack.popLast() else { return }
        undoStack.append(pages)
        pages = nextState
        saveCanvas()
    }
    
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    
    // MARK: - Page Management
    
    func addPage(after index: Int? = nil) {
        let insertIndex = (index ?? currentPageIndex) + 1
        let newPage = PageData(elements: [])
        pages.insert(newPage, at: min(insertIndex, pages.count))
        currentPageIndex = min(insertIndex, pages.count - 1)
        clearSelection()
        undoStack.removeAll()
        redoStack.removeAll()
        saveCanvas()
    }
    
    func deletePage(at index: Int) {
        guard canDeletePage, pages.indices.contains(index) else { return }
        pages.remove(at: index)
        // Adjust current page index if needed
        if currentPageIndex >= pages.count {
            currentPageIndex = pages.count - 1
        }
        clearSelection()
        undoStack.removeAll()
        redoStack.removeAll()
        saveCanvas()
    }
    
    func goToPage(_ index: Int) {
        guard pages.indices.contains(index), index != currentPageIndex else { return }
        clearSelection()
        undoStack.removeAll()
        redoStack.removeAll()
        currentPageIndex = index
        Task {
            await preloadImages()
        }
    }
    
    func nextPage() {
        if currentPageIndex < pages.count - 1 {
            goToPage(currentPageIndex + 1)
        }
    }
    
    func previousPage() {
        if currentPageIndex > 0 {
            goToPage(currentPageIndex - 1)
        }
    }

    func loadCanvas() {
        do {
            let data = try StorageManager.shared.loadCanvas(id: noteId)
            self.pages = data.pages.isEmpty ? [PageData(elements: [])] : data.pages
            self.currentPageIndex = min(data.currentPageIndex, pages.count - 1)
            Task {
                await preloadImages()
            }
            sanitizeElements()
        } catch {
            print("Error loading canvas: \(error)")
            self.pages = [PageData(elements: [])]
            self.currentPageIndex = 0
        }
    }
    
    private func preloadImages() async {
        let currentElements = elements
        let idsAndData = currentElements.compactMap { element -> (UUID, String)? in
            if case .image(let data) = element.data {
                return (element.id, data.src)
            } else if case .bitmapInk(let data) = element.data {
                return (element.id, data.src)
            }
            return nil
        }
        
        for (id, src) in idsAndData {
            // Perform decoding on a background thread
            if let data = Data(base64Encoded: src),
               let uiImage = UIImage(data: data) {
                // Update the cache on the main thread
                await MainActor.run {
                    self.imageCache[id] = uiImage
                }
            }
        }
    }
    
    private func sanitizeElements() {
        var hasChanges = false
        for i in 0..<elements.count {
            var element = elements[i]
            if case .stroke(let data) = element.data, !data.points.isEmpty {
                // Check if it looks like a zombie (x=0, y=0, but points are far)
                // Or if width/height are 0 but points span a larger area
                
                let xs = data.points.map { $0.x }
                let ys = data.points.map { $0.y }
                
                guard let minX = xs.min(), let maxX = xs.max(),
                      let minY = ys.min(), let maxY = ys.max() else { continue }
                
                let width = maxX - minX
                let height = maxY - minY
                
                // If element is at 0,0 and points are offset, OR dimensions don't match
                // We re-normalize to be safe if the discrepancy is significant
                let isZombie = (element.x == 0 && element.y == 0 && (minX > 1 || minY > 1))
                let isDimensionMismatch = (element.width == 0 && width > 1) || (element.height == 0 && height > 1)
                
                if isZombie || isDimensionMismatch {
                    print("Fixing zombie element: \(element.id)")
                    
                    // Normalize points relative to new bounding box
                    // If it was a zombie, points were absolute, so we subtract minX/minY
                    // If it was just dimension mismatch but x/y were correct?
                    // Let's assume points are absolute if x=0,y=0.
                    // If x!=0, points might be relative?
                    // The safest bet for "zombie" (created before fix) is that points are absolute.
                    
                    let normalizedPoints = data.points.map { StrokeData.Point(x: $0.x - minX, y: $0.y - minY) }
                    let newStrokeData = StrokeData(points: normalizedPoints, color: data.color, width: data.width, brushType: data.brushType)
                    
                    element.x = minX
                    element.y = minY
                    element.width = width
                    element.height = height
                    element.data = .stroke(newStrokeData)
                    
                    elements[i] = element
                    hasChanges = true
                }
            }
        }
        
        if hasChanges {
            saveCanvas()
        }
    }
    
    func saveCanvas() {
        saveTrigger.send()
    }
    
    private func performSave() {
        let data = CanvasData(pages: pages, currentPageIndex: currentPageIndex)
        do {
            try StorageManager.shared.saveCanvas(id: noteId, data: data)
            print("Canvas saved successfully (\(pages.count) pages)")
        } catch {
            print("Error saving canvas: \(error)")
        }
    }
    
    func addElement(_ element: CanvasElementData) {
        saveState()
        
        var elementToAdd = element
        
        // Determine which page to add the element to based on its y coordinate
        let pageHeight = CanvasConstants.a4Height + CanvasViewModel.pageGap
        let pageIndex = Int(max(0, elementToAdd.y) / pageHeight)
        let clampedPageIndex = min(max(0, pageIndex), pages.count - 1)
        
        // Convert global coordinate to local coordinate for that page
        let yOffset = CGFloat(clampedPageIndex) * pageHeight
        elementToAdd.y -= yOffset
        
        // Dynamic caching for new images
        if case .image(let data) = elementToAdd.data {
            if let uiImage = UIImage(data: Data(base64Encoded: data.src) ?? Data()) {
                imageCache[elementToAdd.id] = uiImage
            }
        } else if case .bitmapInk(let data) = elementToAdd.data {
             if let uiImage = UIImage(data: Data(base64Encoded: data.src) ?? Data()) {
                imageCache[elementToAdd.id] = uiImage
            }
        }
        
        pages[clampedPageIndex].elements.append(elementToAdd)
        saveCanvas()
    }
    
    func addGraph(expression: String, xMin: Double? = nil, xMax: Double? = nil) {
        let graphData = GraphData(
            expression: expression,
            xMin: xMin ?? -10,
            xMax: xMax ?? 10,
            yMin: nil, // Auto-scale
            yMax: nil,
            color: "#34C759" // Green
        )
        
        let width: CGFloat = 300
        let height: CGFloat = 200
        
        // Calculate global centering if on a later page
        let pageHeight = CanvasConstants.a4Height + CanvasViewModel.pageGap
        let globalYOffset = CGFloat(currentPageIndex) * pageHeight
        
        let newElement = CanvasElementData(
            id: UUID(),
            type: .graph,
            x: (CanvasConstants.a4Width - width) / 2,
            y: globalYOffset + (CanvasConstants.a4Height - height) / 2,
            width: width,
            height: height,
            zIndex: elements.count,
            data: .graph(graphData)
        )
        
        addElement(newElement)
    }
    
    func addText(_ text: String, at point: CGPoint = CGPoint(x: 100, y: 100)) {
        // Calculate size - reduced to 50% of original default
        let fontSize: CGFloat = 14  // Reduced from 20
        let font = UIFont(name: "Caveat-Regular", size: fontSize) ?? .systemFont(ofSize: fontSize)
        let maxConstraint = CGSize(width: 250, height: CGFloat.greatestFiniteMagnitude)  // Reduced from 500
        let boundingRect = text.boundingRect(
            with: maxConstraint,
            options: .usesLineFragmentOrigin,
            attributes: [.font: font],
            context: nil
        )
        
        let width = max(boundingRect.width + 20, 50)   // Reduced from +40, min 100
        let height = max(boundingRect.height + 20, 25)  // Reduced from +40, min 50
        
        // Use position directly without boundary clamping
        let newElement = CanvasElementData(
            id: UUID(),
            type: .text,
            x: point.x,
            y: point.y,
            width: width,
            height: height,
            zIndex: elements.count,
            data: .text(TextData(text: text, fontSize: fontSize, fontFamily: "Caveat", color: "#000000"))
        )
        
        addElement(newElement)
    }
    
    
    func updateElement(_ element: CanvasElementData) {
        if let index = elements.firstIndex(where: { $0.id == element.id }) {
            saveState()
            elements[index] = element
            saveCanvas()
        }
    }
    
    func updateElementText(id: UUID, text: String) {
        if let index = elements.firstIndex(where: { $0.id == id }) {
            saveState()
            var element = elements[index]
            if case .text(let textData) = element.data {
                var newTextData = textData
                newTextData.text = text
                element.data = .text(newTextData)
                elements[index] = element
                saveCanvas()
            }
        }
    }
    
    func removeElement(id: UUID) {
        saveState()
        for i in 0..<pages.count {
            pages[i].elements.removeAll(where: { $0.id == id })
        }
        saveCanvas()
    }
    
    func deleteSelection() {
        guard !selectedElementIds.isEmpty else { return }
        saveState()
        for i in 0..<pages.count {
            pages[i].elements.removeAll(where: { selectedElementIds.contains($0.id) })
        }
        selectedElementIds.removeAll()
        saveCanvas()
    }
    
    func eraseElement(at point: CGPoint) {
        if let id = findElement(at: point) {
            removeElement(id: id)
        }
    }
    
    func selectElement(id: UUID) {
        selectedElementIds = [id]
    }
    
    func clearSelection() {
        // Save any pending text edits before clearing
        if let editingId = editingElementId, !pendingEditedText.isEmpty {
            updateElementText(id: editingId, text: pendingEditedText)
            pendingEditedText = ""
        }
        selectedElementIds.removeAll()
        editingElementId = nil  // Exit edit mode when selection is cleared
    }
    
    
    func mergeSelection(image: UIImage, bounds: CGRect) {
        guard !selectedElementIds.isEmpty else { return }
        
        saveState()
        
        // Remove original elements from all pages
        for i in 0..<pages.count {
            pages[i].elements.removeAll(where: { selectedElementIds.contains($0.id) })
        }
        
        let width = bounds.width
        let height = bounds.height
        
        // Use position directly without boundary clamping
        // Create new merged element
        let newElement = CanvasElementData(
            id: UUID(),
            type: .image,
            x: bounds.minX,
            y: bounds.minY,
            width: width,
            height: height,
            zIndex: elements.count,
            data: .image(ImageData(src: image.pngData()?.base64EncodedString() ?? "", originalWidth: image.size.width, originalHeight: image.size.height))
        )
        
        addElement(newElement)
        
        // Select the new element
        selectedElementIds = [newElement.id]
        
        saveCanvas()
    }
    
    func performInkjetPrinting(image: UIImage, bounds: CGRect) {
        guard !selectedElementIds.isEmpty else { return }
        saveState()
        
        // Capture original IDs to delete later
        let originalIds = selectedElementIds
        
        // Run Inkjet algorithm
        let inkElements = InkjetService.process(image: image)
        
        // Add new ink elements
        for (inkData, rect) in inkElements {
            // Include bounds offset
            let newX = bounds.minX + rect.minX
            let newY = bounds.minY + rect.minY
            
            let newElement = CanvasElementData(
                id: UUID(),
                type: .bitmapInk,
                x: newX,
                y: newY,
                width: rect.width,
                height: rect.height,
                zIndex: elements.count,
                data: .bitmapInk(inkData)
            )
            
            // Cache the image
            if let data = Data(base64Encoded: inkData.src), let uiImage = UIImage(data: data) {
                 imageCache[newElement.id] = uiImage
            }
            addElement(newElement)
        }
        
        // Remove original elements (REPLACE behavior)
        for i in 0..<pages.count {
            pages[i].elements.removeAll(where: { originalIds.contains($0.id) })
        }
        
        // Clear selection to show the result clearly
        clearSelection()
        saveCanvas()
    }
    
    func cropSelection(bounds: CGRect) {
        guard selectedElementIds.count == 1,
              let id = selectedElementIds.first,
              let index = elements.firstIndex(where: { $0.id == id }) else { return }
        
        let element = elements[index]
        
        // Only support Image and BitmapInk for now
        var originalImage: UIImage?
        var originalWidth: CGFloat = 0
        var originalHeight: CGFloat = 0
        
        if case .image(let data) = element.data {
            originalImage = imageCache[id] ?? UIImage(data: Data(base64Encoded: data.src) ?? Data())
            originalWidth = data.originalWidth
            originalHeight = data.originalHeight
        } else if case .bitmapInk(let data) = element.data {
             originalImage = imageCache[id] ?? UIImage(data: Data(base64Encoded: data.src) ?? Data())
             originalWidth = data.originalWidth
             originalHeight = data.originalHeight
        } else {
            return
        }
        
        guard let image = originalImage, let cgImage = image.cgImage else { return }
        
        // 1. Calculate Crop Rect relative to the Element's current frame
        // bounds is the new crop box in Canvas Coordinates
        // element.x/y is the current TopLeft in Canvas Coordinates
        
        let relX = bounds.minX - element.x
        let relY = bounds.minY - element.y
        let relWidth = bounds.width
        let relHeight = bounds.height
        
        // 2. Scale relative rect to actual Image Pixel Mapping
        // The element might be scaled on canvas vs its original pixel size
        let scaleX = originalWidth / element.width
        let scaleY = originalHeight / element.height
        
        let cropPixelRect = CGRect(
            x: relX * scaleX,
            y: relY * scaleY,
            width: relWidth * scaleX,
            height: relHeight * scaleY
        )
        
        // 3. Perform Crop
        guard let croppedCGImage = cgImage.cropping(to: cropPixelRect) else { return }
        let croppedImage = UIImage(cgImage: croppedCGImage)
        
        saveState()
        
        // 4. Update Element
        var newElement = element
        newElement.x = bounds.minX
        newElement.y = bounds.minY
        newElement.width = bounds.width
        newElement.height = bounds.height
        
        let base64 = croppedImage.pngData()?.base64EncodedString() ?? ""
        
        if case .image = element.data {
            newElement.data = .image(ImageData(src: base64, originalWidth: CGFloat(croppedCGImage.width), originalHeight: CGFloat(croppedCGImage.height)))
        } else if case .bitmapInk = element.data {
            newElement.data = .bitmapInk(BitmapInkData(src: base64, originalWidth: CGFloat(croppedCGImage.width), originalHeight: CGFloat(croppedCGImage.height)))
        }
        
        // Update Cache
        imageCache[newElement.id] = croppedImage
        
        elements[index] = newElement
        saveCanvas()
        
        // Re-select to update UI bounds
        selectedElementIds = [newElement.id]
    }
    
    // MARK: - Resizing Selection
    
    private var initialSelectionBounds: CGRect?
    private var initialSelectedElements: [UUID: CanvasElementData] = [:]
    
    func startResizingSelection() {
        saveState()
        initialSelectionBounds = selectedElementsBounds
        initialSelectedElements.removeAll()
        let elementsToSearch = allElementsWithOffsets
        for id in selectedElementIds {
            if let element = elementsToSearch.first(where: { $0.id == id }) {
                initialSelectedElements[id] = element
            }
        }
    }
    
    func resizeSelection(translation: CGSize) {
        guard let initialBounds = initialSelectionBounds, initialBounds.width > 0, initialBounds.height > 0 else { return }
        
        // Adjust translation for zoom
        let deltaWidth = translation.width / scale
        let deltaHeight = translation.height / scale
        
        let newWidth = max(20, initialBounds.width + deltaWidth)
        let newHeight = max(20, initialBounds.height + deltaHeight)
        
        resizeSelection(to: CGSize(width: newWidth, height: newHeight))
    }
    
    private func resizeSelection(to newSize: CGSize) {
        guard let initialBounds = initialSelectionBounds else { return }
        
        let scaleX = newSize.width / initialBounds.width
        let scaleY = newSize.height / initialBounds.height
        
        let pageHeight = CanvasConstants.a4Height + CanvasViewModel.pageGap
        
        for (id, initialElement) in initialSelectedElements {
            // We need to find which page this element belongs to and update it there
            for pageIndex in 0..<pages.count {
                if let elementIndex = pages[pageIndex].elements.firstIndex(where: { $0.id == id }) {
                    var element = pages[pageIndex].elements[elementIndex]
                    let yOffset = CGFloat(pageIndex) * pageHeight
                    
                    // Calculate new position relative to bounds origin (in global coordinates)
                    let relativeX = initialElement.x - initialBounds.minX
                    let relativeY = initialElement.y - initialBounds.minY
                    
                    let newGlobalX = initialBounds.minX + (relativeX * scaleX)
                    let newGlobalY = initialBounds.minY + (relativeY * scaleY)
                    let newWidth = initialElement.width * scaleX
                    let newHeight = initialElement.height * scaleY
                    
                    // Apply new position and size, converting back to local page coordinates
                    element.x = newGlobalX
                    element.y = newGlobalY - yOffset
                    element.width = newWidth
                    element.height = newHeight
                    
                    // Scale content if it's a stroke
                    if case .stroke(let data) = initialElement.data {
                        let newPoints = data.points.map { point in
                            StrokeData.Point(x: point.x * scaleX, y: point.y * scaleY)
                        }
                        let strokeScale = (scaleX + scaleY) / 2.0
                        let newStrokeWidth = data.width * strokeScale
                        
                        element.data = .stroke(StrokeData(points: newPoints, color: data.color, width: newStrokeWidth, brushType: data.brushType))
                    }
                    
                    pages[pageIndex].elements[elementIndex] = element
                    break
                }
            }
        }
    }
    
    func endResizingSelection() {
        initialSelectionBounds = nil
        initialSelectedElements.removeAll()
        saveCanvas()
    }
    
    // MARK: - Export
    
    /// Renders a single page to an image
    @MainActor
    func renderPageToImage(pageIndex: Int) -> UIImage? {
        guard pages.indices.contains(pageIndex) else { return nil }
        
        let pageElements = pages[pageIndex].elements
        
        let pageView = ZStack(alignment: .topLeading) {
            // White background
            Rectangle()
                .fill(Color(hex: CanvasConstants.paperColor))
                .frame(width: CanvasConstants.a4Width, height: CanvasConstants.a4Height)
            
            // Render all elements
            ForEach(pageElements) { element in
                ExportElementView(element: element, imageCache: self.imageCache)
            }
        }
        .frame(width: CanvasConstants.a4Width, height: CanvasConstants.a4Height)
        
        let renderer = ImageRenderer(content: pageView)
        renderer.scale = 2.0 // High resolution
        return renderer.uiImage
    }
    
    /// Renders all pages to images
    @MainActor
    func renderAllPagesToImages() -> [UIImage] {
        var images: [UIImage] = []
        for i in 0..<pages.count {
            if let image = renderPageToImage(pageIndex: i) {
                images.append(image)
            }
        }
        return images
    }
    
    /// Exports specified pages to PDF data
    func exportToPDF(pageIndices: [Int]) -> Data? {
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: CanvasConstants.a4Width, height: CanvasConstants.a4Height))
        
        let data = pdfRenderer.pdfData { context in
            for pageIndex in pageIndices {
                guard pages.indices.contains(pageIndex) else { continue }
                
                context.beginPage()
                
                if let image = renderPageToImage(pageIndex: pageIndex) {
                    image.draw(in: CGRect(x: 0, y: 0, width: CanvasConstants.a4Width, height: CanvasConstants.a4Height))
                }
            }
        }
        
        return data
    }
    
    /// Exports current page to PDF
    func exportCurrentPageToPDF() -> Data? {
        return exportToPDF(pageIndices: [currentPageIndex])
    }
    
    /// Exports all pages to PDF
    func exportAllPagesToPDF() -> Data? {
        return exportToPDF(pageIndices: Array(0..<pages.count))
    }
}

// MARK: - Safe Array Subscript
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
