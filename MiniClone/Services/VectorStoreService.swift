import Foundation
import CoreGraphics

/// A lightweight on-device vector store backed by a binary index file.
/// Embeddings are L2-normalised, so cosine similarity reduces to a Dot Product.
class VectorStoreService {
    static let shared = VectorStoreService()
    
    private let queue = DispatchQueue(label: "io.miniclone.vectorstore", qos: .utility)
    private var records: [NoteEmbeddingRecord] = []
    private let indexURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("MobileCLIPVectorDB", isDirectory: true)
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        indexURL = dbDir.appendingPathComponent("embeddings.json")
        loadFromDisk()
    }
    
    // MARK: - Persistence
    
    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([NoteEmbeddingRecord].self, from: data) else { return }
        records = decoded
        print("VectorStoreService: Loaded \(records.count) embeddings from disk.")
    }
    
    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
    
    // MARK: - Write
    
    /// Persists a single embedding tile for a note page.
    @discardableResult
    func insert(embedding: [Float], pageId: String, tileRect: CGRect) -> UUID {
        let record = NoteEmbeddingRecord(pageId: pageId, tileRect: tileRect, embedding: embedding)
        queue.sync {
            records.append(record)
            saveToDisk()
        }
        return record.id
    }
    
    /// Removes all tiles for a given page, e.g. before re-indexing.
    func delete(pageId: String) {
        queue.sync {
            records.removeAll { $0.pageId == pageId }
            saveToDisk()
        }
    }
    
    // MARK: - Search
    
    /// Returns up to `limit` nearest neighbours via Dot Product similarity.
    /// Since embeddings are L2-normalised, this equals cosine similarity.
    /// Results are sorted highest-score-first (1.0 = identical, 0.0 = orthogonal).
    func nearestNeighbors(to queryVector: [Float], limit: Int = 10) -> [(NoteEmbeddingRecord, Float)] {
        var snapshot: [NoteEmbeddingRecord] = []
        queue.sync { snapshot = records }
        
        let scored: [(NoteEmbeddingRecord, Float)] = snapshot.map { record in
            let score = dotProduct(queryVector, record.embedding)
            return (record, score)
        }
        
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0 }
    }
    
    // MARK: - Helpers
    
    func allRecords() -> [NoteEmbeddingRecord] {
        queue.sync { records }
    }
    
    func count() -> Int {
        queue.sync { records.count }
    }
    
    private func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        let length = min(a.count, b.count)
        var result: Float = 0
        for i in 0..<length {
            result += a[i] * b[i]
        }
        return result
    }
}
