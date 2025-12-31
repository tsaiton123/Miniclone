import SwiftUI
import SwiftData
import Combine

final class FileSystemViewModel: ObservableObject {
    @Published var currentFolder: NoteItem?
    @Published var selectedItems: Set<UUID> = []
    @Published var isGridMode = true
    @Published var searchText = ""
    @Published var navigationPath = NavigationPath()
    
    private var modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Navigation
    
    func navigateTo(folder: NoteItem?) {
        currentFolder = folder
        selectedItems.removeAll()
    }
    
    func navigateUp() {
        if let parent = currentFolder?.parent {
            currentFolder = parent
        } else {
            currentFolder = nil
        }
        selectedItems.removeAll()
    }
    
    // MARK: - CRUD
    
    func createNote(title: String) {
        let newNote = NoteItem(title: title, isFolder: false, parent: currentFolder)
        modelContext.insert(newNote)
        save()
    }
    
    func createFolder(title: String) {
        let newFolder = NoteItem(title: title, isFolder: true, parent: currentFolder)
        modelContext.insert(newFolder)
        save()
    }
    
    func deleteItem(_ item: NoteItem) {
        modelContext.delete(item)
        save()
    }
    
    func renameItem(_ item: NoteItem, newTitle: String) {
        item.title = newTitle
        item.updatedAt = Date()
        save()
    }
    
    func togglePin(_ item: NoteItem) {
        item.isPinned.toggle()
        save()
    }
    
    func moveItem(_ item: NoteItem, to folder: NoteItem?) {
        item.parent = folder
        item.updatedAt = Date()
        save()
    }
    
    private func save() {
        try? modelContext.save()
    }
}
