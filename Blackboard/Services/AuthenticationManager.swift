import Foundation
import AuthenticationServices
import Combine

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var userId: String?
    
    init() {
        checkUserStatus()
    }
    
    func checkUserStatus() {
        // Check if we have a stored user ID
        if let storedUserId = UserDefaults.standard.string(forKey: "userId") {
            if storedUserId == "guest_user" {
                self.userId = storedUserId
                self.isAuthenticated = true
                return
            }
            
            let appleIDProvider = ASAuthorizationAppleIDProvider()
            appleIDProvider.getCredentialState(forUserID: storedUserId) { (credentialState, error) in
                DispatchQueue.main.async {
                    switch credentialState {
                    case .authorized:
                        self.isAuthenticated = true
                        self.userId = storedUserId
                    case .revoked, .notFound:
                        self.isAuthenticated = false
                        self.userId = nil
                    default:
                        break
                    }
                }
            }
        }
    }
    
    func handleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            if let appleIDCredential = auth.credential as? ASAuthorizationAppleIDCredential {
                let userId = appleIDCredential.user
                UserDefaults.standard.set(userId, forKey: "userId")
                self.userId = userId
                self.isAuthenticated = true
            }
        case .failure(let error):
            print("Sign in failed: \(error.localizedDescription)")
        }
    }
    
    func signOut() {
        UserDefaults.standard.removeObject(forKey: "userId")
        self.userId = nil
        self.isAuthenticated = false
    }
    
    func signInAsGuest() {
        let guestId = "guest_user"
        UserDefaults.standard.set(guestId, forKey: "userId")
        self.userId = guestId
        self.isAuthenticated = true
    }
    
    /// Permanently deletes the user's account and all associated data
    /// This fulfills App Store Guideline 5.1.1(v) requirement for account deletion
    func deleteAccount() {
        // Delete all stored canvas files (drawing data)
        StorageManager.shared.deleteAllCanvases()
        
        // Delete SwiftData store (notes and folders)
        StorageManager.shared.deleteSwiftDataStore()
        
        // Clear all UserDefaults
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
        }
        
        // Clear specific keys as fallback
        UserDefaults.standard.removeObject(forKey: "userId")
        UserDefaults.standard.synchronize()
        
        // Sign out
        self.userId = nil
        self.isAuthenticated = false
        
        print("[AuthenticationManager] Account deleted and all data cleared")
    }
}
