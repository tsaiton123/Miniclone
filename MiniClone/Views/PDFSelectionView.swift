import SwiftUI
import PDFKit

struct PDFSelectionView: View {
    let pdfDocument: PDFDocument
    var onImport: (CGRect, UIImage) -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.appTheme) private var appTheme
    @State private var currentPageIndex: Int = 0
    @State private var selectionRect: CGRect = .zero
    @State private var isDragging: Bool = false
    @State private var startPoint: CGPoint = .zero
    @State private var currentGeometrySize: CGSize = .zero
    
    var body: some View {
        VStack {
            if let page = pdfDocument.page(at: currentPageIndex) {
                GeometryReader { geometry in
                    let thumbnailImage = page.thumbnail(of: geometry.size, for: .mediaBox)
                    
                    ZStack(alignment: .topLeading) {
                        // PDF Page View
                        Image(uiImage: thumbnailImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if !isDragging {
                                            startPoint = value.startLocation
                                            isDragging = true
                                        }
                                        
                                        let currentPoint = value.location
                                        let x = min(startPoint.x, currentPoint.x)
                                        let y = min(startPoint.y, currentPoint.y)
                                        let width = abs(currentPoint.x - startPoint.x)
                                        let height = abs(currentPoint.y - startPoint.y)
                                        
                                        selectionRect = CGRect(x: x, y: y, width: width, height: height)
                                    }
                                    .onEnded { _ in
                                        isDragging = false
                                    }
                            )
                        
                        // Selection Overlay
                        Rectangle()
                            .stroke(appTheme.accentColor, lineWidth: 2)
                            .background(appTheme.accentColor.opacity(0.2))
                            .frame(width: selectionRect.width, height: selectionRect.height)
                            .position(x: selectionRect.midX, y: selectionRect.midY)
                    }
                    .onAppear {
                        currentGeometrySize = geometry.size
                    }
                    .onChange(of: geometry.size) { newSize in
                        currentGeometrySize = newSize
                    }
                }
                .padding()
                
                HStack {
                    Button("Previous") {
                        if currentPageIndex > 0 { 
                            currentPageIndex -= 1 
                            selectionRect = .zero
                        }
                    }
                    .disabled(currentPageIndex == 0)
                    
                    Text("Page \(currentPageIndex + 1) of \(pdfDocument.pageCount)")
                    
                    Button("Next") {
                        if currentPageIndex < pdfDocument.pageCount - 1 { 
                            currentPageIndex += 1 
                            selectionRect = .zero
                        }
                    }
                    .disabled(currentPageIndex == pdfDocument.pageCount - 1)
                }
                .padding()
                
                Button("Import Selection") {
                    if let image = extractImage(from: selectionRect, page: page) {
                        print("PDFSelectionView: Extracted image size: \(image.size)")
                        onImport(selectionRect, image)
                        dismiss()
                    } else {
                        print("PDFSelectionView: Failed to extract image")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectionRect.width < 10 || selectionRect.height < 10)
                .padding()
            } else {
                Text("No pages available")
                    .foregroundColor(.gray)
            }
        }
    }
    
    private func extractImage(from rect: CGRect, page: PDFPage) -> UIImage? {
        // Use a high-resolution render of the PDF page
        let renderScale: CGFloat = 2.0 // Render at 2x for better quality
        
        // Calculate the actual displayed size of the thumbnail within the geometry
        let mediaBox = page.bounds(for: .mediaBox)
        let aspectRatio = mediaBox.width / mediaBox.height
        
        var displayedWidth: CGFloat
        var displayedHeight: CGFloat
        
        if currentGeometrySize.width / currentGeometrySize.height > aspectRatio {
            // Height constrained
            displayedHeight = currentGeometrySize.height
            displayedWidth = displayedHeight * aspectRatio
        } else {
            // Width constrained
            displayedWidth = currentGeometrySize.width
            displayedHeight = displayedWidth / aspectRatio
        }
        
        // Calculate offset (the thumbnail is centered in the geometry)
        let xOffset = (currentGeometrySize.width - displayedWidth) / 2
        let yOffset = (currentGeometrySize.height - displayedHeight) / 2
        
        // Adjust selection rect to be relative to the actual thumbnail
        let adjustedRect = CGRect(
            x: rect.minX - xOffset,
            y: rect.minY - yOffset,
            width: rect.width,
            height: rect.height
        )
        
        // Clamp to valid bounds
        let clampedRect = adjustedRect.intersection(CGRect(x: 0, y: 0, width: displayedWidth, height: displayedHeight))
        
        guard clampedRect.width > 0 && clampedRect.height > 0 else {
            print("PDFSelectionView: Selection outside of PDF bounds")
            return nil
        }
        
        // Calculate the scale from display coordinates to PDF coordinates
        let displayToPDFScale = mediaBox.width / displayedWidth
        
        // Convert to PDF coordinates (flip Y axis for PDF coordinate system)
        let pdfRect = CGRect(
            x: clampedRect.minX * displayToPDFScale,
            y: mediaBox.height - (clampedRect.maxY * displayToPDFScale),
            width: clampedRect.width * displayToPDFScale,
            height: clampedRect.height * displayToPDFScale
        )
        
        // Render the PDF region at high resolution
        let outputSize = CGSize(
            width: clampedRect.width * renderScale,
            height: clampedRect.height * renderScale
        )
        
        let renderer = UIGraphicsImageRenderer(size: outputSize)
        return renderer.image { ctx in
            // Fill white background
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: outputSize))
            
            // Set up the transform to render just the selected portion
            let scaleX = outputSize.width / pdfRect.width
            let scaleY = outputSize.height / pdfRect.height
            
            // Flip Y axis for Core Graphics
            ctx.cgContext.translateBy(x: 0, y: outputSize.height)
            ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
            
            // Scale and translate to show only the selected region
            ctx.cgContext.scaleBy(x: scaleX, y: scaleY)
            ctx.cgContext.translateBy(x: -pdfRect.origin.x, y: -pdfRect.origin.y)
            
            // Draw the PDF page
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }
}
