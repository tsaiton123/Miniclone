import SwiftUI

struct SidebarView: View {
    @Binding var selectedTab: Int
    
    // List, Home, Plus
    let items = [
        ("list.bullet", "Menu"),
        ("house", "Home"),
        ("plus", "Add")
    ]
    
    var body: some View {
        VStack(spacing: 25) {
            ForEach(0..<items.count, id: \.self) { index in
                Button(action: {
                    selectedTab = index
                }) {
                    Image(systemName: items[index].0)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(selectedTab == index ? .black : .gray)
                        .frame(width: 44, height: 44)
                }
            }
            Spacer()
        }
        .padding(.vertical, 20)
        .frame(width: 70)
        .background(Color.white)
        // Add a subtle border or shadow to separate from content if needed
    }
}
