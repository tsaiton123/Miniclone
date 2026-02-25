import SwiftUI

struct SidebarView: View {
    @Binding var selectedTab: Int
    var onSettings: () -> Void = {}
    @Environment(\.appTheme) private var appTheme
    
    // List, Home, Plus
    let items = [
        ("list.bullet", "Menu"),
        ("house", "Home"),
        ("plus", "Add")
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            ForEach(0..<items.count, id: \.self) { index in
                Button(action: {
                    selectedTab = index
                }) {
                    Image(systemName: items[index].0)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(selectedTab == index ? appTheme.accentColor : Color.primary.opacity(0.35))
                        .frame(width: 42, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == index ? appTheme.accentColor.opacity(0.1) : Color.clear)
                        )
                }
            }
            Spacer()
            
            // Settings button at the bottom
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(Color.primary.opacity(0.35))
                    .frame(width: 42, height: 42)
            }
        }
        .padding(.vertical, 20)
        .frame(width: 66)
        .background(appTheme.sidebarBackground)
    }
}
