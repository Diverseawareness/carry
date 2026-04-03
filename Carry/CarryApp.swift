import SwiftUI
import PostHog

// MARK: - Shake Gesture Detection

#if DEBUG
extension NSNotification.Name {
    static let deviceDidShake = NSNotification.Name("deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}
#endif

// MARK: - App Delegate (Push Notification Token)

class CarryAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        #if DEBUG
        print("[Push] Device token: \(token)")
        #endif
        Task { await NotificationService.shared.saveDeviceToken(token) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("[Push] Failed to register: \(error.localizedDescription)")
        #endif
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        if let type = userInfo["type"] as? String, type == "groupInvite" {
            // Immediately trigger invite check when push arrives in foreground
            NotificationCenter.default.post(name: .didTapGroupInviteNotification, object: nil)
        }
        completionHandler([.banner, .sound])
    }

    // Handle notification tap — trigger invite check or open round
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let type = userInfo["type"] as? String
        if type == "groupInvite" {
            NotificationCenter.default.post(name: .didTapGroupInviteNotification, object: nil)
        } else if type == "roundStarted" || type == "roundEnded" {
            if let groupIdString = userInfo["groupId"] as? String,
               let groupId = UUID(uuidString: groupIdString) {
                NotificationCenter.default.post(name: .didTapRoundNotification, object: groupId)
            }
        }
        completionHandler()
    }
}

extension NSNotification.Name {
    static let didTapGroupInviteNotification = NSNotification.Name("didTapGroupInviteNotification")
    static let didTapRoundNotification = NSNotification.Name("didTapRoundNotification")
    static let didEndRound = NSNotification.Name("didEndRound")
    static let showNewGamePicker = NSNotification.Name("showNewGamePicker")
    static let showDebugGuestClaim = NSNotification.Name("showDebugGuestClaim")
}

@main
struct CarryApp: App {
    @UIApplicationDelegateAdaptor(CarryAppDelegate.self) var appDelegate
    @StateObject private var authService = AuthService()
    @StateObject private var appRouter = AppRouter()
    @StateObject private var storeService = StoreService()

    // Set to false to enable auth gate (requires Apple Developer account)
    #if DEBUG
    private let devMode = false
    #else
    private let devMode = false
    #endif

    #if DEBUG
    @State private var debugScenario: DebugScenario? = nil
    @State private var showDebugMenu = false
    #endif
    @State private var justOnboarded = false
    private let groupService = GroupService()

    init() {
        let config = PostHogConfig(
            apiKey: "phc_sIOBZwKpwwF00BJCj0ElU90sCdHsVVmGNcxYolduaRb",
            host: "https://us.i.posthog.com"
        )
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = true
        PostHogSDK.shared.setup(config)

        // Increase URL cache for avatar images
        URLCache.shared.memoryCapacity = 50 * 1024 * 1024   // 50 MB
        URLCache.shared.diskCapacity = 200 * 1024 * 1024    // 200 MB
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    #if DEBUG
                    if let scenario = debugScenario {
                        debugView(for: scenario)
                    } else if devMode {
                        MainTabView()
                    } else {
                        releaseRootView
                    }
                    #else
                    releaseRootView
                    #endif
                }

