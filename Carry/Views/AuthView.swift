import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var authService: AuthService
    @State private var error: String?
    @State private var isSigningIn = false

    var body: some View {
        ZStack {
            Color(hex: "#F0F0F0").ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Logo
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(LinearGradient(
                            colors: [Color(hex: "#1B5E20"), Color(hex: "#2E7D32")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 80, height: 80)
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color(hex: "#C4A450").opacity(0.3), lineWidth: 2)
                        .frame(width: 72, height: 72)
                    Text("$")
                        .font(.system(size: 36, weight: .heavy, design: .serif))
                        .foregroundColor(Color(hex: "#C4A450"))
                }

                VStack(spacing: 8) {
                    Text("Carry")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                    Text("Golf Skins Tracker")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "#999999"))
                }

                Spacer()

                // Sign in button
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleSignIn(result: result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .cornerRadius(12)
                .padding(.horizontal, 40)
                .disabled(isSigningIn)

                if isSigningIn {
                    ProgressView()
                        .tint(Color(hex: "#C4A450"))
                }

                if let error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#E05555"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer()
                    .frame(height: 80)
            }
        }
    }

    private func handleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            isSigningIn = true
            error = nil
            Task {
                do {
                    try await authService.signInWithApple(credential: credential)
                } catch {
                    self.error = error.localizedDescription
                }
                isSigningIn = false
            }
        case .failure(let err):
            error = err.localizedDescription
        }
    }
}
