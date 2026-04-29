import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var authService: AuthService
    @State private var error: String?
    @State private var isSigningIn = false
    @State private var showEmailSheet = false

    /// Optional: in debug/test flows, tapping the sign-in button calls this instead of real Apple Sign-In.
    var onDebugSkip: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            let w = geo.size.width

            VStack(spacing: 0) {
                    // ~32% from screen top to logo
                    Spacer()
                        .frame(height: h * 0.32)

                    // Logo: icon + wordmark + tagline
                    Image("carry-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: w * 0.683) // 268/393
                        .accessibilityLabel("Carry")

                    // ~7.7% gap to text block
                    Spacer()
                        .frame(height: h * 0.077)

                    // Text block
                    VStack(spacing: 12) {
                        Text("Track Your Skins Games")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                            .tracking(CarryTracking.tight)

                        Text("Set up skins games in seconds,\nfollow the action live,\n& crown your winners.")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .tracking(CarryTracking.tight)
                            .lineSpacing(6)
                    }
                    .multilineTextAlignment(.center)

                    // Flexible gap pushes button toward bottom
                    Spacer()

                    // Sign-in buttons (Email, Google, Apple) per Figma 1324:2750
                    VStack(spacing: 12) {
                        // Email
                        Button { showEmailSheet = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope")
                                    .font(.system(size: 20))
                                Text("Sign in using Email")
                                    .font(.carry.label)
                                    .tracking(CarryTracking.tight)
                            }
                            .foregroundColor(Color(hexString: "#064102"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 18).fill(Color(hexString: "#BCF0B5")))
                        }
                        .disabled(isSigningIn)

                        // Google
                        Button(action: handleGoogleSignIn) {
                            HStack(spacing: 12) {
                                Image("google-logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                Text("Sign in using Google")
                                    .font(.carry.label)
                                    .tracking(CarryTracking.tight)
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 18).fill(.white))
                        }
                        .disabled(isSigningIn)

                        // Apple
                        if let skip = onDebugSkip {
                            // Debug mode: tappable button that skips real sign-in
                            Button(action: skip) {
                                HStack(spacing: 12) {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 20))
                                    Text("Sign in using Apple")
                                        .font(.carry.label)
                                        .tracking(CarryTracking.tight)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(RoundedRectangle(cornerRadius: 18).fill(.black))
                            }
                        } else {
                            // Real sign-in flow — use native Apple button directly
                            SignInWithAppleButton(.signIn) { request in
                                request.requestedScopes = [.fullName, .email]
                            } onCompletion: { result in
                                handleSignIn(result: result)
                            }
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 52)
                            .cornerRadius(18)
                            .disabled(isSigningIn)
                        }
                    }
                    .padding(.horizontal, w * 0.084)

                    if isSigningIn {
                        ProgressView()
                            .tint(.white)
                            .padding(.top, 12)
                    }

                    if let error {
                        Text(error)
                            .font(.carry.captionLG)
                            .foregroundColor(Color.systemRedColor)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }

                    // Terms
                    HStack(spacing: 0) {
                        Text("By continuing you agree to ")
                            .foregroundColor(Color(hexString: "#A8A8A8"))
                        Button {
                            if let url = URL(string: "https://carryapp.site/terms.html") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Terms")
                                .underline()
                                .foregroundColor(Color.textMid)
                        }
                        Text(" & ")
                            .foregroundColor(Color(hexString: "#A8A8A8"))
                        Button {
                            if let url = URL(string: "https://carryapp.site/privacy.html") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Privacy Policy")
                                .underline()
                                .foregroundColor(Color.textMid)
                        }
                    }
                    .font(.carry.captionLG)
                    .tracking(CarryTracking.tight)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)

                    // ~4% from screen bottom
                    Spacer()
                        .frame(height: h * 0.04)
                }
            .frame(width: w, height: h)
            .offset(y: -geo.safeAreaInsets.top)
            .background(
                Image("welcome-bg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()
                    .accessibilityHidden(true)
            )
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .sheet(isPresented: $showEmailSheet) {
            EmailAuthSheet()
                .environmentObject(authService)
        }
    }

    private func handleGoogleSignIn() {
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else { return }
        isSigningIn = true
        error = nil
        Task {
            do {
                let tokens = try await GoogleSignInService.signIn(presenting: rootVC)
                try await authService.signInWithGoogle(idToken: tokens.idToken, accessToken: tokens.accessToken)
            } catch GoogleSignInService.Failure.cancelled {
                // user dismissed — silent
            } catch let e as GoogleSignInService.Failure {
                self.error = e.errorDescription ?? "Sign in failed. Please try again."
            } catch {
                self.error = "Sign in failed. Please try again."
            }
            isSigningIn = false
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
                    self.error = "Sign in failed. Please try again."
                }
                isSigningIn = false
            }
        case .failure(let err):
            // Error 1001 = user cancelled — don't show anything
            if (err as NSError).code == 1001 { return }
            error = "Sign in failed. Please try again."
        }
    }
}
