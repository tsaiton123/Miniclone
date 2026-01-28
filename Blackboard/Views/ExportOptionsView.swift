import SwiftUI

/// A simplified view for rendering canvas elements during export (without selection state)
struct ExportElementView: View {
    let element: CanvasElementData
    let imageCache: [UUID: UIImage]
    
    var body: some View {
        ZStack {
            switch element.data {
            case .text(let data):
                Text(data.text)
                    .font(.custom(data.fontFamily, size: data.fontSize))
                    .foregroundColor(Color(hex: data.color))
                
            case .graph(let data):
                GraphShape(data: data)
                    .stroke(Color(hex: data.color), lineWidth: 2)
                

                
            case .bitmapInk(let data):
                if let cachedImage = imageCache[element.id] {
                    Image(uiImage: cachedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if let uiImage = UIImage(data: Data(base64Encoded: data.src) ?? Data()) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                }

            case .image(let data):
                if let cachedImage = imageCache[element.id] {
                    Image(uiImage: cachedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if let uiImage = UIImage(data: Data(base64Encoded: data.src) ?? Data()) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                }
                
            case .stroke(let data):
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
        }
        .frame(width: element.width, height: element.height)
        .position(x: element.x + element.width/2, y: element.y + element.height/2)
    }
}

enum ExportFormat: String, CaseIterable {
    case pdf = "PDF"
    case image = "Image"
    
    var icon: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        }
    }
}

enum ExportScope: String, CaseIterable {
    case currentPage = "Current Page"
    case allPages = "All Pages"
    
    var icon: String {
        switch self {
        case .currentPage: return "doc"
        case .allPages: return "doc.on.doc"
        }
    }
}

struct ExportOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: CanvasViewModel
    let noteTitle: String
    
    @State private var selectedFormat: ExportFormat = .pdf
    @State private var selectedScope: ExportScope = .currentPage
    @State private var fileName: String = ""
    @State private var isExporting = false
    @State private var exportItems: [Any] = []
    @State private var isShowingShareSheet = false
    
    init(viewModel: CanvasViewModel, noteTitle: String) {
        self.viewModel = viewModel
        self.noteTitle = noteTitle
    }
    
    private var defaultFileName: String {
        let sanitizedTitle = noteTitle.isEmpty ? "Canvas" : noteTitle
        if selectedScope == .currentPage {
            return "\(sanitizedTitle)-Page\(viewModel.currentPageIndex + 1)"
        } else {
            return sanitizedTitle
        }
    }
    
    private var effectiveFileName: String {
        fileName.isEmpty ? defaultFileName : fileName
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Preview
                previewSection
                
                // File Name
                fileNameSection
                
                // Format Selection
                formatSection
                
                // Scope Selection
                scopeSection
                
                // Export Button
                exportButton
                
                Spacer()
            }
            .padding()
            .navigationTitle("Export Canvas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingShareSheet) {
                ShareSheet(items: exportItems)
            }
            .onChange(of: selectedScope) { _ in
                // Reset custom filename when scope changes so default updates
                if !fileName.isEmpty {
                    fileName = ""
                }
            }
        }
    }
    
    private var fileNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("File Name")
                .font(.headline)
                .foregroundColor(.secondary)
            
            HStack {
                TextField(defaultFileName, text: $fileName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Text(selectedFormat == .pdf ? ".pdf" : ".png")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }
            
            if fileName.isEmpty {
                Text("Default: \(defaultFileName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if let previewImage = viewModel.renderPageToImage(pageIndex: viewModel.currentPageIndex) {
                Image(uiImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .cornerRadius(8)
                    .shadow(radius: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 150)
                    .cornerRadius(8)
                    .overlay(Text("Preview unavailable"))
            }
            
            // Page info
            HStack {
                Text("Page \(viewModel.currentPageIndex + 1) of \(viewModel.pageCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }
    
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Format")
                .font(.headline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Button(action: { selectedFormat = format }) {
                        HStack {
                            Image(systemName: format.icon)
                            Text(format.rawValue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selectedFormat == format ? Color.blue : Color(UIColor.secondarySystemBackground))
                        .foregroundColor(selectedFormat == format ? .white : .primary)
                        .cornerRadius(10)
                    }
                }
            }
        }
    }
    
    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export Scope")
                .font(.headline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                ForEach(ExportScope.allCases, id: \.self) { scope in
                    Button(action: { selectedScope = scope }) {
                        HStack {
                            Image(systemName: scope.icon)
                            Text(scope.rawValue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selectedScope == scope ? Color.blue : Color(UIColor.secondarySystemBackground))
                        .foregroundColor(selectedScope == scope ? .white : .primary)
                        .cornerRadius(10)
                    }
                }
            }
            
            // Info text
            Text(selectedScope == .currentPage
                 ? "Exports only the current page (\(viewModel.currentPageIndex + 1))"
                 : "Exports all \(viewModel.pageCount) page\(viewModel.pageCount > 1 ? "s" : "")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var exportButton: some View {
        Button(action: performExport) {
            HStack {
                if isExporting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
                Text(isExporting ? "Exporting..." : "Export")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isExporting ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
            .font(.headline)
        }
        .disabled(isExporting)
    }
    
    private func performExport() {
        isExporting = true
        let exportFileName = effectiveFileName
        
        DispatchQueue.global(qos: .userInitiated).async {
            var items: [Any] = []
            
            switch selectedFormat {
            case .pdf:
                if let pdfData = selectedScope == .currentPage
                    ? viewModel.exportCurrentPageToPDF()
                    : viewModel.exportAllPagesToPDF() {
                    // Create a temporary file with the user-defined name
                    let fileName = "\(exportFileName).pdf"
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                    try? pdfData.write(to: tempURL)
                    items.append(tempURL)
                }
                
            case .image:
                if selectedScope == .currentPage {
                    if let image = viewModel.renderPageToImage(pageIndex: viewModel.currentPageIndex) {
                        // For single image, create a temporary file with the user-defined name
                        let fileName = "\(exportFileName).png"
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                        if let pngData = image.pngData() {
                            try? pngData.write(to: tempURL)
                            items.append(tempURL)
                        }
                    }
                } else {
                    // For multiple images, add page numbers to each
                    let images = viewModel.renderAllPagesToImages()
                    for (index, image) in images.enumerated() {
                        let fileName = "\(exportFileName)-Page\(index + 1).png"
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                        if let pngData = image.pngData() {
                            try? pngData.write(to: tempURL)
                            items.append(tempURL)
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                isExporting = false
                if !items.isEmpty {
                    exportItems = items
                    isShowingShareSheet = true
                }
            }
        }
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
