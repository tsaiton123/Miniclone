import SwiftUI

struct DashboardLayout<Content: View>: View {
    @Binding var searchText: String
    @Binding var selectedTab: Int
    var onSettings: () -> Void = {}
    let content: Content
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.appTheme) private var appTheme
    
    init(searchText: Binding<String>, selectedTab: Binding<Int>, onSettings: @escaping () -> Void = {}, @ViewBuilder content: () -> Content) {
        self._searchText = searchText
        self._selectedTab = selectedTab
        self.onSettings = onSettings
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            TopBarView(searchText: $searchText, onSettings: onSettings)
            
            HStack(spacing: 0) {
                if horizontalSizeClass != .compact {
                    SidebarView(selectedTab: $selectedTab, onSettings: onSettings)
                    
                    // Divider or separator line
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 1)
                        .ignoresSafeArea()
                }
                
                ZStack {
                    Color(UIColor.systemBackground) // Main content background
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
                .background(Color(UIColor.secondarySystemBackground))
            }
        }
        .background(appTheme.chromeBackground)
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
