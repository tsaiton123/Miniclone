import SwiftUI
import Combine
import UIKit

class CanvasViewModel: ObservableObject {
    @Published var elements: [CanvasElementData] = []
    @Published var selectedElementIds: Set<UUID> = []
    @Published var scale: CGFloat = 1.0
    @Published var offset: CGSize = .zero
    
    @Published var currentStroke: CanvasElementData?
    @Published var selectionBox: CGRect?
    @Published var editingElementId: UUID?
    
    // Cache for images to avoid repeated base64 decoding
    @Published var imageCache: [UUID: UIImage] = [:]
    
    // Styling
    @Published var currentStrokeColor: String = "#ffffff"
    @Published var currentStrokeWidth: CGFloat = 2.0
    
    // Undo/Redo
    private var undoStack: [[CanvasElementData]] = []
    private var redoStack: [[CanvasElementData]] = []
    
    private var noteId: UUID
    private var lastOffset: CGSize = .zero
    private var lastScale: CGFloat = 1.0
    private var selectionStartPoint: CGPoint?
    private var cancellables = Set<AnyCancellable>()
    private var hasCenteredInitial = false
    private let saveTrigger = PassthroughSubject<Void, Never>()
    
    init(noteId: UUID) {
        self.noteId = noteId
        setupDebouncedSave()
        loadCanvas()
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
        offset = CGSize(width: lastOffset.width + translation.width, height: lastOffset.height + translation.height)
    }
    
    func endDrag(translation: CGSize) {
        handleDrag(translation: translation)
        lastOffset = offset
    }
    
    func handleMagnification(value: CGFloat) {
        scale = lastScale * value
    }
    
    func endMagnification(value: CGFloat) {
        handleMagnification(value: value)
        lastScale = scale
        saveCanvas()
    }
    
    func zoomIn() {
        scale = min(scale + 0.1, 5.0)
    }
    
    func zoomOut() {
        scale = max(scale - 0.1, 0.1)
    }
    
