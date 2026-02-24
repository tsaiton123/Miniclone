import SwiftUI
import SwiftData

@main
struct MiniCloneApp: App {
    var sharedModelContainer: ModelContainer
    
    init() {
        let schema = Schema([
            NoteItem.self,
        ])
        
        // Try CloudKit first, fall back to local if it fails
        do {
            let cloudConfig = ModelConfiguration(
                "CloudStore",
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            self.sharedModelContainer = try ModelContainer(for: schema, configurations: [cloudConfig])
        } catch {
            // Fallback to local-only storage
            do {
                let localConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .none
                )
                self.sharedModelContainer = try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                ContentView()
                    .environmentObject(authManager)
                    .environmentObject(themeManager)
                    .environment(\.appTheme, themeManager.currentTheme)
                    .tint(themeManager.currentTheme.accentColor)
            } else {
                LoginView()
                    .environmentObject(authManager)
                    .environmentObject(themeManager)
                    .environment(\.appTheme, themeManager.currentTheme)
                    .tint(themeManager.currentTheme.accentColor)
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
