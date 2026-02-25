import SwiftUI
import Combine

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case blue
    case red
    case black
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .blue: return "Terracotta"
        case .red: return "Crimson"
        case .black: return "Carbon"
        }
    }
    
    var description: String {
        switch self {
        case .blue: return "Warm rust and earthy tones"
        case .red: return "Bold reds with warm highlights"
        case .black: return "Minimal monochrome surfaces"
        }
    }
    
    var accentColor: Color {
        switch self {
        case .blue:
            return Color(red: 0.78, green: 0.32, blue: 0.18) // #C8522E terracotta
        case .red:
            return Color(red: 0.82, green: 0.22, blue: 0.20) // warm crimson
        case .black:
            return Color(red: 0.18, green: 0.18, blue: 0.17) // charcoal
        }
    }
    
    var accentSecondaryColor: Color {
        switch self {
        case .blue:
            return Color(red: 0.88, green: 0.55, blue: 0.38) // warm peach
        case .red:
            return Color(red: 0.95, green: 0.45, blue: 0.40)
        case .black:
            return Color(red: 0.40, green: 0.40, blue: 0.38)
        }
    }
    
    var gradientColors: [Color] {
        [accentColor, accentSecondaryColor]
    }
    
    /// Elevated surface fill for note cards
    var cardBackground: Color {
        switch self {
        case .blue:
            return Color(red: 1.0, green: 1.0, blue: 1.0)
        case .red:
            return Color(red: 1.0, green: 1.0, blue: 1.0)
        case .black:
            return Color(red: 1.0, green: 1.0, blue: 1.0)
        }
    }
    
    /// Distinct warm-tinted background for folder cards
    var folderCardBackground: Color {
        switch self {
        case .blue:
            return Color(red: 0.96, green: 0.94, blue: 0.90) // warm beige
        case .red:
            return Color(red: 0.96, green: 0.92, blue: 0.91) // warm rose tint
        case .black:
            return Color(red: 0.94, green: 0.94, blue: 0.93) // warm light gray
        }
    }
    
    /// Background for hero circles or chips
    var heroBackground: Color {
        accentColor.opacity(0.12)
    }
    
    /// Darker chrome areas like dashboard top bar
    var chromeBackground: Color {
        switch self {
        case .blue:
            return Color(red: 0.14, green: 0.12, blue: 0.10) // warm dark brown
        case .red:
            return Color(red: 0.16, green: 0.08, blue: 0.07) // warm dark red
        case .black:
            return Color(red: 0.08, green: 0.08, blue: 0.07) // warm near-black
        }
    }
    
    /// Warm off-white for main content backgrounds
    var editorialBackground: Color {
        switch self {
        case .blue:
            return Color(red: 0.98, green: 0.97, blue: 0.96) // #FAF8F5
        case .red:
            return Color(red: 0.98, green: 0.96, blue: 0.96)
        case .black:
            return Color(red: 0.97, green: 0.97, blue: 0.97)
        }
    }
    
    /// Warm sidebar background 
    var sidebarBackground: Color {
        switch self {
        case .blue:
            return Color(red: 0.99, green: 0.98, blue: 0.97)
        case .red:
            return Color(red: 0.99, green: 0.97, blue: 0.97)
        case .black:
            return Color(red: 0.98, green: 0.98, blue: 0.98)
        }
    }
    
    var textOnAccent: Color { .white }
    
    var previewGradient: LinearGradient {
        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    var iconName: String {
        switch self {
        case .blue: return "leaf.fill"
        case .red: return "flame.fill"
        case .black: return "circle.hexagongrid.fill"
        }
    }
}

final class ThemeManager: ObservableObject {
    private let themeStorageKey = "selectedAppTheme"
    
    @Published var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: themeStorageKey)
        }
    }
    
    init() {
        let savedValue = UserDefaults.standard.string(forKey: themeStorageKey)
        currentTheme = AppTheme(rawValue: savedValue ?? "") ?? .blue
    }
    
    func select(_ theme: AppTheme) {
        guard theme != currentTheme else { return }
        currentTheme = theme
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .blue
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
