import Foundation
import UIKit

/// Persisted record for one 224×224 tile embedding from a note page.
struct NoteEmbeddingRecord: Codable, Identifiable {
    var id: UUID = UUID()
    /// The page/note this embedding belongs to  
    var pageId: String
    /// Tile coordinates in the original page (stored as a CGRect-compatible struct)
    var tileX: CGFloat
    var tileY: CGFloat
    var tileWidth: CGFloat
    var tileHeight: CGFloat
    /// Timestamp
    var timestamp: Date
    /// L2-normalised 512-d MobileCLIP embedding
    var embedding: [Float]
    
    var tileRect: CGRect {
        CGRect(x: tileX, y: tileY, width: tileWidth, height: tileHeight)
    }
    
    init(pageId: String, tileRect: CGRect, embedding: [Float]) {
        self.pageId = pageId
        self.tileX = tileRect.origin.x
        self.tileY = tileRect.origin.y
        self.tileWidth = tileRect.size.width
        self.tileHeight = tileRect.size.height
        self.timestamp = Date()
        self.embedding = embedding
    }
}
