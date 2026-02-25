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
                                .font(.system(size: 34, weight: .bold))
                                .padding(.leading, 20)
                                .padding(.top, 20)
                            Spacer()
                        }
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)], spacing: 20) {
                            ForEach(filteredItems) { filtered in
                                let item = filtered.note
                                DashboardCardView(
                                    title: item.title,
                                    description: filtered.snippet ?? (item.isFolder ? "Folder • \(item.children?.count ?? 0) items" : "Note • \(item.createdAt.formatted(date: .abbreviated, time: .shortened))"),
                                    highlightQuery: viewModel.searchText,
                                    icon: item.isFolder ? "folder" : "doc.text",
                                    backgroundColor: item.isFolder ? appTheme.cardBackground : Color(UIColor.secondarySystemBackground),
                                    buttonText: item.isFolder ? "Open" : "Get Started",
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
                print("[DEBUG-NAV] userInfo: \(notification.userInfo ?? [:])")
                
                guard let userInfo = notification.userInfo,
                      let noteIdString = userInfo["noteId"] as? String,
                      let noteId = UUID(uuidString: noteIdString),
                      let pageIndex = userInfo["pageIndex"] as? Int else {
                    print("[DEBUG-NAV] ⚠️ Failed to parse notification userInfo")
                    return
                }
                
                print("[DEBUG-NAV] Looking for note with id: \(noteIdString)")
                guard let note = viewModel.findItem(by: noteId) else {
                    print("[DEBUG-NAV] ⚠️ Note NOT FOUND in data store!")
                    return
                }
                
                print("[DEBUG-NAV] ✅ Found note '\(note.title)', navigating to page \(pageIndex)")
                viewModel.navigationPath.append(NavigationTarget(note: note, pageIndex: pageIndex))
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
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
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
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(appTheme.heroBackground)
                        .frame(width: 60, height: 60)
                    Image(systemName: currentLocationName == "Dashboard" ? "square.grid.2x2" : "folder.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(appTheme.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create new items")
                        .font(.title3.bold())
                    Text("Anything you add will live in \(currentLocationName).")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
            
            HStack(spacing: 8) {
                Label(itemCountLabel, systemImage: "tray.full")
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(
                        Capsule()
                            .fill(appTheme.accentColor.opacity(0.1))
                    )
                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
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
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
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
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(appTheme.heroBackground)
                        .frame(width: 60, height: 60)
                    Image(systemName: heroIconName)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(appTheme.accentColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.bold())
                    if !message.isEmpty {
                        Text(message)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
            }
            Text("Keep it short and descriptive for easier search later.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
    
    @ViewBuilder
    private var titleFieldSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Title")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            
            TextField(placeholder, text: $text)
                .focused($isTitleFieldFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(handleCreate)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(appTheme.accentColor.opacity(0.3), lineWidth: 1)
                )
            
            HStack {
                Text("This helps keep things organized.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(trimmedText.count)/\(maxCharacters)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(trimmedText.count >= maxCharacters ? .red : .secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
    
    private var primaryButton: some View {
        Button(action: handleCreate) {
            Text(primaryButtonTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
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
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(iconTint)
                .padding(8)
                .background(
                    Circle()
                        .fill(iconTint.opacity(0.15))
                )
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer(minLength: 0)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(iconTint.opacity(0.08))
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
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tint.opacity(0.15))
                        .frame(width: 58, height: 58)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(tint)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                        if let badgeText {
                            Text(badgeText.uppercased())
                                .font(.caption2.bold())
                                .padding(.vertical, 3)
                                .padding(.horizontal, 8)
                                .background(
                                    Capsule()
                                        .fill(tint.opacity(0.2))
                                )
                        }
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Image(systemName: isLocked ? "lock.fill" : "chevron.forward")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
