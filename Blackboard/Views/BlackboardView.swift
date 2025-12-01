import SwiftUI

struct BlackboardView: View {
    var note: NoteItem
    @StateObject private var viewModel: CanvasViewModel
    
    init(note: NoteItem) {
        self.note = note
        _viewModel = StateObject(wrappedValue: CanvasViewModel(noteId: note.id))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: "#1a1f2e") // Blackboard background
                    .ignoresSafeArea()
                
                gestureReceiver
                
                canvasContent
            }
            .overlay(toolbarOverlay)
        }
        .navigationTitle(note.title)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { viewModel.clearCanvas() }) {
                    Image(systemName: "trash")
                }
            }
        }
        .sheet(isPresented: $isShowingDocumentPicker) {
            DocumentPicker { url in
                selectedPDFURL = url
                isShowingPDFSelection = true
            }
        }
        .fullScreenCover(isPresented: $isShowingPDFSelection) {
            if let url = selectedPDFURL {
                PDFSelectionView(pdfURL: url) { rect, image in
                    viewModel.addElement(CanvasElementData(
                        id: UUID(),
                        type: .image,
                        x: 100,
                        y: 100,
                        width: 200,
                        height: 200 * (image.size.height / image.size.width),
                        zIndex: viewModel.elements.count,
                        data: .image(ImageData(src: image.pngData()?.base64EncodedString() ?? "", originalWidth: image.size.width, originalHeight: image.size.height))
                    ))
                }
            }
        }
    }
    
    @State private var selectedTool: ToolbarView.ToolType = .select
    @State private var isShowingDocumentPicker = false
    @State private var selectedPDFURL: URL?
    @State private var isMovingSelection = false
    @State private var isShowingPDFSelection = false
    @State private var isShowingChat = false
    @State private var chatContext: String?
    @StateObject private var geminiService = GeminiService()
    
    var canvasContent: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.elements.isEmpty {
                VStack(spacing: 10) {
                    Text("Select a tool below")
                    Text("or Double Tap to add text")
                        .font(.subheadline)
                }
                .font(.title)
                .foregroundColor(.gray.opacity(0.5))
            }
            
            ForEach(viewModel.elements) { element in
                CanvasElementView(
                    element: element,
                    isSelected: viewModel.selectedElementIds.contains(element.id),
                    onDelete: {
                        viewModel.removeElement(id: element.id)
                    },
                    isEditing: viewModel.editingElementId == element.id,
                    onTextChange: { newText in
                        viewModel.updateElementText(id: element.id, text: newText)
                        viewModel.editingElementId = nil
                    }
                )
                .onTapGesture(count: 2) {
                    if case .text = element.data {
                        viewModel.selectElement(id: element.id)
                        viewModel.editingElementId = element.id
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if selectedTool == .select {
                                if !viewModel.selectedElementIds.contains(element.id) {
                                    viewModel.selectElement(id: element.id)
                                }
                                
                                if !isMovingSelection {
                                    isMovingSelection = true
                                    viewModel.startMovingSelection()
                                }
                                
                                viewModel.moveSelection(translation: value.translation)
                            }
                        }
                        .onEnded { _ in
                            if selectedTool == .select {
                                viewModel.endMovingSelection()
                                isMovingSelection = false
                            }
                        }
                )
                .allowsHitTesting(selectedTool == .select || selectedTool == .text)
            }
            
            // Render Current Stroke being drawn
            if let currentStroke = viewModel.currentStroke, case .stroke(let data) = currentStroke.data {
                Path { path in
                    guard let first = data.points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: first.y))
                    for point in data.points.dropFirst() {
                        path.addLine(to: CGPoint(x: point.x, y: point.y))
                    }
                }
                .stroke(Color(hex: data.color), style: StrokeStyle(lineWidth: data.width, lineCap: .round, lineJoin: .round))
            }
            
            // Render Selection Box
            if let box = viewModel.selectedElementsBounds {
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Color.blue.opacity(0.1))
                        .border(Color.blue, width: 1)
                        .allowsHitTesting(false)
                    
                    // Ask AI Button
                    Button(action: {
                        let context = viewModel.getSelectedContent()
                        let center = CGPoint(x: box.maxX + 20, y: box.minY)
                        
                        // Capture Snapshot
                        let selectedElements = viewModel.elements.filter { viewModel.selectedElementIds.contains($0.id) }
                        let bounds = box
                        
                        // Create temporary elements relative to bounds
                        let tempElements = selectedElements.map { original -> CanvasElementData in
                            var temp = original
                            temp.x -= bounds.minX
                            temp.y -= bounds.minY
                            return temp
                        }
                        
                        let snapshotView = ZStack(alignment: .topLeading) {
                            Color.black // Background (Blackboard style)
                            ForEach(tempElements) { element in
                                CanvasElementView(element: element, isSelected: false, onDelete: {})
                            }
                        }
                        .frame(width: bounds.width, height: bounds.height)
                        
                        let renderer = ImageRenderer(content: snapshotView)
                        renderer.scale = UIScreen.main.scale
                        let image = renderer.uiImage
                        
                        Task {
                            do {
                                let response = try await geminiService.sendSelectionContext(context, image: image)
                                let (cleanText, graphCommand) = geminiService.parseResponse(response)
                                
                                await MainActor.run {
                                    if !cleanText.isEmpty {
                                        viewModel.addText(cleanText, at: center)
                                    }
                                    
                                    if let command = graphCommand {
                                        viewModel.addGraph(expression: command.expression, xMin: command.xMin, xMax: command.xMax)
                                    }
                                }
                            } catch {
                                print("AI Error: \(error)")
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("Ask AI")
                        }
                        .font(.caption)
                        .padding(6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .shadow(radius: 2)
                    }
                    .offset(y: -40)
                }
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure it fills screen
        .scaleEffect(viewModel.scale, anchor: .topLeading)
        .offset(viewModel.offset)
    }
    
    var gestureReceiver: some View {
        Color.black.opacity(0.001)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if selectedTool == .pen {
                            viewModel.continueStroke(at: value.location)
                        } else if selectedTool == .select {
                            if isMovingSelection {
                                viewModel.moveSelection(translation: value.translation)
                            } else if viewModel.selectionBox != nil {
                                viewModel.updateSelection(to: value.location)
                            } else {
                                // New gesture start
                                if viewModel.isPointInSelectedElement(value.startLocation) {
                                    isMovingSelection = true
                                    viewModel.startMovingSelection()
                                    viewModel.moveSelection(translation: value.translation)
                                } else if let elementId = viewModel.findElement(at: value.startLocation) {
                                    // Click and drag unselected element
                                    viewModel.selectElement(id: elementId)
                                    isMovingSelection = true
                                    viewModel.startMovingSelection()
                                    viewModel.moveSelection(translation: value.translation)
                                } else {
                                    viewModel.startSelection(at: value.startLocation)
                                    viewModel.updateSelection(to: value.location)
                                }
                            }
                        } else {
                            viewModel.handleDrag(translation: value.translation)
                        }
                    }
                    .onEnded { value in
                        if selectedTool == .pen {
                            viewModel.endStroke()
                        } else if selectedTool == .select {
                            if isMovingSelection {
                                viewModel.endMovingSelection()
                                isMovingSelection = false
                            } else {
                                viewModel.endSelection()
                            }
                        } else if selectedTool == .text {
                            // Add text at tap location (startLocation)
                            let location = value.startLocation
                            let canvasX = (location.x - viewModel.offset.width) / viewModel.scale
                            let canvasY = (location.y - viewModel.offset.height) / viewModel.scale
                            
                            let newText = CanvasElementData(
                                id: UUID(),
                                type: .text,
                                x: canvasX,
                                y: canvasY,
                                width: 200,
                                height: 50,
                                zIndex: viewModel.elements.count,
                                data: .text(TextData(text: "New Text", fontSize: 24, fontFamily: "Caveat", color: "#ffffff"))
                            )
                            viewModel.addElement(newText)
                            
                            // Switch back to select tool for convenience
                            selectedTool = .select
                        } else {
                            viewModel.endDrag(translation: value.translation)
                        }
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        viewModel.handleMagnification(value: value)
                    }
                    .onEnded { value in
                        viewModel.endMagnification(value: value)
                    }
            )
            .onTapGesture {
                viewModel.clearSelection()
            }
            .gesture(
                SpatialTapGesture(count: 2)
                    .onEnded { event in
                        let location = event.location
                        let canvasX = (location.x - viewModel.offset.width) / viewModel.scale
                        let canvasY = (location.y - viewModel.offset.height) / viewModel.scale
                        
                        let newText = CanvasElementData(
                            id: UUID(),
                            type: .text,
                            x: canvasX - 100, // Center text on tap
                            y: canvasY - 25,
                            width: 200,
                            height: 50,
                            zIndex: 0,
                            data: .text(TextData(text: "New Text", fontSize: 24, fontFamily: "Caveat", color: "#ffffff"))
                        )
                        viewModel.addElement(newText)
                    }
            )
    }
    
    var toolbarOverlay: some View {
        ZStack {
            // Floating Toolbar (Bottom Center)
            VStack {
                Spacer()
                ToolbarView(
                    selectedTool: $selectedTool,
                    onAddGraph: {
                        // Removed
                    },
                    onAskAI: {
                        isShowingChat.toggle()
                    },
                    onImportPDF: {
                        isShowingDocumentPicker = true
                    },
                    onDeleteSelection: {
                        viewModel.deleteSelection()
                    },
                    onUndo: {
                        viewModel.undo()
                    },
                    onRedo: {
                        viewModel.redo()
                    },
                    canUndo: viewModel.canUndo,
                    canRedo: viewModel.canRedo
                )
                .padding(.bottom, 20)
            }
            
            // Zoom Controls (Bottom Right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Button(action: { viewModel.zoomIn() }) {
                            Image(systemName: "plus.magnifyingglass")
                                .padding(10)
                                .background(Color(UIColor.secondarySystemBackground))
                                .clipShape(Circle())
                        }
                        
                        Text("\(Int(viewModel.scale * 100))%")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.vertical, 4)
                            .background(Color(UIColor.secondarySystemBackground).opacity(0.8))
                            .cornerRadius(4)
                        
                        Button(action: { viewModel.zoomOut() }) {
                            Image(systemName: "minus.magnifyingglass")
                                .padding(10)
                                .background(Color(UIColor.secondarySystemBackground))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 100) // Above toolbar area if needed, or side
                }
            }
            
            // Chat View Overlay
            if isShowingChat {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ChatView(contextToProcess: $chatContext) { command in
                            viewModel.addGraph(expression: command.expression, xMin: command.xMin, xMax: command.xMax)
                        }
                        .padding(.bottom, 100)
                        .padding(.trailing, 20)
                    }
                }
                .transition(.move(edge: .trailing))
                .zIndex(100)
            }
        }
    }

    }

// Helper to make URL Identifiable for fullScreenCover
extension URL: Identifiable {
    public var id: String { absoluteString }
}
