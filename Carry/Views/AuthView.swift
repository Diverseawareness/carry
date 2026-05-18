import SwiftUI
import AuthenticationServices
import UIKit

/// `.preferredColorScheme(.dark)` alone doesn't reliably flip the iOS status
/// bar to light-content on this screen — SwiftUI's hosting controller
/// doesn't always forward the trait. Force-set the host window's
/// `overrideUserInterfaceStyle` AND walk the VC chain calling
/// `setNeedsStatusBarAppearanceUpdate` so the status bar actually refreshes.
/// Reset on disappear so other screens (Onboarding, Home) keep their default
/// (dark text on light backgrounds).
private extension View {
    func forcesLightStatusBar() -> some View {
        self
            .onAppear { applyWindowStyle(.dark) }
            .onDisappear { applyWindowStyle(.unspecified) }
    }
}

private func applyWindowStyle(_ style: UIUserInterfaceStyle) {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
        for window in scene.windows {
            window.overrideUserInterfaceStyle = style
            var vc = window.rootViewController
            while let current = vc {
                current.setNeedsStatusBarAppearanceUpdate()
                vc = current.presentedViewController
            }
        }
    }
}

/// Drives Apple Sign In via `ASAuthorizationController` so we can wrap it in
/// a custom button that matches the typography of the Email + Google buttons
/// (the native `SignInWithAppleButton` doesn't let us override its font size).
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var completion: ((Result<ASAuthorization, Error>) -> Void)?

    func signIn(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        completion?(.success(authorization))
        completion = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion?(.failure(error))
        completion = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? UIWindow()
    }
}

struct AuthView: View {
    @EnvironmentObject var authService: AuthService
    @State private var error: String?
    @State private var isSigningIn = false
    @State private var showEmailSheet = false
    @State private var appleCoordinator = AppleSignInCoordinator()
    // Cross-provider link prompt state. When Google sign-in collides with an
    // existing Apple/email account, AuthService stashes the Google tokens and
    // these flip true to surface the confirmation alert. existingProvider
    // drives the prompt copy ("sign in with Apple" vs "sign in with your
    // password").
    @State private var showLinkPrompt = false
    @State private var linkPromptExistingProvider: String = ""

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

