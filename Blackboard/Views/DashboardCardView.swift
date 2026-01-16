import SwiftUI

struct DashboardCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let title: String
    let description: String
    let icon: String?
    let backgroundColor: Color
    let buttonText: String
    let action: () -> Void
    
    // Use system color scheme to determine text colors
    var isDarkMode: Bool {
        colorScheme == .dark
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.system(size: 32, weight: .regular))
                .foregroundColor(.primary)
                .padding(.top, 20)
            
            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.top, 5)
                .padding(.bottom, 20)
            
            Spacer()
            
            Button(action: action) {
                HStack {
                    Text(buttonText)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding()
                .background(isDarkMode ? Color.blue : Color.white)
                .foregroundColor(isDarkMode ? .white : .blue)
                .border(isDarkMode ? Color.clear : Color.blue.opacity(0.3), width: 1)
            }
            .frame(width: 180)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: 250, alignment: .leading)
        .background(backgroundColor)
    }
}
