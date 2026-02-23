import Foundation
import CoreGraphics
import Combine

/// A single semantic search result linking a near-match embedding back to its note.
struct SemanticSearchResult: Identifiable {
    let id: UUID           // embedding record id
    let pageId: String     // maps to NoteItem.id.uuidString
    let score: Float       // cosine similarity (0…1, higher = more similar)
    let tileRect: CGRect   // tile region that matched inside the page
}

/// Debounces the search query, runs MobileCLIP text encoding, and surfaces the
/// top nearest-neighbour results from VectorStoreService.
@MainActor
final class SemanticSearchService: ObservableObject {
    @Published var results: [SemanticSearchResult] = []
    @Published var isSearching: Bool = false
    
    private var debounceTask: Task<Void, Never>?
    private let debounceDelay: UInt64 = 350_000_000 // 350 ms in nanoseconds
    private let minQueryLength = 3
    private let resultLimit = 8
    
    /// Call this whenever the search text changes.
    func search(query: String) {
        debounceTask?.cancel()
        
        guard query.count >= minQueryLength else {
            results = []
            isSearching = false
            return
        }
        
        debounceTask = Task {
            // Debounce: wait before firing
            try? await Task.sleep(nanoseconds: debounceDelay)
            guard !Task.isCancelled else {
                print("SemanticSearch: task cancelled during debounce")
                return
            }
            
            isSearching = true
            defer { isSearching = false }
            
            do {
                // 1. Check how many records are stored
                let recordCount = VectorStoreService.shared.count()
                print("SemanticSearch: VectorStore has \(recordCount) record(s)")
                
                // 2. Encode query text
                print("SemanticSearch: encoding query '\(query)'...")
                let queryVector = try await CLIPService.shared.encode(text: query)
                print("SemanticSearch: query encoded → \(queryVector.count)-d vector, first5=\(Array(queryVector.prefix(5)).map { String(format: "%.3f", $0) })")
                
                guard !Task.isCancelled else { return }
                
                if recordCount == 0 {
                    print("SemanticSearch: no records in store — please open the note and go back to trigger indexing")
                    results = []
                    return
                }
                
                // 3. Nearest-neighbour lookup
                let matches = VectorStoreService.shared.nearestNeighbors(to: queryVector, limit: resultLimit)
                print("SemanticSearch: \(matches.count) match(es) returned, scores: \(matches.map { String(format: "%.3f", $0.1) })")
                
                // 4. De-duplicate by pageId — NO score filter so we can see everything
                var seen: [String: SemanticSearchResult] = [:]
                for (record, score) in matches {
                    if seen[record.pageId] == nil || score > seen[record.pageId]!.score {
                        seen[record.pageId] = SemanticSearchResult(
                            id: record.id,
                            pageId: record.pageId,
                            score: score,
                            tileRect: record.tileRect
                        )
                    }
                }
                
                let sorted = seen.values.sorted { $0.score > $1.score }
                print("SemanticSearch: final \(sorted.count) unique result(s): \(sorted.map { "\($0.pageId.prefix(8))…=\(String(format: "%.3f", $0.score))" })")
                results = sorted
            } catch {
                print("SemanticSearch: ERROR — \(error)")
                results = []
            }
        }
    }
    
    func clear() {
        debounceTask?.cancel()
        results = []
        isSearching = false
    }
}