    func centerCanvas(in screenSize: CGSize) {
        // Initial centering logic: center the A4 paper in the available screen space
        // We only do this if we haven't centered yet or if the canvas is empty
        guard screenSize.width > 0 && screenSize.height > 0 else { return }
        
        let initialScale: CGFloat = min(
            (screenSize.width - 40) / CanvasConstants.a4Width,
            (screenSize.height - 40) / CanvasConstants.a4Height,
            1.0
        )
        
        scale = initialScale
        lastScale = initialScale
        
        let offsetX = (screenSize.width - CanvasConstants.a4Width * scale) / 2
        let offsetY = (screenSize.height - CanvasConstants.a4Height * scale) / 2
        
        offset = CGSize(width: offsetX, height: offsetY)
        lastOffset = offset
        hasCenteredInitial = true
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
        
        // Otherwise, calculate bounds of selected elements
        var minX: CGFloat = .infinity
        var minY: CGFloat = .infinity
        var maxX: CGFloat = -.infinity
        var maxY: CGFloat = -.infinity
        
        var hasElements = false
        
        for id in selectedElementIds {
            if let element = elements.first(where: { $0.id == id }) {
                hasElements = true
                minX = min(minX, element.x)
                minY = min(minY, element.y)
                maxX = max(maxX, element.x + element.width)
                maxY = max(maxY, element.y + element.height)
            }
        }
        
        guard hasElements else { return nil }
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    private func updateSelectedElements() {
        guard let box = selectionBox else { return }
        
        let selected = elements.filter { element in
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
        
        let left = CGPoint(x: rect.minX, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: rect.maxY) // Not quite, need 4 corners
        
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
        for id in selectedElementIds {
            if let element = elements.first(where: { $0.id == id }) {
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
        // Search in reverse order (topmost first)
        for element in elements.reversed() {
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
        for id in selectedElementIds {
            if let element = elements.first(where: { $0.id == id }) {
                initialElementPositions[id] = CGPoint(x: element.x, y: element.y)
            }
        }
    }
    
    func moveSelection(translation: CGSize) {
        let deltaX = translation.width / scale
        let deltaY = translation.height / scale
        
        for (id, initialPos) in initialElementPositions {
            if let index = elements.firstIndex(where: { $0.id == id }) {
                let element = elements[index]
                let newX = max(0, min(initialPos.x + deltaX, CanvasConstants.a4Width - element.width))
                let newY = max(0, min(initialPos.y + deltaY, CanvasConstants.a4Height - element.height))
                
                elements[index].x = newX
                elements[index].y = newY
            }
        }
    }
    
    func endMovingSelection() {
        initialElementPositions.removeAll()
        saveCanvas()
    }
    
    // MARK: - Drawing
    
    func startStroke(at point: CGPoint) {
        let canvasPoint = toCanvasCoordinates(point)
        // Clamp to A4
        let clampedPoint = CGPoint(
            x: max(0, min(canvasPoint.x, CanvasConstants.a4Width)),
            y: max(0, min(canvasPoint.y, CanvasConstants.a4Height))
        )
        
        let strokeData = StrokeData(points: [StrokeData.Point(x: clampedPoint.x, y: clampedPoint.y)], color: currentStrokeColor, width: currentStrokeWidth)
        
        currentStroke = CanvasElementData(
            id: UUID(),
            type: .stroke,
            x: 0, y: 0,
            width: 0, height: 0,
            zIndex: 1,
            data: .stroke(strokeData)
        )
    }
    
    func continueStroke(at point: CGPoint) {
        guard var stroke = currentStroke, case .stroke(var data) = stroke.data else {
            startStroke(at: point) // Safety fallback
            return
        }
        
        let canvasPoint = toCanvasCoordinates(point)
        // Clamp to A4
        let clampedX = max(0, min(canvasPoint.x, CanvasConstants.a4Width))
        let clampedY = max(0, min(canvasPoint.y, CanvasConstants.a4Height))
        
        data.points.append(StrokeData.Point(x: clampedX, y: clampedY))
        stroke.data = .stroke(data)
        currentStroke = stroke
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
        
        let width = maxX - minX
        let height = maxY - minY
        
        // Normalize points relative to bounding box
        let normalizedPoints = data.points.map { StrokeData.Point(x: $0.x - minX, y: $0.y - minY) }
        let newStrokeData = StrokeData(points: normalizedPoints, color: data.color, width: data.width)
        
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
        undoStack.append(elements)
        redoStack.removeAll()
        
        // Limit stack size
        if undoStack.count > 20 {
            undoStack.removeFirst()
        }
    }
    
    func undo() {
        guard let previousState = undoStack.popLast() else { return }
        redoStack.append(elements)
        elements = previousState
        saveCanvas()
    }
    
    func redo() {
        guard let nextState = redoStack.popLast() else { return }
        undoStack.append(elements)
        elements = nextState
        saveCanvas()
    }
    
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func loadCanvas() {
        do {
            let data = try StorageManager.shared.loadCanvas(id: noteId)
            self.elements = data.elements
            Task {
                await preloadImages()
            }
            sanitizeElements()
        } catch {
            print("Error loading canvas: \(error)")
        }
    }
    
    private func preloadImages() async {
        let currentElements = elements
        let idsAndData = currentElements.compactMap { element -> (UUID, String)? in
            if case .image(let data) = element.data {
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
                    let newStrokeData = StrokeData(points: normalizedPoints, color: data.color, width: data.width)
                    
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
        let data = CanvasData(elements: elements)
        do {
            try StorageManager.shared.saveCanvas(id: noteId, data: data)
            print("Canvas saved successfully")
        } catch {
            print("Error saving canvas: \(error)")
        }
    }
    
    func addElement(_ element: CanvasElementData) {
        saveState()
        var clampedElement = element
        clampedElement.x = max(0, min(element.x, CanvasConstants.a4Width - element.width))
        clampedElement.y = max(0, min(element.y, CanvasConstants.a4Height - element.height))
        
        // Dynamic caching for new images
        if case .image(let data) = clampedElement.data {
            if let uiImage = UIImage(data: Data(base64Encoded: data.src) ?? Data()) {
                imageCache[clampedElement.id] = uiImage
            }
        }
        
        elements.append(clampedElement)
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
        
        let newElement = CanvasElementData(
            id: UUID(),
            type: .graph,
            x: (CanvasConstants.a4Width - width) / 2, // Center on page
            y: (CanvasConstants.a4Height - height) / 2,
            width: width,
            height: height,
            zIndex: elements.count,
            data: .graph(graphData)
        )
        
        addElement(newElement)
    }
    
    func addText(_ text: String, at point: CGPoint = CGPoint(x: 100, y: 100)) {
        // Calculate size
        let font = UIFont(name: "Caveat-Regular", size: 20) ?? .systemFont(ofSize: 20)
        let maxConstraint = CGSize(width: 500, height: CGFloat.greatestFiniteMagnitude)
        let boundingRect = text.boundingRect(
            with: maxConstraint,
            options: .usesLineFragmentOrigin,
            attributes: [.font: font],
            context: nil
        )
        
        let width = max(boundingRect.width + 40, 100)
        let height = max(boundingRect.height + 40, 50)
        
        // Clamp position to boundary
        let clampedX = max(0, min(point.x, CanvasConstants.a4Width - width))
        let clampedY = max(0, min(point.y, CanvasConstants.a4Height - height))
        
        let newElement = CanvasElementData(
            id: UUID(),
            type: .text,
            x: clampedX,
            y: clampedY,
            width: width,
            height: height,
            zIndex: elements.count,
            data: .text(TextData(text: text, fontSize: 20, fontFamily: "Caveat", color: "#ffffff"))
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
        elements.removeAll(where: { $0.id == id })
        saveCanvas()
    }
    
    func deleteSelection() {
        guard !selectedElementIds.isEmpty else { return }
        saveState()
        elements.removeAll(where: { selectedElementIds.contains($0.id) })
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
        selectedElementIds.removeAll()
    }
    
    func getSelectedContent() -> String {
        var content = ""
        for id in selectedElementIds {
            if let element = elements.first(where: { $0.id == id }) {
                switch element.data {
                case .text(let data):
                    content += "Text: \(data.text)\n"
                case .graph(let data):
                    content += "Graph: \(data.expression)\n"
                case .stroke:
                    content += "Stroke (Handwriting)\n"
                case .image:
                    content += "Image\n"
                }
            }
        }
        return content
    }
    
    func mergeSelection(image: UIImage, bounds: CGRect) {
        guard !selectedElementIds.isEmpty else { return }
        
        saveState()
        
        // Remove original elements
        elements.removeAll(where: { selectedElementIds.contains($0.id) })
        
        let width = bounds.width
        let height = bounds.height
        
        // Clamp to boundary
        let clampedX = max(0, min(bounds.minX, CanvasConstants.a4Width - width))
        let clampedY = max(0, min(bounds.minY, CanvasConstants.a4Height - height))
        
        // Create new merged element
        let newElement = CanvasElementData(
            id: UUID(),
            type: .image,
            x: clampedX,
            y: clampedY,
            width: width,
            height: height,
            zIndex: elements.count,
            data: .image(ImageData(src: image.pngData()?.base64EncodedString() ?? "", originalWidth: image.size.width, originalHeight: image.size.height))
        )
        
        elements.append(newElement)
        
        // Select the new element
        selectedElementIds = [newElement.id]
        
        saveCanvas()
    }
    
    // MARK: - Resizing Selection
    
    private var initialSelectionBounds: CGRect?
    private var initialSelectedElements: [UUID: CanvasElementData] = [:]
    
    func startResizingSelection() {
        saveState()
        initialSelectionBounds = selectedElementsBounds
        initialSelectedElements.removeAll()
        for id in selectedElementIds {
            if let element = elements.first(where: { $0.id == id }) {
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
        
        for (id, initialElement) in initialSelectedElements {
            if let index = elements.firstIndex(where: { $0.id == id }) {
                var element = elements[index]
                
                // Calculate new position relative to bounds origin
                let relativeX = initialElement.x - initialBounds.minX
                let relativeY = initialElement.y - initialBounds.minY
                
                let newX = initialBounds.minX + (relativeX * scaleX)
                let newY = initialBounds.minY + (relativeY * scaleY)
                let newWidth = initialElement.width * scaleX
                let newHeight = initialElement.height * scaleY
                
                // Clamp to A4
                element.x = max(0, min(newX, CanvasConstants.a4Width - newWidth))
                element.y = max(0, min(newY, CanvasConstants.a4Height - newHeight))
                element.width = min(newWidth, CanvasConstants.a4Width - element.x)
                element.height = min(newHeight, CanvasConstants.a4Height - element.y)
                
                // Scale content
                if case .stroke(let data) = initialElement.data {
                    let newPoints = data.points.map { point in
                        StrokeData.Point(x: point.x * scaleX, y: point.y * scaleY)
                    }
                    let scale = (scaleX + scaleY) / 2.0
                    let newWidth = data.width * scale
                    
                    element.data = .stroke(StrokeData(points: newPoints, color: data.color, width: newWidth))
                }
                
                elements[index] = element
            }
        }
    }
    
    func endResizingSelection() {
        initialSelectionBounds = nil
        initialSelectedElements.removeAll()
        saveCanvas()
    }
}
