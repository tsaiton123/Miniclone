import SwiftUI

struct DashboardCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTheme) private var appTheme
    
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
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.system(size: horizontalSizeClass == .compact ? 24 : 32, weight: .regular))
                .foregroundColor(.primary)
                .padding(.top, horizontalSizeClass == .compact ? 15 : 20)
            
            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.top, 5)
                .padding(.bottom, horizontalSizeClass == .compact ? 15 : 20)
            
            Spacer()
            
            Button(action: action) {
                HStack {
                    Text(buttonText)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding()
                .background(isDarkMode ? appTheme.accentColor : appTheme.accentColor.opacity(0.12))
                .foregroundColor(isDarkMode ? appTheme.textOnAccent : appTheme.accentColor)
                .border(isDarkMode ? Color.clear : appTheme.accentColor.opacity(0.3), width: 1)
                .cornerRadius(10)
            }
            .frame(width: horizontalSizeClass == .compact ? 150 : 180)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: horizontalSizeClass == .compact ? 220 : 250)
        .background(backgroundColor)
    }
}
