import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.appTheme) private var appTheme
    
    var body: some View {
        ZStack {
            appTheme.editorialBackground
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "pencil.and.outline")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(appTheme.accentColor.opacity(0.7))
                
                Text("MiniClone")
                    .font(.system(size: 36, weight: .regular, design: .serif))
                    .foregroundColor(.primary)
                
                Text("Sign in to continue")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.secondary)
                    .tracking(0.3)
                
                SignInWithAppleButton(
                    onRequest: { request in
                        request.requestedScopes = [.fullName, .email]
                    },
                    onCompletion: { result in
                        authManager.handleSignIn(result: result)
                    }
                )
                .signInWithAppleButtonStyle(.black)
                .frame(width: 260, height: 44)
                .padding(.top, 20)
                
                Button(action: {
                    authManager.signInAsGuest()
                }) {
                    Text("Continue as Guest")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
        }
    }
}
