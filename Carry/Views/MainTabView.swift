import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appRouter: AppRouter

    enum Tab {
        case home, skinGames, profile
    }

    var initialTab: Tab = .home
    var initialGroups: [SavedGroup]? = nil

    @State private var selectedTab: Tab = .home
    @State private var skinGameGroups: [SavedGroup] = []
    @State private var showTabBar: Bool = true
    @State private var isLoadingGroups: Bool = false
    @State private var pendingActiveGroupId: UUID? = nil
    @State private var refreshTimer: Timer? = nil

    private let groupService = GroupService()

    init(initialTab: Tab = .home, initialGroups: [SavedGroup]? = nil) {
        self.initialTab = initialTab
        self.initialGroups = initialGroups
        self._selectedTab = State(initialValue: initialTab)
        if let groups = initialGroups {
            self._skinGameGroups = State(initialValue: groups)
        }
    }

    @ObservedObject private var syncQueue = SyncQueue.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            Group {
                switch selectedTab {
                case .home:
                    HomeView(selectedTab: $selectedTab, skinGameGroups: $skinGameGroups, showTabBar: $showTabBar, isLoadingGroups: isLoadingGroups, pendingActiveGroupId: $pendingActiveGroupId)
                case .skinGames:
                    GroupsListView(groups: $skinGameGroups, showTabBar: $showTabBar, pendingActiveGroupId: $pendingActiveGroupId, isLoadingGroups: isLoadingGroups)
                case .profile:
                    ProfileView(skinGameGroups: $skinGameGroups)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top) {
                if !syncQueue.isOnline {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 12, weight: .semibold))
                        Text("No connection")
                            .font(.system(size: 13, weight: .semibold))
                        if syncQueue.pendingCount > 0 {
                            Text("· \(syncQueue.pendingCount) pending")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.systemRedColor)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: syncQueue.isOnline)
                }
            }

            // Floating tab bar — hidden when navigated into a group
            if showTabBar {
                tabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .carryToastOverlay()
        .onAppear {
            // Clear old cached demo data when running with real auth
            if authService.isAuthenticated {
                GroupStorage.shared.save([])
            }

            // Load persisted groups — skip when debug scenario provides initial groups
            if initialGroups == nil {
                if authService.isAuthenticated, let userId = authService.currentUser?.id {
                    // Authenticated: load from Supabase
                    loadGroupsFromSupabase(userId: userId)
                } else if !authService.isAuthenticated {
                    // Not authenticated (dev mode only): load from UserDefaults
                    let summaries = GroupStorage.shared.load()
                    if !summaries.isEmpty {
                        skinGameGroups = GroupStorage.shared.hydrate(summaries)
                    }
                }
                // If authenticated but currentUser not yet loaded, wait for onChange below
            } else if initialGroups?.isEmpty == true {
                // Debug empty scenario — briefly show loading state
                #if DEBUG
                isLoadingGroups = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    isLoadingGroups = false
                }
                #endif
            }

            // New users land on Skin Games tab to set up their first game
            if authService.isNewUser {
                selectedTab = .skinGames
                authService.isNewUser = false
            }
        }
        .onChange(of: authService.currentUser) {
            // Auth loaded — now fetch groups from Supabase
            if let userId = authService.currentUser?.id, skinGameGroups.isEmpty {
                loadGroupsFromSupabase(userId: userId)
            }
        }
        .onChange(of: skinGameGroups) { _, newValue in
            // Always save locally as a cache
            GroupStorage.shared.save(newValue)
        }
        .onChange(of: appRouter.shouldRefreshGroups) {
            if appRouter.shouldRefreshGroups {
                appRouter.shouldRefreshGroups = false
                if let userId = authService.currentUser?.id {
                    loadGroupsFromSupabase(userId: userId)
                }
            }
        }
        .onChange(of: appRouter.navigateToTab) {
            if let tab = appRouter.navigateToTab {
                appRouter.navigateToTab = nil
                if tab == "skinGames" { selectedTab = .skinGames }
                else if tab == "home" { selectedTab = .home }
                else if tab == "profile" { selectedTab = .profile }
            }
        }
        .onChange(of: appRouter.pendingRoundGroupId) {
            if let groupId = appRouter.pendingRoundGroupId {
                appRouter.pendingRoundGroupId = nil
                selectedTab = .skinGames
                // Reload groups first, then open the group
                if let userId = authService.currentUser?.id {
                    loadGroupsFromSupabase(userId: userId)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    pendingActiveGroupId = groupId
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didEndRound)) { _ in
            // Clear stale cache first, then reload fresh from Supabase
            GroupStorage.shared.save([])
            if let userId = authService.currentUser?.id {
                loadGroupsFromSupabase(userId: userId)
            }
        }
        .onChange(of: appRouter.debugResetGroups) {
            if appRouter.debugResetGroups {
                appRouter.debugResetGroups = false
                #if DEBUG
                skinGameGroups = SavedGroup.demo
                #endif
            }
        }
        .onChange(of: appRouter.debugClearGroups) {
            if appRouter.debugClearGroups {
                appRouter.debugClearGroups = false
                skinGameGroups = []
                GroupStorage.shared.clear()
            }
        }
        .onChange(of: selectedTab) {
            // Auto-refresh every 15s while on Games tab
            refreshTimer?.invalidate()
            refreshTimer = nil
            if selectedTab == .skinGames {
                startAutoRefresh()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            guard let userId = authService.currentUser?.id else {
                #if DEBUG
                print("[AutoRefresh] No current user, skipping")
                #endif
                return
            }
            Task {
                do {
                    let groups = try await groupService.loadGroups(userId: userId)
                    #if DEBUG
                    print("[AutoRefresh] Loaded \(groups.count) groups")
                    for g in groups {
                        let pending = g.members.filter { $0.isPendingAccept }
                        if !pending.isEmpty {
                            print("[AutoRefresh] Group '\(g.name)' has \(pending.count) pending: \(pending.map(\.name))")
                        }
                    }
                    #endif
                    await MainActor.run {
                        skinGameGroups = groups
                    }
                } catch {
                    #if DEBUG
                    print("[AutoRefresh] loadGroups failed: \(error)")
                    #endif
                }
            }
        }
    }

    // MARK: - Supabase Group Loading

    private func loadGroupsFromSupabase(userId: UUID) {
        guard !isLoadingGroups else { return }
        isLoadingGroups = true
        Task {
            do {
                let groups = try await groupService.loadGroups(userId: userId)
                await MainActor.run {
                    skinGameGroups = groups
                    isLoadingGroups = false
                }
            } catch {
                #if DEBUG
                print("[GroupService] Failed to load groups: \(error)")
                #endif
                await MainActor.run {
                    // Fall back to local cache
                    let summaries = GroupStorage.shared.load()
                    if !summaries.isEmpty {
                        skinGameGroups = GroupStorage.shared.hydrate(summaries)
                    } else if skinGameGroups.isEmpty {
                        // Only show error if we have no cached data either —
                        // a brand-new user with zero groups is not an error.
                    }
                    isLoadingGroups = false
                }
            }
        }
    }

    func refreshGroups() async {
        guard let userId = authService.currentUser?.id, authService.isAuthenticated else {
            // Dev mode: nothing to refresh
            try? await Task.sleep(nanoseconds: 300_000_000)
            return
        }
        do {
            let groups = try await groupService.loadGroups(userId: userId)
            await MainActor.run {
                skinGameGroups = groups
            }
        } catch {
            #if DEBUG
            print("[GroupService] Refresh failed: \(error)")
            #endif
            await MainActor.run {
                ToastManager.shared.error("Couldn't refresh groups")
            }
        }
    }

    // MARK: - Floating Pill Tab Bar

    private var tabBar: some View {
        HStack(spacing: 6) {
            floatingTab(icon: "house.fill", label: "Home", tab: .home)
            floatingTab(icon: "person.2.fill", label: "Games", tab: .skinGames)
            floatingTab(icon: "person.crop.circle", label: "Profile", tab: .profile)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.white.opacity(0.85))
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
                .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.bgLight, lineWidth: 0.5)
        )
        .padding(.horizontal, 60)
        .padding(.bottom, -8)
    }

    private func floatingTab(icon: String, label: String, tab: Tab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            }
            .foregroundColor(isSelected ? .white : Color.textDisabled)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? Color.textPrimary : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}
