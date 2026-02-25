import SwiftUI
import SwiftData

struct FileSystemView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: FileSystemViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.appTheme) private var appTheme
    @Query private var allItems: [NoteItem]
    
    @State private var activeSheet: DashboardSheetType?
    @State private var newItemTitle = ""
    @State private var itemToRename: NoteItem?
    @State private var renameTitle = ""
    
    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: FileSystemViewModel(modelContext: modelContext))
    }
    
    /// Count of notes (not folders) for free tier limit check
    var noteCount: Int {
        allItems.filter { !$0.isFolder }.count
    }
    
    /// Whether the user can create more notes
    var canCreateNote: Bool {
        return true
    }
    
    /// Message shown when the user hits their note quota
    var noteLimitMessage: String? {
        return nil
    }
    
    struct NavigationTarget: Hashable {
        let note: NoteItem
        let pageIndex: Int?
    }
    
    struct FilteredItem: Identifiable {
        let note: NoteItem
        let snippet: String?
        let pageIndex: Int?
        var id: UUID { note.id }
    }
    
    var filteredItems: [FilteredItem] {
        let items = allItems.filter { item in
            item.parent == viewModel.currentFolder
        }
        
        if viewModel.searchText.isEmpty {
            return items.sorted {
                if $0.isPinned != $1.isPinned {
                    return $0.isPinned && !$1.isPinned
                }
                return $0.createdAt > $1.createdAt
            }.map { FilteredItem(note: $0, snippet: nil, pageIndex: nil) }
        } else {
            let query = viewModel.searchText
            // Title match (existing)
            let titleMatches = items.filter { $0.title.localizedCaseInsensitiveContains(query) }
            // OCR keyword match (new)
            let ocrResults = HandwritingIndexService.shared.search(query: query)
            let ocrNoteIds = Set(ocrResults.map { $0.pageId.components(separatedBy: "_").first ?? $0.pageId })
            let ocrMatches = items.filter { !$0.isFolder && ocrNoteIds.contains($0.id.uuidString) }
            
            // Merge: title matches first, then OCR-only matches, deduplicated
            var seen = Set(titleMatches.map { $0.id })
            let combined = titleMatches + ocrMatches.filter { seen.insert($0.id).inserted }
            
            return combined.map { item in
                let match = ocrResults.first(where: { $0.pageId.hasPrefix(item.id.uuidString) })
                let snippet = match?.snippet
                let pageIndex = match.flatMap { m in
                    let parts = m.pageId.components(separatedBy: "_")
                    return parts.count > 1 ? Int(parts[1]) : nil
                }
                return FilteredItem(note: item, snippet: snippet, pageIndex: pageIndex)
            }
        }
    }
    
    @State private var selectedTab = 1
    @State private var openedFromSearch = false
    
    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            DashboardLayout(searchText: $viewModel.searchText, selectedTab: $selectedTab, noteNames: Dictionary(uniqueKeysWithValues: allItems.filter { !$0.isFolder }.map { ($0.id.uuidString, $0.title) }), onSettings: {
                activeSheet = .settings
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
                                .font(.system(size: 34, weight: .regular, design: .serif))
                                .padding(.leading, 20)
                                .padding(.top, 20)
                            Spacer()
                        }
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)], spacing: 20) {
                            ForEach(filteredItems) { filtered in
                                let item = filtered.note
                                DashboardCardView(
                                    title: item.title,
                                    description: filtered.snippet ?? (item.isFolder ? "Folder · \(item.children?.count ?? 0) items" : "Note · \(item.createdAt.formatted(date: .abbreviated, time: .shortened))"),
                                    highlightQuery: viewModel.searchText,
                                    icon: item.isFolder ? "folder" : "doc.text",
                                    backgroundColor: item.isFolder ? appTheme.folderCardBackground : appTheme.cardBackground,
                                    buttonText: item.isFolder ? "Browse" : "Open Note",
                                    isFolder: item.isFolder,
                                    action: {
                                        if item.isFolder {
                                            viewModel.navigateTo(folder: item)
                                        } else {
                                            viewModel.navigationPath.append(NavigationTarget(note: item, pageIndex: filtered.pageIndex))
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
                    }
                }
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: NavigationTarget.self) { target in
                MiniCloneView(note: target.note, initialPageIndex: target.pageIndex)
                    .toolbar(.visible, for: .navigationBar)
            }
            .navigationDestination(for: NoteItem.self) { item in
                MiniCloneView(note: item)
                    .toolbar(.visible, for: .navigationBar) // Show navbar in editor
            }
            .onChange(of: selectedTab) { newValue in
                if newValue == 2 { // "Add" button index is now 2
                    activeSheet = .addOptions
                    // Reset tab to home
                    selectedTab = 1
                }
            }
            .sheet(item: $activeSheet) { type in
                switch type {
                case .addOptions:
                    AddItemOptionsSheet(
                        canCreateNote: canCreateNote,
                        currentLocationName: viewModel.currentFolder?.title ?? "Dashboard",
                        itemCount: filteredItems.count,
                        noteLimitMessage: noteLimitMessage,
                        onSelectNote: {
                            newItemTitle = ""
                            // Change active sheet without dismissing
                            activeSheet = .createNote
                        },
                        onSelectFolder: {
                            newItemTitle = ""
                            // Change active sheet without dismissing
                            activeSheet = .createFolder
                        }
                    )
                case .createNote:
                    ItemCreationSheet(
                        title: "New Note",
                        message: "Name your note. You can always rename it later.",
                        placeholder: "Note title",
                        text: $newItemTitle
                    ) { title in
                        viewModel.createNote(title: title)
                        activeSheet = nil
                    }
                case .createFolder:
                    ItemCreationSheet(
                        title: "New Folder",
                        message: "Give your folder a descriptive name.",
                        placeholder: "Folder name",
                        text: $newItemTitle
                    ) { title in
                        viewModel.createFolder(title: title)
                        activeSheet = nil
                    }
                case .settings:
                    SettingsView()
                        .environmentObject(authManager)
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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenNoteFromSearch"))) { notification in
                print("[DEBUG-NAV] Received OpenNoteFromSearch notification")
                
                guard let userInfo = notification.userInfo,
                      let noteIdString = userInfo["noteId"] as? String,
                      let noteId = UUID(uuidString: noteIdString),
                      let pageIndex = userInfo["pageIndex"] as? Int else {
                    print("[DEBUG-NAV] ⚠️ Failed to parse notification userInfo")
                    return
                }
                
                guard let note = viewModel.findItem(by: noteId) else {
                    print("[DEBUG-NAV] ⚠️ Note NOT FOUND in data store!")
                    return
                }
                
                let fromSearch = (userInfo["fromSearch"] as? Bool) ?? false
                print("[DEBUG-NAV] ✅ Opening note '\(note.title)' page \(pageIndex), fromSearch=\(fromSearch)")
                openedFromSearch = fromSearch
                viewModel.navigationPath.append(NavigationTarget(note: note, pageIndex: pageIndex))
            }
            .onChange(of: viewModel.navigationPath) { oldPath, newPath in
                // When user taps Back and the path shrinks, check if we should reopen search
                if openedFromSearch && newPath.count < oldPath.count && newPath.isEmpty {
                    openedFromSearch = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: NSNotification.Name("ReopenSearchResults"), object: nil)
                    }
                }
            }
        }
    }
    
    enum DashboardSheetType: String, Identifiable {
        case addOptions, createNote, createFolder, settings
        var id: String { rawValue }
    }
    
    // Removed isShowingAddSheet as it's now part of activeSheet

    
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
    @Environment(\.appTheme) private var appTheme
    
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
                    .foregroundColor(item.isFolder ? appTheme.accentColor : .gray)
                
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

