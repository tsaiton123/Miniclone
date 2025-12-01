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
}