                // Floating debug button (dev mode only)
                #if DEBUG
                if devMode {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button { showDebugMenu = true } label: {
                                Image(systemName: "ladybug.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(Color.debugOrange.opacity(0.85)))
                                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                            }
                            .padding(.trailing, 12)
                            .padding(.bottom, 80)
                        }
                    }
                }
                #endif
            }
            .preferredColorScheme(.light)
            .environmentObject(authService)
            .environmentObject(appRouter)
            .environmentObject(storeService)
            .onReceive(NotificationCenter.default.publisher(for: .didTapGroupInviteNotification)) { _ in
                // Navigate to Home tab where invite cards will appear
                appRouter.navigateToTab = "home"
            }
            .onReceive(NotificationCenter.default.publisher(for: .didTapRoundNotification)) { notification in
                if let groupId = notification.object as? UUID {
                    appRouter.navigateToTab = "skinGames"
                    appRouter.pendingRoundGroupId = groupId
                }
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                // Universal Links: https://carryapp.site/invite?group=UUID
                if let url = activity.webpageURL {
                    handleIncomingURL(url)
                }
            }
            #if DEBUG
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                showDebugMenu = true
            }
            .fullScreenCover(isPresented: $showDebugMenu) {
                DebugMenuView(activeScenario: debugScenario) { scenario in
                    debugScenario = scenario
                }
                .environmentObject(authService)
                .environmentObject(appRouter)
                .environmentObject(storeService)
            }
            #endif
        }
    }

    // MARK: - Release Root View

    @ViewBuilder
    private var releaseRootView: some View {
        ZStack {
        if authService.isLoading {
            ZStack {
                Color.white.ignoresSafeArea()
                GolfBallLoader(size: 60)
            }
        } else if !authService.isAuthenticated {
            AuthView()
                .transition(.opacity)
        } else if !authService.isOnboarded {
            ZStack {
                Color.white.ignoresSafeArea()
                OnboardingView {
                    justOnboarded = true
                    claimPhoneInvitesIfNeeded()
                }
            }
            .transition(.opacity)
        } else {
            MainTabView(initialTab: justOnboarded ? .skinGames : .home)
                .transition(.opacity)
                .onAppear {
                    if justOnboarded {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            justOnboarded = false
                        }
                    } else {
                        // Returning user — claim phone invites
                        claimPhoneInvitesIfNeeded()
                    }
                }
        }
        }
        .animation(.easeOut(duration: 0.35), value: authService.isAuthenticated)
        .animation(.easeOut(duration: 0.35), value: authService.isOnboarded)
    }

    // MARK: - Deep Link Handling

    /// Handle an incoming URL from either custom scheme (onOpenURL) or Universal Links (onContinueUserActivity).
    private func handleIncomingURL(_ url: URL) {
        if let invite = GroupInviteParser.parse(url) {
            if let groupId = invite.groupId {
                // Create invite row if user isn't already a member, then navigate to Home
                Task {
                    guard let userId = try? SupabaseManager.shared.client.auth.session.user.id else { return }
                    try? await groupService.inviteMember(groupId: groupId, playerId: userId)
                    await MainActor.run {
                        appRouter.navigateToTab = "home"
                    }
                }
            } else {
                appRouter.pendingGroupInvite = invite
            }
        }
    }

    /// Claim any phone-based group invites for the current user.
    /// Called after sign-in or onboarding completes so SMS-invited users get their groups.
    private func claimPhoneInvitesIfNeeded() {
        Task {
            do {
                let session = try await SupabaseManager.shared.client.auth.session
                let phone = session.user.phone ?? ""
                guard !phone.isEmpty else { return }

                let userId = session.user.id
                let pending = try await groupService.checkPhoneInvites(phone: phone)
                for membership in pending {
                    try await groupService.claimPhoneInvite(membershipId: membership.id, realPlayerId: userId)
                }
                if !pending.isEmpty {
                    // Navigate to Home tab where invite cards will appear
                    await MainActor.run {
                        appRouter.navigateToTab = "home"
                    }
                }
            } catch {
                #if DEBUG
                print("[Carry] Phone claim failed: \(error)")
                #endif
            }
        }
    }

    // MARK: - Debug Screen Router

    #if DEBUG
    @ViewBuilder
    private func debugView(for scenario: DebugScenario) -> some View {
        let world = scenario.worldState

        switch world.startScreen {
        case .home:
            MainTabView(initialGroups: world.groups)
                .onAppear { if let p = world.isPremium { storeService.isPremium = p } }

        case .homeEmpty:
            MainTabView(initialGroups: [])
                .onAppear { if let p = world.isPremium { storeService.isPremium = p } }

        case .groupSetup:
            RoundCoordinatorView(
                currentUserId: world.currentUserId,
                creatorId: world.creatorId,
                preselectedCourse: world.course,
                skipCourseSelection: true,
                initialTeeTime: Calendar.current.date(byAdding: .hour, value: 2, to: Date()),
                initialBuyIn: Double(world.roundConfig.buyIn),
                onExit: { debugScenario = .home }
            )
            .onAppear { if let p = world.isPremium { storeService.isPremium = p } }

        case .scorecard:
            RoundCoordinatorView(
                currentUserId: world.currentUserId,
                creatorId: world.creatorId,
                preselectedCourse: world.course,
                skipCourseSelection: true,
                initialTeeTime: Calendar.current.date(byAdding: .hour, value: -1, to: Date()),
                initialBuyIn: Double(world.roundConfig.buyIn),
                initialRoundConfig: world.roundConfig,
                initialDemoMode: world.demoMode,
                onExit: { debugScenario = .home },
                isViewer: world.isViewer
            )
            .onAppear { if let p = world.isPremium { storeService.isPremium = p } }

        case .onboarding:
            DebugOnboardingFlowView(onComplete: {
                debugScenario = .homeEmpty
            })

        case .welcome:
            AuthView()

        case .inviteOverlay:
            // Overlay removed — invites now show as Home tab cards
            MainTabView(initialTab: .home)

        case .paywall:
            PaywallView()

        case .createGroup:
            MainTabView(initialTab: .skinGames)
        }
    }
    #endif
}

#if DEBUG
/// Debug wrapper: Welcome → Onboarding → Home.
private struct DebugOnboardingFlowView: View {
    @EnvironmentObject var authService: AuthService
    var onComplete: () -> Void
    @State private var showOnboarding = false

    var body: some View {
        if showOnboarding {
            OnboardingView(onComplete: onComplete)
                .transition(.move(edge: .trailing))
        } else {
            AuthView(onDebugSkip: {
                authService.isAuthenticated = true
                authService.isOnboarded = false
                withAnimation(.easeInOut(duration: 0.3)) {
                    showOnboarding = true
                }
            })
        }
    }
}
#endif

