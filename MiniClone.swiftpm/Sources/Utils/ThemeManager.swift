import SwiftUI
import Combine

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case blue
    case red
    case black
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .blue: return "Pacific Blue"
        case .red: return "Crimson"
        case .black: return "Carbon"
        }
    }
    
    var description: String {
        switch self {
        case .blue: return "Bright, energetic blues"
        case .red: return "Bold reds with warm highlights"
        case .black: return "Minimal monochrome surfaces"
        }
    }
    
    var accentColor: Color {
        switch self {
        case .blue:
            return Color(red: 0.20, green: 0.45, blue: 0.95)
        case .red:
            return Color(red: 0.88, green: 0.20, blue: 0.27)
        case .black:
            return Color(red: 0.13, green: 0.13, blue: 0.15)
        }
    }
    
    var accentSecondaryColor: Color {
        switch self {
        case .blue:
            return Color(red: 0.36, green: 0.72, blue: 1.0)
        case .red:
            return Color(red: 1.0, green: 0.45, blue: 0.45)
        case .black:
            return Color(red: 0.35, green: 0.35, blue: 0.37)
        }
    }
    
    var gradientColors: [Color] {
        [accentColor, accentSecondaryColor]
    }
    
    /// Elevated surface fill that still respects the theme
    var cardBackground: Color {
        switch self {
        case .blue:
            return Color(red: 0.17, green: 0.30, blue: 0.55, opacity: 0.12)
        case .red:
            return Color(red: 0.60, green: 0.15, blue: 0.20, opacity: 0.16)
        case .black:
            return Color(red: 0.15, green: 0.15, blue: 0.18, opacity: 0.35)
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
            return Color(red: 0.07, green: 0.14, blue: 0.26)
        case .red:
            return Color(red: 0.19, green: 0.06, blue: 0.08)
        case .black:
            return Color(red: 0.05, green: 0.05, blue: 0.05)
        }
    }
    
    var textOnAccent: Color { .white }
    
    var previewGradient: LinearGradient {
        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    var iconName: String {
        switch self {
        case .blue: return "circle.fill"
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
