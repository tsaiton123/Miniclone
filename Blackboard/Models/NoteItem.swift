import Foundation
import SwiftData

@Model
final class NoteItem {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isFolder: Bool
    var isPinned: Bool
    
    @Relationship(deleteRule: .cascade, inverse: \NoteItem.parent)
    var children: [NoteItem]?
    
    @Relationship(deleteRule: .nullify)
    var parent: NoteItem?
    
    init(title: String, isFolder: Bool = false, parent: NoteItem? = nil) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isFolder = isFolder
        self.isPinned = false
        self.parent = parent
    }
}
