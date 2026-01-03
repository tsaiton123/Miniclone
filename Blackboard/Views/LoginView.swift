import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "pencil.and.outline")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.primary)
            
            Text("Cognote")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Sign in to continue")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            SignInWithAppleButton(
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: { result in
                    authManager.handleSignIn(result: result)
                }
            )
            .signInWithAppleButtonStyle(.black)
            .frame(width: 280, height: 45)
            .padding(.top, 20)
            
            Button(action: {
                authManager.signInAsGuest()
            }) {
                Text("Continue as Guest")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 10)
        }
    }
}
