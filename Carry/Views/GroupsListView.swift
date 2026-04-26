 import SwiftUI

struct GroupsListView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var storeService: StoreService
    @EnvironmentObject var appRouter: AppRouter
    @Binding var groups: [SavedGroup]
    @Binding var pendingActiveGroupId: UUID?
    var isLoadingGroups: Bool = false
    @State private var showCreateGroup = false
    @State private var showQuickStart = false
    @State private var showPaywall = false
    @State private var showNewGamePicker = false
    @State private var showQRScanner = false
    @State private var activeGroup: SavedGroup? = nil
    @State private var groupCardPulse = false
    @State private var contextMenuGroup: SavedGroup? = nil
    @State private var showLeaveGroupConfirm = false
    @State private var showDeleteGroupConfirm = false
    @State private var showRecurringPrompt = false
    @State private var completedGroupId: UUID? = nil
    @State private var promptedGroupIds: Set<UUID> = []
    @State private var justConvertedGroupId: UUID? = nil
    @State private var isConvertingGroup = false
    @State private var showDebugCreateGroupCard = false
    @State private var showConvertSetupSheet = false
    @State private var convertGroupName = ""
    @State private var convertTeeTime: Date = Date()
    @State private var convertHasTeeTime = false
    /// Inline tee-time picker state for phase-1 (shown when `convertHasTeeTime`).
    /// Mirrors the shared `TeeTimePickerSheet` + QuickStartSheet's consecutive
    /// pills — same UI, just embedded in the sheet instead of stacked.
    @State private var convertScheduleMode: Int = 0   // 0 = single, 1 = recurring
    @State private var convertRepeatMode: Int = 0     // 0 = weekly, 1 = biweekly, 2 = monthly
    @State private var convertSelectedDayPill: Int? = nil
    @State private var convertConsecutiveInterval: Int = 0
    /// Two-phase flow inside `showConvertSetupSheet`: first the user names
    /// the group + sets a tee time (`.setup`), then the same sheet swaps to
    /// the invite-crew view (`.inviteCrew`) so the transition feels like one
    /// flow rather than "sheet dismisses, group opens, another sheet pops up."
    private enum ConvertSheetPhase { case prompt, setup, inviteCrew }
    @State private var convertSheetPhase: ConvertSheetPhase = .setup
    /// Snapshot of the group shown in phase 2. Stored directly (not looked up
    /// from `groups` by id) so debug previews can show a mock without
    /// inserting the mock into `skinGameGroups` — otherwise the MainTabView
    /// poll would diff it as a kicked group and fire the removal alert.
    @State private var inviteCrewGroup: SavedGroup? = nil
    private enum InviteShareMode: Int { case link = 0, qr = 1 }
    @State private var inviteShareMode: InviteShareMode = .link
    /// Set when a !isPremium user taps the Quick Game card — the paywall
    /// opens and, on successful trial start or subscription, this flag drives
    /// the onChange(of: isPremium) handler to open the Quick Start sheet so
    /// the user doesn't have to tap Quick Game a second time.
    @State private var pendingQuickStartAfterPaywall: Bool = false

    var body: some View {
        gamesContentWithAlerts
            // Hide the parent tab bar whenever the user has drilled into a
            // specific group's detail view. Re-publishes on every body
            // recomputation, so unmounting the tab automatically clears the
            // contribution — no stale state can linger across tab switches.
            .preference(key: TabBarHiddenKey.self, value: activeGroup != nil)
            .onChange(of: groups) { _, newGroups in
                // Late arrival — a pending "open this group" target (set by
                // the scanner or a deep link) that wasn't in `groups` when
                // the first open attempt ran. When the refreshed list now
                // includes it, open it. Handles the scan → auto-join →
                // open-details flow where the group only becomes visible
                // after the groups fetch completes.
                if let pendingId = pendingActiveGroupId,
                   let group = newGroups.first(where: { $0.id == pendingId }) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                        activeGroup = group
                    }
                    pendingActiveGroupId = nil
                }

                // If the user is viewing a group detail and that group vanishes
                // from the list (creator kicked them, or they left via another
                // device), pop back to the list so they're not stuck on a
                // stale detail screen. MainTabView surfaces the "Removed from
                // {name}" alert separately; this handler just unwinds the
                // navigation state.
                if let current = activeGroup,
                   !newGroups.contains(where: { $0.id == current.id }) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                        activeGroup = nil
                    }
                }
            }
            .onChange(of: pendingActiveGroupId) { _, newId in
                guard let newId else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if let group = groups.first(where: { $0.id == newId }) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                            activeGroup = group
                        }
                        pendingActiveGroupId = nil
                    }
                    // If the group isn't in the list yet, leave
                    // `pendingActiveGroupId` set — the `onChange(of: groups)`
                    // handler above will pick it up when the refresh arrives.
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showNewGamePicker)) { _ in
                showNewGamePicker = true
            }
            #if DEBUG
            .onReceive(appRouter.$debugShowRecurringPrompt) { show in
                guard show else { return }
                appRouter.debugShowRecurringPrompt = false
                completedGroupId = groups.first(where: { $0.isQuickGame })?.id ?? groups.first?.id
                showRecurringPrompt = true
            }
            .onReceive(appRouter.$debugShowCreateGroupCard) { show in
                guard show else { return }
                appRouter.debugShowCreateGroupCard = false
                showDebugCreateGroupCard = true
            }
            .onReceive(appRouter.$debugShowInviteSheet) { show in
                guard show else { return }
                appRouter.debugShowInviteSheet = false
                if let group = groups.first {
                    justConvertedGroupId = group.id
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                        activeGroup = group
                    }
                }
            }
            .onReceive(appRouter.$debugShowConvertInviteCrew) { show in
                guard show else { return }
                appRouter.debugShowConvertInviteCrew = false
                presentDebugConvertInviteCrew()
            }
            .onReceive(appRouter.$debugShowConvertPrompt) { show in
                guard show else { return }
                appRouter.debugShowConvertPrompt = false
                presentDebugConvertPrompt()
            }
            .overlay {
                if showDebugCreateGroupCard {
                    debugCreateGroupCardOverlay
                }
            }
            #endif
            .onChange(of: storeService.isPremium) { _, newValue in
                // User completed the forced paywall (trial started or subscribed).
                // Auto-open Quick Start so they don't have to tap Quick Game a
                // second time. Same pattern as the Join Game flow in HomeView.
                if newValue, pendingQuickStartAfterPaywall {
                    pendingQuickStartAfterPaywall = false
                    showQuickStart = true
                }
            }
    }

    private var gamesContentWithAlerts: some View {
        gamesContentWithSheets
            .modifier(GroupsAlertModifiers(
                showLeaveGroupConfirm: $showLeaveGroupConfirm,
                showDeleteGroupConfirm: $showDeleteGroupConfirm,
                showRecurringPrompt: $showRecurringPrompt,
                contextMenuGroup: $contextMenuGroup,
                completedGroupId: $completedGroupId,
                groups: $groups,
                showPaywall: $showPaywall,
                onLeaveGroup: { leaveGroup($0) },
                onDeleteGroup: { deleteGroup($0) },
                onConvertAndCopy: { showConvertSetup(groupId: $0) },
                onConvert: { convertQuickGame(groupId: $0) },
                onDeleteQuickGame: { _ in completedGroupId = nil }
            ))
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: activeGroup?.id)
    }

    // MARK: - Quick Start

    @ViewBuilder
    private var quickStartSheetContent: some View {
        if let user = authService.currentUser {
            let userName = user.displayName.isEmpty ? "You" : user.displayName
            let parts = userName.split(separator: " ")
            let userInitials = parts.count >= 2
                ? "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
                : String(userName.prefix(2)).uppercased()
            let currentPlayer = Player(
                id: Player.stableId(from: user.id),
                name: userName,
                initials: userInitials,
                color: "#4CAF50",
                handicap: user.handicap,
                avatar: "",
                group: 1,
                ghinNumber: nil,
                venmoUsername: nil,
                avatarUrl: user.avatarUrl,
                profileId: user.id,
                homeClub: user.homeClub
            )
            QuickGameSheet(
                currentUser: currentPlayer,
                recentQuickGames: {
                    // Deduplicate by course — keep most recent per course
                    var seen = Set<String>()
                    return groups.filter { $0.isQuickGame }.filter { game in
                        let key = game.lastCourse?.courseName ?? game.id.uuidString
                        guard !seen.contains(key) else { return false }
                        seen.insert(key)
                        return true
                    }
                }(),
                onCreate: { savedGroup in
                    handleQuickGameCreate(savedGroup: savedGroup)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.white)
        }
    }

    private func leaveGroup(_ group: SavedGroup) {
        if authService.isAuthenticated, let userId = authService.currentUser?.id {
            Task {
                try? await GroupService().removeMember(groupId: group.id, playerId: userId)
            }
        }
        withAnimation(.easeOut(duration: 0.25)) {
            groups.removeAll { $0.id == group.id }
        }
        ToastManager.shared.success("Left \(group.name)")
    }

    private func deleteGroup(_ group: SavedGroup) {
        Task {
            try? await GroupService().deleteGroup(groupId: group.id)
        }
        withAnimation(.easeOut(duration: 0.25)) {
            groups.removeAll { $0.id == group.id }
        }
        ToastManager.shared.success("Deleted \(group.name)")
    }

    private func showConvertSetup(groupId: UUID) {
        let courseName = groups.first(where: { $0.id == groupId })?.lastCourse?.courseName
        convertGroupName = courseName != nil ? "\(courseName!) Skins" : ""
        convertHasTeeTime = false
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let minute = comps.minute ?? 0
        if minute < 30 { comps.minute = 30 } else { comps.minute = 0; comps.hour = (comps.hour ?? 0) + 1 }
        convertTeeTime = cal.date(from: comps) ?? now
        completedGroupId = groupId
        showConvertSetupSheet = true
    }

    private func convertQuickGame(groupId: UUID) {
        isConvertingGroup = true
        Task {
            // Auto-name from course: "{CourseName} Skins"
            let courseName = groups.first(where: { $0.id == groupId })?.lastCourse?.courseName
            let groupName = courseName != nil ? "\(courseName!) Skins" : "Skins Game"

            try? await GroupService().convertQuickGameToGroup(
                groupId: groupId,
                groupName: groupName
            )
            if let userId = authService.currentUser?.id,
               let refreshed = try? await GroupService().loadGroups(userId: userId) {
                await MainActor.run {
                    groups = refreshed
                    isConvertingGroup = false
                    if let idx = groups.firstIndex(where: { $0.id == groupId }) {
                        groups[idx].activeRound = nil
                        groups[idx].concludedRound = nil
                        justConvertedGroupId = groupId
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                            activeGroup = groups[idx]
                        }
                    }
                }
            } else {
                await MainActor.run { isConvertingGroup = false }
            }
        }
    }

    private func convertQuickGameWithSetup(
        groupId: UUID,
        name: String,
        teeTime: Date?,
        recurrence: GameRecurrence?,
        consecutiveInterval: Int
    ) {
        isConvertingGroup = true
        Task {
            let groupService = GroupService()
            do {
                try await groupService.convertQuickGameToGroup(
                    groupId: groupId,
                    groupName: name
                )
                // Clear the Quick Game's `tee_times_json` — those slots are
                // "play now" past times and would otherwise linger as stale
                // future-round schedule, tripping `needsNextSchedule` in
                // GroupManagerView. Fresh group derives its tee times from the
                // new `scheduled_date` on reload (or stays empty until the
                // creator sets one via Game Options).
                try await groupService.saveTeeTimes(groupId: groupId, teeTimes: [])
                let recurrenceJSON: String? = {
                    guard let recurrence else { return nil }
                    guard let data = try? JSONEncoder().encode(recurrence),
                          let str = String(data: data, encoding: .utf8) else { return nil }
                    return str
                }()
                try await groupService.updateGroup(
                    groupId: groupId,
                    update: SkinsGroupUpdate(
                        scheduledDate: teeTime,
                        clearScheduledDate: teeTime == nil,
                        recurrence: recurrenceJSON,
                        clearRecurrence: recurrence == nil,
                        teeTimeInterval: consecutiveInterval > 0 ? consecutiveInterval : nil
                    )
                )
            } catch {
                #if DEBUG
                print("[Carry] convertQuickGameWithSetup failed: \(error)")
                #endif
                await MainActor.run {
                    isConvertingGroup = false
                    ToastManager.shared.error("Couldn't create group — please try again")
                }
                return
            }

            guard let userId = authService.currentUser?.id,
                  let refreshed = try? await groupService.loadGroups(userId: userId) else {
                await MainActor.run {
                    isConvertingGroup = false
                    ToastManager.shared.error("Group created but couldn't refresh — pull down to reload")
                }
                return
            }

            await MainActor.run {
                groups = refreshed
                isConvertingGroup = false
                ToastManager.shared.success("Group successfully created")
                if let idx = groups.firstIndex(where: { $0.id == groupId }) {
                    groups[idx].activeRound = nil
                    groups[idx].concludedRound = nil
                    // Stay in the sheet; swap to the invite-crew phase so the
                    // creator can share the QR or text absent players without
                    // breaking flow.
                    inviteCrewGroup = groups[idx]
                }
                // Mark this group as just-converted so that when the invite
                // sheet dismisses and GroupManagerView mounts, the name
                // editor auto-opens for the user to pick a real name.
                justConvertedGroupId = groupId
                withAnimation(.easeInOut(duration: 0.25)) {
                    convertSheetPhase = .inviteCrew
                }
            }
        }
    }

    /// User tapped Done (or swiped) in the invite-crew phase — dismiss the
    /// sheet, open the new group, and reset sheet state for next time.
    private func finishConvertFlow() {
        // Capture the snapshot before we nil `inviteCrewGroup` so debug
        // mocks (not present in `groups`) can still land in GroupManagerView.
        let captured = inviteCrewGroup
        showConvertSetupSheet = false
        convertSheetPhase = .setup
        inviteCrewGroup = nil
        inviteShareMode = .link
        if let groupId = captured?.id {
            // Prefer the fresh server copy (real flow); fall back to the
            // captured snapshot (debug mock doesn't live in `groups` to
            // avoid MainTabView's poll flagging it as a stale group).
            let resolved = groups.first(where: { $0.id == groupId }) ?? captured
            if let group = resolved {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    activeGroup = group
                }
            }
        }
    }

    #if DEBUG
    /// Debug-only: jump straight to phase 2 of the convert sheet with a mock
    /// post-conversion group so the invite-crew flow can be previewed
    /// without playing a full Quick Game + tapping Create Group.
    /// Seeds 20 players (the max: 5 groups × 4 players) + a realistic round
    /// in history so the results card shows non-zero skins/money.
    ///
    /// Also inserts the mock into `groups` and stamps `justConvertedGroupId`
    /// so dismissing the sheet (X / swipe) lands the user in the mock
    /// GroupManagerView with the rename-on-appear auto-trigger firing —
    /// lets us exercise the full flow end-to-end in the simulator.
    /// Caveat: MainTabView's 15s poll will see the mock as "removed" and
    /// fire a stale alert; dismiss it and continue.
    private func presentDebugConvertInviteCrew() {
        let (mock, _) = makeDebugConversionMock(
            creatorId: authService.currentPlayerId,
            groupName: "Test Skins"
        )
        // Do NOT insert into `groups` — MainTabView's 15s poll would diff it
        // as missing from the server and fire a bogus "Removed from group"
        // alert. `finishConvertFlow` uses `inviteCrewGroup` directly for
        // debug mocks so the detail view still opens.
        inviteCrewGroup = mock
        inviteShareMode = .link
        justConvertedGroupId = mock.id
        convertSheetPhase = .inviteCrew
        showConvertSetupSheet = true
    }

    /// Debug-only: jump to phase 1 (the "Convert game into a recurring
    /// Skins Group" prompt) in isolation so the Figma 1:1 match can be
    /// reviewed without playing a real Quick Game.
    private func presentDebugConvertPrompt() {
        completedGroupId = UUID()  // placeholder — destructive action is gated elsewhere
        convertSheetPhase = .prompt
        showConvertSetupSheet = true
    }

    /// Debug-only: from phase 2 of the debug prompt flow, short-circuit
    /// `convertQuickGameWithSetup` (which hits Supabase with a fake UUID and
    /// would fail) and advance directly to the invite-crew phase with a mock
    /// group carrying the name the user typed.
    private func jumpToDebugInviteCrewWith(name: String) {
        let (mock, _) = makeDebugConversionMock(
            creatorId: authService.currentPlayerId,
            groupName: name.isEmpty ? "Test Skins" : name
        )
        // Do NOT insert into `groups` — see presentDebugConvertInviteCrew.
        inviteCrewGroup = mock
        inviteShareMode = .link
        justConvertedGroupId = mock.id
        withAnimation(.easeInOut(duration: 0.25)) {
            convertSheetPhase = .inviteCrew
        }
    }

    /// Debug-only: build a mock 20-player converted group (5 groups × 4
    /// players) with a realistic completed round so the results card shows
    /// non-zero skins and winnings. Returns the SavedGroup and the HomeRound
    /// it embeds for future reference.
    private func makeDebugConversionMock(
        creatorId: Int,
        groupName: String
    ) -> (SavedGroup, HomeRound) {
        // 20 players across 5 groups. First player in each group is the
        // scorer (creator for Group 1; invited Carry users for Groups 2–5).
        // Mix of Carry users + guests to exercise both invite row styles.
        let colors = ["#D4A017", "#4A90D9", "#E05555", "#2ECC71", "#9B59B6", "#E67E22",
                      "#16A085", "#F39C12", "#8E44AD", "#C0392B"]
        let names = [
            ("You", "YO", false),                 // creator, Group 1 scorer
            ("Tyson Briner", "TB", false),
            ("Garret Edwards", "GE", false),
            ("Jon Jones", "JJ", true),            // guest
            ("Keith Baker", "KB", false),         // Group 2 scorer
            ("Alex Morgan", "AM", false),
            ("Pat Nelson", "PN", true),
            ("Ziggy Briner", "ZB", true),
            ("Sam Carter", "SC", false),          // Group 3 scorer
            ("Mike Ross", "MR", false),
            ("Harvey Specter", "HS", true),
            ("Louis Litt", "LL", true),
            ("Donna Paulsen", "DP", false),       // Group 4 scorer
            ("Rachel Zane", "RZ", false),
            ("Kate Wilson", "KW", true),
            ("Chris Green", "CG", true),
            ("Lee Park", "LP", false),            // Group 5 scorer
            ("Maya Rao", "MR", false),
            ("Jamie Lee", "JL", true),
            ("Robin Ward", "RW", true)
        ]

        var players: [Player] = []
        for (idx, entry) in names.enumerated() {
            let groupNum = (idx / 4) + 1
            let id = idx == 0 ? creatorId : 9000 + idx
            players.append(Player(
                id: id, name: entry.0, initials: entry.1,
                color: colors[idx % colors.count],
                handicap: Double(Int.random(in: 0...25)),
                avatar: "🏌️", group: groupNum,
                ghinNumber: nil, venmoUsername: nil,
                isPendingAccept: idx != 0, // everyone except creator is invited
                isGuest: entry.2,
                profileId: idx == 0 ? nil : UUID()
            ))
        }

        // Fake winnings distribution — non-trivial to preview the results card.
        let buyIn = 25
        let pot = buyIn * players.count
        let skinsDistribution: [Int: Int] = [
            players[0].id: 5,  players[1].id: 3, players[2].id: 1, players[3].id: 0,
            players[4].id: 2,  players[5].id: 2, players[6].id: 1, players[7].id: 0,
            players[8].id: 1,  players[9].id: 1, players[10].id: 1, players[11].id: 0,
            players[12].id: 0, players[13].id: 0, players[14].id: 0, players[15].id: 0,
            players[16].id: 1, players[17].id: 0, players[18].id: 0, players[19].id: 0
        ]
        let winnings: [Int: Int] = [
            players[0].id: 125, players[1].id: 75,  players[2].id: 25,  players[3].id: -25,
            players[4].id: 50,  players[5].id: 50,  players[6].id: 25,  players[7].id: -25,
            players[8].id: 25,  players[9].id: 25,  players[10].id: 25, players[11].id: -25,
            players[12].id: -25, players[13].id: -25, players[14].id: -25, players[15].id: -25,
            players[16].id: 25, players[17].id: -25, players[18].id: -25, players[19].id: -25
        ]
        let wonHoles: [Int: [Int]] = skinsDistribution.reduce(into: [:]) { acc, kv in
            acc[kv.key] = kv.value > 0 ? Array(1...kv.value) : []
        }

        let mockCourse = SelectedCourse(
            courseId: 0,
            courseName: "Ruby Hill Golf Club",
            clubName: "Ruby Hill",
            location: "",
            teeBox: nil,
            apiTee: nil
        )

        var round = HomeRound(
            id: UUID(),
            groupName: groupName,
            courseName: "Ruby Hill Golf Club",
            players: players,
            status: .completed,
            currentHole: 18,
            totalHoles: 18,
            buyIn: buyIn,
            skinsWon: 18,
            totalSkins: 18,
            yourSkins: 5,
            invitedBy: nil,
            creatorId: creatorId,
            startedAt: Date().addingTimeInterval(-4 * 3600),
            completedAt: Date()
        )
        round.scorerPlayerId = creatorId
        round.concludedAt = Date()
        round.playerWinnings = winnings
        round.playerWonHoles = wonHoles
        round.winningsDisplay = "gross"
        _ = pot  // silence unused-var warning — pot is implicit via buyIn * players.count

        let mockGroupId = UUID()
        let mock = SavedGroup(
            id: mockGroupId,
            name: groupName,
            members: players,
            lastPlayed: nil,
            creatorId: creatorId,
            lastCourse: mockCourse,
            activeRound: nil,
            concludedRound: nil,
            roundHistory: [round],
            potSize: Double(pot),
            buyInPerPlayer: Double(buyIn),
            scheduledDate: nil,
            recurrence: nil,
            handicapPercentage: 0.7,
            isQuickGame: false,
            scorerIds: nil,
            teeTimes: nil,
            teeTimeInterval: nil
        )
        return (mock, round)
    }
    #endif

    private func convertAndCopyInvite(groupId: UUID) {
        let link = "https://carryapp.site/invite?group=\(groupId.uuidString)"
        UIPasteboard.general.string = link
        ToastManager.shared.success("Invite link copied!")
        convertQuickGame(groupId: groupId)
    }

    private func handleQuickGameCreate(savedGroup: SavedGroup) {
        guard let userId = authService.currentUser?.id else { return }
        showQuickStart = false

        // Create guest profiles + Supabase group, THEN open detail
        Task {
            do {
                let guestService = GuestProfileService()
                let groupService = GroupService()

                // 1. Create guest profiles for players without profileId
                let guestPlayers = savedGroup.members.filter { $0.profileId == nil && !$0.name.isEmpty && !$0.isPendingInvite }
                var guestUUIDs: [(index: Int, uuid: UUID)] = []

                if !guestPlayers.isEmpty {
                    let names = guestPlayers.map(\.name)
                    let initials = guestPlayers.map(\.initials)
                    let handicaps = guestPlayers.map(\.handicap)
                    let colors = guestPlayers.map(\.color)
                    let uuids = try await guestService.createGuestProfiles(
                        names: names, initials: initials,
                        handicaps: handicaps, colors: colors,
                        creatorId: userId
                    )
                    guard uuids.count == guestPlayers.count else {
                        throw NSError(domain: "QuickGame", code: 1, userInfo: [NSLocalizedDescriptionKey: "Guest profile count mismatch: expected \(guestPlayers.count), got \(uuids.count)"])
                    }
                    for (i, uuid) in uuids.enumerated() {
                        guestUUIDs.append((index: i, uuid: uuid))
                    }
                }

                // 2. Rebuild members with real Supabase UUIDs (index-based, not name-based)
                var guestIndex = 0
                let updatedMembers = savedGroup.members.map { player -> Player in
                    if player.profileId != nil { return player }
                    guard !player.name.trimmingCharacters(in: .whitespaces).isEmpty else { return player }
                    guard guestIndex < guestUUIDs.count else { return player }
                    let guestId = guestUUIDs[guestIndex].uuid
                    guestIndex += 1
                    return Player(
                        id: Player.stableId(from: guestId),
                        name: player.name,
                        initials: player.initials,
                        color: player.color,
                        handicap: player.handicap,
                        avatar: player.avatar,
                        group: player.group,
                        ghinNumber: nil,
                        venmoUsername: nil,
                        avatarImageName: nil,
                        avatarUrl: nil,
                        isGuest: true,
                        profileId: guestId
                    )
                }

                // 3. Build full UUID list + group number map + scorer IDs to invite
                var allMemberUUIDs: [UUID] = []
                var memberGroupNums: [UUID: Int] = [:]
                var scorerIdsToInvite: Set<UUID> = []
                for player in updatedMembers where !player.name.isEmpty {
                    if let profileId = player.profileId {
                        allMemberUUIDs.append(profileId)
                        memberGroupNums[profileId] = player.group
                        // Non-creator Carry users (scorers for groups 2+) should be invited
                        if !player.isGuest && !player.isPendingInvite && profileId != userId {
                            scorerIdsToInvite.insert(profileId)
                        }
                    }
                }

                #if DEBUG
                print("[QuickGame] scorerIdsToInvite: \(scorerIdsToInvite)")
                #endif

                let courseName = savedGroup.lastCourse?.courseName
                let courseClubName = savedGroup.lastCourse?.clubName
                let teeBox = savedGroup.lastCourse?.teeBox

                // Encode holes JSON so it persists from creation
                var holesJson: String? = nil
                if let holes = teeBox?.holes,
                   let data = try? JSONEncoder().encode(holes) {
                    holesJson = String(data: data, encoding: .utf8)
                }

                // 4. Create group — scorers inserted as 'invited' directly (triggers push)
                let groupDTO = try await groupService.createGroup(
                    name: savedGroup.name,
                    createdBy: userId,
                    memberIds: allMemberUUIDs,
                    buyIn: savedGroup.buyInPerPlayer,
                    scheduledDate: savedGroup.scheduledDate,
                    courseName: courseName,
                    courseClubName: courseClubName,
                    teeBoxName: teeBox?.name,
                    teeBoxColor: teeBox?.color,
                    teeBoxCourseRating: teeBox?.courseRating,
                    teeBoxSlopeRating: teeBox?.slopeRating,
                    teeBoxPar: teeBox?.par,
                    handicapPercentage: savedGroup.handicapPercentage,
                    allActive: true,
                    isQuickGame: true,
                    memberGroupNums: memberGroupNums,
                    teeTimeInterval: savedGroup.teeTimeInterval,
                    scorerIdsToInvite: scorerIdsToInvite,
                    lastTeeBoxHolesJson: holesJson
                )

                // 5. Create Supabase invite records for SMS-invited scorers
                for member in updatedMembers where member.isPendingInvite {
                    if let phone = member.phoneNumber, !phone.isEmpty {
                        try? await groupService.inviteMemberByPhone(
                            groupId: groupDTO.id, phone: phone, invitedBy: userId, groupNum: member.group
                        )
                    }
                }

                // 6. Persist scorer IDs so other devices see them
                let maxGroup = updatedMembers.map(\.group).max() ?? 1
                var scorerIntIds: [Int] = []
                for g in 1...maxGroup {
                    let groupPlayers = updatedMembers.filter { $0.group == g }
                    scorerIntIds.append(groupPlayers.first?.id ?? 0)
                }
                try? await groupService.updateGroup(
                    groupId: groupDTO.id,
                    update: SkinsGroupUpdate(scorerIds: scorerIntIds)
                )

                // 6. Insert group with real IDs and open detail view
                let realGroup = SavedGroup(
                    id: groupDTO.id,
                    name: savedGroup.name,
                    members: updatedMembers,
                    lastPlayed: nil,
                    creatorId: savedGroup.creatorId,
                    lastCourse: savedGroup.lastCourse,
                    activeRound: nil,
                    roundHistory: [],
                    potSize: savedGroup.potSize,
                    buyInPerPlayer: savedGroup.buyInPerPlayer,
                    scheduledDate: savedGroup.scheduledDate,
                    handicapPercentage: savedGroup.handicapPercentage,
                    isQuickGame: true,
                    teeTimes: savedGroup.teeTimes
                )

                await MainActor.run {
                    groups.insert(realGroup, at: 0)
                    activeGroup = realGroup
                }

                #if DEBUG
                print("[QuickGame] Group created successfully: \(groupDTO.id)")
                #endif
            } catch {
                #if DEBUG
                print("[QuickGame] Failed: \(error.localizedDescription)")
                print("[QuickGame] Full error: \(error)")
                #endif
                await MainActor.run {
                    ToastManager.shared.error("Sync failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Round Coordinator Overlay

    @ViewBuilder
    private func roundCoordinatorOverlay(group: SavedGroup) -> some View {
        let activeRound = group.activeRound ?? group.concludedRound
        let isLive = activeRound != nil
        let roundConfig: RoundConfig? = activeRound.map { Self.buildRoundConfig(from: $0, group: group) }

        RoundCoordinatorView(
            initialMembers: group.members,
            groupName: group.name,
            currentUserId: authService.currentPlayerId,
            creatorId: group.creatorId,
            groupId: group.id,
            startInActiveMode: isLive,
            preselectedCourse: group.lastCourse,
            skipCourseSelection: !isLive,
            onCourseSelected: { updatedCourse in
                if let idx = groups.firstIndex(where: { $0.id == group.id }) {
                    groups[idx].lastCourse = updatedCourse
                }
                if authService.isAuthenticated {
                    Task {
                        try? await GroupService().persistCourseSelection(groupId: group.id, course: updatedCourse)
                    }
                }
            },
            onTeeTimeChanged: { newDate in
                if let idx = groups.firstIndex(where: { $0.id == group.id }) {
                    groups[idx].scheduledDate = newDate
                }
                if authService.isAuthenticated {
                    Task {
                        // Also persist the standard 8-minute interval so other devices
                        // can reconstruct staggered tee times for multi-group rounds.
                        try? await GroupService().updateGroup(
                            groupId: group.id,
                            update: SkinsGroupUpdate(scheduledDate: newDate, teeTimeInterval: 8)
                        )
                    }
                }
            },
            onRecurrenceChanged: { newRecurrence in
                if let idx = groups.firstIndex(where: { $0.id == group.id }) {
                    groups[idx].recurrence = newRecurrence
                }
                if authService.isAuthenticated {
                    let encoded: String? = {
                        guard let r = newRecurrence else { return nil }
                        guard let data = try? JSONEncoder().encode(r) else { return nil }
                        return String(data: data, encoding: .utf8)
                    }()
                    Task {
                        try? await GroupService().updateGroup(
                            groupId: group.id,
                            update: SkinsGroupUpdate(recurrence: encoded, clearRecurrence: newRecurrence == nil)
                        )
                    }
                }
            },
            initialTeeTime: group.scheduledDate,
            initialTeeTimes: group.teeTimes,
            initialRecurrence: group.recurrence,
            initialBuyIn: group.buyInPerPlayer,
            initialCarriesEnabled: group.carriesEnabled,
            initialRoundConfig: roundConfig,
            roundHistory: group.roundHistory,
            onExit: {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    activeGroup = nil
                }
                justConvertedGroupId = nil
                // Refresh groups from Supabase
                if authService.isAuthenticated, let userId = authService.currentUser?.id {
                    Task {
                        if let refreshed = try? await GroupService().loadGroups(userId: userId) {
                            groups = refreshed
                        }
                    }
                }
                // Old "Play again?" prompt removed — now handled inside RoundCompleteView's create group card
            },
            onLeaveGroup: {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    activeGroup = nil
                    groups.removeAll { $0.id == group.id }
                }
                if authService.isAuthenticated, let userId = authService.currentUser?.id {
                    Task {
                        try? await GroupService().removeMember(groupId: group.id, playerId: userId)
                    }
                }
            },
            onDeleteGroup: {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    activeGroup = nil
                    groups.removeAll { $0.id == group.id }
                }
                if authService.isAuthenticated {
                    Task {
                        try? await GroupService().deleteGroup(groupId: group.id)
                    }
                }
            },
            isViewer: !group.isQuickGame && isLive && authService.currentPlayerId != (activeRound?.scorerPlayerId ?? group.creatorId) && authService.currentPlayerId != group.creatorId,
            scheduledLabel: group.scheduledLabel,
            isQuickGame: group.isQuickGame,
            showInviteCrewOnAppear: justConvertedGroupId == group.id,
            onGroupRefreshed: { refreshedGroup in
                if let idx = groups.firstIndex(where: { $0.id == refreshedGroup.id }) {
                    groups[idx] = refreshedGroup
                }
            },
            onCreateGroup: {
                // Creator tapped "Create Group" from final results. Dismiss
                // the RoundCoordinatorView overlay first, THEN open the
                // convert sheet — SwiftUI only allows one sheet at a time,
                // and the Round overlay (plus any in-flight sheet inside it)
                // must fully dismiss before a new sheet can present. Delay
                // matches the overlay's spring animation (~450ms).
                if let round = group.activeRound ?? group.concludedRound {
                    Task {
                        try? await RoundService().updateRoundStatus(roundId: round.id, status: "completed")
                    }
                }
                completedGroupId = group.id
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    activeGroup = nil
                }
                convertSheetPhase = .prompt
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    showConvertSetupSheet = true
                }
            },
            onDeclineGroup: {
                if let idx = groups.firstIndex(where: { $0.id == group.id }) {
                    groups[idx].archiveConcludedRound()
                }
            }
        )
        .ignoresSafeArea()
        .transition(.move(edge: isLive ? .bottom : .trailing))
        .zIndex(1)
    }

    /// Build a clean RoundConfig from a HomeRound + group (unique ID, no cached scores)
    private static func buildRoundConfig(from round: HomeRound, group: SavedGroup) -> RoundConfig {
        let allPlayers = round.players
        // Group players by their assigned group number (from group_num column)
        let maxGroup = allPlayers.map(\.group).max() ?? 1
        var groups: [GroupConfig] = []
        if maxGroup > 1 {
            for g in 1...maxGroup {
                let playerIDs = allPlayers.filter { $0.group == g }.map(\.id)
                if !playerIDs.isEmpty {
                    groups.append(GroupConfig(id: g, startingSide: "front", playerIDs: playerIDs))
                }
            }
        }
        // Fallback: split into foursomes if no group assignments
        if groups.isEmpty {
            let groupSize = 4
            for i in stride(from: 0, to: allPlayers.count, by: groupSize) {
                let end = min(i + groupSize, allPlayers.count)
                let playerIDs = allPlayers[i..<end].map(\.id)
                groups.append(GroupConfig(id: groups.count + 1, startingSide: "front", playerIDs: Array(playerIDs)))
            }
        }
        if groups.isEmpty {
            groups.append(GroupConfig(id: 1, startingSide: "front", playerIDs: allPlayers.map(\.id)))
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let resolvedTeeBox = round.teeBox ?? group.lastCourse?.teeBox
        var config = RoundConfig(
            id: round.id.uuidString,
            number: 1,
            course: round.courseName,
            date: dateFormatter.string(from: Date()),
            buyIn: round.buyIn,
            gameType: "skins",
            skinRules: round.skinRules,
            teeBox: resolvedTeeBox,
            groups: groups,
            creatorId: round.creatorId,
            groupName: group.name,
            players: allPlayers,
            holes: resolvedTeeBox?.holes
        )
        config.supabaseRoundId = round.id
        config.supabaseGroupId = group.id
        // HomeRound.scheduledDate is already resolved to the CURRENT user's
        // tee time (buildHomeRound picks teeTimes[userGroup-1] per memory).
        // Pipe through to the scorecard header's subtitle.
        config.scorerTeeTime = round.scheduledDate
        return config
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.carry.bodySMBold)
                .foregroundColor(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 10)
    }

    // MARK: - Group Card

    private func groupCard(_ group: SavedGroup) -> some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                activeGroup = group
            }
        } label: {
            VStack(spacing: 0) {
                if let round = group.activeRound ?? group.concludedRound {
                    // ── ACTIVE / GAME DONE CARD ─────────────────────────
                    // Concluded rounds and pending rounds should never display as "not started"
                    // even if currentHole is 0 on this device (scores not yet synced).
                    let isGameDone = round.isGameDone
                    let hasPending = round.hasPendingResults
                    let isNotStarted = round.currentHole == 0 && round.status != .concluded && !hasPending
                    let isLiveScoring = !isNotStarted && !isGameDone && !hasPending

                    // Top: group name + badge
                    HStack {
                        Text(group.name)
                            .font(.carry.bodyLGBold)
                            .foregroundColor(.black)

                        Spacer()

                        if isGameDone {
                            // "✓ Game Done" badge
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color.successGreen)
                                Text("Game Done")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color.successGreen)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.concludedGreen))
                        } else {
                            // LIVE badge — brand green pill
                            let showHole = !isNotStarted
                            HStack(spacing: 5) {
                                PulsatingDot(color: Color.successGreen, size: 6)
                                Text("LIVE")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundColor(Color.successGreen)

                                if showHole {
                                    Text("Hole \(round.currentHole)")
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundColor(Color.successGreen)
                                }
                            }
                            .padding(.leading, 10)
                            .padding(.trailing, 11)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.concludedGreen))
                        }
                    }

                    // Course name (no tee time — shown on Home card)
                    Text(round.courseName)
                        .font(.carry.bodySM)
                        .foregroundColor(Color(hexString: "#7A7A7E"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)

                    // Player pills — sorted by winnings
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(round.sortedPlayers) { player in
                                let winnings = round.playerWinnings[player.id] ?? 0
                                HStack(spacing: 6) {
                                    PlayerAvatar(player: player, size: 28)
                                    Text(player.shortName)
                                        .font(.carry.captionLG)
                                        .foregroundColor(Color.textPrimary)
                                        .lineLimit(1)
                                    Text("$\(winnings)")
                                        .font(.carry.captionLGSemibold)
                                        .monospacedDigit()
                                        .foregroundColor(winnings > 0 ? Color.textPrimary : Color.textSecondary)
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.bgSecondary))
                            }
                        }
                    }
                    .padding(.top, 8)

                    // Bottom button — per state
                    if isNotStarted || isLiveScoring {
                        HStack(spacing: 6) {
                            PulsatingDot(color: Color.successGreen, size: 6)
                            Text("LIVE Scorecard")
                                .font(.carry.bodySMSemibold)
                                .foregroundColor(Color.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 13).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.dividerLight, lineWidth: 1))
                        .padding(.top, 10)
                    } else if isGameDone {
                        HStack(spacing: 6) {
                            Text("Show Final Results")
                                .font(.carry.bodySMSemibold)
                                .foregroundColor(.white)
                            Text("·")
                                .font(.carry.bodySMSemibold)
                                .foregroundColor(.white.opacity(0.5))
                            Text("\(round.skinsWon) Skins")
                                .font(.carry.bodySMSemibold)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 13).fill(Color.textPrimary))
                        .padding(.top, 10)
                    } else if hasPending {
                        HStack(spacing: 6) {
                            PulsatingDot(color: Color.successGreen, size: 6)
                            Text("Show Pending Results · \(round.completedGroups)/\(round.totalGroups) Groups")
                                .font(.carry.bodySMSemibold)
                                .foregroundColor(Color.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 13).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.dividerLight, lineWidth: 1))
                        .padding(.top, 10)
                    } else if isLiveScoring {
                        // Handled above with isNotStarted
                    }

                } else {
                    // ── IDLE GROUP VERSION ────────────────────────────────
                    // Top: name + buy-in pill
                    HStack {
                        Text(group.name)
                            .font(.carry.bodyLGBold)
                            .foregroundColor(.black)
                        Spacer()
                        if group.buyInPerPlayer > 0 {
                            HStack(spacing: 5) {
                                Text("$")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(Color.white.opacity(0.3)))
                                Text("\(Int(group.buyInPerPlayer)) Buy-In")
                                    .font(.carry.captionLG)
                                    .foregroundColor(.white)
                            }
                            .padding(.leading, 5)
                            .padding(.trailing, 11)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(Color.goldMuted)
                            )
                        }
                    }

                    // Course name
                    if let courseName = group.lastCourse?.courseName ?? group.roundHistory.first?.courseName {
                        HStack {
                            Text(courseName)
                                .font(.carry.bodySM)
                                .foregroundColor(Color.textTertiary)
                            Spacer()
                        }
                        .padding(.top, 6)
                    }

                    // Scheduled tee time
                    if let label = group.scheduledLabel {
                        Text(label)
                            .font(.carry.bodySM)
                            .foregroundColor(Color.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                            .padding(.bottom, 12)
                    }

                    // Player pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(group.members) { player in
                                HStack(spacing: 6) {
                                    PlayerAvatar(player: player, size: 28)
                                    Text(player.shortName)
                                        .font(.carry.captionLG)
                                        .foregroundColor(Color.textPrimary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(Color.bgSecondary)
                                )
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            )
            .overlay {
                if let round = group.activeRound ?? group.concludedRound {
                    let showGlow = round.currentHole > 0 && !round.isGameDone
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            showGlow
                                ? Color.concludedGreen.opacity(groupCardPulse ? 0.8 : 0.3)
                                : Color.bgLight,
                            lineWidth: showGlow ? 2 : 1
                        )
                        .animation(showGlow ? .easeInOut(duration: 1.65).repeatForever(autoreverses: true) : .default, value: groupCardPulse)
                        .onAppear { if showGlow { groupCardPulse = true } }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            var label = group.name
            if let round = group.activeRound ?? group.concludedRound {
                label += ", \(round.courseName)"
                if round.isGameDone {
                    label += ", Game done"
                } else {
                    label += ", Live"
                    if round.currentHole > 0 { label += ", Hole \(round.currentHole)" }
                }
            }
            label += ", \(group.members.count) players"
            return label
        }())
        .accessibilityHint("Opens skins game")
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            if let url = group.inviteURL() {
                ShareLink(
                    item: url,
                    subject: Text("Join \(group.name)"),
                    message: Text("Tap to join our skins game on Carry")
                ) {
                    Label("Share Group Invite", systemImage: "square.and.arrow.up")
                }
            }
            if group.creatorId == authService.currentPlayerId {
                Button(role: .destructive) {
                    contextMenuGroup = group
                    showDeleteGroupConfirm = true
                } label: {
                    Label(group.isQuickGame ? "Delete Game" : "Delete Group", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    contextMenuGroup = group
                    showLeaveGroupConfirm = true
                } label: {
                    Label(group.isQuickGame ? "Leave Game" : "Leave Group", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }

    // MARK: - Convert Setup Sheet

    @FocusState private var convertNameFocused: Bool

    @ViewBuilder
    private var convertSetupSheet: some View {
        switch convertSheetPhase {
        case .prompt:
            convertPromptPhaseView
        case .setup:
            convertSetupPhaseView
        case .inviteCrew:
            convertInviteCrewPhaseView
        }
    }

    /// Figma `1187:10698` — full-view "Convert game into a recurring Skins
    /// Group" prompt. First step in the Quick Game → Group conversion sheet.
    /// Yes advances to the name/tee-time step; No Delete is destructive.
    /// Advance from `.prompt` → `.setup`. Pre-fill the group name from the
    /// Quick Game's course (e.g. "Ruby Hill Skins") so the happy path is a
    /// single tap on the next step.
    private func advanceToSetupPhase() {
        if convertGroupName.trimmingCharacters(in: .whitespaces).isEmpty,
           let groupId = completedGroupId,
           let course = groups.first(where: { $0.id == groupId })?.lastCourse?.courseName,
           !course.isEmpty {
            convertGroupName = "\(course) Skins"
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            convertSheetPhase = .setup
        }
    }

    private var convertPromptPhaseView: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 209 - 108)  // match Figma content top (209) minus sheet chrome (~108)

            VStack(spacing: 42) {
                VStack(spacing: 24) {
                    // Figma 1187:10724 — standalone Carry glyph (dark-green
                    // dollar-sign flag), 73×67pt. Uses the dedicated
                    // `carry-glyph` asset, not the word-mark `carry-logo`.
                    Image("carry-glyph")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 73, height: 67)

                    Text("Convert game into a recurring Skins Group")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .lineSpacing(41 - 36)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 24) {
                    convertPromptBenefitRow("Set up recurring tee times")
                    convertPromptBenefitRow("Track stats over time")
                    convertPromptBenefitRow("All-time leaderboard")
                    convertPromptBenefitRow("Invite anytime via QR or link")
                }
            }
            .padding(.horizontal, 37)

            Spacer()

            VStack(spacing: 17) {
                Button {
                    // Skip the name-setup step — convert immediately with an
                    // auto-generated name ("{Course} Skins"). User can rename
                    // in GroupManagerView once they land there; the rename
                    // editor auto-opens via `showInviteCrewOnAppear` passed
                    // to GroupManagerView.
                    guard let groupId = completedGroupId else { return }
                    let autoName: String = {
                        if let course = groups.first(where: { $0.id == groupId })?.lastCourse?.courseName, !course.isEmpty {
                            return "\(course) Skins"
                        }
                        return "Skins Game"
                    }()
                    #if DEBUG
                    if !groups.contains(where: { $0.id == groupId }) {
                        jumpToDebugInviteCrewWith(name: autoName)
                        return
                    }
                    #endif
                    convertQuickGameWithSetup(
                        groupId: groupId,
                        name: autoName,
                        teeTime: nil,
                        recurrence: nil,
                        consecutiveInterval: 0
                    )
                } label: {
                    Text("Yes, Create a Group")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 13).fill(.black))
                }
                .buttonStyle(.plain)

                Button {
                    convertPromptDeleteGame()
                } label: {
                    Text("No Delete This Game")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(red: 0.851, green: 0.176, blue: 0.125))  // #D92D20
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 27)
            .padding(.bottom, 16)
        }
    }

    private func convertPromptBenefitRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.black)
            Text(text)
                .font(.system(size: 23, weight: .regular))
                .foregroundColor(.black)
        }
    }

    /// "No Delete This Game" — hard-deletes the Quick Game group (FK cascade
    /// removes the completed round + scores). Placeholder — wired up after
    /// user confirms the visual match.
    private func convertPromptDeleteGame() {
        guard let groupId = completedGroupId else {
            showConvertSetupSheet = false
            return
        }
        Task {
            try? await GroupService().deleteGroup(groupId: groupId)
            await MainActor.run {
                groups.removeAll { $0.id == groupId }
                completedGroupId = nil
                showConvertSetupSheet = false
                convertSheetPhase = .setup
                ToastManager.shared.success("Game deleted")
            }
        }
    }

    private var convertSetupPhaseView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Text("Name Your Group")
                        .font(.carry.labelBold)
                        .foregroundColor(Color.textPrimary)
                        .padding(.top, 28)
                        .padding(.bottom, 24)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Group Name")
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.textPrimary)

                        TextField("e.g. Friday Skins", text: $convertGroupName)
                            .font(.carry.bodyLG)
                            .foregroundColor(Color.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.borderLight, lineWidth: 1))
                            .focused($convertNameFocused)
                            .submitLabel(.done)
                            .onSubmit { convertNameFocused = false }
                    }
                    .padding(.horizontal, 24)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Next Tee Time")
                                .font(.carry.bodySMBold)
                                .foregroundColor(Color.textPrimary)
                            Spacer()
                            Toggle("", isOn: $convertHasTeeTime)
                                .labelsHidden()
                                .tint(Color.successGreen)
                        }

                        if convertHasTeeTime {
                            convertTeeTimePicker
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            let trimmedName = convertGroupName.trimmingCharacters(in: .whitespaces)
            let canAdvance = !trimmedName.isEmpty
            Button {
                guard canAdvance else { return }
                if let groupId = completedGroupId {
                    #if DEBUG
                    // Debug preview short-circuit: if the staged groupId isn't
                    // a real group on this device (it was seeded by
                    // presentDebugConvertPrompt with a random UUID), skip the
                    // Supabase calls and jump straight to phase 2 with a
                    // mock so the full flow can be walked without a real
                    // Quick Game in Supabase.
                    if !groups.contains(where: { $0.id == groupId }) {
                        jumpToDebugInviteCrewWith(name: trimmedName)
                        completedGroupId = nil
                        return
                    }
                    #endif
                    convertQuickGameWithSetup(
                        groupId: groupId,
                        name: trimmedName,
                        teeTime: convertHasTeeTime ? convertTeeTime : nil,
                        recurrence: convertHasTeeTime ? buildConvertRecurrence() : nil,
                        consecutiveInterval: convertHasTeeTime ? convertConsecutiveInterval : 0
                    )
                }
                completedGroupId = nil
            } label: {
                Text("Create Group")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 19)
                            .fill(canAdvance ? Color.textPrimary : Color.borderMedium)
                    )
            }
            .disabled(!canAdvance)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        // Tap anywhere outside the TextField to dismiss the keyboard. The
        // plain `.onTapGesture` on a background doesn't fire for taps inside
        // the ScrollView, so we resign first responder via the responder
        // chain — robust across SwiftUI + UIKit interop.
        .contentShape(Rectangle())
        .onTapGesture { dismissKeyboard() }
        // Keep the Create Group button anchored at the bottom of the sheet
        // when the keyboard opens rather than floating above it.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func dismissKeyboard() {
        convertNameFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    /// Inline tee-time picker shown in phase-1 when "Next Tee Time" toggle is
    /// on. Matches the shared `TeeTimePickerSheet` + the Consecutive Tee Times
    /// pills from QuickStartSheet (Figma `599:27567`), embedded rather than
    /// nested in a separate sheet.
    private var convertTeeTimePicker: some View {
        VStack(spacing: 40) {
            // Single Game / Recurring pill toggle
            HStack(spacing: 0) {
                ForEach(Array(["Next Game", "Recurring"].enumerated()), id: \.offset) { idx, label in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            convertScheduleMode = idx
                            if idx == 0 {
                                convertSelectedDayPill = nil
                            } else if convertSelectedDayPill == nil {
                                let weekday = Calendar.current.component(.weekday, from: convertTeeTime)
                                convertSelectedDayPill = GameRecurrence.pillIndex(fromWeekday: weekday)
                            }
                        }
                    } label: {
                        Text(label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(convertScheduleMode == idx ? .white : Color.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Capsule().fill(convertScheduleMode == idx ? Color.textPrimary : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Capsule().fill(Color.bgPrimary))

            VStack(spacing: 8) {
                Text(convertScheduleMode == 0 ? "Date & Time" : "Start Date & Time")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.textPrimary)

                DatePicker(
                    "",
                    selection: $convertTeeTime,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 120)
                .clipped()
            }

            if convertScheduleMode == 1 {
                VStack(spacing: 16) {
                    Text("How Often?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.textPrimary)

                    HStack(spacing: 8) {
                        ForEach(Array(["Weekly", "Biweekly", "Monthly"].enumerated()), id: \.offset) { idx, label in
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    convertRepeatMode = idx
                                    if idx <= 1 && convertSelectedDayPill == nil {
                                        let weekday = Calendar.current.component(.weekday, from: convertTeeTime)
                                        convertSelectedDayPill = GameRecurrence.pillIndex(fromWeekday: weekday)
                                    }
                                    if idx == 2 { convertSelectedDayPill = nil }
                                }
                            } label: {
                                Text(label)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(convertRepeatMode == idx ? .white : Color.textPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule().fill(convertRepeatMode == idx ? Color.textPrimary : Color.bgPrimary)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if convertRepeatMode == 0 || convertRepeatMode == 1 {
                        let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { i in
                                Button {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        convertSelectedDayPill = i
                                    }
                                } label: {
                                    Text(dayLabels[i])
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(convertSelectedDayPill == i ? .white : Color.textPrimary)
                                        .frame(width: 40, height: 40)
                                        .background(
                                            Circle().fill(convertSelectedDayPill == i ? Color.textPrimary : Color.bgPrimary)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            VStack(spacing: 12) {
                Text("Consecutive Tee Times")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color.textPrimary)

                HStack(spacing: 10) {
                    ForEach([0, 8, 10, 12], id: \.self) { minutes in
                        Button {
                            convertConsecutiveInterval = minutes
                        } label: {
                            Text(minutes == 0 ? "Off" : "+\(minutes) min")
                                .font(.carry.bodySMSemibold)
                                .foregroundColor(convertConsecutiveInterval == minutes ? .white : Color.textPrimary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(convertConsecutiveInterval == minutes ? Color.textPrimary : Color.bgPrimary)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func buildConvertRecurrence() -> GameRecurrence? {
        guard convertScheduleMode == 1 else { return nil }
        switch convertRepeatMode {
        case 0:
            guard let pill = convertSelectedDayPill else { return nil }
            return .weekly(dayOfWeek: GameRecurrence.weekday(fromPillIndex: pill))
        case 1:
            guard let pill = convertSelectedDayPill else { return nil }
            return .biweekly(dayOfWeek: GameRecurrence.weekday(fromPillIndex: pill))
        case 2:
            let day = Calendar.current.component(.day, from: convertTeeTime)
            return .monthly(dayOfMonth: day)
        default:
            return nil
        }
    }

    private var convertInviteCrewPhaseView: some View {
        // Fall back to looking the group up in `groups` by `completedGroupId`
        // if the dedicated `inviteCrewGroup` state slipped (e.g. a transient
        // SwiftUI re-render cleared it between sheet-open and mount). In the
        // real flow one of these paths is always populated.
        let group = inviteCrewGroup ?? groups.first(where: { $0.id == completedGroupId })
        return VStack(spacing: 0) {
            // Figma 1194:12235 — close X is its own row at the top of the
            // sheet (y=122 on canvas), above the centered title (y=154).
            HStack {
                Spacer()
                Button {
                    finishConvertFlow()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.textSecondary)
                        .frame(width: 31.5, height: 31.5)
                        .background(
                            Circle().fill(Color(red: 0.941, green: 0.941, blue: 0.941))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.trailing, 15)
            // Design on right places the close X clearly below the sheet's
            // drag-indicator capsule, not tucked into it. 20pt lands the
            // 31.5pt circle centered in the space under the indicator.
            .padding(.top, 20)

            // Figma 1194:12287 — Inter Bold 21pt, line-height 32, centered.
            Text("Invite Players to Join")
                .font(.system(size: 21, weight: .bold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 31)
                .padding(.top, 0)
                .padding(.bottom, 14)

            // Figma 1194:12272 — segmented at y=200 on canvas, 14pt horizontal,
            // 50pt tall. 36pt gap below segmented to card top (y=286.69 - 250).
            inviteModeSegmentedControl
                .padding(.horizontal, 14)
                .padding(.bottom, 36)

            if let group {
                ScrollView {
                    switch inviteShareMode {
                    case .link:
                        convertShareLinkView(group: group)
                            .padding(.horizontal, 7)
                    case .qr:
                        convertInviteQRCard(group: group)
                            .padding(.horizontal, 19)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading group…")
                        .font(.system(size: 14))
                        .foregroundColor(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Figma 1194:12281 — Share Invite tab CTA at y=780 on canvas,
            // button h=56, 27pt horizontal margins. Card bottom at y=734 →
            // 46pt gap to button top. 38pt from button bottom to sheet bottom.
            if let group, inviteShareMode == .link {
                convertInviteCTA(group: group)
                    .padding(.horizontal, 27)
                    .padding(.top, 46)
                    .padding(.bottom, 38)
            }
        }
    }

    /// Custom pill segmented control — Figma `1174:3392`. Native SwiftUI
    /// `Picker(.segmented)` renders a UIKit `UISegmentedControl` which has
    /// a rectangular look that doesn't match. This builds the rounded-pill
    /// variant: #F0F0F0 track, white selected chip, fully-rounded corners.
    private var inviteModeSegmentedControl: some View {
        HStack(spacing: 0) {
            inviteModeSegmentButton(title: "Share Invite", mode: .link)
            inviteModeSegmentButton(title: "Scan QR", mode: .qr)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 3)
        .frame(height: 50)
        .background(
            Capsule(style: .continuous)
                .fill(Color(red: 0.941, green: 0.941, blue: 0.941))
        )
    }

    private func inviteModeSegmentButton(title: String, mode: InviteShareMode) -> some View {
        let isSelected = inviteShareMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                inviteShareMode = mode
            }
        } label: {
            Text(title)
                .fixedSize()
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    Group {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
                                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func convertInviteQRCard(group: SavedGroup) -> some View {
        // Figma 1194:10791 — light-green card with the 262pt QR and
        // "Scan to Join Group Directly" caption centered inside. Fixed
        // height (549pt) matches Figma's card dimensions.
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            QRCodeView(
                string: GroupInviteLink.url(for: group.id).absoluteString,
                size: 262,
                foreground: UIColor(Color.greenDark),
                background: UIColor(Color.successBgLight)
            )
            Text("Scan to Join Group Directly")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 549)
        .background(RoundedRectangle(cornerRadius: 32).fill(Color.successBgLight))
    }

    @ViewBuilder
    private func convertShareLinkView(group: SavedGroup) -> some View {
        let data = shareCardData(for: group)
        // Figma 1194:12315 — bordered white card filling the sheet width
        // (not the 390pt social-image size). Thin gray stroke, rounded corners.
        ResultsShareCard(data: data, theme: .light, showAppStoreBadge: false, fixedWidth: nil)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.borderLight, lineWidth: 1)
            )
    }

    /// The action button sitting below the scroll content. Figma shows it as
    /// the "Share Results & Invite Link" CTA on the Share Invite tab only.
    @ViewBuilder
    private func convertInviteCTA(group: SavedGroup) -> some View {
        let data = shareCardData(for: group)
        let inviteURL = GroupInviteLink.url(for: group.id)
        let subject = "Join my Skins Group on Carry"
        let message = "\(subject) — \(inviteURL.absoluteString)"

        if let image = ShareCardRenderer.render(data: data, theme: .light) {
            ShareLink(
                item: Image(uiImage: image),
                subject: Text(subject),
                message: Text(message),
                preview: SharePreview(subject, image: Image(uiImage: image))
            ) {
                convertInviteCTALabel(text: "Share Results & Invite Link")
            }
            .buttonStyle(.plain)
        } else {
            // ImageRenderer occasionally returns nil on first render — fall
            // back to link-only share so the button is never missing.
            ShareLink(item: inviteURL, subject: Text(subject), message: Text(message)) {
                convertInviteCTALabel(text: "Share Invite Link")
            }
            .buttonStyle(.plain)
        }
    }

    private func convertInviteCTALabel(text: String) -> some View {
        // Figma `1174:3361` — #1A1A1A bg, 17pt radius, 12pt vertical padding,
        // 20pt link-03 icon + 10pt gap + 16pt Inter SemiBold text in white.
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 20, height: 20)
            Text(text)
                .font(.system(size: 16, weight: .semibold))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 17).fill(Color(red: 0.102, green: 0.102, blue: 0.102)))
    }

    /// Build a ShareCardData snapshot from the group's most recent round.
    /// Mirrors the helper in GroupManagerView so Quick Game → Group
    /// conversions get the same share-card content on the Games tab sheet.
    private func shareCardData(for group: SavedGroup) -> ShareCardData {
        let lastRound = group.roundHistory.first
        let players = group.members.filter { !$0.name.isEmpty }
        let sorted = players.sorted {
            (lastRound?.playerWinnings[$0.id] ?? 0) > (lastRound?.playerWinnings[$1.id] ?? 0)
        }
        let entries = sorted.map { player in
            ShareCardEntry(
                name: player.shortName,
                initials: player.initials,
                color: player.color,
                skinsWon: lastRound?.playerWonHoles[player.id]?.count ?? 0,
                moneyAmount: lastRound?.playerWinnings[player.id] ?? 0
            )
        }
        let buyIn = lastRound?.buyIn ?? Int(group.buyInPerPlayer)
        return ShareCardData(
            courseName: lastRound?.courseName ?? group.lastCourse?.courseName ?? group.name,
            date: lastRound?.completedAt ?? Date(),
            teeName: lastRound?.teeBox?.name,
            handicapPct: Int(group.handicapPercentage * 100),
            entries: entries,
            potTotal: buyIn * max(players.count, 1),
            buyIn: buyIn
        )
    }

    // MARK: - Converting Overlay

    @ViewBuilder
    private var convertingOverlay: some View {
        if isConvertingGroup {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.3)
            }
            .transition(.opacity)
        }
    }

    // MARK: - Content

    private var gamesContentWithSheets: some View {
        gamesContent
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupSheet { newGroup in
                    groups.insert(newGroup, at: 0)
                    showCreateGroup = false
                    // Land inside the newly created group's details.
                    // `pendingActiveGroupId` is observed by a delayed handler
                    // above that waits for the sheet dismissal animation to
                    // settle, then sets `activeGroup` with a spring animation
                    // — same path used when tapping an existing group row.
                    pendingActiveGroupId = newGroup.id
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
            }
            .sheet(isPresented: $showQuickStart) {
                quickStartSheetContent
            }
            .sheet(isPresented: $showNewGamePicker) {
                newGamePickerSheet
                    .presentationDetents([.fraction(0.65)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.white)
            }
            .fullScreenCover(isPresented: $showQRScanner) {
                QRScannerView { payload in
                    handleScannedInvite(payload)
                }
            }
            .overlay {
                if let group = activeGroup {
                    roundCoordinatorOverlay(group: group)
                }
            }
            .overlay { convertingOverlay }
            .animation(.easeInOut(duration: 0.2), value: isConvertingGroup)
            .sheet(isPresented: $showConvertSetupSheet, onDismiss: {
                // Swipe-to-dismiss from phase 2 should still open the new
                // group and reset sheet state. Dismissing from phase 1 cancels
                // the conversion — clear the staged groupId so re-tapping
                // Create Group on the same Recent Games tile doesn't retrigger
                // with stale state.
                if inviteCrewGroup != nil {
                    finishConvertFlow()
                } else {
                    convertSheetPhase = .setup
                    completedGroupId = nil
                }
            }) {
                convertSetupSheet
                    .presentationDetents(
                        convertSheetPhase == .setup
                            ? [.height(520), .large]
                            : [.large]
                    )
                    .presentationDragIndicator(convertSheetPhase == .prompt ? .hidden : .visible)
                    .presentationBackground(.white)
                    // Lock swipe-to-dismiss for the commit phases (prompt +
                    // setup). Once we reach inviteCrew the group is already
                    // created server-side; allowing swipe there lets the user
                    // drop into the new group (onDismiss → finishConvertFlow
                    // sets activeGroup).
                    .interactiveDismissDisabled(convertSheetPhase != .inviteCrew)
            }
    }

    private var gamesContent: some View {
        // Default ZStack alignment (center) so the VStack lays out
        // identically to HomeView (which uses the same default). Using
        // `alignment: .bottom` here previously nudged the VStack — and
        // therefore the header title — down from the safe-area top,
        // producing a visible vertical shift between Home and Games.
        ZStack {
            Color.bgSecondary.ignoresSafeArea()

            VStack(spacing: 0) {
                gamesHeader
                gamesList
            }

            topFadeGradient
        }
        // Empty-state scan-invite CTA — applied as an overlay so its
        // bottom anchoring doesn't affect the underlying layout.
        .overlay(alignment: .bottom) {
            let hasVisibleGroups = groups.contains { !$0.isConcludedQuickGame }
            if !hasVisibleGroups && !isLoadingGroups {
                scanInviteEmptyStateButton
            }
        }
    }

    private var scanInviteEmptyStateButton: some View {
        Button {
            showQRScanner = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "qrcode.viewfinder")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                Text("Have an Invite? Scan QR")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(Color.textPrimary)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Tab bar in MainTabView is a floating capsule ~60pt tall whose top
        // edge sits ~59pt above the safe-area bottom. Target: the button's
        // visible bottom ends 40pt above that top edge, per the Figma spec.
        // Visible bottom = outer `padding(.bottom)` + inner `padding(.vertical, 16)`
        // above safe-area bottom → 83 + 16 = 99pt = 59 + 40.
        .padding(.bottom, 83)
        .accessibilityLabel("Scan an invite QR code")
    }

    private var topFadeGradient: some View {
        VStack {
            LinearGradient(
                colors: [Color.bgSecondary, Color.bgSecondary.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 50)
            .allowsHitTesting(false)
            Spacer()
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .onDisappear {
                    if storeService.isPremium {
                        showCreateGroup = true
                    }
                }
        }
    }

    // MARK: - Header

    private var gamesHeader: some View {
        // Hide the "+ New Game" capsule while the list has no cards — the
        // empty-state callout already surfaces a prominent CTA, and two
        // buttons would compete. As soon as a group exists the header
        // button returns for quick access at scale.
        let hasVisibleGroups = groups.contains { !$0.isConcludedQuickGame }
        return HStack {
            Text("Skins Games")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color.pureBlack)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        // Lock to 44pt so the title sits at the same vertical position as
        // the Home tab's "Hey, Daniel" greeting (Home's header has a 44x44
        // QR button that forces the row to 44pt; empty-state here has no
        // trailing controls, so without this the header is ~28pt tall and
        // the title visibly shifts up between tab switches).
        .frame(minHeight: 44)
        .overlay(alignment: .trailing) {
            if hasVisibleGroups {
                HStack(spacing: 8) {
                    Button {
                        showQRScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 34, height: 34)
                            .foregroundColor(Color.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Scan invite QR code")

                    Button {
                        showNewGamePicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                            Text("New")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Capsule().fill(Color.textPrimary))
                    }
                    .accessibilityLabel("Create new skins game")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    // MARK: - Games List

    private var gamesList: some View {
        ScrollView {
            // LazyVStack so only visible cards instantiate. With up to 20
            // players × 4 avatars per card × 10+ groups, an eager VStack
            // renders every avatar immediately on view load even if the
            // user never scrolls to them.
            LazyVStack(spacing: 0) {
                let visibleGroups = groups.filter { !$0.isConcludedQuickGame }

                if visibleGroups.isEmpty && isLoadingGroups {
                    ProgressView()
                        .padding(.vertical, 60)
                } else if visibleGroups.isEmpty {
                    emptyState
                } else {
                    let currentId = authService.currentPlayerId
                    let myGames = visibleGroups.filter { $0.creatorId == currentId }
                    let otherGames = visibleGroups.filter { $0.creatorId != currentId }

                    if !myGames.isEmpty {
                        sectionHeader("My Games")
                        ForEach(myGames) { group in
                            groupCard(group)
                                .padding(.bottom, 8)
                        }
                    }

                    if !otherGames.isEmpty {
                        sectionHeader("Member Of")
                            .padding(.top, myGames.isEmpty ? 0 : 16)
                        ForEach(otherGames) { group in
                            groupCard(group)
                                .padding(.bottom, 8)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollBounceBehavior(.always)
        .refreshable {
            if authService.isAuthenticated, let userId = authService.currentUser?.id {
                let groupService = GroupService()
                if let refreshed = try? await groupService.loadGroups(userId: userId) {
                    groups = refreshed
                }
            } else {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    // MARK: - New Game Picker Sheet

    private var newGamePickerSheet: some View {
        VStack(spacing: 16) {
            // Skins Game Group card
            Button {
                showNewGamePicker = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if !storeService.isPremium {
                        showPaywall = true
                    } else {
                        showCreateGroup = true
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 16) {
                    Image("picker-group")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)

                    Text("Recurring game with your crew. Leaderboards, & settlements.")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(Color(hexString: "#3E3E3E"))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 28)
                .background(RoundedRectangle(cornerRadius: 32).fill(Color.successBgLight.opacity(0.8)))
                // Premium badge removed — both Quick Game and Skins Group
                // require Premium now (the 3-free-Quick-Games allowance was
                // dropped in Free Tier v2 cleanup), so flagging only one as
                // Premium would be misleading. The paywall fires on tap.
            }
            .buttonStyle(.plain)

            // Quick Game card. Free-tier v2: starting any game requires
            // Premium. New downloaders get a 30-day trial via "Try It Free";
            // lapsed users get "Subscribe". On success, the onChange handler
            // above auto-opens Quick Start so one tap is enough.
            Button {
                showNewGamePicker = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if !storeService.isPremium {
                        pendingQuickStartAfterPaywall = true
                        showPaywall = true
                    } else {
                        showQuickStart = true
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 16) {
                    Image("picker-quick")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)

                    Text("Start a skins game in seconds\n— only scorers need the app.")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(Color(hexString: "#3E3E3E"))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 28)
                .background(RoundedRectangle(cornerRadius: 32).fill(Color.successBgLight.opacity(0.8)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
    }

    // MARK: - Empty State

    // MARK: - Debug Create Group Card

    private var debugCreateGroupCardOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showDebugCreateGroupCard = false }

            VStack(spacing: 0) {
                Image("carry-glyph")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(Color(hexString: "#BCF0B5"))
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .padding(.top, 36)
                    .padding(.bottom, 16)

                Text("Create a Group")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Color.textPrimary)
                    .padding(.bottom, 24)

                VStack(alignment: .leading, spacing: 16) {
                    debugBenefitRow("Manage players & who's playing today")
                    debugBenefitRow("Set up recurring tee times")
                    debugBenefitRow("Track stats over time")
                }
                .padding(.horizontal, 28)

                Spacer().frame(height: 40)

                VStack(spacing: 12) {
                    Button {
                        if storeService.isPremium {
                            showDebugCreateGroupCard = false
                            ToastManager.shared.success("Group successfully created")
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        Text("Create Group")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.textPrimary))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showDebugCreateGroupCard = false
                    } label: {
                        Text("Skip")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.systemRedColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.systemRedColor.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
            .background(RoundedRectangle(cornerRadius: 24).fill(.white))
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    /// Scanned QR payload handler. Unlike `CarryApp.handleIncomingURL` which
    /// only creates an `invited` row (the Universal Link path assumes the
    /// user will tap Accept on the Home invite card), an in-app scan is an
    /// explicit consent gesture — the user opened the scanner and pointed
    /// at the code — so we promote the membership straight to `active` and
    /// land the user inside the group. The creator's device shows the
    /// standard "X joined — tap Manage to add to tee sheet" toast when the
    /// new active member surfaces in `refreshGroupData`.
    private func handleScannedInvite(_ payload: String) {
        showQRScanner = false

        guard
            let url = URL(string: payload),
            let invite = GroupInviteParser.parse(url),
            let groupId = invite.groupId
        else {
            ToastManager.shared.error("That QR isn't a Carry invite.")
            return
        }

        Task {
            guard let userId = try? await SupabaseManager.shared.client.auth.session.user.id else { return }
            let service = GroupService()
            do {
                let groupName = try await service.joinGroupViaInvite(groupId: groupId, playerId: userId)
                await MainActor.run {
                    ToastManager.shared.success("Joined \(groupName)")
                    appRouter.shouldRefreshGroups = true
                    appRouter.pendingRoundGroupId = groupId
                }
            } catch {
                await MainActor.run {
                    ToastManager.shared.error("Couldn't join that group. Try again.")
                }
            }
        }
    }

    private func debugBenefitRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.textPrimary)
            Text(text)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Color.textPrimary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.carry.displaySM)
                .foregroundColor(Color.textDisabled)

            Text("No Skin Games Yet")
                .font(.carry.bodyLG)
                .foregroundColor(Color.textTertiary)

            Text("Create a skin game to track skins with your crew.")
                .font(.carry.captionLG)
                .foregroundColor(Color.textDisabled)
                .multilineTextAlignment(.center)

            Button {
                showNewGamePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text("New Skins Game")
                        .font(.carry.bodySMBold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Color.pureBlack)
                )
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 60)
    }
}

// MARK: - Game Recurrence

enum GameRecurrence: Codable, Equatable {
    case weekly(dayOfWeek: Int)     // 1=Sunday … 7=Saturday
    case biweekly(dayOfWeek: Int)
    case monthly(dayOfMonth: Int)

    /// Short label for display, e.g. "Every Friday" or "Every 2 weeks · Friday"
    var label: String {
        switch self {
        case .weekly(let day):
            return "Every \(Self.dayName(day))"
        case .biweekly(let day):
            return "Every 2 weeks · \(Self.dayName(day))"
        case .monthly(let dayOfMonth):
            let suffix: String
            switch dayOfMonth {
            case 1, 21, 31: suffix = "st"
            case 2, 22: suffix = "nd"
            case 3, 23: suffix = "rd"
            default: suffix = "th"
            }
            return "Monthly · \(dayOfMonth)\(suffix)"
        }
    }

    /// Compact label for group detail header, e.g. "Every Fri" or "Every 2 wks · Fri"
    var shortLabel: String {
        switch self {
        case .weekly(let day):
            return "Every \(Self.shortDayName(day))"
        case .biweekly(let day):
            return "Every 2 wks · \(Self.shortDayName(day))"
        case .monthly(let dayOfMonth):
            let suffix: String
            switch dayOfMonth {
            case 1, 21, 31: suffix = "st"
            case 2, 22: suffix = "nd"
            case 3, 23: suffix = "rd"
            default: suffix = "th"
            }
            return "Monthly · \(dayOfMonth)\(suffix)"
        }
    }

    private static func shortDayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols // ["Sun", "Mon", ...]
        guard weekday >= 1, weekday <= 7 else { return "" }
        return symbols[weekday - 1]
    }

    /// Day of week (1-7) for weekly/biweekly, nil for monthly
    var dayOfWeek: Int? {
        switch self {
        case .weekly(let d), .biweekly(let d): return d
        case .monthly: return nil
        }
    }

    /// Next occurrence from today (or the given date)
    func nextDate(after ref: Date = Date()) -> Date {
        let cal = Calendar.current
        switch self {
        case .weekly(let day):
            return cal.nextDate(after: ref, matching: DateComponents(weekday: day), matchingPolicy: .nextTime) ?? ref
        case .biweekly(let day):
            // Next occurrence of this weekday, then add 7 days (every other week)
            let next = cal.nextDate(after: ref, matching: DateComponents(weekday: day), matchingPolicy: .nextTime) ?? ref
            return cal.date(byAdding: .day, value: 7, to: next) ?? next
        case .monthly(let dayOfMonth):
            return cal.nextDate(after: ref, matching: DateComponents(day: dayOfMonth), matchingPolicy: .nextTime) ?? ref
        }
    }

    private static func dayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols // ["Sunday", "Monday", ...]
        guard weekday >= 1, weekday <= 7 else { return "" }
        return symbols[weekday - 1]
    }

    /// Weekday index (1-7) from a pill index (0=Mon … 6=Sun)
    static func weekday(fromPillIndex i: Int) -> Int {
        // Pill: 0=Mon,1=Tue,2=Wed,3=Thu,4=Fri,5=Sat,6=Sun
        // Calendar: 1=Sun,2=Mon,3=Tue,4=Wed,5=Thu,6=Fri,7=Sat
        return (i + 2) > 7 ? 1 : (i + 2)  // 0→2(Mon), 4→6(Fri), 6→1(Sun)
    }

    /// Pill index (0=Mon … 6=Sun) from a weekday (1-7)
    static func pillIndex(fromWeekday w: Int) -> Int {
        // 1(Sun)→6, 2(Mon)→0, 3(Tue)→1, …, 7(Sat)→5
        return w == 1 ? 6 : w - 2
    }
}

// MARK: - Alert Modifiers (extracted to reduce body complexity)

private struct GroupsAlertModifiers: ViewModifier {
    @Binding var showLeaveGroupConfirm: Bool
    @Binding var showDeleteGroupConfirm: Bool
    @Binding var showRecurringPrompt: Bool
    @Binding var contextMenuGroup: SavedGroup?
    @Binding var completedGroupId: UUID?
    @Binding var groups: [SavedGroup]
    @Binding var showPaywall: Bool
    var onLeaveGroup: (SavedGroup) -> Void
    var onDeleteGroup: (SavedGroup) -> Void
    var onConvertAndCopy: (UUID) -> Void
    var onConvert: (UUID) -> Void
    var onDeleteQuickGame: (UUID) -> Void

    func body(content: Content) -> some View {
        content
            .alert("Leave Group?", isPresented: $showLeaveGroupConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Leave", role: .destructive) {
                    if let group = contextMenuGroup {
                        onLeaveGroup(group)
                    }
                    contextMenuGroup = nil
                }
            } message: {
                Text("You'll be removed from \(contextMenuGroup?.name ?? "this group") and future games.")
            }
            .alert(
                contextMenuGroup?.isQuickGame == true ? "Delete Game?" : "Delete Group?",
                isPresented: $showDeleteGroupConfirm
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let group = contextMenuGroup {
                        onDeleteGroup(group)
                    }
                    contextMenuGroup = nil
                }
            } message: {
                let label = contextMenuGroup?.isQuickGame == true ? "game" : "group"
                Text("This will remove \(contextMenuGroup?.name ?? "this \(label)") for all members. This can't be undone.")
            }
            .alert("Play again?", isPresented: $showRecurringPrompt) {
                Button("Make it a group") {
                    if let groupId = completedGroupId {
                        onConvertAndCopy(groupId)
                    }
                    // Don't clear completedGroupId here — the setup sheet needs it
                }
                Button("No, just this once", role: .cancel) {
                    if let groupId = completedGroupId {
                        onDeleteQuickGame(groupId)
                    }
                    completedGroupId = nil
                }
            } message: {
                Text("Turn this into a recurring group and invite your crew to join on Carry.")
            }
    }
}

// MARK: - Saved Group Model

struct SavedGroup: Identifiable, Equatable {
    static func == (lhs: SavedGroup, rhs: SavedGroup) -> Bool {
        lhs.id == rhs.id
        && lhs.name == rhs.name
        && lhs.members.map(\.id) == rhs.members.map(\.id)
        && lhs.members.map(\.isPendingAccept) == rhs.members.map(\.isPendingAccept)
        && lhs.potSize == rhs.potSize
        && lhs.buyInPerPlayer == rhs.buyInPerPlayer
        && lhs.scheduledDate == rhs.scheduledDate
        && lhs.lastCourse?.courseName == rhs.lastCourse?.courseName
        && lhs.recurrence == rhs.recurrence
        && lhs.activeRound?.id == rhs.activeRound?.id
        && lhs.concludedRound?.id == rhs.concludedRound?.id
        && lhs.roundHistory.map(\.id) == rhs.roundHistory.map(\.id)
        && lhs.handicapPercentage == rhs.handicapPercentage
        && lhs.isQuickGame == rhs.isQuickGame
        && lhs.scorerIds == rhs.scorerIds
        && lhs.carriesEnabled == rhs.carriesEnabled
    }
    let id: UUID
    let name: String
    let members: [Player]
    let lastPlayed: String?
    let creatorId: Int
    var lastCourse: SelectedCourse?
    var activeRound: HomeRound? = nil
    var concludedRound: HomeRound? = nil  // all groups finished, awaiting user review
    var roundHistory: [HomeRound] = []
    var potSize: Double = 0        // total pot in dollars (0 = no pot set)
    var buyInPerPlayer: Double = 0 // per-player contribution
    var scheduledDate: Date? = nil // next scheduled tee time
    var recurrence: GameRecurrence? = nil // recurring schedule
    var handicapPercentage: Double = 1.0 // 0.0–1.0
    var isQuickGame: Bool = false // true for Quick Game groups (show compact date header)
    var scorerIds: [Int]? = nil // per-group scorer player IDs from Supabase
    var teeTimes: [Date?]? = nil // per-group tee times (Quick Game consecutive)
    var teeTimeInterval: Int? = nil // minutes between consecutive tee times
    var winningsDisplay: String = "gross" // "gross" or "net" — how winnings are shown
    var carriesEnabled: Bool = false // whether carries are enabled for this game
    var todayDeselectedIds: [UUID] = [] // profile UUIDs the creator swiped off today's tee sheet

    // Cached formatters. DateFormatter allocation is O(ms) — when
    // `scheduledLabel` was building a fresh formatter on every access,
    // 10 group cards × multiple body re-evaluations per scroll meant
    // dozens of redundant allocations per frame. Static instances are
    // thread-safe for the read-only `string(from:)` method used here.
    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    /// Human-readable scheduled date, e.g. "Every Friday · 8:00 AM" or "Sat, Mar 14 · 8:24 AM"
    var scheduledLabel: String? {
        if let rec = recurrence {
            if let date = scheduledDate {
                return "\(rec.label) · \(Self.shortTimeFormatter.string(from: date))"
            }
            return rec.label
        }
        guard let date = scheduledDate else { return nil }
        let time = Self.shortTimeFormatter.string(from: date)
        if Calendar.current.isDateInToday(date) {
            return "Today · \(time)"
        }
        return "\(Self.shortDayFormatter.string(from: date)) · \(time)"
    }

    /// Concluded quick game — no active round, has round history. Hidden from Games tab.
    var isConcludedQuickGame: Bool {
        isQuickGame && activeRound == nil && !roundHistory.isEmpty
    }

    /// Move `concludedRound` into `roundHistory` locally so UI filters that key
    /// off roundHistory (e.g. `isConcludedQuickGame`) update immediately — without
    /// waiting for the async server reload after the user declines to save/convert.
    mutating func archiveConcludedRound() {
        guard let concluded = concludedRound else { return }
        roundHistory.insert(concluded, at: 0)
        concludedRound = nil
    }

    /// True if the group has an active/concluded round or a tee time within the next hour.
    var isLiveOrUpcoming: Bool {
        if activeRound != nil || concludedRound != nil { return true }
        guard let date = scheduledDate else { return false }
        let now = Date()
        return date > now && date.timeIntervalSince(now) <= 3600
    }

    /// Builds a carry://join-group deep-link URL for sharing this group.
    func inviteURL() -> URL? {
        GroupInviteParser.buildURL(groupId: id)
    }

    #if DEBUG
    static let demo: [SavedGroup] = [
        SavedGroup(
            id: UUID(),
            name: "The Friday Skins",
            members: Player.allPlayers,
            lastPlayed: "Mar 1",
            creatorId: 1,
            lastCourse: SelectedCourse(courseId: 1, courseName: "Torrey Pines South", clubName: "Torrey Pines", location: "La Jolla, CA", teeBox: TeeBox.demo[1], apiTee: nil),
            activeRound: HomeRound.demoActive.first,
            roundHistory: [
                HomeRound(
                    id: UUID(),
                    groupName: "The Friday Skins",
                    courseName: "Ruby Hill",
                    players: Player.allPlayers,
                    status: .completed,
                    currentHole: 18,
                    totalHoles: 18,
                    buyIn: 50,
                    skinsWon: 8,
                    totalSkins: 18,
                    yourSkins: 2,
                    invitedBy: nil,
                    creatorId: 1,
                    startedAt: Calendar.current.date(byAdding: .hour, value: -5, to: Date()),
                    completedAt: Calendar.current.date(byAdding: .hour, value: -1, to: Date()),
                    playerWinnings: [1: 150, 3: 150, 2: 75, 6: 75, 5: 75, 9: 75],
                    playerWonHoles: [1: [3, 11], 3: [1, 7], 2: [5], 6: [9], 5: [14], 9: [16]]
                ),
                HomeRound(
                    id: UUID(),
                    groupName: "The Friday Skins",
                    courseName: "Torrey Pines South",
                    players: Player.allPlayers,
                    status: .completed,
                    currentHole: 18,
                    totalHoles: 18,
                    buyIn: 50,
                    skinsWon: 14,
                    totalSkins: 18,
                    yourSkins: 3,
                    invitedBy: nil,
                    creatorId: 1,
                    startedAt: Calendar.current.date(byAdding: .day, value: -7, to: Date()),
                    completedAt: Calendar.current.date(byAdding: .day, value: -7, to: Date()),
                    playerWinnings: [1: 129, 2: 129, 3: 86, 6: 86, 5: 86, 8: 43, 10: 43],
                    playerWonHoles: [1: [2, 8, 15], 2: [4, 10, 13], 3: [6, 17], 6: [1, 12], 5: [7, 18], 8: [3], 10: [11]]
                ),
                HomeRound(
                    id: UUID(),
                    groupName: "The Friday Skins",
                    courseName: "Blackhawk CC",
                    players: Player.allPlayers,
                    status: .completed,
                    currentHole: 18,
                    totalHoles: 18,
                    buyIn: 50,
                    skinsWon: 10,
                    totalSkins: 18,
                    yourSkins: 1,
                    invitedBy: nil,
                    creatorId: 1,
                    startedAt: Calendar.current.date(byAdding: .day, value: -14, to: Date()),
                    completedAt: Calendar.current.date(byAdding: .day, value: -14, to: Date()),
                    playerWinnings: [1: 60, 3: 120, 7: 60, 4: 60, 11: 120, 2: 60, 12: 60, 9: 60],
                    playerWonHoles: [1: [5], 3: [2, 14], 7: [8], 4: [11], 11: [3, 16], 2: [6], 12: [9], 9: [17]]
                ),
                HomeRound(
                    id: UUID(),
                    groupName: "The Friday Skins",
                    courseName: "Castlewood CC",
                    players: Player.allPlayers,
                    status: .completed,
                    currentHole: 18,
                    totalHoles: 18,
                    buyIn: 50,
                    skinsWon: 11,
                    totalSkins: 18,
                    yourSkins: 0,
                    invitedBy: nil,
                    creatorId: 1,
                    startedAt: Calendar.current.date(byAdding: .day, value: -21, to: Date()),
                    completedAt: Calendar.current.date(byAdding: .day, value: -21, to: Date()),
                    playerWinnings: [3: 109, 6: 164, 2: 55, 8: 55, 5: 109, 10: 55, 7: 55],
                    playerWonHoles: [3: [1, 10], 6: [4, 9, 15], 2: [7], 8: [12], 5: [3, 18], 10: [6], 7: [13]]
                ),
            ],
            potSize: 200,
            buyInPerPlayer: 50,
            scheduledDate: Calendar.current.date(byAdding: .hour, value: -2, to: Date()),
            recurrence: .weekly(dayOfWeek: 6)  // Every Friday
        ),
        SavedGroup(
            id: UUID(),
            name: "Weekend Warriors",
            members: Array(Player.allPlayers.prefix(4)),
            lastPlayed: "Feb 22",
            creatorId: 1,
            lastCourse: SelectedCourse(courseId: 2, courseName: "Riverwalk Golf Club", clubName: "Riverwalk Golf Club", location: "San Diego, CA", teeBox: TeeBox.demo[1], apiTee: nil),
            activeRound: nil,
            roundHistory: [
                HomeRound(
                    id: UUID(),
                    groupName: "Weekend Warriors",
                    courseName: "Riverwalk Golf Club",
                    players: Array(Player.allPlayers.prefix(4)),
                    status: .completed,
                    currentHole: 18,
                    totalHoles: 18,
                    buyIn: 25,
                    skinsWon: 12,
                    totalSkins: 18,
                    yourSkins: 0,
                    invitedBy: nil,
                    creatorId: 1,
                    startedAt: Calendar.current.date(byAdding: .day, value: -14, to: Date()),
                    completedAt: Calendar.current.date(byAdding: .day, value: -14, to: Date())
                ),
            ],
            potSize: 100,
            buyInPerPlayer: 25,
            scheduledDate: Calendar.current.date(byAdding: .day, value: 5, to: Date())
        ),
        SavedGroup(
            id: UUID(),
            name: "Thursday Boys",
            members: Array(Player.allPlayers.suffix(4)),
            lastPlayed: "Feb 15",
            creatorId: 2,
            lastCourse: SelectedCourse(courseId: 3, courseName: "Balboa Park Golf Course", clubName: "Balboa Park", location: "San Diego, CA", teeBox: TeeBox.demo[0], apiTee: nil),
            activeRound: nil,
            roundHistory: [
                HomeRound(
                    id: UUID(),
                    groupName: "Thursday Boys",
                    courseName: "Balboa Park Golf Course",
                    players: Array(Player.allPlayers.suffix(4)),
                    status: .completed,
                    currentHole: 18,
                    totalHoles: 18,
                    buyIn: 20,
                    skinsWon: 10,
                    totalSkins: 18,
                    yourSkins: 1,
                    invitedBy: nil,
                    creatorId: 2,
                    startedAt: Calendar.current.date(byAdding: .day, value: -10, to: Date()),
                    completedAt: Calendar.current.date(byAdding: .day, value: -10, to: Date())
                ),
            ],
            potSize: 80,
            buyInPerPlayer: 20,
            scheduledDate: nil
        ),
    ]

    /// Demo groups showing all 4 active card states
    static var demoAllCardStates: [SavedGroup] {
        HomeRound.demoAllCardStates.map { round in
            SavedGroup(
                id: UUID(),
                name: round.groupName,
                members: round.players,
                lastPlayed: "Mar 1",
                creatorId: 1,
                lastCourse: SelectedCourse(courseId: 1, courseName: round.courseName, clubName: "Torrey Pines", location: "La Jolla, CA", teeBox: TeeBox.demo[1], apiTee: nil),
                activeRound: round.isGameDone ? nil : round,
                concludedRound: round.isGameDone ? round : nil,
                roundHistory: [],
                potSize: 200,
                buyInPerPlayer: 50,
                scheduledDate: round.scheduledDate
            )
        }
    }

    /// Demo groups with a concluded round (for debug scenario)
    static let demoConcluded: [SavedGroup] = [
        SavedGroup(
            id: UUID(),
            name: "The Friday Skins",
            members: Player.allPlayers,
            lastPlayed: "Mar 1",
            creatorId: 1,
            lastCourse: SelectedCourse(courseId: 1, courseName: "Torrey Pines South", clubName: "Torrey Pines", location: "La Jolla, CA", teeBox: TeeBox.demo[1], apiTee: nil),
            activeRound: nil,
            concludedRound: HomeRound.demoConcluded.first,
            roundHistory: HomeRound.demoRecent,
            potSize: 200,
            buyInPerPlayer: 50,
            scheduledDate: Calendar.current.date(byAdding: .hour, value: -4, to: Date()),
            recurrence: .weekly(dayOfWeek: 6)
        ),
    ]
    #endif
}

// MARK: - Create Group Sheet

struct CreateGroupSheet: View {
    @EnvironmentObject var authService: AuthService
    let onCreate: (SavedGroup) -> Void

    @State private var groupName = ""
    @State private var selectedCourse: SelectedCourse?
    @State private var showCourseSelector = false
    @State private var handicapPct: Double = 1.0
    @State private var buyInAmount: Double = 0
    @State private var scheduledDate: Date? = nil
    @State private var showDatePicker = false
    @State private var teeTimeInterval: Int = 0  // 0 = single, 8/10/12 = minutes between groups

    // Recurrence
    @State private var scheduleMode: Int = 0  // 0 = Single Game, 1 = Recurring
    @State private var repeatMode: Int = 0  // 0=Never, 1=Weekly, 2=Biweekly, 3=Monthly
    @State private var selectedDayPill: Int? = nil  // 0=Mon…6=Sun (pill index)

    // Member search
    @State private var memberSearchText = ""
    @State private var memberSearchResults: [ProfileDTO] = []
    @State private var isMemberSearching = false
    @State private var memberSearchTask: Task<Void, Never>?
    @State private var selectedMembers: [Player] = []

    // Phone invite (inline below search results)
    @State private var phoneText = ""
    @State private var guests: [Player] = []
    @State private var nextGuestID = 100
    private var isFormValid: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty
            && (selectedMembers.count + guests.count) >= 1
            && selectedCourse != nil
            && buyInAmount > 0
            && scheduledDate != nil
    }

    enum InputField: Hashable { case groupName, memberSearch, inlinePhone }
    @FocusState private var focusedField: InputField?

    private var creatorPlayer: Player? {
        guard let profile = authService.currentUser else { return nil }
        return Player(from: profile)
    }



    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Skins Group")
                .font(.carry.sectionTitle)
                .foregroundColor(Color.pureBlack)
                .padding(.top, 40)
                .padding(.bottom, 24)
                .accessibilityAddTraits(.isHeader)

            ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                // Group name field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Group Name")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)
                        .padding(.leading, 4)

                    TextField("Friday Skins", text: $groupName)
                        .font(.carry.bodyLG)
                        .focused($focusedField, equals: .groupName)
                        .carryInput(focused: focusedField == .groupName)
                }
                .id(InputField.groupName)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                // Members section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Members")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)
                        .padding(.leading, 4)

                    if !selectedMembers.isEmpty || !guests.isEmpty {
                        Text("\(selectedMembers.count + guests.count) player\(selectedMembers.count + guests.count == 1 ? "" : "s")")
                            .font(.carry.caption)
                            .foregroundColor(Color.textTertiary)
                            .padding(.leading, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

                // Search bar
                memberSearchBar
                    .id(InputField.memberSearch)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                // Search results (shown when typing — pills hidden so results sit right below search bar)
                if !memberSearchText.isEmpty {
                    memberSearchResultsList
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                } else if !selectedMembers.isEmpty || !guests.isEmpty {
                    // Selected member chips (shown when not searching)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedMembers) { player in
                                selectedMemberChip(player, isGuest: false)
                            }
                            ForEach(guests) { player in
                                selectedMemberChip(player, isGuest: true)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 18)
                }

                // Tee Time section
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Tee Time")
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.textPrimary)
                        Spacer()
                        Text("Tee times can be updated")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.textSecondary)
                    }
                    .padding(.leading, 4)

                    if let date = scheduledDate {
                        Button {
                            showDatePicker = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Self.teeTimeFormatter.string(from: date))
                                        .font(.carry.bodyLG)
                                        .foregroundColor(Color.textPrimary)
                                    if scheduleMode == 1 && repeatMode > 0 {
                                        let freqLabel = repeatMode == 1 ? "Weekly" : repeatMode == 2 ? "Every 2 weeks" : "Monthly"
                                        Text(freqLabel)
                                            .font(.carry.caption)
                                            .foregroundColor(Color.textTertiary)
                                    }
                                }
                                Spacer()
                                Text("Change")
                                    .font(.carry.captionLG)
                                    .foregroundColor(Color.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.borderLight, lineWidth: 1))
                    } else {
                        Button {
                            showDatePicker = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.fill")
                                    .font(.carry.bodySM)
                                    .foregroundColor(Color.textPrimary)
                                Text("Add Tee Time")
                                    .font(.carry.bodyLG)
                                    .foregroundColor(Color.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.carry.micro)
                                    .foregroundColor(Color.textDisabled)
                            }
                            .frame(minHeight: 22)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.borderLight, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .id("teeTime")
                .onChange(of: scheduledDate) {
                    if scheduledDate != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation { scrollProxy.scrollTo("createButton", anchor: .bottom) }
                        }
                    }
                }

                // Course section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Course")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)
                        .padding(.leading, 4)

                    Button {
                        showCourseSelector = true
                    } label: {
                        if let course = selectedCourse {
                            // Course selected — show details card
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(course.courseName)
                                        .font(.carry.bodySemibold)
                                        .foregroundColor(Color.textPrimary)
                                    if let tee = course.teeBox {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(Color(hexString: tee.color))
                                                .frame(width: 8, height: 8)
                                            Text(tee.name)
                                                .font(.carry.caption)
                                                .foregroundColor(Color.textTertiary)
                                            Text("\u{00B7}")
                                                .foregroundColor(Color.textDisabled)
                                            Text(String(format: "%.1f / %d", tee.courseRating, tee.slopeRating))
                                                .font(.carry.caption)
                                                .foregroundColor(Color.textTertiary)
                                        }
                                    }
                                    if !course.location.isEmpty {
                                        Text(course.location)
                                            .font(.carry.caption)
                                            .foregroundColor(Color.textTertiary)
                                    }
                                }

                                Spacer()

                                Text("Change")
                                    .font(.carry.captionLG)
                                    .foregroundColor(Color.textTertiary)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.borderLight, lineWidth: 1)
                            )
                        } else {
                            // No course selected
                            HStack(spacing: 10) {
                                Image(systemName: "flag.fill")
                                    .font(.carry.bodySM)
                                    .foregroundColor(Color.textPrimary)
                                Text("Select a course")
                                    .font(.carry.bodyLG)
                                    .foregroundColor(Color.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.carry.micro)
                                    .foregroundColor(Color.textDisabled)
                            }
                            .frame(minHeight: 22)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.borderLight, lineWidth: 1)
                            )
                        }
                    }
                    .buttonStyle(.plain)

                    // Handicap % row (only when course is selected)
                    if selectedCourse != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Handicap Allowance")
                                    .font(.carry.bodySMBold)
                                    .foregroundColor(Color.textPrimary)
                                Spacer()
                                Text("\(Int(handicapPct * 100))%")
                                    .font(.carry.captionLGSemibold)
                                    .foregroundColor(Color.textPrimary)
                            }
                            Slider(value: $handicapPct, in: 0.1...1.0, step: 0.05)
                                .tint(Color.textPrimary)
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                // Buy-In field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Buy-In per Player")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)
                        .padding(.leading, 4)

                    VStack(spacing: 8) {
                        HStack {
                            Text("$\(Int(buyInAmount))")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(Color.textPrimary)
                                .monospacedDigit()
                            Spacer()
                            if buyInAmount > 0, (selectedMembers.count + guests.count) >= 2 {
                                let totalPlayers = selectedMembers.count + guests.count
                                Text("Pot: $\(Int(buyInAmount * Double(totalPlayers)))")
                                    .font(.carry.bodySMBold)
                                    .foregroundColor(Color.goldAccent)
                            }
                        }

                        Slider(value: $buyInAmount, in: 0...500, step: 5)
                            .tint(Color.goldAccent)

                        HStack {
                            Text("$0")
                                .font(.carry.micro)
                                .foregroundColor(Color.textDisabled)
                            Spacer()
                            Text("$1,000")
                                .font(.carry.micro)
                                .foregroundColor(Color.textDisabled)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.borderLight, lineWidth: 1)
                    )
                }
                .id("buyIn")
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                // Create button
                Button {
                    focusedField = nil
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    let allMembers = selectedMembers + guests
                    let buyIn = buyInAmount
                    // Build recurrence from selected repeat mode (only in Recurring mode)
                    let recurrence: GameRecurrence? = {
                        guard scheduleMode == 1 else { return nil }
                        switch repeatMode {
                        case 1:
                            guard let pill = selectedDayPill else { return nil }
                            return .weekly(dayOfWeek: GameRecurrence.weekday(fromPillIndex: pill))
                        case 2:
                            guard let pill = selectedDayPill else { return nil }
                            return .biweekly(dayOfWeek: GameRecurrence.weekday(fromPillIndex: pill))
                        case 3:
                            let day = Calendar.current.component(.day, from: scheduledDate ?? Date())
                            return .monthly(dayOfMonth: day)
                        default:
                            return nil
                        }
                    }()

                    // Persist to Supabase if authenticated
                    if authService.isAuthenticated, let userId = authService.currentUser?.id {
                        let trimmedName = groupName.trimmingCharacters(in: .whitespaces)
                        let memberUUIDs = allMembers.compactMap(\.profileId)

                        // Optimistic: show group immediately with temp ID
                        let tempGroup = SavedGroup(
                            id: UUID(),
                            name: trimmedName,
                            members: allMembers,
                            lastPlayed: nil,
                            creatorId: authService.currentPlayerId,
                            lastCourse: selectedCourse,
                            potSize: buyIn * Double(allMembers.count),
                            buyInPerPlayer: buyIn,
                            scheduledDate: scheduledDate,
                            recurrence: recurrence
                        )
                        onCreate(tempGroup)
                        if let date = scheduledDate {
                            NotificationService.shared.scheduleTeeTimeReminder(groupId: tempGroup.id, groupName: tempGroup.name, teeTime: date)
                        }
                        ToastManager.shared.success("Skins game created!")

                        // Sync to Supabase in background, then replace temp group with real one
                        Task {
                            do {
                                let groupService = GroupService()
                                // Encode holes JSON so par/hcp data survives across devices
                                var holesJson: String? = nil
                                if let holes = selectedCourse?.teeBox?.holes,
                                   !holes.isEmpty,
                                   let data = try? JSONEncoder().encode(holes) {
                                    holesJson = String(data: data, encoding: .utf8)
                                }
                                let dto = try await groupService.createGroup(
                                    name: trimmedName,
                                    createdBy: userId,
                                    memberIds: memberUUIDs,
                                    buyIn: buyIn,
                                    scheduledDate: scheduledDate,
                                    recurrence: recurrence,
                                    courseName: selectedCourse?.courseName,
                                    courseClubName: selectedCourse?.clubName,
                                    teeBoxName: selectedCourse?.teeBox?.name,
                                    teeBoxColor: selectedCourse?.teeBox?.color,
                                    teeBoxCourseRating: selectedCourse?.teeBox?.courseRating,
                                    teeBoxSlopeRating: selectedCourse?.teeBox?.slopeRating,
                                    teeBoxPar: selectedCourse?.teeBox?.par,
                                    handicapPercentage: handicapPct,
                                    lastTeeBoxHolesJson: holesJson
                                )
                                // Replace temp group with real Supabase group on next refresh
                                #if DEBUG
                                print("[GroupService] Group synced to Supabase: \(dto.id)")
                                #endif
                                let mCount = memberUUIDs.count + 1
                                let hasRec = recurrence != nil
                                Analytics.groupCreated(name: trimmedName, memberCount: mCount, buyIn: buyIn, hasRecurrence: hasRec)

                                // Create Supabase records for phone-invited guests
                                for guest in guests where guest.isPendingInvite {
                                    if let phone = guest.phoneNumber, !phone.isEmpty {
                                        try? await groupService.inviteMemberByPhone(
                                            groupId: dto.id, phone: phone, invitedBy: userId
                                        )
                                    }
                                }
                            } catch {
                                #if DEBUG
                                print("[GroupService] Failed to sync group: \(error)")
                                #endif
                                await MainActor.run {
                                    ToastManager.shared.error("Couldn't sync to server — will retry")
                                }
                            }
                        }
                    } else {
                        // Dev mode: local-only
                        let group = SavedGroup(
                            id: UUID(),
                            name: groupName.trimmingCharacters(in: .whitespaces),
                            members: allMembers,
                            lastPlayed: nil,
                            creatorId: authService.currentPlayerId,
                            lastCourse: selectedCourse,
                            potSize: buyIn * Double(allMembers.count),
                            buyInPerPlayer: buyIn,
                            scheduledDate: scheduledDate,
                            recurrence: recurrence
                        )
                        onCreate(group)
                        if let date = scheduledDate {
                            NotificationService.shared.scheduleTeeTimeReminder(groupId: group.id, groupName: group.name, teeTime: date)
                        }
                        ToastManager.shared.success("Skins game created!")
                    }
                } label: {
                    Text("Continue")
                        .font(.carry.headlineBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isFormValid ? Color.textPrimary : Color.borderSubtle)
                        )
                }
                .disabled(!isFormValid)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 30)
                .id("createButton")

                } // end inner VStack
            } // end ScrollView
            .onChange(of: focusedField) { _, field in
                guard let field else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    scrollProxy.scrollTo(field, anchor: .center)
                }
            }
            } // end ScrollViewReader
        }
        .background(Color.white)
        .onAppear {
            scheduledDate = nil
            // Seed creator as first member
            if selectedMembers.isEmpty, let creator = creatorPlayer {
                selectedMembers = [creator]
            }
            // Auto-focus name field so keyboard pre-loads during sheet animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                focusedField = .groupName
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { focusedField = nil }
        .onChange(of: showDatePicker) {
            if showDatePicker { focusedField = nil }
        }
        .onChange(of: showCourseSelector) {
            if showCourseSelector { focusedField = nil }
        }
        .onChange(of: repeatMode) { focusedField = nil }
        .sheet(isPresented: $showCourseSelector) {
            CourseSelectionView { course in
                selectedCourse = course
                showCourseSelector = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.white)
        }
        .sheet(isPresented: $showDatePicker) {
            teeTimeSheetContent
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
    }


    @ViewBuilder
    private var teeTimeSheetContent: some View {
        let dateBinding = Binding<Date>(
            get: { scheduledDate ?? Date() },
            set: { scheduledDate = $0 }
        )
        let repeatBinding = Binding<Int>(
            get: { max(repeatMode - 1, 0) },
            set: { repeatMode = $0 + 1 }
        )
        TeeTimePickerSheet(
            scheduleMode: $scheduleMode,
            selectedDate: dateBinding,
            repeatMode: repeatBinding,
            selectedDayPill: $selectedDayPill,
            onSet: {
                if scheduledDate == nil { scheduledDate = Date() }
                showDatePicker = false
            },
            onCancel: { showDatePicker = false }
        )
    }

    private static let teeTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · h:mm a"
        return f
    }()

    /// Default tee time: tomorrow at 8:00 AM
    private static func defaultTeeTime() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    // Form validity is tracked via isFormValid @State + onChange handlers

    /// Filter handicap/index input: digits + one decimal, max 1 decimal place, capped at 54.0
    /// Allows 0…54.0 or +0.1…+10.0 (plus handicap) with one decimal place.
    // Uses shared filterHandicapInput() from Player.swift

    // MARK: - Member Search Bar

    private var memberSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.carry.body)
                .foregroundColor(Color.textDisabled)

            TextField("Search by name...", text: $memberSearchText)
                .font(.carry.body)
                .focused($focusedField, equals: .memberSearch)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: memberSearchText) {
                    debounceMemberSearch(memberSearchText)
                }

            if !memberSearchText.isEmpty {
                Button {
                    memberSearchText = ""
                    memberSearchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.carry.bodyLG)
                        .foregroundColor(Color.textDisabled)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(focusedField == .memberSearch ? Color(hexString: "#333333") : Color.borderLight, lineWidth: focusedField == .memberSearch ? 1.5 : 1)
            .animation(.easeOut(duration: 0.15), value: focusedField)
        )
    }

    // MARK: - Search Results

    private var memberSearchResultsList: some View {
        VStack(spacing: 8) {
            if isMemberSearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Searching...")
                        .font(.carry.captionLG)
                        .foregroundColor(Color.textDisabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // Carry user results
                ForEach(memberSearchResults, id: \.id) { profile in
                    memberSearchResultRow(profile)
                }

                // Inline phone invite — shows when 2+ chars typed
                if memberSearchText.count >= 2 && !isMemberSearching {
                    inlinePhoneInvite
                }
            }
        }
    }

    private var inlinePhoneInvite: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send Invite to \"\(memberSearchText)\"")
                .font(.carry.bodySMSemibold)
                .foregroundColor(Color.textTertiary)

            HStack(spacing: 10) {
                Image(systemName: "iphone")
                    .font(.system(size: 14))
                    .foregroundColor(Color.textDisabled)

                TextField("Enter Phone Number", text: $phoneText)
                    .font(.carry.bodyLG)
                    .foregroundColor(Color.textPrimary)
                    .keyboardType(.phonePad)
                    .focused($focusedField, equals: .inlinePhone)
                    .onChange(of: phoneText) { _, newValue in
                        let digits = newValue.filter { $0.isNumber }
                        if digits.count > 10 {
                            phoneText = String(digits.prefix(10))
                        }
                    }

                let digits = phoneText.filter { $0.isNumber }
                Button {
                    sendInlineInvite()
                } label: {
                    Text("Send")
                        .font(.carry.bodySMSemibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(Capsule().fill(digits.count >= 10 ? Color.textPrimary : Color.borderSubtle))
                }
                .buttonStyle(.plain)
                .disabled(digits.count < 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.borderLight, lineWidth: 1))
    }

    private func sendInlineInvite() {
        let digits = phoneText.filter { $0.isNumber }
        guard digits.count >= 10 else { return }
        let name = memberSearchText.trimmingCharacters(in: .whitespaces)

        let guestColors = ["#E67E22", "#9B59B6", "#1ABC9C", "#C0392B", "#2980B9", "#27AE60"]
        let colorIdx = (nextGuestID - 100) % guestColors.count
        let guest = Player(
            id: nextGuestID,
            name: name.isEmpty ? ScorerAssignmentView.formatPhone(digits) : name,
            initials: "✉️",
            color: guestColors[colorIdx],
            handicap: 0,
            avatar: "✉️",
            group: 1,
            ghinNumber: nil,
            venmoUsername: nil,
            phoneNumber: digits,
            isPendingInvite: true
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            guests.append(guest)
        }
        nextGuestID += 1

        // Open native SMS
        let body = "Join my skins game on Carry! Download here: https://carryapp.site"
        let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "sms:\(digits)&body=\(encoded)") {
            UIApplication.shared.open(url)
        }

        // Reset
        memberSearchText = ""
        memberSearchResults = []
        phoneText = ""
        focusedField = nil
    }

    private func memberSearchResultRow(_ profile: ProfileDTO) -> some View {
        let isAlreadyAdded = selectedMembers.contains { $0.profileId == profile.id }

        return Button {
            guard !isAlreadyAdded else { return }
            var player = Player(from: profile)
            player.isPendingAccept = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedMembers.append(player)
            }
            memberSearchText = ""
            memberSearchResults = []
        } label: {
            HStack(spacing: 10) {
                PlayerAvatar(player: Player(from: profile), size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(profile.firstName) \(profile.lastName)".trimmingCharacters(in: .whitespaces))
                        .font(.carry.bodySemibold)
                        .foregroundColor(Color.textPrimary)

                    let subtitle = [profile.homeClub, profile.handicap != 0 ? String(format: "%.1f", profile.handicap) : nil]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.carry.bodySM)
                            .foregroundColor(Color(hexString: "#BFC0C2"))
                    }
                }

                Spacer()

                if isAlreadyAdded {
                    Text("Added")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.textDisabled)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 14).fill(isAlreadyAdded ? Color.bgSecondary : .white))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.borderLight, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isAlreadyAdded)
    }

    // MARK: - Selected Member Chip

    private func selectedMemberChip(_ player: Player, isGuest: Bool) -> some View {
        // Dimensions bumped 15% from the original baseline so the member
        // pills read a bit larger in the Create Skins Group sheet without
        // affecting any other avatar stack in the app. Keep ratios intact:
        // avatar 24→28, inner text +~15%, paddings and xmark +~15%.
        let isCreator = player.id == creatorPlayer?.id && !isGuest
        return HStack(spacing: 7) {
            if player.isPendingInvite {
                ZStack {
                    Circle()
                        .fill(Color.pendingBg)
                    Circle()
                        .strokeBorder(Color.pendingBorder, lineWidth: 1)
                    Image(systemName: "iphone")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.pendingFill)
                }
                .frame(width: 28, height: 28)
            } else {
                PlayerAvatar(player: player, size: 28)
            }

            Text(player.isPendingInvite ? ScorerAssignmentView.formatPhone(player.phoneNumber ?? "Invited") : player.shortName)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.textPrimary)
                .lineLimit(1)

            if isCreator {
                Text("You")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.textDark)
            } else {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if isGuest {
                            guests.removeAll { $0.id == player.id }
                        } else {
                            selectedMembers.removeAll { $0.id == player.id }
                        }
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.textTertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.bgSecondary))
        .overlay(Capsule().strokeBorder(Color.borderSubtle, lineWidth: 0.5))
    }

    // Invite Player Button removed — inline phone invite integrated into search results

    // MARK: - Debounced Search

    private func debounceMemberSearch(_ query: String) {
        memberSearchTask?.cancel()
        guard query.count >= 2 else {
            memberSearchResults = []
            isMemberSearching = false
            return
        }

        isMemberSearching = true

        memberSearchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)  // 400ms debounce
            guard !Task.isCancelled else { return }

            let offlineResults = PlayerSearchService.shared.searchPlayersOffline(query: query)
            do {
                let results = try await withThrowingTaskGroup(of: [ProfileDTO].self) { group in
                    group.addTask {
                        try await PlayerSearchService.shared.searchPlayers(query: query)
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 3_000_000_000)
                        throw CancellationError()
                    }
                    let first = try await group.next() ?? []
                    group.cancelAll()
                    return first
                }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    memberSearchResults = results.isEmpty ? offlineResults : results
                    isMemberSearching = false
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    memberSearchResults = offlineResults
                    isMemberSearching = false
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("1 - Empty (first run)") {
    GroupsListView(groups: .constant([]), pendingActiveGroupId: .constant(nil))
        .environmentObject(AuthService())
        .environmentObject(StoreService())
}

#Preview("2 - Populated") {
    GroupsListView(groups: .constant(SavedGroup.demo), pendingActiveGroupId: .constant(nil))
        .environmentObject(AuthService())
        .environmentObject(StoreService())
}
#endif
