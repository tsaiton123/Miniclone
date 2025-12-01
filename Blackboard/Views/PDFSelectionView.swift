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
                    // Capture image from selection
                    // In a real app, we would use PDFPage.draw(with:to:) to get high-res image
                    // For now, we'll just pass the rect and a placeholder
                    let placeholder = UIImage(systemName: "doc.text")!
                    onImport(selectionRect, placeholder)
                    dismiss()
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
}
