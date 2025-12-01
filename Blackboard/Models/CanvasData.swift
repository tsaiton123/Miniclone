import Foundation
import SwiftUI

// MARK: - Canvas Data Structure
struct CanvasData: Codable {
    var version: String = "1.0"
    var savedAt: Date = Date()
    var elements: [CanvasElementData]
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
    
    struct Point: Codable {
        var x: CGFloat
        var y: CGFloat
    }
}