struct AddItemOptionsSheet: View {
    let canCreateNote: Bool
    let currentLocationName: String
    let itemCount: Int
    let noteLimitMessage: String?
    let onSelectNote: () -> Void
    let onSelectFolder: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    @State private var selectedDetent: PresentationDetent = .large
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    
                    VStack(spacing: 16) {
                        CreateOptionButton(
                            title: "Blank Note",
                            subtitle: canCreateNote ? "Start from a fresh page instantly." : "You've reached your note limit. Upgrade to keep creating.",
                            icon: "square.and.pencil",
                            tint: appTheme.accentColor,
                            badgeText: canCreateNote ? nil : "Limit Reached",
                            isLocked: !canCreateNote,
                            action: { dismissAndExecute(onSelectNote) }
                        )
                        
                        CreateOptionButton(
                            title: "Folder",
                            subtitle: "Group related notes and keep everything organized.",
                            icon: "folder.badge.plus",
                            tint: appTheme.accentSecondaryColor,
                            badgeText: nil,
                            isLocked: false,
                            action: { dismissAndExecute(onSelectFolder) }
                        )
                    }
                    
                    if let noteLimitMessage {
                        InfoCallout(
                            icon: "info.circle.fill",
                            iconTint: .orange,
                            message: noteLimitMessage
                        )
                    }
                    
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
            .background(appTheme.editorialBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .onAppear {
            selectedDetent = .large
        }
    }
    
    private var itemCountLabel: String {
        itemCount == 1 ? "1 item" : "\(itemCount) items"
    }
    
    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CREATE NEW")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundColor(appTheme.accentColor.opacity(0.7))
            
