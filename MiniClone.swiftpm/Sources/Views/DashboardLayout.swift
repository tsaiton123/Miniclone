import SwiftUI

struct DashboardLayout<Content: View>: View {
    @Binding var searchText: String
    @Binding var selectedTab: Int
    var onSettings: () -> Void = {}
    var noteNames: [String: String] = [:]
    let content: Content
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.appTheme) private var appTheme
    @State private var isShowingSearchByDraw = false
    /// Cached results so we can re-show them when user returns from a note
    @State private var cachedSearchResults: [SearchByDrawView.DrawSearchResult] = []
    
    init(searchText: Binding<String>, selectedTab: Binding<Int>, noteNames: [String: String] = [:], onSettings: @escaping () -> Void = {}, @ViewBuilder content: () -> Content) {
        self._searchText = searchText
        self._selectedTab = selectedTab
        self.noteNames = noteNames
        self.onSettings = onSettings
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            TopBarView(searchText: $searchText, onSettings: onSettings)
            
            HStack(spacing: 0) {
                if horizontalSizeClass != .compact {
                    SidebarView(selectedTab: $selectedTab, onSettings: onSettings)
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 1)
                        .ignoresSafeArea()
                }
                
                ZStack {
                    appTheme.editorialBackground
                        .ignoresSafeArea()
                    
                    content
                }
            }
            
            if horizontalSizeClass == .compact {
                Divider()
                HStack {
                    Spacer()
                    TabButton(icon: "house.fill", label: "Home", isSelected: selectedTab == 1) {
                        selectedTab = 1
                    }
                    Spacer()
                    TabButton(icon: "plus.circle.fill", label: "Add", isSelected: false) {
                        selectedTab = 2
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(appTheme.sidebarBackground)
            }
        }
        .background(appTheme.chromeBackground)
        .sheet(isPresented: $isShowingSearchByDraw, onDismiss: {
            // If user tapped Cancel (not a result), clear cached results
            // cachedSearchResults is only cleared when Cancel is pressed, not when a result is selected
        }) {
            SearchByDrawView(
                noteNames: noteNames,
                initialResults: cachedSearchResults,
                sharedResults: $cachedSearchResults,
                onSelectResult: { noteId, pageIndex in
                    print("[DEBUG-DASHBOARD] Result selected: noteId=\(noteId), pageIndex=\(pageIndex)")
                    
                    // Dismiss the sheet
                    isShowingSearchByDraw = false
                    
                    // Navigate to the note full-screen via the main NavigationStack
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("OpenNoteFromSearch"),
                            object: nil,
                            userInfo: ["noteId": noteId, "pageIndex": pageIndex, "fromSearch": true]
                        )
                    }
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowSearchByDraw"))) { _ in
            cachedSearchResults = []  // Fresh search
            isShowingSearchByDraw = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ReopenSearchResults"))) { _ in
            // Re-open the search sheet with cached results
            if !cachedSearchResults.isEmpty {
                isShowingSearchByDraw = true
            }
        }
    }
}

struct TabButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.appTheme) private var appTheme
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(label)
                    .font(.caption2)
            }
            .foregroundColor(isSelected ? appTheme.accentColor : .gray)
            .frame(maxWidth: .infinity)
        }
    }
}
