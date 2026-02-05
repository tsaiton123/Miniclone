import Foundation
import SwiftData
import UniformTypeIdentifiers
import CoreTransferable

// Custom UTType for NoteItem drag-and-drop
extension UTType {
    static var noteItem: UTType {
        UTType(exportedAs: "com.blackboard.noteitem")
    }
}

@Model
final class NoteItem {
    // CloudKit requires all properties to have default values
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isFolder: Bool = false
    var isPinned: Bool = false
    
    @Relationship(deleteRule: .cascade, inverse: \NoteItem.parent)
    var children: [NoteItem]? = nil
    
    @Relationship(deleteRule: .nullify)
    var parent: NoteItem? = nil
    
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
