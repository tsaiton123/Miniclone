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
    private let distanceThreshold: Float = 1.0
    
    /// Note title lookup: noteId UUID string -> title
    var noteNames: [String: String]
    /// Pre-populated results (used when re-opening after viewing a note)
    var initialResults: [DrawSearchResult]
    /// Binding to share results with parent so they can be cached
    @Binding var sharedResults: [DrawSearchResult]
    /// Called when a result is tapped — caller handles navigation
    var onSelectResult: (String, Int) -> Void
    
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
                    resultsView
                } else {
                    drawingView
                }
            }
            .navigationTitle(hasSearched ? "Results" : "Search by Draw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if hasSearched {
                        Button("Back") {
                            hasSearched = false
                            noMatchesFound = false
                            searchResults = []
                            isSearching = false
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .background(appTheme.editorialBackground)
        }
        .onAppear {
            // If we have cached results (re-opened after viewing a note), show them immediately
            if !initialResults.isEmpty {
                searchResults = initialResults
                hasSearched = true
                noMatchesFound = false
            }
        }
    }
    
    // MARK: - Drawing View
    
    private var drawingView: some View {
        VStack(spacing: 0) {
            Text("DRAW WHAT YOU'RE LOOKING FOR")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(appTheme.accentColor.opacity(0.7))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(appTheme.editorialBackground)
            
            GeometryReader { geometry in
                CanvasRepresentable(canvasView: $canvasView, strokeCount: $strokeCount)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                    .overlay(
                        Rectangle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
                    .padding()
            }
            
            HStack(spacing: 16) {
                Button(action: {
                    canvasView.drawing = PKDrawing()
                    strokeCount = 0
                }) {
                    Text("Clear")
                        .font(.system(size: 14, weight: .medium))
                        .tracking(0.3)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(
                            Rectangle()
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                }
                
                Button(action: { performSearch() }) {
                    HStack {
                        if isSearching {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13))
                        }
                        Text("Search")
                            .font(.system(size: 14, weight: .medium))
                            .tracking(0.3)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(strokeCount == 0 ? Color.gray : appTheme.accentColor)
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
                        .font(.system(size: 40))
                        .foregroundColor(appTheme.accentColor.opacity(0.4))
                    Text("No Matches Found")
                        .font(.system(size: 22, weight: .regular, design: .serif))
                    Text("Try drawing a simpler or more distinct shape.")
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else {
                // Results header
                HStack {
                    Text("\(searchResults.count) MATCH\(searchResults.count == 1 ? "" : "ES") FOUND")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(appTheme.accentColor.opacity(0.7))
                    Spacer()
                }
                .padding()
                .background(appTheme.editorialBackground)
                
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(searchResults) { result in
                            Button(action: {
                                // Share current results with parent before navigating
                                sharedResults = searchResults
                                onSelectResult(result.noteId, result.pageIndex)
                            }) {
                                HStack(spacing: 16) {
                                    ZStack {
                                        Rectangle()
                                            .fill(appTheme.accentColor.opacity(0.08))
                                            .frame(width: 48, height: 48)
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 20))
                                            .foregroundColor(appTheme.accentColor)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(result.noteTitle)
                                            .font(.system(size: 16, weight: .regular, design: .serif))
                                            .foregroundColor(.primary)
                                        Text("Page \(result.pageIndex + 1)")
                                            .font(.system(size: 12, weight: .light))
                                            .foregroundColor(.secondary)
                                        
                                        // Heatmap gradient bar
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Rectangle()
                                                    .fill(Color.gray.opacity(0.12))
                                                    .frame(height: 4)
                                                
                                                Rectangle()
                                                    .fill(
                                                        LinearGradient(
                                                            colors: heatmapGradient(for: result.similarity),
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                                    .frame(width: geo.size.width * CGFloat(result.similarity) / 100.0, height: 4)
                                            }
                                        }
                                        .frame(height: 4)
                                    }
                                    
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(appTheme.accentColor)
                                }
                                .padding(16)
                                .background(Color.white)
                                .overlay(
                                    Rectangle()
                                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
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
    
    /// Returns gradient colors for the heatmap bar based on similarity percentage.
    /// Red → Orange → Yellow → Green as similarity increases.
    private func heatmapGradient(for percent: Int) -> [Color] {
        if percent >= 80 {
            return [Color(hue: 0.25, saturation: 0.7, brightness: 0.85),
                    Color(hue: 0.35, saturation: 0.8, brightness: 0.9)]  // Green
        } else if percent >= 60 {
            return [Color(hue: 0.1, saturation: 0.8, brightness: 0.95),
                    Color(hue: 0.2, saturation: 0.75, brightness: 0.9)]  // Yellow-Green
        } else if percent >= 40 {
            return [Color(hue: 0.05, saturation: 0.85, brightness: 0.95),
                    Color(hue: 0.12, saturation: 0.8, brightness: 0.95)] // Orange-Yellow
        } else {
            return [Color(hue: 0.0, saturation: 0.75, brightness: 0.9),
                    Color(hue: 0.05, saturation: 0.8, brightness: 0.95)] // Red-Orange
        }
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
                
                let filtered = results
                    .filter { $0.distance < distanceThreshold }
                    .prefix(5)
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
                    sharedResults = Array(filtered)
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
