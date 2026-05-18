import SwiftUI
import PostHog
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

// MARK: - Shake Gesture Detection

// Shake fires a notification in ALL builds.
// - Release builds: GroupManagerView listens to show a fullscreen QR (so
//   members in the same foursome can scan to join without passing phones).
// - Debug builds: CarryApp listens to open the Debug menu (see below).
extension NSNotification.Name {
    static let deviceDidShake = NSNotification.Name("deviceDidShake")
    /// Fired by the Debug menu's "Preview Fullscreen QR" action so Debug
    /// builds can exercise the Release-only shake-to-QR flow without
    /// triggering the Debug menu itself. GroupManagerView listens for this.
    static let debugPreviewFullScreenQR = NSNotification.Name("debugPreviewFullScreenQR")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}

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

        // Always register on launch. Apple says this is a no-op if the user
        // hasn't authorized notifications yet, but refreshes the device token
        // whenever it has changed — including when the aps-environment
        // entitlement flips between development and production (e.g., when a
        // user upgrades from a dev/TestFlight build to an App Store build, or
        // restores from a backup). Without this, a stale sandbox token can
        // linger in the backend after a prod build is installed, causing
        // pushes to silently fail.
        UIApplication.shared.registerForRemoteNotifications()

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
        if type == "memberJoined" || type == "memberDeclined" {
            // Creator viewing GroupManagerView when an invitee accepts/declines:
            // poll every 30s would catch it eventually, but the push gives us
            // an immediate signal — refresh the group state now.
            if let groupIdString = userInfo["groupId"] as? String,
               let groupId = UUID(uuidString: groupIdString) {
                NotificationCenter.default.post(name: .didReceiveGroupStateChangePush, object: groupId)
            }
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
    /// Posted when iOS locally archives a concludedRound into roundHistory
    /// (e.g., user declined the convert prompt). Tells MainTabView to stamp
    /// `skinGameGroupsLocallyMutatedAt` so the next poll's empty-result
    /// guard kicks in. Without this, the Home tab showed empty state for
    /// ~15s after the convert decline (Bug G).
    static let didLocallyArchiveRound = NSNotification.Name("didLocallyArchiveRound")
    static let showNewGamePicker = NSNotification.Name("showNewGamePicker")
    /// Posted when the user taps "Yes" on the Demo Round convert sheet.
    /// HomeView listens, clears the demo overlay, switches to skinGames tab,
    /// then forwards `.showCreateSkinsGroup` so GroupsListView opens the
    /// Create Group sheet directly (bypassing the QG/SG picker — the demo
    /// flow only converts into a recurring Skins Group).
    static let demoRoundAcceptedConvert = NSNotification.Name("demoRoundAcceptedConvert")
    /// Forwarded from `.demoRoundAcceptedConvert`. GroupsListView listens
    /// and sets `showCreateGroup = true` directly. Lands the user in the
    /// new group's details after creation.
    static let showCreateSkinsGroup = NSNotification.Name("showCreateSkinsGroup")
    /// Posted when the creator's device receives a memberJoined / memberDeclined
    /// push while the app is foregrounded. Object = group UUID. GroupManagerView
    /// listens to refresh its roster immediately instead of waiting for the 30s
    /// auto-refresh poll.
    static let didReceiveGroupStateChangePush = NSNotification.Name("didReceiveGroupStateChangePush")
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
        // URLCache setup is trivially fast — keep it sync so avatars can
        // start caching on first fetch.
        URLCache.shared.memoryCapacity = 50 * 1024 * 1024   // 50 MB
        URLCache.shared.diskCapacity = 200 * 1024 * 1024    // 200 MB

        #if DEBUG
        // Reset the first-launch Demo Round dismissal on every debug build
        // launch so the card always re-renders on Home (when groups empty).
        // Lets us test the dismiss UX within a session and verify the card
        // visual without manually toggling UserDefaults every iteration.
        // Production builds preserve show-once behavior.
        DemoRoundController.isDismissed = false
        // Same idea for the first-group QR coach mark: reset every cold
        // launch so we can verify rendering + dismiss behavior without
        // manually wiping UserDefaults.
        UserDefaults.standard.removeObject(forKey: "hasSeenFirstQuickGameQRCoachMark")
        UserDefaults.standard.removeObject(forKey: "hasSeenFirstSkinsGroupQRCoachMark")
        #endif

        // PostHog setup runs on a detached background task. Its setup() kicks
        // off a feature-flag config fetch that has caused 8-22s startup hangs
        // on iPhone 12 when us-assets.i.posthog.com is slow. Doing this off
        // main means the UI renders and stays responsive regardless of
        // PostHog's reachability. A small delay before setup also gives
        // SwiftUI's first frame room to paint before PostHog touches the
        // URL loading system.
        Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s
            let config = PostHogConfig(
                apiKey: "phc_sIOBZwKpwwF00BJCj0ElU90sCdHsVVmGNcxYolduaRb",
                host: "https://us.i.posthog.com"
            )
            config.captureApplicationLifecycleEvents = true
            config.captureScreenViews = true
            PostHogSDK.shared.setup(config)
        }
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
                // Google Sign-In returns to the app via a custom URL scheme
                // matching the reversed iOS client ID. Let GIDSignIn claim
                // the URL first; only fall through to invite/round handling
                // if it wasn't a Google callback.
                #if canImport(GoogleSignIn)
                if GIDSignIn.sharedInstance.handle(url) {
                    return
                }
                #endif
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
        // Supabase auth callback (email confirmation, magic link, password
        // reset). When the user taps the link in their email, the verify
        // endpoint redirects to carryapp.site/auth/confirm with tokens in
        // the URL fragment — iOS Universal Links route that back into the
        // app, where we exchange it for a session.
        if url.host == "carryapp.site", url.path.hasPrefix("/auth/") {
            Task {
                do {
                    try await authService.handleAuthCallback(url: url)
                } catch {
                    // Log the actual cause so this isn't a black box on failure.
                    // Common shape: the URL fragment carrying the recovery /
                    // signup tokens got stripped somewhere (e.g. web fallback's
                    // "Open Carry" link didn't preserve the hash), so
                    // session(from:) has nothing to parse.
                    NSLog("‼️AUTHDEBUG handleAuthCallback failed url=%@ error=%@",
                          url.absoluteString,
                          String(reflecting: error))
                    ToastManager.shared.error("Couldn't complete sign-in. Try signing in with your email and password.")
                }
            }
            return
        }

        if let invite = GroupInviteParser.parse(url) {
            if let groupId = invite.groupId {
                // Tapping the invite link / scanning the QR is itself the
                // accept — promote straight to active so the user lands inside
                // the group with no second confirmation step (and no "You're
                // Invited!" push fired back at the device that just scanned).
                Task {
                    guard let userId = try? await SupabaseManager.shared.client.auth.session.user.id else {
                        #if DEBUG
                        print("[handleIncomingURL] no auth session for groupId=\(groupId)")
                        #endif
                        return
                    }
                    do {
                        let groupName = try await groupService.joinGroupViaInvite(groupId: groupId, playerId: userId)
                        // Mirror the QR-scan / clipboard path in HomeView so a
                        // tapped Universal Link lands the user on the Games
                        // tab inside the joined group with a success toast.
                        // Setting BOTH navigateToTab AND pendingRoundGroupId
                        // is defense in depth: navigateToTab handles tab
                        // switch, pendingRoundGroupId opens the group card.
                        await MainActor.run {
                            ToastManager.shared.success("Joined \(groupName)")
                            appRouter.shouldRefreshGroups = true
                            appRouter.navigateToTab = "skinGames"
                            appRouter.pendingRoundGroupId = groupId
                        }
                    } catch {
                        #if DEBUG
                        print("[handleIncomingURL] joinGroupViaInvite failed for groupId=\(groupId): \(error)")
                        #endif
                        await MainActor.run {
                            ToastManager.shared.error("Couldn't join group. Try again.")
                        }
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

