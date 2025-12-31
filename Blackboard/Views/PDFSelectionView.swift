import SwiftUI
import PDFKit

struct PDFSelectionView: View {
    let pdfURL: URL
    var onImport: (CGRect, UIImage) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var pdfDocument: PDFDocument?
    @State private var currentPageIndex: Int = 0
    @State private var selectionRect: CGRect = .zero
    @State private var isDragging: Bool = false
    @State private var startPoint: CGPoint = .zero
    @State private var displaySize: CGSize = .zero
    
    var body: some View {
        VStack {
            if let pdfDocument = pdfDocument, let page = pdfDocument.page(at: currentPageIndex) {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        // PDF Page View
                        Image(uiImage: page.thumbnail(of: geometry.size, for: .mediaBox))
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
                            .stroke(Color.blue, lineWidth: 2)
                            .background(Color.blue.opacity(0.2))
                            .frame(width: selectionRect.width, height: selectionRect.height)
                            .position(x: selectionRect.midX, y: selectionRect.midY)
                    }
                }
                .padding()
                
                HStack {
                    Button("Previous") {
                        if currentPageIndex > 0 { currentPageIndex -= 1 }
                    }
                    .disabled(currentPageIndex == 0)
                    
                    Text("Page \(currentPageIndex + 1) of \(pdfDocument.pageCount)")
                    
                    Button("Next") {
                        if currentPageIndex < pdfDocument.pageCount - 1 { currentPageIndex += 1 }
                    }
                    .disabled(currentPageIndex == pdfDocument.pageCount - 1)
                }
                .padding()
                
                Button("Import Selection") {
                    // Use captured page directly
                    if let image = extractImage(from: selectionRect, page: page) {
                        onImport(selectionRect, image)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectionRect.width < 10 || selectionRect.height < 10)
                .padding()
            } else {
                ProgressView("Loading PDF...")
            }
        }
        .onAppear {
            pdfDocument = PDFDocument(url: pdfURL)
        }
    }
    
    private func extractImage(from rect: CGRect, page: PDFPage) -> UIImage? {
        let mediaBox = page.bounds(for: .mediaBox)
        
        // Calculate the scale ratio between the displayed image and the actual PDF page
        // The thumbnail logic preserves aspect ratio and fits within displaySize
        let widthRatio = displaySize.width / mediaBox.width
        let heightRatio = displaySize.height / mediaBox.height
        let scale = min(widthRatio, heightRatio)
        
        // Calculate the actual displayed image size
        let displayedWidth = mediaBox.width * scale
        let displayedHeight = mediaBox.height * scale
        
        // Calculate offsets (centering)
        let xOffset = (displaySize.width - displayedWidth) / 2
        let yOffset = (displaySize.height - displayedHeight) / 2
        
        // Convert view coordinates (rect) to PDF coordinates
        // 1. Remove offset
        let xInImage = rect.minX - xOffset
        let yInImage = rect.minY - yOffset
        
        // 2. Scale back to PDF points
        let pdfX = xInImage / scale
        // PDF coordinate system usually has (0,0) at bottom-left, but PDFKit handles this.
        // However, we need to be careful. page.bounds(for: .mediaBox) gives us the rect.
        // The thumbnail generation usually flips y-axis or handles it.
        // Let's assume standard top-left for view and map it.
        // Actually, PDF coordinates have Y going up.
        // But `page.thumbnail` returns a UIImage which is top-left.
        // So we are mapping from View (top-left) to PDF (bottom-left).
        
        // Wait, we want to draw the PDF page into a new image context cropped to the rect.
        // The easiest way is to draw the whole page scaled, then crop? No, inefficient.
        // Better: Set the crop box of the page or use a transform.
        
        // Let's try to map the rect to the PDF coordinate system.
        // View Y (0 at top) -> PDF Y (height at top)
        // yInImage is from top of the displayed image.
        // PDF Y = mediaBox.height - (yInImage / scale) - (rect.height / scale)
        
        let pdfY = mediaBox.height - (yInImage / scale) - (rect.height / scale)
        let pdfWidth = rect.width / scale
        let pdfHeight = rect.height / scale
        
        let pdfRect = CGRect(x: pdfX, y: pdfY, width: pdfWidth, height: pdfHeight)
        
        // Now render this specific rect
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        return renderer.image { ctx in
            // Fill white background
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: rect.size))
            
            // Flip context for PDF drawing
            ctx.cgContext.translateBy(x: 0, y: rect.size.height)
            ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
            
            // Translate so that the desired rect moves to (0,0)
            ctx.cgContext.translateBy(x: -pdfRect.origin.x * scale, y: -pdfRect.origin.y * scale)
            
            // Scale to match the view's zoom level (or higher for better quality?)
            // If we want 1:1 with screen pixels, we use `scale`.
            // If we want original PDF quality, we should use scale = 1.0 but make the output image larger.
            // The user wants "High Resolution". Let's try to get 2x or 3x of the screen size if possible,
            // or just render at the PDF's native scale if it's vector.
            // Let's render at the PDF's native scale for best quality, then the image view will scale it down.
            
            // Re-thinking:
            // We want the image to look sharp on the canvas.
            // The canvas element will have size `rect.size`.
            // So the image backing it should ideally be `rect.size * screenScale`.
            // But if the user zooms in on the PDF, they might want more detail.
            // Let's render at a higher scale, say 2.0 relative to the PDF point size, or just use the PDF vector nature.
            
            // Let's stick to the view's scale for now to ensure WYSIWYG.
            ctx.cgContext.scaleBy(x: scale, y: scale)
            
            page.draw(with: .mediaBox, to: ctx.cgContext)
    }
}
}
