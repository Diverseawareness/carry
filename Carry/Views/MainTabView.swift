import SwiftUI

/// SwiftUI preference key used by tab content (HomeView, GroupsListView) to
/// publish whether they're currently in a "fullscreen" state where the tab
/// bar should be hidden — i.e. HomeView when an active round is selected,
/// GroupsListView when the user has drilled into a specific group.
///
/// Why this exists: previously a `Binding<Bool>` named `showTabBar` was
/// passed to both children and they wrote to it via `.onChange`. That had a
/// fatal bug class — `.onChange` only fires on value transitions, so when a
/// tab mounted with its tracked value already in the "no fullscreen" state
/// (e.g. nil → nil on first launch), nothing fired and the previous tab's
/// stale value lingered. First impression: app launches with tab bar
/// invisible. Reopening the app fixes it (state resets), but no first-time
/// user would ever come back.
///
/// Preference keys are SwiftUI's native upward-data-flow mechanism. They
/// re-publish on every body recomputation, so a tab's contribution
/// disappears the instant it unmounts — no stale-state lingering possible.
struct TabBarHiddenKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct MainTabView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appRouter: AppRouter
    /// Used to pause the 15s auto-refresh poll while the app is backgrounded
    /// or inactive. Previously the timer kept firing (and hitting Supabase)
    /// while the user was in another app — wasted network, battery, and
    /// Supabase quota. Active-phase gating brings the work down to zero
    /// whenever Carry isn't on screen.
    @Environment(\.scenePhase) private var scenePhase

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
    /// Name of a group this user was just removed from (creator kicked them).
    /// Triggers a one-shot alert explaining the absence; cleared after display.
    @State private var removedFromGroupName: String? = nil
    /// Debounce for the removal alert: we only fire once a group has been
    /// missing for two consecutive polls. Guards against transient states
    /// during fresh group creation (skins_groups INSERT lands before the
    /// creator's group_members row), eventual consistency, and partial writes.
    @State private var pendingKickedGroupId: UUID? = nil
    /// Set true after the first successful loadGroupsFromSupabase OR poll
    /// completes. Gates the "Added to <group>!" toast so a brand-new user
    /// doesn't get spam-toasted for every group they're already in on first
    /// fetch — only surfaces additions that happen AFTER the initial load.
    @State private var didCompleteInitialGroupLoad: Bool = false
    /// Stamp set when a local mutation to `skinGameGroups` happens that the
    /// server may not have replicated yet (e.g., `archiveConcludedRound` on
    /// convert-prompt decline). The 15s poll's empty-result handling reads
    /// this — within 10s of a local mutation, refuse to overwrite a
    /// non-empty list with a transient empty result from the server.
    /// Same pattern as the 6 race-guard stamps in GroupManagerView. Without
    /// this, the convert-decline flow showed an empty Home tab for ~15s.
    /// 7th instance — see refresh-race-guards.md.
    @State private var skinGameGroupsLocallyMutatedAt: Date? = nil

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
                    // Detect "I was removed from a group." Guards before we
                    // surface the alert:
                    //   1. Debounce — the group must be missing from the
                    //      fresh fetch for two consecutive polls. A single
                    //      miss is often transient: the two-step create
                    //      flow (skins_groups INSERT lands before the
                    //      creator's group_members row), eventual consistency,
                    //      a partial write, or a brief RLS/auth blip.
                    //   2. Explicit `"removed"` status required — the
                    //      status column carries intent ("active" / "invited"
                    //      / "declined" / "removed"). Only `"removed"` means
                    //      the creator actually kicked the user. Everything
                    //      else — including `"active"` (the fetch was wrong
                    //      but the user is still in) and `nil` (uncertain) —
                    //      should NOT fire the alert. The previous logic
                    //      fired whenever status != "invited", which
                    //      surfaced a false alarm any time the fetch
                    //      transiently returned empty.
                    // On the first miss we also defer the state stomp so
                    // the currently visible group card doesn't flicker out
                    // before we've confirmed anything.
                    let freshIds = Set(groups.map(\.id))
                    let previousIds = Set(skinGameGroups.map(\.id))

                    // Detect "I was just added to a new group" — fires the
                    // companion toast to the server-side phoneInviteReconciled
                    // push (which only delivers as a banner; this catches the
                    // foreground case + dev builds where APNs sandbox doesn't
                    // deliver). Gated on didCompleteInitialGroupLoad so the
                    // first load doesn't toast for every existing membership.
                    if didCompleteInitialGroupLoad {
                        let addedIds = freshIds.subtracting(previousIds)
                        for addedId in addedIds {
                            guard let added = groups.first(where: { $0.id == addedId }) else { continue }
                            // Skip groups I created — those came from my own
                            // tap, not an invite-add. Match on currentPlayerId
                            // (Int) the same way GroupsListView does.
                            if added.creatorId == authService.currentPlayerId { continue }
                            ToastManager.shared.success("Added to \(added.name)!")
                        }

                        // Detect "a new member joined a group I created" —
                        // companion toast on the SENDER side. Fires for each
                        // newly-active member that wasn't in the previous
                        // member list. Pairs with the recipient toast above:
                        // both sides get in-app feedback when a phone-invite
                        // auto-reconciles or a search-add lands. Only fires
                        // for groups I created (avoids toast spam on groups
                        // where I'm just a member).
                        let myCreatedGroupIds = Set(
                            groups.filter { $0.creatorId == authService.currentPlayerId }.map(\.id)
                        )
                        for groupId in myCreatedGroupIds {
                            guard let prev = skinGameGroups.first(where: { $0.id == groupId }),
                                  let fresh = groups.first(where: { $0.id == groupId }) else { continue }
                            // Carry-only diff: this toast is the sender-side
                            // signal for "a Carry user joined my group" (across
                            // devices, in response to invite acceptance / phone
                            // reconciliation). Guests are created BY the
                            // sender, not joiners — including them here causes
                            // spurious "X joined" toasts during drag-and-drop
                            // when the snapshot's transient member-list shape
                            // makes a guest appear "new" in the diff. The
                            // `!$0.isGuest` filter eliminates the bug class
                            // by restricting the comparison to Carry users.
                            // Locked 2026-05-10.
                            let prevActiveProfileIds = Set(
                                prev.members
                                    .filter { !$0.isPendingAccept && !$0.isPendingInvite && !$0.isGuest }
                                    .compactMap(\.profileId)
                            )
                            let freshActiveMembers = fresh.members.filter {
                                !$0.isPendingAccept && !$0.isPendingInvite && !$0.isGuest
                            }
                            for member in freshActiveMembers {
                                guard let pid = member.profileId,
                                      !prevActiveProfileIds.contains(pid),
                                      pid != userId  // never toast for self
                                else { continue }
                                ToastManager.shared.success("\(member.shortName) joined \(fresh.name)!")
                            }
                        }
                    }

                    let missingNow = skinGameGroups.first(where: { !freshIds.contains($0.id) })
                    if let missing = missingNow {
                        if pendingKickedGroupId == missing.id {
                            // Two distinct reasons a group can vanish from
                            // our fetch:
                            //   1. Creator removed us → membershipStatus
                            //      returns "removed" / "invited" / "declined"
                            //   2. Creator deleted the entire group → skins_groups
                            //      row gone → membershipStatus returns nil
                            //      (no group_members row to query). Without
                            //      a separate existence check the polling
                            //      logic mistakes this for a transient fetch
                            //      error and never clears the local state.
                            // groupExists() distinguishes them.
                            let status = await groupService.membershipStatus(groupId: missing.id, userId: userId)
                            let exists = await groupService.groupExists(groupId: missing.id)

                            // Only fire the "Removed from <group>" alert on
                            // non-creator devices. If the current user IS the
                            // creator and the group was deleted (exists ==
                            // false), THEY deleted it — they don't need to
                            // be told. Silent state cleanup only.
                            let isCreator = missing.creatorId == authService.currentPlayerId
                            if !isCreator && (status == "removed" || exists == false) {
                                removedFromGroupName = missing.name
                            }
                            pendingKickedGroupId = nil
                            // Stomp local state when the user really is gone:
                            // either an explicit removal/decline status, OR
                            // the group itself was deleted. Skip stomp on
                            // exists == nil (fetch error) — let next poll
                            // re-confirm.
                            if status == "removed"
                                || status == "invited"
                                || status == "declined"
                                || exists == false {
                                skinGameGroups = groups
                            }
                        } else {
                            pendingKickedGroupId = missing.id
                            // Defer stomp until next poll confirms
                        }
                    } else {
                        pendingKickedGroupId = nil
                        // Transient-empty guard: if the server returns an
                        // empty list AND we have a recent local mutation
                        // AND we currently have non-empty state, skip the
                        // assignment. The server write may not have
                        // replicated yet (e.g., convert-decline's
                        // archiveConcludedRound just ran; the 'completed'
                        // status flip may be in flight). Without this, the
                        // Home tab showed an empty state for ~15s until
                        // the next poll. Bug G fix, 2026-05-10.
                        let isRecentLocalMutation = skinGameGroupsLocallyMutatedAt.map { Date().timeIntervalSince($0) < 10 } ?? false
                        if groups.isEmpty && !skinGameGroups.isEmpty && isRecentLocalMutation {
                            #if DEBUG
                            print("[AutoRefresh] Skipping empty result — recent local mutation, treating as transient")
                            #endif
                        } else {
                            skinGameGroups = groups
                        }
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

    // MARK: - Main Content

    private var mainContentBase: some View {
        mainContentWithDataHandlers
            .onReceive(NotificationCenter.default.publisher(for: .didEndRound)) { _ in clearCacheAndReload() }
            .onReceive(NotificationCenter.default.publisher(for: .didCancelRound)) { _ in clearCacheAndReload() }
            .onReceive(NotificationCenter.default.publisher(for: .didLocallyArchiveRound)) { _ in
                skinGameGroupsLocallyMutatedAt = Date()
            }
            .onChange(of: selectedTab) { handleTabChanged() }
            .onChange(of: scenePhase) { _, phase in handleScenePhaseChange(phase) }
            .onDisappear { refreshTimer?.invalidate(); refreshTimer = nil }
    }

    /// Pause the auto-refresh poll when the app goes to background or
    /// becomes inactive; resume when active. Mirrors the existing
    /// tab-switch gating (`handleTabChanged`) so the timer only burns
    /// cycles while the user is actually looking at the Games tab of a
    /// foregrounded Carry.
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if selectedTab == .skinGames && refreshTimer == nil {
                startAutoRefresh()
            }
        case .background, .inactive:
            refreshTimer?.invalidate()
            refreshTimer = nil
        @unknown default:
            break
        }
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
            .alert(
                "Removed from \(removedFromGroupName ?? "group")",
                isPresented: Binding(
                    get: { removedFromGroupName != nil },
                    set: { if !$0 { removedFromGroupName = nil } }
                )
            ) {
                Button("OK", role: .cancel) { removedFromGroupName = nil }
            } message: {
                Text("The creator removed you from this game. It's no longer on your Home tab.")
            }
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
        // Single source of truth for tab-bar visibility. Children publish
        // their fullscreen state via `.preference(key: TabBarHiddenKey.self,
        // value: ...)`; we mirror that into local `showTabBar` here. Because
        // preferences re-publish on every render of the contributing view,
        // unmounting a tab automatically clears its contribution — switching
        // tabs always reflects the new tab's actual state, never the prior
        // tab's leftover writes.
        .onPreferenceChange(TabBarHiddenKey.self) { hidden in
            showTabBar = !hidden
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            HomeView(selectedTab: $selectedTab, skinGameGroups: $skinGameGroups, isLoadingGroups: isLoadingGroups, pendingActiveGroupId: $pendingActiveGroupId)
        case .skinGames:
            GroupsListView(groups: $skinGameGroups, pendingActiveGroupId: $pendingActiveGroupId, isLoadingGroups: isLoadingGroups)
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
                    // Mark the initial load complete so the auto-refresh
                    // poll can start firing the "Added to <group>!" toast
                    // for any groups added AFTER this point. Without this
                    // gate the first poll would toast for every existing
                    // membership.
                    didCompleteInitialGroupLoad = true
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
                    // Even on error: mark initial load done so subsequent
                    // polls behave normally (we don't want a permanent gate).
                    didCompleteInitialGroupLoad = true
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