            HStack(spacing: 16) {
                ZStack {
                    Rectangle()
                        .fill(appTheme.heroBackground)
                        .frame(width: 52, height: 52)
                    Image(systemName: currentLocationName == "Dashboard" ? "square.grid.2x2" : "folder.fill")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(appTheme.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create new items")
                        .font(.system(size: 20, weight: .regular, design: .serif))
                    Text("Anything you add will live in \(currentLocationName).")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13, weight: .light))
                }
            }
            
            HStack(spacing: 8) {
                Label(itemCountLabel, systemImage: "tray.full")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.3)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .overlay(
                        Rectangle()
                            .stroke(appTheme.accentColor.opacity(0.2), lineWidth: 1)
                    )
                Spacer()
            }
        }
        .padding(20)
        .background(
            Color.white
        )
        .overlay(
            Rectangle()
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    private func dismissAndExecute(_ action: () -> Void) {
        // We don't necessarily want to dismiss if we're switching content in a single sheet
        action()
    }
}

struct ItemCreationSheet: View {
    let title: String
    let message: String
    let placeholder: String
    @Binding var text: String
    let onConfirm: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    @FocusState private var isTitleFieldFocused: Bool
    @State private var selectedDetent: PresentationDetent = .large
    
    private let maxCharacters = 60
    
    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var heroIconName: String {
        title.lowercased().contains("folder") ? "folder.badge.plus" : "square.and.pencil"
    }
    
    private var primaryButtonTitle: String {
        title.lowercased().contains("folder") ? "Create Folder" : "Create Note"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroSection
                    titleFieldSection
                    primaryButton
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
            .background(appTheme.editorialBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .onAppear {
            selectedDetent = .large
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isTitleFieldFocused = true
            }
        }
        .onChange(of: text) { newValue in
            if newValue.count > maxCharacters {
                text = String(newValue.prefix(maxCharacters))
            }
        }
    }
    
    @ViewBuilder
    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.lowercased().contains("folder") ? "NEW FOLDER" : "NEW NOTE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundColor(appTheme.accentColor.opacity(0.7))
            
            HStack(spacing: 16) {
                ZStack {
                    Rectangle()
                        .fill(appTheme.heroBackground)
                        .frame(width: 52, height: 52)
                    Image(systemName: heroIconName)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(appTheme.accentColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .regular, design: .serif))
                    if !message.isEmpty {
                        Text(message)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13, weight: .light))
                    }
                }
            }
            Text("Keep it short and descriptive for easier search later.")
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color.white)
        .overlay(
            Rectangle()
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var titleFieldSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TITLE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(appTheme.accentColor.opacity(0.6))
            
            TextField(placeholder, text: $text)
                .focused($isTitleFieldFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(handleCreate)
                .font(.system(size: 16, weight: .regular, design: .serif))
                .padding(14)
                .background(Color.white)
                .overlay(
                    Rectangle()
                        .stroke(appTheme.accentColor.opacity(0.25), lineWidth: 1)
                )
            
            HStack {
                Text("This helps keep things organized.")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(trimmedText.count)/\(maxCharacters)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(trimmedText.count >= maxCharacters ? .red : .secondary)
            }
        }
        .padding(20)
        .background(Color.white)
        .overlay(
            Rectangle()
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    private var primaryButton: some View {
        Button(action: handleCreate) {
            HStack {
                Text(primaryButtonTitle)
                    .font(.system(size: 14, weight: .medium))
                    .tracking(0.3)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 12))
            }
            .foregroundColor(trimmedText.isEmpty ? .secondary : appTheme.textOnAccent)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(trimmedText.isEmpty ? Color.gray.opacity(0.15) : appTheme.accentColor)
        }
        .disabled(trimmedText.isEmpty)
    }
    
    private func handleCreate() {
        let value = trimmedText
        guard !value.isEmpty else { return }
        onConfirm(value)
        text = ""
        dismiss()
    }
}

struct InfoCallout: View {
    let icon: String
    let iconTint: Color
    let message: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(iconTint)
                .padding(8)
                .background(
                    Rectangle()
                        .fill(iconTint.opacity(0.1))
                )
            
            Text(message)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(.secondary)
            
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.white)
        .overlay(
            Rectangle()
                .stroke(iconTint.opacity(0.15), lineWidth: 1)
        )
    }
}

struct CreateOptionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let badgeText: String?
    let isLocked: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    Rectangle()
                        .fill(tint.opacity(0.08))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(tint)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 16, weight: .regular, design: .serif))
                        if let badgeText {
                            Text(badgeText.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(0.8)
                                .padding(.vertical, 3)
                                .padding(.horizontal, 8)
                                .overlay(
                                    Rectangle()
                                        .stroke(tint.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Image(systemName: isLocked ? "lock.fill" : "arrow.right")
                    .font(.system(size: 12))
                    .foregroundColor(tint)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .overlay(
                Rectangle()
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
