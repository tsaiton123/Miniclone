import Foundation
import SwiftData

@Model
final class NoteItem {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    
    init(title: String) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
