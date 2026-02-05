import SwiftUI
import SwiftData
import CloudKit

@main
struct BlackboardApp: App {
    var sharedModelContainer: ModelContainer
    
    init() {
        print("🚀 [BlackboardApp] Initializing...")
        
        let schema = Schema([
            NoteItem.self,
        ])
        
        // Try CloudKit first
        do {
            print("☁️ [BlackboardApp] Attempting CloudKit ModelContainer...")
            
            // Use a named configuration to help with CloudKit
            let cloudConfig = ModelConfiguration(
                "CloudStore",
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            
            let container = try ModelContainer(for: schema, configurations: [cloudConfig])
            print("✅ [BlackboardApp] CloudKit ModelContainer created successfully!")
            self.sharedModelContainer = container
        } catch let error as NSError {
            print("❌ [BlackboardApp] CloudKit FAILED!")
            print("❌ [BlackboardApp] Error: \(error)")
            print("❌ [BlackboardApp] UserInfo: \(error.userInfo)")
            
            // Fallback to local-only storage
            do {
                print("📱 [BlackboardApp] Falling back to local storage...")
                let localConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .none
                )
                self.sharedModelContainer = try ModelContainer(for: schema, configurations: [localConfig])
                print("✅ [BlackboardApp] Local ModelContainer created")
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var subscriptionManager = SubscriptionManager()

    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                ContentView()
                    .environmentObject(authManager)
                    .environmentObject(subscriptionManager)
                    .onAppear {
                        checkCloudKitStatus()
                    }
            } else {
                LoginView()
                    .environmentObject(authManager)
                    .environmentObject(subscriptionManager)
            }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func checkCloudKitStatus() {
        print("🔍 [BlackboardApp] Checking iCloud status...")
        
        if FileManager.default.ubiquityIdentityToken != nil {
            print("✅ [BlackboardApp] iCloud identity token present")
        } else {
            print("❌ [BlackboardApp] No iCloud identity token")
        }
        
        // Use nil to get the default container from entitlements
        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            print("✅ [BlackboardApp] Default iCloud container URL: \(containerURL)")
        } else {
            print("❌ [BlackboardApp] Could not get default iCloud container URL")
        }
        
        // Check the default CloudKit container
        let container = CKContainer.default()
        print("📦 [BlackboardApp] Default CKContainer ID: \(container.containerIdentifier ?? "nil")")
        
        container.accountStatus { status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    print("✅ [BlackboardApp] CloudKit account: Available")
                case .noAccount:
                    print("❌ [BlackboardApp] CloudKit account: No Account")
                case .restricted:
                    print("❌ [BlackboardApp] CloudKit account: Restricted")
                case .couldNotDetermine:
                    print("❌ [BlackboardApp] CloudKit account: Could Not Determine")
                case .temporarilyUnavailable:
                    print("❌ [BlackboardApp] CloudKit account: Temporarily Unavailable")
                @unknown default:
                    print("❌ [BlackboardApp] CloudKit account: Unknown")
                }
                if let error = error {
                    print("❌ [BlackboardApp] CloudKit error: \(error)")
                }
            }
        }
    }
}
