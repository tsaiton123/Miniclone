import Foundation
import UIKit
import Vision

/// Lightweight on-device handwriting index backed by Vision OCR.
/// Extracts words from canvas page images and stores them as a JSON dictionary.
/// Zero added app size — uses the Vision framework built into iOS.
@MainActor
final class HandwritingIndexService {
    static let shared = HandwritingIndexService()
    
    // pageId (NoteItem.id.uuidString) → set of lowercased words found in that note
    private var index: [String: Set<String>] = [:]
    // pageId → raw concatenated text for snippet generation
    private var fullTextIndex: [String: String] = [:]
    // pageId → note title (for debugging)
    private var titleIndex: [String: String] = [:]
    private let indexURL: URL
    private let fullTextURL: URL
    private let titleURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        indexURL = appSupport.appendingPathComponent("handwriting_index.json")
        fullTextURL = appSupport.appendingPathComponent("handwriting_fulltext.json")
        titleURL = appSupport.appendingPathComponent("handwriting_titles.json")
        loadFromDisk()
    }
    
    /// Returns the raw OCR text for all indexed notes.
    func getFullTextIndex() -> [String: String] {
        return fullTextIndex
    }
    
    /// Returns the mapping from note ID to its original title.
    func getTitleIndex() -> [String: String] {
        // Return a index keyed by noteId (stripping _pageIndex)
        var result: [String: String] = [:]
        for (pageId, title) in titleIndex {
            let noteId = pageId.components(separatedBy: "_").first ?? pageId
            result[noteId] = title
        }
        return result
    }
    
    // MARK: - Persistence
    
    private func loadFromDisk() {
        if let data = try? Data(contentsOf: indexURL),
           let raw = try? JSONDecoder().decode([String: [String]].self, from: data) {
            index = raw.mapValues { Set($0) }
        }
        
        if let data = try? Data(contentsOf: fullTextURL),
           let raw = try? JSONDecoder().decode([String: String].self, from: data) {
            fullTextIndex = raw
        }
        
        if let data = try? Data(contentsOf: titleURL),
           let raw = try? JSONDecoder().decode([String: String].self, from: data) {
            titleIndex = raw
        }
        
        print("HandwritingIndex: loaded \(index.count) page(s) from disk")
    }
    
    private func saveToDisk() {
        let raw = index.mapValues { Array($0) }
        if let data = try? JSONEncoder().encode(raw) {
            try? data.write(to: indexURL, options: .atomic)
        }
        
        if let data = try? JSONEncoder().encode(fullTextIndex) {
            try? data.write(to: fullTextURL, options: .atomic)
        }
        
        if let data = try? JSONEncoder().encode(titleIndex) {
            try? data.write(to: titleURL, options: .atomic)
        }
    }
    
    // MARK: - Indexing
    
    /// OCR-indexes a single canvas page image for a given note.
    /// Safe to call multiple times — accumulates words across pages.
    func index(image: UIImage, pageId: String, title: String? = nil) async {
        guard let cgImage = image.cgImage else { return }
        
        let (words, fullString) = await recognizeText(in: cgImage)
        if words.isEmpty {
            print("HandwritingIndex: no text found on page for \(pageId.prefix(8))…")
            // Even if empty, we might want to keep the record to avoid "reset" deleting it
            return
        }
        
        if let title = title {
            titleIndex[pageId] = title
        }
        
        // Update index for this specific pageId (which is now noteId_pageIndex)
        index[pageId] = words
        
        // Store raw text for snippets (overwrite for this specific page)
        fullTextIndex[pageId] = fullString
        
        saveToDisk()
        print("HandwritingIndex: indexed \(words.count) word(s) for page \(pageId.prefix(8))…")
    }
    
    /// Call when a note is deleted to remove all its page index entries.
    func delete(pageId: String) {
        // pageId here is the note UUID string
        let keysToRemove = index.keys.filter { $0.hasPrefix(pageId) }
        for key in keysToRemove {
            index.removeValue(forKey: key)
            fullTextIndex.removeValue(forKey: key)
            titleIndex.removeValue(forKey: key)
        }
        saveToDisk()
    }
    
    /// Clears all page indices for a note (call before re-indexing all pages).
    func reset(pageId: String) {
        let keysToRemove = index.keys.filter { $0.hasPrefix(pageId) }
        for key in keysToRemove {
            index.removeValue(forKey: key)
            fullTextIndex.removeValue(forKey: key)
            titleIndex.removeValue(forKey: key)
        }
    }
    
    // MARK: - Search
    
    struct SearchResult {
        let pageId: String
        let score: Int
        let snippet: String?
    }
    
    /// Returns pageIds whose indexed words match the query with some tolerance.
    /// Case-insensitive. Returns results sorted by match score.
    func search(query: String) -> [SearchResult] {
        let normalizedQuery = normalizeForSearch(query)
        let queryWords = normalizedQuery
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        guard !queryWords.isEmpty else { return [] }
        
        var results: [SearchResult] = []
        for (pageId, words) in index {
            var hits = 0
            for qw in queryWords {
                // 1. Exact or substring match in any indexed word
                if words.contains(where: { $0.contains(qw) }) {
                    hits += 10 // High weight for exact/substring
                } else {
                    // 2. Fuzzy match in any indexed word
                    for word in words {
                        let distance = levenshteinDistance(s1: word, s2: qw)
                        // Tolerance: 1 error for short words, 2 for longer ones
                        let maxDist = qw.count <= 4 ? 1 : 2
                        if distance <= maxDist {
                            hits += (10 - distance) // Medium weight
                            break
                        }
                    }
                }
            }
            
            if hits > 0 {
                let snippet = generateSnippet(for: pageId, query: queryWords.first ?? "")
                results.append(SearchResult(pageId: pageId, score: hits, snippet: snippet))
            }
        }
        
        return results.sorted { $0.score > $1.score }
    }
    
    private func normalizeForSearch(_ text: String) -> String {
        return text.lowercased()
            // Math Aliasing: treat various OCR "upward" marks as exponents
            .replacingOccurrences(of: "\"", with: "^")
            .replacingOccurrences(of: "'", with: "^")
            .replacingOccurrences(of: "“", with: "^")
            .replacingOccurrences(of: "”", with: "^")
            // Other common OCR swaps
            .replacingOccurrences(of: "0", with: "o") // Normalize o/0 for fuzzy
            .replacingOccurrences(of: "1", with: "i") // Normalize i/1 for fuzzy
    }
    
    private func levenshteinDistance(s1: String, s2: String) -> Int {
        let s1Norm = normalizeForSearch(s1)
        let s2Norm = normalizeForSearch(s2)
        
        let empty = [Int](repeating: 0, count: s2Norm.count + 1)
        var last = [Int](0...s2Norm.count)
        
        for (i, char1) in s1Norm.enumerated() {
            var cur = [i + 1] + empty.dropFirst()
            for (j, char2) in s2Norm.enumerated() {
                cur[j + 1] = char1 == char2 ? last[j] : min(last[j], last[j + 1], cur[j]) + 1
            }
            last = cur
        }
        return last.last ?? 0
    }
    
    private func generateSnippet(for pageId: String, query: String) -> String? {
        guard let fullText = fullTextIndex[pageId] else { return nil }
        
        // Find the first occurrence of the query word (using fuzzy criteria for snippet start if possible)
        let lowerText = normalizeForSearch(fullText)
        let lowerQuery = normalizeForSearch(query)
        
        guard let range = lowerText.range(of: lowerQuery) else { return nil }
        
        let centerIndex = range.lowerBound
        let start = lowerText.index(centerIndex, offsetBy: -40, limitedBy: lowerText.startIndex) ?? lowerText.startIndex
        let end = lowerText.index(centerIndex, offsetBy: 60, limitedBy: lowerText.endIndex) ?? lowerText.endIndex
        
        var snippet = String(fullText[start..<end])
        if start > lowerText.startIndex { snippet = "..." + snippet }
        if end < lowerText.endIndex { snippet = snippet + "..." }
        
        return snippet.replacingOccurrences(of: "\n", with: " ")
    }
    
    // MARK: - Private
    
    private func recognizeText(in cgImage: CGImage) async -> (Set<String>, String) {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                var words: Set<String> = []
                var fullString = ""
                
                for obs in observations {
                    guard let top = obs.topCandidates(1).first else { continue }
                    let line = top.string
                    fullString += line + " "
                    
                    // For the index, we store normalized tokens but keep special chars like '=' and '^'
                    line.components(separatedBy: .whitespacesAndNewlines)
                        .filter { $0.count >= 1 }
                        .forEach { words.insert(self.normalizeForSearch($0)) }
                }
                continuation.resume(returning: (words, fullString.trimmingCharacters(in: .whitespaces)))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}
