import SwiftUI

struct DashboardLayout<Content: View>: View {
    @Binding var searchText: String
    @Binding var selectedTab: Int
    var onSettings: () -> Void = {}
    let content: Content
    
    init(searchText: Binding<String>, selectedTab: Binding<Int>, onSettings: @escaping () -> Void = {}, @ViewBuilder content: () -> Content) {
        self._searchText = searchText
        self._selectedTab = selectedTab
        self.onSettings = onSettings
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            TopBarView(searchText: $searchText)
            
            HStack(spacing: 0) {
                SidebarView(selectedTab: $selectedTab, onSettings: onSettings)
                
                // Divider or separator line
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1)
                    .ignoresSafeArea()
                
                ZStack {
                    Color(UIColor.systemBackground) // Main content background
                        .ignoresSafeArea()
                    
                    content
                }
            }
        }
        .background(Color(hex: "1a1a1a")) // Match top bar background for status bar area
    }
}

