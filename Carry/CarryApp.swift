import SwiftUI

@main
struct CarryApp: App {
    @StateObject private var authService = AuthService()

    // Set to false to enable auth gate (requires Apple Developer account)
    private let devMode = false

    // Debug: jump to a specific screen for testing. Set to nil for normal flow.
    // Options: "scorecard", "onboarding", "groups", "home"
    private let debugScreen: String? = nil

    var body: some Scene {
        WindowGroup {
            Group {
                if let screen = debugScreen {
                    switch screen {
                    case "home":
                        MainTabView()
                    case "groups":
                        RoundCoordinatorView()
                    case "onboarding":
                        OnboardingView()
                    default:
                        ScorecardView()
                    }
                } else if devMode {
                    ScorecardView()
                } else if authService.isLoading {
                    ProgressView()
                } else if !authService.isAuthenticated {
                    AuthView()
                } else if !authService.isOnboarded {
                    OnboardingView()
                } else {
                    MainTabView()
                }
            }
            .environmentObject(authService)
        }
    }
}
