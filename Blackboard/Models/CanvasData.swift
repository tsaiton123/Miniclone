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
        case bitmapInk
    }
}

// MARK: - Content Data
enum ElementContentData: Codable {
    case text(TextData)
    case graph(GraphData)
    case image(ImageData)
    case stroke(StrokeData)
    case bitmapInk(BitmapInkData)
    
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
        } else if let value = try? container.decode(BitmapInkData.self, forKey: .bitmapInk) {
            self = .bitmapInk(value)
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
        case .bitmapInk(let data):
            try container.encode(data, forKey: .bitmapInk)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case text, graph, image, stroke, bitmapInk
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

struct BitmapInkData: Codable, Equatable {
    var src: String // Base64
    var originalWidth: CGFloat
    var originalHeight: CGFloat
}

// MARK: - Brush Types
enum BrushType: String, Codable, CaseIterable {
    case pen
    case pencil
    case marker
    case highlighter
    
    /// Icon name for toolbar display
    var iconName: String {
        switch self {
        case .pen: return "pencil.tip"
        case .pencil: return "pencil"
        case .marker: return "pencil.tip.crop.circle"
        case .highlighter: return "highlighter"
        }
    }
    
    /// Display name for UI
    var displayName: String {
        rawValue.capitalized
    }
    
    /// Opacity for the brush stroke
    var opacity: Double {
        switch self {
        case .pen: return 1.0
        case .pencil: return 0.85
        case .marker: return 0.7
        case .highlighter: return 0.4
        }
    }
    
    /// Width multiplier for different brush types
    var widthMultiplier: CGFloat {
        switch self {
        case .pen: return 1.0
        case .pencil: return 1.0
        case .marker: return 2.0
        case .highlighter: return 4.0
        }
    }
    
    /// Line cap style for the brush
    var lineCap: CGLineCap {
        switch self {
        case .pen, .pencil: return .round
        case .marker, .highlighter: return .butt
        }
    }
    
    /// Line join style for the brush
    var lineJoin: CGLineJoin {
        switch self {
        case .pen, .pencil: return .round
        case .marker, .highlighter: return .bevel
        }
    }
}

struct StrokeData: Codable {
    var points: [Point]
    var color: String
    var width: CGFloat
    var brushType: BrushType
    
    struct Point: Codable, Equatable {
        var x: CGFloat
        var y: CGFloat
    }
    
    // Convenience initializer with default brush type
    init(points: [Point], color: String, width: CGFloat, brushType: BrushType = .pen) {
        self.points = points
        self.color = color
        self.width = width
        self.brushType = brushType
    }
    
    // Custom decoding for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = try container.decode([Point].self, forKey: .points)
        color = try container.decode(String.self, forKey: .color)
        width = try container.decode(CGFloat.self, forKey: .width)
        // Default to .pen for old strokes that don't have brushType
        brushType = (try? container.decode(BrushType.self, forKey: .brushType)) ?? .pen
    }
    
    enum CodingKeys: String, CodingKey {
        case points, color, width, brushType
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
        case (.bitmapInk(let l), .bitmapInk(let r)): return l == r
        default: return false
        }
    }
}

extension TextData: Equatable {}
extension GraphData: Equatable {}
extension ImageData: Equatable {}
extension StrokeData: Equatable {}
