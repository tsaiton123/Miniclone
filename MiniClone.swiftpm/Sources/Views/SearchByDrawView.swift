import SwiftUI
import PencilKit

struct SearchByDrawView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.appTheme) private var appTheme
    @State private var canvasView = PKCanvasView()
    @State private var isSearching = false
    @State private var strokeCount = 0
    @State private var searchResults: [DrawSearchResult] = []
    @State private var hasSearched = false
    @State private var noMatchesFound = false
    
    /// Similarity threshold — results with distance above this are filtered out.
    /// Distance is 0-1: 0 = identical, 1 = completely different.
    private let distanceThreshold: Float = 1.0
    
    /// Note title lookup: noteId UUID string -> title
    var noteNames: [String: String]
    /// Called when the user taps a result to navigate
    var onNavigate: (String, Int) -> Void
    
    struct DrawSearchResult: Identifiable {
        let id = UUID()
        let noteId: String
        let noteTitle: String
        let pageIndex: Int
        let similarity: Int // 0-100%
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if hasSearched {
                    // Results View
                    resultsView
                } else {
                    // Drawing View
                    drawingView
                }
            }
            .navigationTitle(hasSearched ? "Results" : "Search by Draw")
            .navigationBarItems(
                leading: hasSearched ? Button("Back") {
                    hasSearched = false
                    noMatchesFound = false
                    searchResults = []
                    isSearching = false
                } : nil,
                trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .background(Color(UIColor.systemGroupedBackground))
        }
    }
    
    // MARK: - Drawing View
    
    private var drawingView: some View {
        VStack(spacing: 0) {
            Text("Draw what you're looking for")
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
            
            GeometryReader { geometry in
                CanvasRepresentable(canvasView: $canvasView, strokeCount: $strokeCount)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                    .padding()
            }
            
            HStack(spacing: 20) {
                Button(action: {
                    canvasView.drawing = PKDrawing()
                    strokeCount = 0
                }) {
                    Text("Clear")
                        .font(.headline)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                }
                
                Button(action: { performSearch() }) {
                    HStack {
                        if isSearching {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text("Search")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(strokeCount == 0 ? Color.gray : appTheme.accentColor)
                    .cornerRadius(10)
                }
                .disabled(strokeCount == 0 || isSearching)
            }
            .padding()
        }
    }
    
    // MARK: - Results View
    
    private var resultsView: some View {
        VStack(spacing: 0) {
            if noMatchesFound {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("No Matches Found")
                        .font(.title2.bold())
                    Text("Try drawing a simpler or more distinct shape.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else {
                // Results header
                HStack {
                    Text("\(searchResults.count) match\(searchResults.count == 1 ? "" : "es") found")
                        .font(.headline)
                    Spacer()
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(searchResults) { result in
                            Button(action: {
                                presentationMode.wrappedValue.dismiss()
                                // Small delay to let the sheet dismiss before navigating
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    onNavigate(result.noteId, result.pageIndex)
                                }
                            }) {
                                HStack(spacing: 16) {
                                    // Icon
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(appTheme.accentColor.opacity(0.15))
                                            .frame(width: 50, height: 50)
                                        Image(systemName: "doc.text")
                                            .font(.title2)
                                            .foregroundColor(appTheme.accentColor)
                                    }
                                    
                                    // Note info
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(result.noteTitle)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text("Page \(result.pageIndex + 1)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    // Similarity badge
                                    Text("\(result.similarity)%")
                                        .font(.system(.body, design: .rounded).bold())
                                        .foregroundColor(similarityColor(result.similarity))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(similarityColor(result.similarity).opacity(0.15))
                                        )
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func similarityColor(_ percent: Int) -> Color {
        if percent >= 80 { return .green }
        if percent >= 60 { return .orange }
        return .red
    }
    
    private func performSearch() {
        isSearching = true
        
        let drawing = canvasView.drawing
        print("[DEBUG-DRAW] performSearch() called. Stroke count: \(drawing.strokes.count)")
        
        let bounds = drawing.bounds
        let size = CGSize(width: max(bounds.width, 200) + 40, height: max(bounds.height, 200) + 40)
        let rect = CGRect(origin: .zero, size: size)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(rect)
            let offsetX = (size.width - bounds.width) / 2 - bounds.origin.x
            let offsetY = (size.height - bounds.height) / 2 - bounds.origin.y
            context.cgContext.translateBy(x: offsetX, y: offsetY)
            drawing.image(from: drawing.bounds, scale: 2.0).draw(in: drawing.bounds)
        }
        
        print("[DEBUG-DRAW] ✅ Image rendered: \(image.size.width)x\(image.size.height)")
        
        Task {
            do {
                let results = try await ImageMatchingService.shared.search(queryImage: image)
                
                // Filter by threshold and map to display results
                let filtered = results
                    .filter { $0.distance < distanceThreshold }
                    .prefix(5) // Show top 5 at most
                    .map { result -> DrawSearchResult in
                        let components = result.pageId.components(separatedBy: "_")
                        let noteId = components.first ?? result.pageId
                        let pageIndex = components.count > 1 ? (Int(components[1]) ?? 0) : 0
                        let title = noteNames[noteId] ?? "Unknown Note"
                        let similarity = max(0, min(100, Int((1.0 - result.distance) * 100)))
                        return DrawSearchResult(
                            noteId: noteId,
                            noteTitle: title,
                            pageIndex: pageIndex,
                            similarity: similarity
                        )
                    }
                
                print("[DEBUG-DRAW] \(results.count) raw result(s), \(filtered.count) above threshold")
                
                await MainActor.run {
                    searchResults = Array(filtered)
                    noMatchesFound = filtered.isEmpty
                    hasSearched = true
                    isSearching = false
                }
            } catch {
                print("[DEBUG-DRAW] ⚠️ Search error: \(error)")
                await MainActor.run {
                    noMatchesFound = true
                    hasSearched = true
                    isSearching = false
                }
            }
        }
    }
}

// UIKit PKCanvasView wrapper
struct CanvasRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var strokeCount: Int
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 5)
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.delegate = context.coordinator
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasRepresentable
        
        init(_ parent: CanvasRepresentable) {
            self.parent = parent
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            DispatchQueue.main.async {
                self.parent.strokeCount = canvasView.drawing.strokes.count
            }
        }
    }
}
