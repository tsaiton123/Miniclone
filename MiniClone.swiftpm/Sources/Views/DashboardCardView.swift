import SwiftUI

struct DashboardCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTheme) private var appTheme
    
    let title: String
    let description: String
    let highlightQuery: String?
    let icon: String?
    let backgroundColor: Color
    let buttonText: String
    let action: () -> Void
    
    init(title: String, description: String, highlightQuery: String? = nil, icon: String? = nil, backgroundColor: Color, buttonText: String, action: @escaping () -> Void) {
        self.title = title
        self.description = description
        self.highlightQuery = highlightQuery
        self.icon = icon
        self.backgroundColor = backgroundColor
        self.buttonText = buttonText
        self.action = action
    }
    
    // Use system color scheme to determine text colors
    var isDarkMode: Bool {
        colorScheme == .dark
    }
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        VStack(alignment: .leading) {
            highlightedText(title, query: highlightQuery)
                .font(.system(size: horizontalSizeClass == .compact ? 24 : 32, weight: .regular))
                .foregroundColor(.primary)
                .padding(.top, horizontalSizeClass == .compact ? 15 : 20)
            
            highlightedText(description, query: highlightQuery)
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
    
    private func normalized(_ text: String) -> String {
        return text.lowercased()
            .replacingOccurrences(of: "\"", with: "^")
            .replacingOccurrences(of: "'", with: "^")
            .replacingOccurrences(of: "“", with: "^")
            .replacingOccurrences(of: "”", with: "^")
    }
    
    private func highlightedText(_ text: String, query: String?) -> Text {
        guard let query = query, !query.isEmpty else { return Text(text) }
        
        let queryLower = normalized(query)
        let lowerText = normalized(text)
        
        var result = Text("")
        var searchRange = lowerText.startIndex..<lowerText.endIndex
        var ranges: [Range<String.Index>] = []
        
        // Find ranges based on normalized comparison
        while let range = lowerText.range(of: queryLower, options: .caseInsensitive, range: searchRange) {
            ranges.append(range)
            searchRange = range.upperBound..<lowerText.endIndex
        }
        
        if ranges.isEmpty {
            return Text(text)
        }
        
        var currentIndex = text.startIndex
        for range in ranges {
            // Text before match
            result = result + Text(text[currentIndex..<range.lowerBound])
            // Highlighted match (use original text from the range)
            result = result + Text(text[range]).bold().underline().foregroundColor(appTheme.accentColor)
            currentIndex = range.upperBound
        }
        
        // Final part
        result = result + Text(text[currentIndex...])
        
        return result
    }
}
