import Foundation
import SwiftUI

// MARK: - Page Data Structure
struct PageData: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var elements: [CanvasElementData]
    
    init(id: UUID = UUID(), elements: [CanvasElementData] = []) {
        self.id = id
        self.elements = elements
    }
}

// MARK: - Canvas Data Structure (Multi-Page)
struct CanvasData: Codable {
    var version: String = "1.1"
    var savedAt: Date = Date()
    var pages: [PageData]
    var currentPageIndex: Int = 0
    
    // Default initializer
    init(pages: [PageData] = [PageData(elements: [])], currentPageIndex: Int = 0) {
        self.pages = pages.isEmpty ? [PageData(elements: [])] : pages
        self.currentPageIndex = currentPageIndex
    }
    
    // Migration initializer for old format
    init(elements: [CanvasElementData]) {
        self.pages = [PageData(elements: elements)]
        self.currentPageIndex = 0
    }
    
    // Custom decoding for backward compatibility
    enum CodingKeys: String, CodingKey {
        case version, savedAt, pages, currentPageIndex, elements
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        version = (try? container.decode(String.self, forKey: .version)) ?? "1.0"
        savedAt = (try? container.decode(Date.self, forKey: .savedAt)) ?? Date()
        currentPageIndex = (try? container.decode(Int.self, forKey: .currentPageIndex)) ?? 0
        
        // Try new multi-page format first
        if let decodedPages = try? container.decode([PageData].self, forKey: .pages), !decodedPages.isEmpty {
            pages = decodedPages
        } else if let elements = try? container.decode([CanvasElementData].self, forKey: .elements) {
            // Migrate from old single-page format
            pages = [PageData(elements: elements)]
        } else {
            // Empty document
            pages = [PageData(elements: [])]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(savedAt, forKey: .savedAt)
        try container.encode(pages, forKey: .pages)
        try container.encode(currentPageIndex, forKey: .currentPageIndex)
    }
}

// MARK: - Element Data Wrapper
struct CanvasElementData: Codable, Identifiable {
    var id: UUID
    var type: ElementType
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var zIndex: Int
    var data: ElementContentData
    
    enum ElementType: String, Codable {
        case text
        case graph
        case image
        case stroke
    }
}

// MARK: - Content Data
enum ElementContentData: Codable {
    case text(TextData)
    case graph(GraphData)
    case image(ImageData)
    case stroke(StrokeData)
    
    // Custom decoding to handle polymorphic types
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(TextData.self, forKey: .text) {
            self = .text(value)
        } else if let value = try? container.decode(GraphData.self, forKey: .graph) {
            self = .graph(value)
        } else if let value = try? container.decode(ImageData.self, forKey: .image) {
            self = .image(value)
        } else if let value = try? container.decode(StrokeData.self, forKey: .stroke) {
            self = .stroke(value)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath, debugDescription: "Unknown element data type"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let data):
            try container.encode(data, forKey: .text)
        case .graph(let data):
            try container.encode(data, forKey: .graph)
        case .image(let data):
            try container.encode(data, forKey: .image)
        case .stroke(let data):
            try container.encode(data, forKey: .stroke)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case text, graph, image, stroke
    }
}

// MARK: - Specific Data Types
struct TextData: Codable {
    var text: String
    var fontSize: CGFloat
    var fontFamily: String
    var color: String // Hex
}

struct GraphData: Codable {
    var expression: String
    var xMin: Double
    var xMax: Double
    var yMin: Double?
    var yMax: Double?
    var color: String
}

struct ImageData: Codable {
    var src: String // Base64 or local path
    var originalWidth: CGFloat
    var originalHeight: CGFloat
}

struct StrokeData: Codable {
    var points: [Point]
    var color: String
    var width: CGFloat
    
    struct Point: Codable, Equatable {
        var x: CGFloat
        var y: CGFloat
    }
}

extension CanvasElementData: Equatable {
    static func == (lhs: CanvasElementData, rhs: CanvasElementData) -> Bool {
        return lhs.id == rhs.id &&
            lhs.type == rhs.type &&
            lhs.x == rhs.x &&
            lhs.y == rhs.y &&
            lhs.width == rhs.width &&
            lhs.height == rhs.height &&
            lhs.zIndex == rhs.zIndex &&
            lhs.data == rhs.data
    }
}

extension ElementContentData: Equatable {
    static func == (lhs: ElementContentData, rhs: ElementContentData) -> Bool {
        switch (lhs, rhs) {
        case (.text(let l), .text(let r)): return l == r
        case (.graph(let l), .graph(let r)): return l == r
        case (.image(let l), .image(let r)): return l == r
        case (.stroke(let l), .stroke(let r)): return l == r
        default: return false
        }
    }
}

extension TextData: Equatable {}
extension GraphData: Equatable {}
extension ImageData: Equatable {}
extension StrokeData: Equatable {}
