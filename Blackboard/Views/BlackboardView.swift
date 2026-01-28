import SwiftUI
import PDFKit
import UniformTypeIdentifiers




struct BlackboardView: View {
    var note: NoteItem
    @StateObject private var viewModel: CanvasViewModel
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var authManager: AuthenticationManager
    
    init(note: NoteItem) {
        self.note = note
        _viewModel = StateObject(wrappedValue: CanvasViewModel(noteId: note.id))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color(hex: CanvasConstants.workspaceColor) // Workspace background
                    .ignoresSafeArea()
                
                gestureReceiver
                
                gestureReceiver
                
                canvasContent(geometry: geometry)
                
                toolbarOverlay
            }
            .onAppear {
                viewModel.centerCanvas(in: geometry.size)
                // Refresh subscription status when view appears
                Task {
                    await subscriptionManager.refreshStatus()
                }
            }
        }
        .navigationTitle(note.title)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { viewModel.clearCanvas() }) {
                    Image(systemName: "trash")
                }
            }
        }
        .fileImporter(
            isPresented: $isShowingDocumentPicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                print("BlackboardView: fileImporter success: \(urls)")
                if let url = urls.first {
                    handleImportedPDF(url: url)
                }
            case .failure(let error):
                print("BlackboardView: fileImporter failed: \(error.localizedDescription)")
            }
        }
        .fullScreenCover(item: $selectedPDFDocument) { document in
            PDFSelectionView(pdfDocument: document) { rect, image in
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
                selectedPDFDocument = nil
            }
        }
        .sheet(isPresented: $isShowingImagePicker) {
            ImagePicker { image in
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
        .onChange(of: isShowingDocumentPicker) { newValue in
            print("BlackboardView: isShowingDocumentPicker changed to \(newValue)")
        }
        .onChange(of: viewModel.currentStroke) { stroke in
            // Collapse toolbar when starting to draw with pencil
            if stroke != nil {
                isPenToolbarCollapsed = true
            }
        }
        .onChange(of: viewModel.isCanvasTouched) { isTouched in
            // Collapse toolbar when canvas is touched (by finger or pencil)
            if isTouched {
                isPenToolbarCollapsed = true
            }
        }
    }
    
    @State private var selectedTool: ToolbarView.ToolType = .select
    @State private var isShowingDocumentPicker = false
    @State private var isShowingImagePicker = false
    @State private var selectedPDFDocument: PDFDocument?
    @State private var isMovingSelection = false
    @State private var isResizingSelection = false
    @State private var isShowingChat = false
    @State private var isShowingCalculator = false
    @State private var isShowingSettings = false
    @AppStorage("isFingerDrawingEnabled") private var isFingerDrawingEnabled = false
    @State private var chatContext: String?
    @State private var isShowingPaywall = false
    @State private var isPenToolbarCollapsed = false
    @State private var isShowingExportOptions = false
    @State private var showingSignOutAlert = false
    @State private var showingDeleteAccountAlert = false
    @State private var isAIProcessing = false

    @State private var isPreparingInkjet = false
    @State private var inkjetPreWarmElements: [CanvasElementData] = []
    
    // Crop Mode State
    @State private var isCropping = false
    @State private var cropRect: CGRect?
    
    @StateObject private var geminiService = GeminiService()


    @StateObject private var quotaManager = AIQuotaManager.shared
    
    func canvasContent(geometry: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            // A4 Paper Background
            Rectangle()
                .fill(isPreparingInkjet ? Color.white : Color(hex: CanvasConstants.paperColor))
                .frame(width: CanvasConstants.a4Width, height: CanvasConstants.a4Height)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                .allowsHitTesting(false)
            
            ForEach(viewModel.elements) { element in
                CanvasElementView(
                    element: element,
                    viewModel: viewModel,
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
                .equatable()
                .onTapGesture(count: 2) {
                    if case .text = element.data {
                        viewModel.selectElement(id: element.id)
                        viewModel.editingElementId = element.id
                    }
                }
                .onTapGesture {
                    if selectedTool == .select {
                        viewModel.selectElement(id: element.id)
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if selectedTool == .select {
                                // Only move if the element is already selected
                                if viewModel.selectedElementIds.contains(element.id) {
                                    if !isMovingSelection {
                                        isMovingSelection = true
                                        viewModel.startMovingSelection()
                                    }
                                    
                                    viewModel.moveSelection(translation: value.translation)
                                }
                            }
                        }
                        .onEnded { _ in
                            if selectedTool == .select {
                                // Only end moving if we were actually moving
                                if isMovingSelection {
                                    viewModel.endMovingSelection()
                                    isMovingSelection = false
                                }
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
                .stroke(
                    Color(hex: data.color).opacity(data.brushType.opacity),
                    style: StrokeStyle(
                        lineWidth: data.width * data.brushType.widthMultiplier,
                        lineCap: data.brushType.lineCap,
                        lineJoin: data.brushType.lineJoin
                    )
                )
            }
            
            // Render Eraser Circle Preview
            if let eraserPos = viewModel.currentEraserPosition {
                Circle()
                    .stroke(Color.gray.opacity(0.8), lineWidth: 1.5)
                    .frame(width: viewModel.currentEraserWidth * 2, height: viewModel.currentEraserWidth * 2)
                    .position(eraserPos)
            }
            
            // Render Selection Box or Crop Overlay
            if let box = viewModel.selectedElementsBounds, !isPreparingInkjet {
                if isCropping, let initialCropRect = cropRect {
                     // ----------------- CROP OVERLAY -----------------
                    ZStack {
                        // Dimmed background helper (optional, maybe just the box)
                        
                        // Crop Rectangle
                        Rectangle()
                            .stroke(Color.white, lineWidth: 2)
                            .shadow(radius: 2)
                            .frame(width: cropRect!.width, height: cropRect!.height)
                            .position(x: cropRect!.midX, y: cropRect!.midY)
                        
                        // Grid lines (3x3 Rule of Thirds) - Optional polish
                        Path { path in
                            let r = cropRect!
                            // Verticals
                            path.move(to: CGPoint(x: r.minX + r.width/3, y: r.minY))
                            path.addLine(to: CGPoint(x: r.minX + r.width/3, y: r.maxY))
                            path.move(to: CGPoint(x: r.minX + 2*r.width/3, y: r.minY))
                            path.addLine(to: CGPoint(x: r.minX + 2*r.width/3, y: r.maxY))
                            // Horizontals
                            path.move(to: CGPoint(x: r.minX, y: r.minY + r.height/3))
                            path.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height/3))
                            path.move(to: CGPoint(x: r.minX, y: r.minY + 2*r.height/3))
                            path.addLine(to: CGPoint(x: r.maxX, y: r.minY + 2*r.height/3))
                        }
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        
                        // Corner Handles
                        // TL
                        cropHandle(x: cropRect!.minX, y: cropRect!.minY) { drag in
                            // Adjust Left and Top
                            let newX = min(drag.location.x, cropRect!.maxX - 20)
                            let newY = min(drag.location.y, cropRect!.maxY - 20)
                            let newW = cropRect!.maxX - newX
                            let newH = cropRect!.maxY - newY
                            cropRect = CGRect(x: newX, y: newY, width: newW, height: newH)
                        }
                        // TR
                        cropHandle(x: cropRect!.maxX, y: cropRect!.minY) { drag in
                            // Adjust Right and Top
                            let newX = max(drag.location.x, cropRect!.minX + 20)
                            let newY = min(drag.location.y, cropRect!.maxY - 20)
                            let newW = newX - cropRect!.minX
                            let newH = cropRect!.maxY - newY
                            cropRect = CGRect(x: cropRect!.minX, y: newY, width: newW, height: newH)
                        }
                        // BL
                        cropHandle(x: cropRect!.minX, y: cropRect!.maxY) { drag in
                            // Adjust Left and Bottom
                            let newX = min(drag.location.x, cropRect!.maxX - 20)
                            let newY = max(drag.location.y, cropRect!.minY + 20)
                            let newW = cropRect!.maxX - newX
                            let newH = newY - cropRect!.minY
                            cropRect = CGRect(x: newX, y: cropRect!.minY, width: newW, height: newH)
                        }
                        // BR
                        cropHandle(x: cropRect!.maxX, y: cropRect!.maxY) { drag in
                            // Adjust Right and Bottom
                            let newX = max(drag.location.x, cropRect!.minX + 20)
                            let newY = max(drag.location.y, cropRect!.minY + 20)
                            let newW = newX - cropRect!.minX
                            let newH = newY - cropRect!.minY
                            cropRect = CGRect(x: cropRect!.minX, y: cropRect!.minY, width: newW, height: newH)
                        }
                        
                        // Floating Actions (Confirm/Cancel)
                        HStack(spacing: 20) {
                            Button(action: {
                                isCropping = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(.white)
                                    .background(Circle().fill(Color.red))
                                    .shadow(radius: 4)
                            }
                            
                            Button(action: {
                                viewModel.cropSelection(bounds: cropRect!)
                                isCropping = false
                            }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(.white)
                                    .background(Circle().fill(Color.green))
                                    .shadow(radius: 4)
                            }
                        }
                        .position(x: cropRect!.midX, y: cropRect!.maxY + 60)
                    }
                    
                } else {
                    // ----------------- STANDARD SELECTION -----------------
                    ZStack(alignment: .top) {
                        Rectangle()
                            .fill(Color.blue.opacity(0.1))
                            .border(Color.blue, width: 1)
                            .allowsHitTesting(false)
                        
                        // Resize Handle
                        Circle()
                            .fill(Color.white)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.blue, lineWidth: 1))
                            .frame(width: 44, height: 44) // Increase touch target
                            .contentShape(Circle())
                            .position(x: box.width, y: box.height)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        if !isResizingSelection {
                                            isResizingSelection = true
                                            viewModel.startResizingSelection()
                                        }
                                        viewModel.resizeSelection(translation: value.translation)
                                    }
                                    .onEnded { _ in
                                        viewModel.endResizingSelection()
                                        isResizingSelection = false
                                    }
                            )
                        
                        // Action Buttons
                        HStack(spacing: 12) {
                            // Ask AI Menu - Requires Pro subscription
                            if subscriptionManager.currentTier.hasAIFeatures {
                                Menu {
                                    Button(action: {
                                        performAIAction(mode: .explain, box: box)
                                    }) {
                                        Label("Explain", systemImage: "text.bubble")
                                    }
                                    
                                    Button(action: {
                                        performAIAction(mode: .solve, box: box)
                                    }) {
                                        Label("Solve", systemImage: "function")
                                    }
                                    
                                    Button(action: {
                                        performAIAction(mode: .plot, box: box)
                                    }) {
                                        Label("Plot", systemImage: "chart.xyaxis.line")
                                    }
                                } label: {
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
                            } else {
                                // Show locked AI button that opens paywall
                                Button(action: {
                                    isShowingPaywall = true
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "lock.fill")
                                        Text("Ask AI")
                                    }
                                    .font(.caption)
                                    .padding(6)
                                    .background(Color.gray)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                    .shadow(radius: 2)
                                }
                            }
                            
                            // Merge Button (Only if multiple items selected)
                            if viewModel.selectedElementIds.count > 1 {
                                Button(action: {
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
                                        ForEach(tempElements) { element in
                                            CanvasElementView(element: element, viewModel: viewModel, isSelected: false, onDelete: {})
                                        }
                                    }
                                    .frame(width: bounds.width, height: bounds.height)
                                    
                                    let renderer = ImageRenderer(content: snapshotView)
                                    renderer.scale = UIScreen.main.scale
                                    if let image = renderer.uiImage {
                                        viewModel.mergeSelection(image: image, bounds: bounds)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "square.on.square")
                                        Text("Merge")
                                    }
                                    .font(.caption)
                                    .padding(6)
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                    .shadow(radius: 2)
                                }
                            }
                            
                            // Crop Button (Only if 1 item selected)
                            if viewModel.selectedElementIds.count == 1 {
                                Button(action: {
                                    cropRect = box
                                    isCropping = true
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "crop")
                                        Text("Crop")
                                    }
                                    .font(.caption)
                                    .padding(6)
                                    .background(Color.teal)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                    .shadow(radius: 2)
                                }
                            }
                            
                            // Inkjet Button
                            Button(action: {
                                // 1. Prepare UI for Wysiwyg Capture
                                isPreparingInkjet = true
                                
                                // 2. Wait for UI update (background flash & hide selection)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    
                                    // 3. Capture Screen
                                    // Locate the window (assuming single window app)
                                    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                          let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
                                        isPreparingInkjet = false
                                        return
                                    }
                                    
                                    // Convert Canvas Coordinates (box) to Screen Coordinates
                                    // Canvas Point -> * Scale + Offset -> View Point -> + Window Origin -> Screen Point
                                    let scale = viewModel.scale
                                    let offset = viewModel.offset
                                    
                                    // Find where the canvas content starts on screen relative to window
                                    // We approximate this by looking at geometry.frame(in: .global).minX/Y
                                    // But GeometryReader 'geometry' is available in body. We can use it here if we capture it in closure?
                                    // Simplification: Assume pure transform based capture.
                                    
                                    // Calculate frame of the content within the Scroll/Zoom view
                                    let contentRect = CGRect(
                                        x: box.minX * scale + offset.width,
                                        y: box.minY * scale + offset.height,
                                        width: box.width * scale,
                                        height: box.height * scale
                                    )
                                    
                                    // Get the global position of the BlackboardView (the geometry reader container)
                                    let globalFrame = geometry.frame(in: .global)
                                    
                                    // Final Screen Rect = View Origin + Content Rect
                                    let screenRect = CGRect(
                                        x: globalFrame.minX + contentRect.minX,
                                        y: globalFrame.minY + contentRect.minY,
                                        width: contentRect.width,
                                        height: contentRect.height
                                    )
                                    
                                    // scale for retina
                                    let renderScale = UIScreen.main.scale
                                    
                                    // Draw Hierarchy
                                    let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
                                    let fullScreenImage = renderer.image { ctx in
                                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                                    }
                                    
                                    // Crop Image
                                    let cropRect = CGRect(
                                        x: screenRect.origin.x * renderScale,
                                        y: screenRect.origin.y * renderScale,
                                        width: screenRect.width * renderScale,
                                        height: screenRect.height * renderScale
                                    )
                                    
                                    if let cgImage = fullScreenImage.cgImage?.cropping(to: cropRect) {
                                        let croppedImage = UIImage(cgImage: cgImage)
                                        
                                        // Process Inkjet immediately
                                        viewModel.performInkjetPrinting(image: croppedImage, bounds: box)
                                    }
                                    
                                    // 4. Restore UI
                                    isPreparingInkjet = false
                                }
                            }) {
                                HStack(spacing: 4) {
                                    if isPreparingInkjet {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "printer.fill")
                                    }
                                    Text("Inkjet")
                                }
                                .font(.caption)
                                .padding(6)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .shadow(radius: 2)
                            }
                            .disabled(isPreparingInkjet)
                        }
                        .offset(y: -40)
                    }
                    .frame(width: box.width, height: box.height)
                    .position(x: box.midX, y: box.midY)
                }
            }
        }
        .frame(width: CanvasConstants.a4Width, height: CanvasConstants.a4Height)
        // Content can extend beyond canvas boundaries for visibility when dragging
        .scaleEffect(viewModel.scale, anchor: .topLeading)
        .offset(viewModel.offset)
    }
    
    var gestureReceiver: some View {
        CanvasInputView(viewModel: viewModel, selectedTool: $selectedTool, isFingerDrawingEnabled: $isFingerDrawingEnabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var toolbarOverlay: some View {
        ZStack {
            // Floating Toolbar (Top Center)
            VStack {
                ToolbarView(
                    selectedTool: $selectedTool,
                    strokeColor: $viewModel.currentStrokeColor,
                    strokeWidth: $viewModel.currentStrokeWidth,
                    brushType: $viewModel.currentBrushType,
                    eraserWidth: $viewModel.currentEraserWidth,
                    isDrawing: isPenToolbarCollapsed,
                    onPenTapped: {
                        isPenToolbarCollapsed.toggle()
                    },
                    onEraserTapped: {
                        isPenToolbarCollapsed.toggle()
                    },
                    onAddGraph: {
                        // Removed
                    },
                    onAskAI: {
                        if subscriptionManager.currentTier.hasAIFeatures {
                            isShowingChat.toggle()
                        } else {
                            isShowingPaywall = true
                        }
                    },
                    onImportPDF: {
                        if subscriptionManager.currentTier.hasPDFImport {
                            print("ToolbarView: Import PDF tapped")
                            isShowingDocumentPicker = true
                        } else {
                            isShowingPaywall = true
                        }
                    },
                    onImportImage: {
                        isShowingImagePicker = true
                    },
                    onToggleCalculator: {
                        isShowingCalculator.toggle()
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
                    onExport: {
                        isShowingExportOptions = true
                    },
                    onSettings: {
                        isShowingSettings = true
                    },
                    canUndo: viewModel.canUndo,
                    canRedo: viewModel.canRedo
                )
                .padding(.top, 60)
                Spacer()
            }
            .sheet(isPresented: $isShowingExportOptions) {
                ExportOptionsView(viewModel: viewModel, noteTitle: note.title)
            }
            .sheet(isPresented: $isShowingSettings) {
                NavigationView {
                    Form {
                        // Hide subscription section when bypass is enabled
                        if !kSubscriptionBypassEnabled {
                            Section(header: Text("Subscription")) {
                                SubscriptionStatusView()
                                    .environmentObject(subscriptionManager)
                            }
                        }
                        
                        Section(header: Text("Input")) {
                            Toggle("Enable Finger Drawing", isOn: $isFingerDrawingEnabled)
                        }
                        
                        Section(footer: Text("When enabled, use two fingers to scroll/pan the canvas while drawing.")) {
                            EmptyView()
                        }
                        
                        Section(header: Text("Account")) {
                            Button(action: {
                                showingSignOutAlert = true
                            }) {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                    Text("Sign Out")
                                }
                                .foregroundColor(.primary)
                            }
                            
                            Button(action: {
                                showingDeleteAccountAlert = true
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Delete Account")
                                }
                                .foregroundColor(.red)
                            }
                        }
                        
                        Section(footer: Text("Deleting your account will permanently remove all your notes and data. This action cannot be undone. Note: App Store subscriptions are managed by Apple and must be cancelled separately in Settings → Apple ID → Subscriptions.")) {
                            EmptyView()
                        }
                    }
                    .alert("Sign Out", isPresented: $showingSignOutAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("Sign Out", role: .destructive) {
                            isShowingSettings = false
                            authManager.signOut()
                        }
                    } message: {
                        Text("Are you sure you want to sign out?")
                    }
                    .alert("Delete Account", isPresented: $showingDeleteAccountAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("Delete Account", role: .destructive) {
                            isShowingSettings = false
                            authManager.deleteAccount()
                        }
                    } message: {
                        Text("Are you sure you want to delete your account? This will permanently delete all your notes and data. This action cannot be undone.\n\nNote: Your App Store subscription (if any) is tied to your Apple ID and must be cancelled separately in Settings.")
                    }
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                isShowingSettings = false
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView()
                    .environmentObject(subscriptionManager)
            }
            .onChange(of: isShowingPaywall) { newValue in
                // When paywall is dismissed, refresh subscription status
                if !newValue {
                    Task {
                        await subscriptionManager.refreshStatus()
                        print("[BlackboardView] Refreshed subscription after paywall dismissed: \(subscriptionManager.currentTier.displayName)")
                    }
                }
            }


            
            // Page Controls (Bottom Left)
            VStack {
                Spacer()
                HStack {
                    VStack(spacing: 8) {
                        Button(action: { viewModel.previousPage() }) {
                            Image(systemName: "chevron.up")
                                .padding(10)
                                .background(Color(UIColor.secondarySystemBackground))
                                .clipShape(Circle())
                        }
                        .disabled(viewModel.isFirstPage)
                        
                        Text("\(viewModel.currentPageIndex + 1)/\(viewModel.pageCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(4)
                        
                        Button(action: { viewModel.nextPage() }) {
                            Image(systemName: "chevron.down")
                                .padding(10)
                                .background(Color(UIColor.secondarySystemBackground))
                                .clipShape(Circle())
                        }
                        .disabled(viewModel.isLastPage)
                        
                        Divider()
                            .frame(width: 30)
                            .padding(.vertical, 4)
                        
                        Button(action: { viewModel.addPage() }) {
                            Image(systemName: "plus.rectangle.on.rectangle")
                                .padding(10)
                                .background(Color(UIColor.secondarySystemBackground))
                                .clipShape(Circle())
                        }
                        
                        Button(action: { viewModel.deletePage(at: viewModel.currentPageIndex) }) {
                            Image(systemName: "minus.rectangle")
                                .foregroundColor(viewModel.canDeletePage ? .red : .gray)
                                .padding(10)
                                .background(Color(UIColor.secondarySystemBackground))
                                .clipShape(Circle())
                        }
                        .disabled(!viewModel.canDeletePage)
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 100)
                    Spacer()
                }
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
            
            // Calculator Overlay
            if isShowingCalculator {
                VStack {
                    HStack {
                        CalculatorView()
                            .padding(.leading, 20)
                            .padding(.top, 100)
                        Spacer()
                    }
                    Spacer()
                }
                .transition(.move(edge: .leading))
                .zIndex(100)
            }
            
            // Status Overlay (top-left corner)
            VStack {
                HStack {
                    if kSubscriptionBypassEnabled {
                        // Show AI quota when bypass is enabled
                        HStack(spacing: 4) {
                            Image(systemName: quotaManager.canMakeRequest ? "sparkles" : "exclamationmark.triangle.fill")
                            Text("\(quotaManager.remainingQuota)/\(AIQuotaManager.dailyLimit)")
                        }
                        .font(.caption)
                        .padding(6)
                        .background(quotaManager.canMakeRequest ? Color.purple : Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    } else {
                        // Show tier badge when bypass is disabled
                        Text("Tier: \(subscriptionManager.currentTier.displayName)")
                            .font(.caption)
                            .padding(6)
                            .background(subscriptionManager.currentTier == .pro ? Color.purple : (subscriptionManager.currentTier == .basic ? Color.blue : Color.gray))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    Spacer()
                }
                .padding(.top, 50)
                .padding(.leading, 20)
                Spacer()
            }
            
            // AI Processing Indicator
            if isAIProcessing {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("AI thinking...")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.purple.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .shadow(radius: 5)
                        Spacer()
                    }
                    .padding(.bottom, 120)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: isAIProcessing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }


    
    func performAIAction(mode: GeminiService.AIMode, box: CGRect) {
        // Check AI quota before proceeding
        guard quotaManager.checkAndRecordUsage() else {
            viewModel.addText("Daily AI limit reached (\(AIQuotaManager.dailyLimit) requests). Resets at midnight.", at: CGPoint(x: box.maxX + 20, y: box.minY))
            return
        }
        
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
            Color.white // White background so black strokes are visible to AI
            ForEach(tempElements) { element in
                CanvasElementView(element: element, viewModel: viewModel, isSelected: false, onDelete: {})
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        
        let renderer = ImageRenderer(content: snapshotView)
        renderer.scale = UIScreen.main.scale
        let image = renderer.uiImage
        
        isAIProcessing = true
        
        Task {
            do {
                let response = try await geminiService.sendSelectionContext(context, image: image, mode: mode)
                let (cleanText, graphCommand) = geminiService.parseResponse(response)
                
                await MainActor.run {
                    isAIProcessing = false
                    
                    if !cleanText.isEmpty {
                        // Estimate the size of the text to be added (50% smaller)
                        let font = UIFont(name: "Caveat-Regular", size: 8) ?? .systemFont(ofSize: 8)
                        let maxConstraint = CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
                        let boundingRect = cleanText.boundingRect(
                            with: maxConstraint,
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            attributes: [.font: font],
                            context: nil
                        )
                        let estimatedSize = CGSize(
                            width: max(boundingRect.width + 15, 75),
                            height: max(boundingRect.height + 15, 30)
                        )
                        
                        // Find blank space near the selection that won't overlap other elements
                        let preferredPosition = CGPoint(x: box.maxX + 20, y: box.minY)
                        let smartPosition = viewModel.findBlankSpace(
                            near: preferredPosition,
                            size: estimatedSize,
                            excludeIds: viewModel.selectedElementIds
                        )
                        
                        // Use AI-specific method for proper sizing
                        viewModel.addAIResponseText(cleanText, at: smartPosition)
                    }
                    
                    if let command = graphCommand {
                        viewModel.addGraph(expression: command.expression, xMin: command.xMin, xMax: command.xMax)
                    }
                }
            } catch {
                await MainActor.run {
                    isAIProcessing = false
                }
                print("AI Error: \(error)")
            }
        }
    }
    
    private func handleImportedPDF(url: URL) {
        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            print("BlackboardView: Error: Could not access security scoped resource for \(url)")
            return
        }
        
        // Copy PDF data into memory BEFORE releasing security-scoped access
        // This prevents race conditions where the document becomes inaccessible
        // after the defer block executes but before PDFSelectionView renders
        var pdfData: Data?
        do {
            pdfData = try Data(contentsOf: url)
        } catch {
            print("BlackboardView: Failed to read PDF data: \(error)")
            url.stopAccessingSecurityScopedResource()
            return
        }
        
        // Now safe to release security-scoped access
        url.stopAccessingSecurityScopedResource()
        
        // Create PDFDocument from in-memory data (no longer depends on URL access)
        guard let data = pdfData, let document = PDFDocument(data: data) else {
            print("BlackboardView: Failed to create PDF document from data")
            return
        }
        
        print("BlackboardView: Successfully loaded PDF with \(document.pageCount) pages")
        
        // Setting selectedPDFDocument triggers the fullScreenCover(item:) presentation
        DispatchQueue.main.async {
            self.selectedPDFDocument = document
        }
    }
        
    // MARK: - Crop Helper
    func cropHandle(x: CGFloat, y: CGFloat, onChanged: @escaping (DragGesture.Value) -> Void) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 20, height: 20)
            .overlay(Circle().stroke(Color.teal, lineWidth: 2))
            .shadow(radius: 2)
            .position(x: x, y: y)
            .gesture(
                DragGesture()
                    .onChanged(onChanged)
            )
    }
}

// Helper to make URL Identifiable for fullScreenCover
extension URL: Identifiable {
    public var id: String { absoluteString }
}

// Make PDFDocument Identifiable for fullScreenCover(item:)
extension PDFDocument: @retroactive Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

struct ImagePicker: UIViewControllerRepresentable {
    var onImagePicked: (UIImage) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
    
}
