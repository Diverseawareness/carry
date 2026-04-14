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
        #if DEBUG
        mainContentBase
            .onChange(of: appRouter.debugResetGroups) {
                if appRouter.debugResetGroups {
                    appRouter.debugResetGroups = false
                    skinGameGroups = SavedGroup.demo
                }
            }
            .onChange(of: appRouter.debugClearGroups) {
                if appRouter.debugClearGroups {
                    appRouter.debugClearGroups = false
                    skinGameGroups = []
                    GroupStorage.shared.clear()
                }
            }
        #else
        mainContentBase
        #endif
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor in
                guard let userId = authService.currentUser?.id else {
                    #if DEBUG
                    print("[AutoRefresh] No current user, skipping")
                    #endif
                    return
                }
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
                    skinGameGroups = groups
                } catch {
                    #if DEBUG
                    print("[AutoRefresh] loadGroups failed: \(error)")
                    #endif
                }
            }
        }
    }

    // MARK: - Supabase Group Loading

    // MARK: - Main Content

    private var mainContentBase: some View {
        mainContentWithDataHandlers
            .onReceive(NotificationCenter.default.publisher(for: .didEndRound)) { _ in clearCacheAndReload() }
            .onReceive(NotificationCenter.default.publisher(for: .didCancelRound)) { _ in clearCacheAndReload() }
            .onChange(of: selectedTab) { handleTabChanged() }
            .onDisappear { refreshTimer?.invalidate(); refreshTimer = nil }
    }

    private var mainContentWithDataHandlers: some View {
        mainLayout
            .carryToastOverlay()
            .onAppear(perform: handleAppear)
            .onChange(of: authService.currentUser) { handleUserChanged() }
            .onChange(of: skinGameGroups) { _, newValue in GroupStorage.shared.save(newValue) }
            .onChange(of: appRouter.shouldRefreshGroups) { handleRefreshRequest() }
            .onChange(of: appRouter.navigateToTab) { handleTabNavigation() }
            .onChange(of: appRouter.pendingRoundGroupId) { handlePendingRound() }
    }

    private var mainLayout: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top) { offlineBanner }

            if showTabBar {
                tabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            HomeView(selectedTab: $selectedTab, skinGameGroups: $skinGameGroups, showTabBar: $showTabBar, isLoadingGroups: isLoadingGroups, pendingActiveGroupId: $pendingActiveGroupId)
        case .skinGames:
            GroupsListView(groups: $skinGameGroups, showTabBar: $showTabBar, pendingActiveGroupId: $pendingActiveGroupId, isLoadingGroups: isLoadingGroups)
        case .profile:
            ProfileView(skinGameGroups: $skinGameGroups)
        }
    }

    @ViewBuilder
    private var offlineBanner: some View {
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

    // MARK: - Event Handlers

    private func handleAppear() {
        if authService.isAuthenticated {
            GroupStorage.shared.save([])
        }

        if initialGroups == nil {
            if authService.isAuthenticated, let userId = authService.currentUser?.id {
                loadGroupsFromSupabase(userId: userId)
            } else if !authService.isAuthenticated {
                let summaries = GroupStorage.shared.load()
                if !summaries.isEmpty {
                    skinGameGroups = GroupStorage.shared.hydrate(summaries)
                }
            }
        } else if initialGroups?.isEmpty == true {
            #if DEBUG
            isLoadingGroups = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                isLoadingGroups = false
            }
            #endif
        }

        if authService.isNewUser {
            selectedTab = .skinGames
            authService.isNewUser = false
        }
    }

    private func handleUserChanged() {
        if let userId = authService.currentUser?.id, skinGameGroups.isEmpty {
            loadGroupsFromSupabase(userId: userId)
        }
    }

    private func handleRefreshRequest() {
        if appRouter.shouldRefreshGroups {
            appRouter.shouldRefreshGroups = false
            if let userId = authService.currentUser?.id {
                loadGroupsFromSupabase(userId: userId)
            }
        }
    }

    private func handleTabNavigation() {
        if let tab = appRouter.navigateToTab {
            appRouter.navigateToTab = nil
            if tab == "skinGames" { selectedTab = .skinGames }
            else if tab == "home" { selectedTab = .home }
            else if tab == "profile" { selectedTab = .profile }
        }
    }

    private func handlePendingRound() {
        if let groupId = appRouter.pendingRoundGroupId {
            appRouter.pendingRoundGroupId = nil
            selectedTab = .skinGames
            if let userId = authService.currentUser?.id {
                loadGroupsFromSupabase(userId: userId)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pendingActiveGroupId = groupId
            }
        }
    }

    private func handleTabChanged() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if selectedTab == .skinGames {
            startAutoRefresh()
        }
    }

    /// Clear local cache and reload groups from Supabase.
    private func clearCacheAndReload() {
        GroupStorage.shared.save([])
        if let userId = authService.currentUser?.id {
            loadGroupsFromSupabase(userId: userId)
        }
    }

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

    @MainActor
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
            // Silently fail — polling errors shouldn't toast on every refresh cycle
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
