import SwiftUI
import SwiftData

struct FileSystemView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: FileSystemViewModel
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Query private var allItems: [NoteItem]
    
    @State private var isShowingCreateNote = false
    @State private var isShowingCreateFolder = false
    @State private var newItemTitle = ""
    @State private var itemToRename: NoteItem?
    @State private var renameTitle = ""
    @State private var isShowingPaywall = false
    
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
    
    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
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
                
                if viewModel.isGridMode {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 20) {
                            ForEach(filteredItems) { item in
                                FileSystemItemView(item: item, onRename: {
                                    itemToRename = item
                                    renameTitle = item.title
                                })
                                .onTapGesture {
                                    if item.isFolder {
                                        viewModel.navigateTo(folder: item)
                                    } else {
                                        viewModel.navigationPath.append(item)
                                    }
                                }
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
                            }
                        }
                        .padding()
                    }
                } else {
                    List {
                        ForEach(filteredItems) { item in
                            HStack {
                                Image(systemName: item.isFolder ? "folder.fill" : "doc.text.fill")
                                    .foregroundColor(item.isFolder ? .blue : .gray)
                                Text(item.title)
                                Spacer()
                                if item.isPinned {
                                    Image(systemName: "pin.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if item.isFolder {
                                    viewModel.navigateTo(folder: item)
                                } else {
                                    viewModel.navigationPath.append(item)
                                }
                            }
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
                        }
                    }
                }
            }
            .navigationTitle(viewModel.currentFolder?.title ?? "My Files")
            .navigationDestination(for: NoteItem.self) { item in
                BlackboardView(note: item)
            }
            .searchable(text: $viewModel.searchText)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            if canCreateNote {
                                newItemTitle = ""
                                isShowingCreateNote = true
                            } else {
                                isShowingPaywall = true
                            }
                        }) {
                            Label("New Note", systemImage: "doc.badge.plus")
                        }
                        Button(action: {
                            newItemTitle = ""
                            isShowingCreateFolder = true
                        }) {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                        Button(action: { viewModel.isGridMode.toggle() }) {
                            Label(viewModel.isGridMode ? "List View" : "Grid View", systemImage: viewModel.isGridMode ? "list.bullet" : "square.grid.2x2")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
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
            .alert("Rename", isPresented: Binding(get: { itemToRename != nil }, set: { if !$0 { itemToRename = nil } })) {
                TextField("Title", text: $renameTitle)
                Button("Cancel", role: .cancel) { }
                Button("Rename") {
                    if let item = itemToRename {
                        viewModel.renameItem(item, newTitle: renameTitle)
                    }
                }
            }
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView()
                    .environmentObject(subscriptionManager)
            }
        }
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
