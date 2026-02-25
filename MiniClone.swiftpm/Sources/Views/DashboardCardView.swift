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
    let isFolder: Bool
    let action: () -> Void
    
    init(title: String, description: String, highlightQuery: String? = nil, icon: String? = nil, backgroundColor: Color, buttonText: String, isFolder: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.description = description
        self.highlightQuery = highlightQuery
        self.icon = icon
        self.backgroundColor = backgroundColor
        self.buttonText = buttonText
        self.isFolder = isFolder
        self.action = action
    }
    
    var isDarkMode: Bool {
        colorScheme == .dark
    }
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Uppercase label
            Text(labelText)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundColor(appTheme.accentColor.opacity(0.7))
                .padding(.top, horizontalSizeClass == .compact ? 16 : 22)
                .padding(.bottom, 10)
            
            // Title — serif
            highlightedText(title, query: highlightQuery)
                .font(.system(size: horizontalSizeClass == .compact ? 22 : 28, weight: .regular, design: .serif))
                .foregroundColor(.primary)
            
            // Description
            highlightedText(description, query: highlightQuery)
                .font(.system(size: 14, weight: .light))
                .foregroundColor(.secondary)
                .padding(.top, 6)
                .padding(.bottom, horizontalSizeClass == .compact ? 14 : 18)
                .lineSpacing(3)
            
            Spacer()
            
            // Button — editorial squared-off
            Button(action: action) {
                HStack {
                    Text(buttonText)
                        .font(.system(size: 13, weight: .medium))
                        .tracking(0.3)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(isDarkMode ? appTheme.accentColor : Color.clear)
                .foregroundColor(isDarkMode ? appTheme.textOnAccent : appTheme.accentColor)
                .overlay(
                    Rectangle()
                        .stroke(appTheme.accentColor.opacity(isDarkMode ? 0 : 0.4), lineWidth: 1)
                )
            }
            .frame(width: horizontalSizeClass == .compact ? 150 : 180)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: horizontalSizeClass == .compact ? 220 : 250)
        .background(backgroundColor)
        .overlay(
            Rectangle()
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    private var labelText: String {
        if isFolder {
            return "FOLDER"
        } else {
            return "NOTE"
        }
    }
    
    private func normalized(_ text: String) -> String {
        return text.lowercased()
            .replacingOccurrences(of: "\"", with: "^")
            .replacingOccurrences(of: "'", with: "^")
            .replacingOccurrences(of: "\u{201C}", with: "^")
            .replacingOccurrences(of: "\u{201D}", with: "^")
    }
    
    private func highlightedText(_ text: String, query: String?) -> Text {
        guard let query = query, !query.isEmpty else { return Text(text) }
        
        let queryLower = normalized(query)
        let lowerText = normalized(text)
        
        var result = Text("")
        var searchRange = lowerText.startIndex..<lowerText.endIndex
        var ranges: [Range<String.Index>] = []
        
        while let range = lowerText.range(of: queryLower, options: .caseInsensitive, range: searchRange) {
            ranges.append(range)
            searchRange = range.upperBound..<lowerText.endIndex
        }
        
        if ranges.isEmpty {
            return Text(text)
        }
        
        var currentIndex = text.startIndex
        for range in ranges {
            result = result + Text(text[currentIndex..<range.lowerBound])
            result = result + Text(text[range]).bold().underline().foregroundColor(appTheme.accentColor)
            currentIndex = range.upperBound
        }
        
        result = result + Text(text[currentIndex...])
        
        return result
    }
}
