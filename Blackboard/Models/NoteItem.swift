import Foundation
import SwiftData
import UniformTypeIdentifiers

// Custom UTType for NoteItem drag-and-drop
extension UTType {
    static var noteItem: UTType {
        UTType(exportedAs: "com.blackboard.noteitem")
    }
}

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

// MARK: - Transferable for Drag-and-Drop
extension NoteItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.id.uuidString)
    }
}
