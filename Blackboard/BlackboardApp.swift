import SwiftUI
import SwiftData

@main
struct BlackboardApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            NoteItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var subscriptionManager = SubscriptionManager()

    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                ContentView()
                    .environmentObject(authManager)
                    .environmentObject(subscriptionManager)
            } else {
                LoginView()
                    .environmentObject(authManager)
                    .environmentObject(subscriptionManager)
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
