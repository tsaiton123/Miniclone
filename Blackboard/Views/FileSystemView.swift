import SwiftUI
import SwiftData

struct FileSystemView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: FileSystemViewModel
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var authManager: AuthenticationManager
    @Query private var allItems: [NoteItem]
    
    @State private var isShowingCreateNote = false
    @State private var isShowingCreateFolder = false
    @State private var newItemTitle = ""
    @State private var itemToRename: NoteItem?
    @State private var renameTitle = ""
    @State private var isShowingPaywall = false
    @State private var isShowingSettings = false
    
    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: FileSystemViewModel(modelContext: modelContext))
    }
    
    /// Count of notes (not folders) for free tier limit check
    var noteCount: Int {
        allItems.filter { !$0.isFolder }.count
    }
    
    /// Whether the user can create more notes
    var canCreateNote: Bool {
        subscriptionManager.currentTier.hasUnlimitedNotes || noteCount < subscriptionManager.currentTier.maxNotes
    }
    
    var filteredItems: [NoteItem] {
        let items = allItems.filter { item in
            item.parent == viewModel.currentFolder
        }
        
        if viewModel.searchText.isEmpty {
            return items.sorted {
                if $0.isPinned != $1.isPinned {
                    return $0.isPinned && !$1.isPinned
                }
                return $0.createdAt > $1.createdAt
            }
        } else {
            return items.filter { $0.title.localizedCaseInsensitiveContains(viewModel.searchText) }
        }
    }
    
    @State private var selectedTab = 1
    
    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            DashboardLayout(searchText: $viewModel.searchText, selectedTab: $selectedTab, onSettings: {
                isShowingSettings = true
            }) {
                VStack {
                    // Breadcrumbs
                    if let current = viewModel.currentFolder {
                        HStack {
                            Button(action: { viewModel.navigateUp() }) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            Spacer()
                            Text(current.title)
                                .font(.headline)
                            Spacer()
                        }
                        .padding()
                    }
                    
                    ScrollView {
                        // Title
                        HStack {
                            Text(viewModel.currentFolder?.title ?? "Dashboard")
                                .font(.system(size: 34, weight: .bold))
                                .padding(.leading, 20)
                                .padding(.top, 20)
                            Spacer()
                        }
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)], spacing: 20) {
                            ForEach(filteredItems) { item in
                                DashboardCardView(
                                    title: item.title,
                                    description: item.isFolder ? "Folder • \(item.children?.count ?? 0) items" : "Note • \(item.createdAt.formatted(date: .abbreviated, time: .shortened))",
                                    icon: item.isFolder ? "folder" : "doc.text",
                                    backgroundColor: item.isFolder ? Color.blue.opacity(0.1) : Color(UIColor.secondarySystemBackground), // Light Blue for Folders
                                    buttonText: item.isFolder ? "Open" : "Get Started",
                                    action: {
                                        if item.isFolder {
                                            viewModel.navigateTo(folder: item)
                                        } else {
                                            viewModel.navigationPath.append(item)
                                        }
                                    }
                                )
                                .contextMenu {
                                    Button(action: { viewModel.togglePin(item) }) {
                                        Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
                                    }
                                    Button(action: {
                                        itemToRename = item
                                        renameTitle = item.title
                                    }) {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    Button(role: .destructive, action: { viewModel.deleteItem(item) }) {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .draggable(item.id.uuidString)
                                .dropDestination(for: String.self) { droppedStrings, _ in
                                    // Only folders can accept drops
                                    guard item.isFolder else { return false }
                                    
                                    for uuidString in droppedStrings {
                                        guard let uuid = UUID(uuidString: uuidString),
                                              let droppedItem = viewModel.findItem(by: uuid) else { continue }
                                        
                                        // Prevent dropping item on itself or its own children
                                        if droppedItem.id != item.id && !isDescendant(droppedItem, of: item) {
                                            viewModel.moveItem(droppedItem, to: item)
                                        }
                                    }
                                    return true
                                } isTargeted: { isTargeted in
                                    // Visual feedback handled by SwiftUI default highlighting
                                }
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: NoteItem.self) { item in
                BlackboardView(note: item)
                    .toolbar(.visible, for: .navigationBar) // Show navbar in editor
            }
            .onChange(of: selectedTab) { newValue in
                if newValue == 2 { // "Add" button index is now 2
                    isShowingAddSheet = true
                    // Reset tab to home or keep generic?
                    selectedTab = 1
                }
            }
            .confirmationDialog("Create New", isPresented: $isShowingAddSheet, titleVisibility: .visible) {
                Button("New Note") {
                    if canCreateNote {
                        newItemTitle = ""
                        isShowingCreateNote = true
                    } else {
                        isShowingPaywall = true
                    }
                }
                Button("New Folder") {
                    newItemTitle = ""
                    isShowingCreateFolder = true
                }
                Button("Cancel", role: .cancel) { }
            }
            .alert("New Note", isPresented: $isShowingCreateNote) {
                TextField("Title", text: $newItemTitle)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    viewModel.createNote(title: newItemTitle)
                }
            }
            .alert("New Folder", isPresented: $isShowingCreateFolder) {
                TextField("Title", text: $newItemTitle)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    viewModel.createFolder(title: newItemTitle)
                }
            }
            .alert("Rename", isPresented: Binding(
                get: { itemToRename != nil },
                set: { if !$0 { itemToRename = nil } }
            )) {
                TextField("New Name", text: $renameTitle)
                Button("Cancel", role: .cancel) {
                    itemToRename = nil
                }
                Button("Rename") {
                    if let item = itemToRename {
                        viewModel.renameItem(item, newTitle: renameTitle)
                        itemToRename = nil
                    }
                }
            } message: {
                Text("Enter a new name for \"\(itemToRename?.title ?? "")\"")
            }
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView()
                    .environmentObject(subscriptionManager)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
                    .environmentObject(subscriptionManager)
                    .environmentObject(authManager)
            }
        }
    }
    
    @State private var isShowingAddSheet = false
    
    /// Helper to check if an item is a descendant of another (to prevent circular moves)
    private func isDescendant(_ potentialParent: NoteItem, of item: NoteItem) -> Bool {
        var current: NoteItem? = item.parent
        while let parent = current {
            if parent.id == potentialParent.id {
                return true
            }
            current = parent.parent
        }
        return false
    }
}

struct FileSystemItemView: View {
    let item: NoteItem
    var onRename: () -> Void
    
    var body: some View {
        VStack {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(height: 100)
                
                Image(systemName: item.isFolder ? "folder.fill" : "doc.text.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                    .foregroundColor(item.isFolder ? .blue : .gray)
                
                if item.isPinned {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "pin.fill")
                                .foregroundColor(.orange)
                                .padding(8)
                        }
                        Spacer()
                    }
                }
            }
            
            Text(item.title)
                .font(.caption)
                .lineLimit(1)
        }
    }
}