                    // Logo: fixed 268×170pt frame per Figma welcome_v2,
                    // scaledToFit preserves aspect ratio inside the bounds.
                    Image("carry-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 268, height: 170)
                        .accessibilityLabel("Carry")

                    // 20pt gap from logo to headline per Figma welcome_v2
                    Spacer()
                        .frame(height: 20)

                    // Text block — fixedSize on vertical axis prevents the
                    // subtitle from being clipped to one line on tighter
                    // screens when the spacer below tries to expand.
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
                    .fixedSize(horizontal: false, vertical: true)

                    // 55pt minimum gap between tagline and Email button per
                    // Figma welcome_v2; flexes to absorb extra screen height
                    // so the buttons stay anchored near the bottom.
                    Spacer(minLength: 55)

                    // Sign-in buttons (Email, Google, Apple) per Figma 1324:2750
                    VStack(spacing: 12) {
                        // Email — .plain button style + manual loading dim,
                        // matching Google so neither shifts on press.
                        Button { showEmailSheet = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope")
                                    .font(.system(size: 20))
                                Text("Sign in with Email")
                                    .font(.carry.label)
                                    .tracking(CarryTracking.tight)
                            }
                            .foregroundColor(Color(hexString: "#064102"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 18).fill(Color(hexString: "#BCF0B5")))
                        }
                        .buttonStyle(.plain)
                        .opacity(isSigningIn ? 0.85 : 1)
                        .disabled(isSigningIn)

                        // Google — .plain button style suppresses the default
                        // press animation (the small downward shift); opacity
                        // dims to 85% only while a sign-in is in flight.
                        // Spinner is inline (replaces the label) so the
                        // surrounding layout doesn't reflow when isSigningIn
                        // flips — a standalone ProgressView below would
                        // compress the flex Spacer above and shift all three
                        // buttons up.
                        Button(action: handleGoogleSignIn) {
                            ZStack {
                                if isSigningIn {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    HStack(spacing: 12) {
                                        Image("googleIcon")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 20, height: 20)
                                        Text("Sign in with Google")
                                            .font(.carry.label)
                                            .tracking(CarryTracking.tight)
                                    }
                                }
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 18).fill(.white))
                        }
                        .buttonStyle(.plain)
                        .opacity(isSigningIn ? 0.85 : 1)
                        .disabled(isSigningIn)

                        // Apple — custom button (not native SignInWithAppleButton)
                        // so the typography matches Email + Google. Triggers
                        // ASAuthorizationController via AppleSignInCoordinator.
                        Button(action: {
                            if let skip = onDebugSkip {
                                skip()
                            } else {
                                handleAppleSignIn()
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 20))
                                Text("Sign in with Apple")
                                    .font(.carry.label)
                                    .tracking(CarryTracking.tight)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 18).fill(.black))
                        }
                        .buttonStyle(.plain)
                        .opacity(isSigningIn ? 0.85 : 1)
                        .disabled(isSigningIn)
                    }
                    .padding(.horizontal, w * 0.084)

                    if let error {
                        Text(error)
                            .font(.carry.captionLG)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }

                    // Terms — white at 50% opacity, single visual color across
                    // copy + links per Figma welcome_v2.
                    HStack(spacing: 0) {
                        Text("By continuing you agree to ")
                        Button {
                            if let url = URL(string: "https://carryapp.site/terms.html") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Terms")
                                .underline()
                        }
                        Text(" & ")
                        Button {
                            if let url = URL(string: "https://carryapp.site/privacy.html") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Privacy Policy")
                                .underline()
                        }
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .font(.carry.captionLG)
                    .tracking(CarryTracking.tight)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)

                    // Bottom margin — base ~4% of screen + 24pt nudge so the
                    // button stack sits noticeably higher (Figma welcome_v2).
                    Spacer()
                        .frame(height: h * 0.04 + 24)
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
        .forcesLightStatusBar()
        // Surface "We found your Carry account" prompt after a Google sign-in
        // collides with an existing different-provider account. Tapping the
        // primary action routes the user through the existing provider; the
        // post-sign-in handler then auto-links Google via consumePendingLink.
        .alert(
            "Found your Carry account",
            isPresented: $showLinkPrompt,
            presenting: linkPromptExistingProvider
        ) { provider in
            switch provider {
            case "apple":
                Button("Sign in with Apple") { handleAppleSignIn() }
                Button("Cancel", role: .cancel) { authService.pendingProviderLink = nil }
            case "email":
                Button("Use email & password") { showEmailSheet = true }
                Button("Cancel", role: .cancel) { authService.pendingProviderLink = nil }
            default:
                Button("OK", role: .cancel) { authService.pendingProviderLink = nil }
            }
        } message: { provider in
            switch provider {
            case "apple":
                Text("An account for this email already exists with Apple Sign-In. To add Google, sign in with Apple — we'll link Google to your account automatically.")
            case "email":
                Text("An account for this email already exists with email & password. Sign in with your password and we'll link Google to your account automatically.")
            default:
                Text("An account already exists for this email.")
            }
        }
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
            // Fetch Google tokens first so we can reference them in BOTH the
            // happy-path sign-in call AND the dedupe-collision branch below
            // (which needs to stash them on AuthService so the subsequent
            // Apple/email sign-in can auto-link).
            let tokens: GoogleSignInService.Tokens
            do {
                tokens = try await GoogleSignInService.signIn(presenting: rootVC)
            } catch GoogleSignInService.Failure.cancelled {
                isSigningIn = false
                return  // silent
            } catch let e as GoogleSignInService.Failure {
                self.error = e.errorDescription ?? "Sign in failed. Please try again."
                isSigningIn = false
                return
            } catch {
                self.error = "Couldn't connect to Google. Please try again."
                isSigningIn = false
                return
            }

            do {
                try await authService.signInWithGoogle(
                    idToken: tokens.idToken,
                    accessToken: tokens.accessToken,
                    nonce: tokens.rawNonce
                )
            } catch AuthError.emailAlreadyRegistered(let existingProvider) {
                // Dedupe trigger blocked the signup because this email already
                // has a different-provider account. Stash the Google tokens and
                // prompt the user to sign in with the existing provider — after
                // that sign-in succeeds, AuthService.consumePendingLink() will
                // auto-link Google to the now-authenticated user (flow C from
                // the auth-v2 status doc).
                authService.pendingProviderLink = PendingProviderLink(
                    provider: "google",
                    idToken: tokens.idToken,
                    accessToken: tokens.accessToken,
                    rawNonce: tokens.rawNonce,
                    existingProvider: existingProvider
                )
                self.linkPromptExistingProvider = existingProvider
                self.showLinkPrompt = true
            } catch let e as AuthError {
                self.error = e.errorDescription ?? "Sign in failed. Please try again."
            } catch {
                self.error = "Sign in failed. Please try again."
            }
            isSigningIn = false
        }
    }

    private func handleAppleSignIn() {
        appleCoordinator.signIn { result in
            handleSignIn(result: result)
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
                    // If we got here from a Google-collision link prompt,
                    // AuthService has stashed the Google tokens — drain them
                    // now so Google auto-links to the just-signed-in user.
                    // No-op when there's no pending link.
                    await authService.consumePendingLink()
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
