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
        // End any Live Activities orphaned by a previous force-quit or crash.
        // If the user opens a scorecard this session, setupLiveActivity() starts fresh.
        LiveActivityService.shared.cleanupOrphanedActivities()
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Dismiss the Live Activity when the app is force-quit.
        // If the user re-opens the app and enters the scorecard, setupLiveActivity()
        // restarts it automatically.
        LiveActivityService.shared.endAll()
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
        let type = userInfo["type"] as? String ?? ""

        // Check user's notification preferences
        guard NotificationService.shared.shouldShowPush(type: type) else {
            completionHandler([])
            return
        }

        if type == "groupInvite" {
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
        } else if type == "roundStarted" || type == "roundEnded" || type == "gameForceEnded" {
            // All three route to the group's round — gameForceEnded will land on the
            // scorecard where RoundCompleteView auto-shows via the force_completed flag.
            if let groupIdString = userInfo["groupId"] as? String,
               let groupId = UUID(uuidString: groupIdString) {
                NotificationCenter.default.post(name: .didTapRoundNotification, object: groupId)
            }
        }
        // gameDeleted has no navigation target — the round is gone. If the user is still
        // on the scorecard, polling detects status='cancelled' and shows the Game Ended
        // alert; otherwise the app just opens to wherever they left off.
        completionHandler()
    }
}

extension NSNotification.Name {
    static let didTapGroupInviteNotification = NSNotification.Name("didTapGroupInviteNotification")
    static let didTapRoundNotification = NSNotification.Name("didTapRoundNotification")
    static let didEndRound = NSNotification.Name("didEndRound")
    static let didCancelRound = NSNotification.Name("didCancelRound")
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
    @AppStorage("disclaimerAccepted") private var disclaimerAccepted = false
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
        } else if !authService.isOnboarded {
            ZStack {
                Color.white.ignoresSafeArea()
                OnboardingView {
                    justOnboarded = true
                    claimPhoneInvitesIfNeeded()
                }
            }
        } else {
            MainTabView(initialTab: justOnboarded ? .skinGames : .home)
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
    }

    // MARK: - Deep Link Handling

    /// Handle an incoming URL from either custom scheme (onOpenURL) or Universal Links (onContinueUserActivity).
    private func handleIncomingURL(_ url: URL) {
        if let invite = GroupInviteParser.parse(url) {
            if let groupId = invite.groupId {
                // Create invite row if user isn't already a member, then navigate into the group
                Task {
                    guard let userId = try? await SupabaseManager.shared.client.auth.session.user.id else { return }
                    try? await groupService.inviteMember(groupId: groupId, playerId: userId)
                    await MainActor.run {
                        appRouter.shouldRefreshGroups = true
                        appRouter.pendingRoundGroupId = groupId
                    }
                }
            } else {
                appRouter.pendingGroupInvite = invite
            }
            return
        }

        // Live Activity deep link: carry://round/<roundId>?group=<groupId>
        // For grouped rounds we route via the existing pending-round flow
        // (skins tab → open scorecard). For Quick Games (no groupId) we just
        // land on the Home tab where the active round card is visible.
        if url.scheme == "carry", url.host == "round" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let groupIdString = components?.queryItems?.first(where: { $0.name == "group" })?.value
            if let groupIdString, let groupId = UUID(uuidString: groupIdString) {
                appRouter.navigateToTab = "skinGames"
                appRouter.pendingRoundGroupId = groupId
            } else {
                appRouter.navigateToTab = "home"
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
        // Handle scenarios that don't use DebugWorldState directly
        if scenario == .disclaimer {
            DisclaimerView {
                debugScenario = .homeEmpty
            }
        } else {

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
            .ignoresSafeArea(.container, edges: .bottom)
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
            .ignoresSafeArea(.container, edges: .bottom)
            .onAppear { if let p = world.isPremium { storeService.isPremium = p } }

        case .onboarding:
            DebugOnboardingFlowView(onComplete: {
                debugScenario = .homeEmpty
            })

        case .onboarding3Step:
            // Skip auth — go straight to onboarding with Apple name pre-filled
            ZStack {
                Color.white.ignoresSafeArea()
                OnboardingView {
                    debugScenario = .homeEmpty
                }
            }

        case .onboarding4Step:
            // Skip auth — go straight to onboarding with no name (forces name step)
            ZStack {
                Color.white.ignoresSafeArea()
                OnboardingView {
                    debugScenario = .homeEmpty
                }
                .onAppear {
                    // Clear name so hasAppleName = false
                    if var user = authService.currentUser {
                        user.firstName = ""
                        user.lastName = ""
                        user.displayName = "Player"
                        authService.currentUser = user
                    }
                }
            }

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
        } // else
    }
    #endif
}

#if DEBUG
private struct DebugOnboardingFlowView: View {
    @EnvironmentObject var authService: AuthService
    var onComplete: () -> Void
    @State private var showOnboarding = false

    var body: some View {
        if showOnboarding {
            ZStack {
                Color.white.ignoresSafeArea()
                OnboardingView(onComplete: onComplete)
            }
        } else {
            AuthView(onDebugSkip: {
                authService.isAuthenticated = true
                authService.isOnboarded = false
                showOnboarding = true
            })
        }
    }
}
#endif

