import SwiftUI

/// Identifiable wrapper for item-based sheets (avoids stale state with .sheet(isPresented:))
private struct SheetItem: Identifiable {
    let id: Int
}

private extension View {
    /// Apply a modifier only when the condition is true. Used here to gate
    /// drag/drop on `isCreator` so non-creators don't get drag affordances.
    @ViewBuilder
    func applyIf<T: View>(_ condition: Bool, _ transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}

struct GroupManagerView: View {
    @EnvironmentObject var storeService: StoreService
    @State private var allMembers: [Player]
    var onCourseChanged: ((SelectedCourse) -> Void)?
    var onTeeTimeChanged: ((Date?) -> Void)?
    @State private var currentCourse: SelectedCourse?
    @State private var showCourseChange = false
    @State private var selectedIDs: Set<Int>
    @State private var groups: [[Player]]
    @State private var startingSides: [String]  // "front" or "back" per group
    @State private var dragPlayer: Player?
    @State private var dragSourceGroup: Int?
    @State private var dropTargetGroup: Int?
    @State private var dropTargetIndex: Int?  // target row index for within-group reorder
    @State private var orderSyncTask: Task<Void, Never>?
    @State private var teeTimesSyncTask: Task<Void, Never>?
    @State private var showAddSheet = false
    @State private var showGuestEntry = false
    @State private var showInviteEntry = false
    @State private var guestName = ""
    @State private var guestHandicap = ""
    @State private var invitePhone = ""
    @State private var inviteSent = false
    @State private var guests: [Player] = []
    @State private var nextGuestID = 100  // IDs above real players
    @State private var showTeeTimes = true  // off by default, toggled in settings
    @State private var teeTimes: [Date?] = []  // one per group, nil = not set
    @State private var showSettings = false
    @State private var showLeaderboard = false
    @State private var showPaywall = false
    @State private var paywallTrigger: PaywallTrigger = .general
    @State private var showQRInvite = false
    /// Fullscreen QR shown when the user shakes their phone inside a group
    /// detail. Big, tap-to-dismiss surface so multiple people can scan at
    /// once without passing the phone around. Debug builds skip this path
    /// to avoid fighting the shake-opens-Debug-Menu shortcut.
    @State private var showFullScreenQR = false
    @State private var leaderboardTab: Int = 0  // 0 = Round, 1 = All Time
    @State private var groupName = "The Friday Skins"  // editable group/event name
    @State private var showSwapPicker = false
    @State private var pendingSwapPlayer: Player?   // player being moved
    @State private var pendingSwapFrom: Int?         // source group index
    @State private var pendingSwapTo: Int?           // destination group index (full)
    @State private var scorerIDs: [Int]              // one scorer player ID per group
    @State private var showTeeTimePicker = false
    @State private var teeTimePickerGroupIndex: Int = 0
    @State private var teeTimePickerDate: Date = Date()
    @State private var scorerPickerItem: SheetItem? = nil  // nil = hidden; .id = group index
    @State private var showNameEditor = false
    @State private var editingName = ""
    @State private var teeTimesLinked = false  // true when times are set at consecutive intervals
    @State private var selectedTees: [String]  // tee color per group (e.g. "Combos", "Blues")
    @State private var carriesEnabled: Bool  // carries toggle (off by default for multi-group)
    @State private var scoringMode: ScoringMode = .everyone  // .single or .everyone (on by default)
    @State private var winningsDisplay: String = "gross"  // "gross" or "net" — how winnings show in UI
    @State private var handicapPercentage: Double = 1.0  // 1.0 = 100%, 0.7 = 70%
    @State private var buyInText: String = ""  // per-player buy-in amount
    @State private var showManageMembers = false
    @State private var showPlayerGroups = false
    @State private var showTipBanner = true  // green tip banner, dismissible
    @State private var roundDate: Date = Date()  // mandatory round date (defaults to today)
    @State private var showDatePicker = false  // date picker sheet
    @State private var showLeaveDeleteAlert = false
    @State private var showCloseQuickGameAlert = false
    /// Quick-Game swipe is destructive (hard-deletes the player from the
    /// game; the scorer often has no valid replacement among guests). We
    /// capture the pending (player, groupIndex) here and confirm before
    /// calling removePlayer. Regular groups skip this — swipe for them is
    /// a non-destructive deselect from today's tee sheet only.
    @State private var pendingQuickGameRemoval: (player: Player, groupIndex: Int)? = nil
    /// Wall-clock of the most recent `saveScorerIds()` call. Refresh skips
    /// overwriting local scorerIDs with server state for a short window
    /// after a save, protecting against the 30s poll stomping the creator's
    /// just-made assignment before the server's own write has propagated
    /// back (classic write-then-read race).
    @State private var scorerIdsLastSavedAt: Date? = nil
    @State private var countdownText = ""  // updated every second by timer
    @State private var refreshTimer: Timer? = nil  // 30s auto-refresh polling
    @State private var isJoiningRound = false  // loading state for "Join Round" button

    // Recurrence state for date picker
    @State private var scheduleMode: Int = 0       // 0 = Single Game, 1 = Recurring
    @State private var repeatMode: Int = 0         // 0=Never, 1=Weekly, 2=Biweekly, 3=Monthly
    @State private var selectedDayPill: Int? = nil  // 0=Mon…6=Sun (pill index)
    var onRecurrenceChanged: ((GameRecurrence?) -> Void)?

    private let teeTimeInterval: TimeInterval = 8 * 60  // 8 minutes between groups

    var onBack: (() -> Void)?
    let onConfirm: (RoundConfig) -> Void
    var onLeaveGroup: (() -> Void)?
    var onDeleteGroup: (() -> Void)?
    let currentUserId: Int
    let creatorId: Int
    let isLiveRound: Bool
    @State private var roundStarted: Bool
    let roundHistory: [HomeRound]
    var supabaseGroupId: UUID? = nil
    var scheduledLabel: String? = nil
    var isQuickGame: Bool = false
    var showInviteCrewOnAppear: Bool = false
    var onGroupRefreshed: ((SavedGroup) -> Void)?

    @State private var showShareCardSheet: Bool = false
    @State private var showInviteShareSheet: Bool = false
    @State private var inviteShareLink: String = ""
    @State private var cachedHoles: [Hole]? = nil  // preserves API holes across Supabase refreshes
    @State private var invitePhones: [Int: String] = [:]  // playerId → phone number
    @State private var recentlyRemovedIds: Set<Int> = []  // players manually deleted; refresh skips re-merging them

    /// Only the group creator can manage settings, players and tee times.
    private var isCreator: Bool { currentUserId == creatorId }

    init(allMembers: [Player], selectedCourse: SelectedCourse? = nil, onCourseChanged: ((SelectedCourse) -> Void)? = nil, onTeeTimeChanged: ((Date?) -> Void)? = nil, onRecurrenceChanged: ((GameRecurrence?) -> Void)? = nil, initialTeeTime: Date? = nil, initialTeeTimes: [Date?]? = nil, initialBuyIn: Double = 0, initialDate: Date? = nil, initialRecurrence: GameRecurrence? = nil, initialCarriesEnabled: Bool = false, preselected: Set<Int>? = nil, groupName: String = "The Friday Skins", currentUserId: Int = 1, creatorId: Int = 1, isLiveRound: Bool = false, roundStarted: Bool = false, roundHistory: [HomeRound] = [], onLeaveGroup: (() -> Void)? = nil, onDeleteGroup: (() -> Void)? = nil, scheduledLabel: String? = nil, onBack: (() -> Void)? = nil, supabaseGroupId: UUID? = nil, isQuickGame: Bool = false, showInviteCrewOnAppear: Bool = false, onGroupRefreshed: ((SavedGroup) -> Void)? = nil, onConfirm: @escaping (RoundConfig) -> Void) {
        self._allMembers = State(initialValue: allMembers)
        self._currentCourse = State(initialValue: selectedCourse)
        // Cache API holes so they survive Supabase refreshes that lose hole data
        if let holes = selectedCourse?.teeBox?.holes, !holes.isEmpty {
            self._cachedHoles = State(initialValue: holes)
        }
        #if DEBUG
        print("[GroupManagerView.init] course=\(selectedCourse?.courseName ?? "nil") teeBox=\(selectedCourse?.teeBox?.name ?? "nil") holes=\(selectedCourse?.teeBox?.holes?.count ?? 0)")
        #endif
        self.onCourseChanged = onCourseChanged
        self.onTeeTimeChanged = onTeeTimeChanged
        self.onRecurrenceChanged = onRecurrenceChanged
        self.onBack = onBack
        self.onConfirm = onConfirm
        self.onLeaveGroup = onLeaveGroup
        self.onDeleteGroup = onDeleteGroup
        self.currentUserId = currentUserId
        self.creatorId = creatorId
        self.isLiveRound = isLiveRound
        self._roundStarted = State(initialValue: roundStarted)
        self.roundHistory = roundHistory
        self.supabaseGroupId = supabaseGroupId
        self.isQuickGame = isQuickGame
        self.showInviteCrewOnAppear = showInviteCrewOnAppear
        self.scheduledLabel = scheduledLabel
        self.onGroupRefreshed = onGroupRefreshed
        self._groupName = State(initialValue: groupName)
        // Exclude pending invites from the default Playing roster — they don't
        // belong on the tee sheet until they accept. Creator adds them
        // deliberately via Manage Members → All Members after they join.
        //
        // Persisted deselections survive nav away + back: swipe-off-today writes
        // the deselected id into UserDefaults keyed by group UUID, so reopening
        // the group detail page keeps the swiped player off the tee sheet until
        // the user deliberately adds them back via Manage Members.
        let defaultSel = Set(
            allMembers
                .filter { !$0.isPendingInvite && !$0.isPendingAccept }
                .map(\.id)
        )
        let deselected: Set<Int> = {
            guard let gid = supabaseGroupId else { return [] }
            let key = "deselectedIDs_\(gid.uuidString)"
            let arr = UserDefaults.standard.array(forKey: key) as? [Int] ?? []
            return Set(arr)
        }()
        let sel = preselected ?? defaultSel.subtracting(deselected)
        _selectedIDs = State(initialValue: sel)
        let playing = allMembers.filter { sel.contains($0.id) }
        let grouped = Self.autoGroup(playing)
        let safeGrouped: [[Player]]
        if grouped.isEmpty || grouped.allSatisfy({ $0.isEmpty }) {
            safeGrouped = allMembers.isEmpty ? [[]] : [allMembers]
        } else {
            safeGrouped = grouped
        }
        let groupCount = max(safeGrouped.count, 1)
        _groups = State(initialValue: safeGrouped)
        _startingSides = State(initialValue: Self.defaultSides(count: groupCount))
        var computedTeeTimes: [Date?]
        if let savedTeeTimes = initialTeeTimes, !savedTeeTimes.isEmpty {
            // Use per-group tee times (from Quick Game with consecutive intervals)
            computedTeeTimes = savedTeeTimes
            while computedTeeTimes.count < groupCount { computedTeeTimes.append(nil) }
        } else {
            computedTeeTimes = Array<Date?>(repeating: nil, count: groupCount)
            if let teeTime = initialTeeTime, groupCount > 0 {
                computedTeeTimes[0] = teeTime
            }
        }
        _teeTimes = State(initialValue: computedTeeTimes)
        _scorerIDs = State(initialValue: safeGrouped.map { $0.first?.id ?? 0 })
        _selectedTees = State(initialValue: Array(repeating: "Combos", count: groupCount))
        _buyInText = State(initialValue: initialBuyIn > 0 ? "\(Int(initialBuyIn))" : "")
        _carriesEnabled = State(initialValue: initialCarriesEnabled)
        // Round date: use initialDate, or extract date from tee time, or default to today
        _roundDate = State(initialValue: initialDate ?? initialTeeTime ?? Date())

        // Pre-fill recurrence state from group data
        if let recurrence = initialRecurrence {
            switch recurrence {
            case .weekly(let day):
                _scheduleMode = State(initialValue: 1)
                _repeatMode = State(initialValue: 1)
                _selectedDayPill = State(initialValue: GameRecurrence.pillIndex(fromWeekday: day))
            case .biweekly(let day):
                _scheduleMode = State(initialValue: 1)
                _repeatMode = State(initialValue: 2)
                _selectedDayPill = State(initialValue: GameRecurrence.pillIndex(fromWeekday: day))
            case .monthly:
                _scheduleMode = State(initialValue: 1)
                _repeatMode = State(initialValue: 3)
                _selectedDayPill = State(initialValue: nil)
            }
        }
    }

    // MARK: - Auto-grouping

    /// Splits players into balanced groups of 3-4 (foursomes preferred).
    /// 5→3+2, 6→3+3, 7→4+3, 8→4+4, 9→3+3+3, 10→4+3+3, 11→4+4+3, 12→4+4+4, etc.
    static func autoGroup(_ players: [Player]) -> [[Player]] {
        let n = players.count
        guard n > 0 else { return [] }

        // If players have explicit group assignments (e.g. from Quick Game), respect them
        let maxAssigned = players.map(\.group).max() ?? 1
        if maxAssigned > 1 {
            var result: [[Player]] = Array(repeating: [], count: maxAssigned)
            for player in players {
                let idx = max(0, min(player.group - 1, maxAssigned - 1))
                result[idx].append(player)
            }
            // Strip ALL empty groups, not just trailing. A middle empty group
            // (e.g. creator removed everyone in Group 2 via Manage Members
            // while Group 3 still has players) would otherwise leave a
            // phantom slot in the tee sheet. Player.group metadata may be
            // stale after compacting, but it's re-derived on the next save
            // via `syncGroupNumsToSupabase`.
            result.removeAll { $0.isEmpty }
            return result.isEmpty ? [players] : result
        }

        // Fallback: auto-split by count (no explicit assignments)
        if n <= 4 { return [players] }

        let numGroups = (n + 3) / 4  // ceil(n/4)
        let baseSize = n / numGroups
        let remainder = n % numGroups

        var result: [[Player]] = []
        var idx = 0
        for g in 0..<numGroups {
            let size = baseSize + (g < remainder ? 1 : 0)
            result.append(Array(players[idx..<idx+size]))
            idx += size
        }
        return result
    }

    static func defaultSides(count: Int) -> [String] {
        // All groups start on front 9 (hole 1)
        Array(repeating: "front", count: count)
    }

    private var allAvailable: [Player] {
        // Dedup by Player.id — `allMembers` and `guests` can each carry a
        // copy of the same guest after a save round-trip (PlayerGroupsSheet
        // inserts to server + appends locally; the next refresh pulls the
        // same guest back in `allMembers`). Without this filter, the
        // downstream `Dictionary(uniqueKeysWithValues:)` at
        // `leaderboardPlayers` crashes with `Duplicate values for key: N`
        // and SwiftUI's ForEach trips its own duplicate-id check. First
        // occurrence wins so the `allMembers` record (freshest server data)
        // is preferred over any locally-appended copy.
        var seen = Set<Int>()
        return (allMembers + guests).filter { seen.insert($0.id).inserted }
    }

    // MARK: - Player Groups Sheet (extracted to PlayerGroupsSheet.swift)

    // All pg* functions, bindings, and state moved to PlayerGroupsSheet struct.
    // Sheet is presented via .sheet(isPresented:) with onSave/onCancel callbacks.


    /// Extracted to reduce body complexity for Swift type checker.
    @ViewBuilder
    private var manageMembersSheet: some View {
        ManageMembersSheet(
            allAvailable: allAvailable,
            selectedIDs: selectedIDs,
            nextGuestID: nextGuestID,
            supabaseGroupId: supabaseGroupId,
            onCancel: { showManageMembers = false },
            onDone: { result in
                // Drop any players the sheet long-press-removed from local
                // state before adopting the new selection. The sheet
                // already persisted the server DELETE — this just keeps
                // the UI in sync until the next 30s refreshGroupData pass.
                if !result.removedPlayerIds.isEmpty {
                    guests.removeAll { result.removedPlayerIds.contains($0.id) }
                    allMembers.removeAll { result.removedPlayerIds.contains($0.id) }
                }
                selectedIDs = result.selectedIDs.subtracting(result.removedPlayerIds)
                guests.append(contentsOf: result.newGuests)
                nextGuestID = result.nextGuestID
                regroup()
                showManageMembers = false

                // Sync new members to Supabase as invites
                if let groupId = supabaseGroupId {
                    let newMembers = result.newGuests.filter { $0.profileId != nil }
                    if !newMembers.isEmpty {
                        Task {
                            let groupService = GroupService()
                            for member in newMembers {
                                guard let profileId = member.profileId else { continue }
                                do {
                                    try await groupService.inviteMember(groupId: groupId, playerId: profileId)
                                    #if DEBUG
                                    print("[GroupManager] Invited \(member.name) to group")
                                    #endif
                                } catch {
                                    #if DEBUG
                                    print("[GroupManager] Failed to invite \(member.name): \(error)")
                                    #endif
                                }
                            }
                            await MainActor.run {
                                ToastManager.shared.success("Invite\(newMembers.count == 1 ? "" : "s") sent!")
                            }
                        }
                    }
                }
            }
        )
    }

    private func regroup() {
        let playing = allAvailable.filter {
            selectedIDs.contains($0.id)
        }
        groups = Self.autoGroup(playing)
        startingSides = Self.defaultSides(count: groups.count)
        syncTeeTimes()
        syncScorerIDs()
        syncSelectedTees()
    }

    /// Persist which member IDs are currently deselected for today's tee sheet.
    /// Keyed by group UUID so the swipe-off-today survives nav + relaunch.
    /// Called from `.onChange(of: selectedIDs)` so every mutation path (swipe,
    /// Manage Members tap, refresh intersection, hard-remove) stays in sync
    /// without needing to sprinkle persist calls at each site.
    private func persistDeselectedForToday() {
        guard let gid = supabaseGroupId else { return }
        let key = "deselectedIDs_\(gid.uuidString)"
        let allIds = Set(allMembers.map(\.id))
        let deselected = Array(allIds.subtracting(selectedIDs))
        UserDefaults.standard.set(deselected, forKey: key)
    }

    private func syncTeeTimes() {
        while teeTimes.count < groups.count {
            teeTimes.append(nil)
        }
        while teeTimes.count > groups.count {
            teeTimes.removeLast()
        }
    }

    /// Returns (groupNum, scorerName) for any group whose assigned scorer
    /// hasn't accepted yet. Used to gate Start Round and tell the creator
    /// they need to wait (or reassign). Previously skipped Group 1 under
    /// the "creator is always Group 1 scorer" invariant — but in both Quick
    /// Games and Skins Groups, the creator's tee-time slot can land them in
    /// Group 2+, meaning a different (possibly pending) user scores Group 1.
    /// Parallel logic for both flows: check every group.
    private var pendingScorerWarnings: [(group: Int, name: String)] {
        var result: [(group: Int, name: String)] = []
        for i in 0..<min(scorerIDs.count, groups.count) {
            let scorerId = scorerIDs[i]
            guard let scorer = groups[i].first(where: { $0.id == scorerId }) else { continue }
            if scorer.isPendingInvite || scorer.isPendingAccept {
                result.append((group: i + 1, name: scorer.shortName))
            }
        }
        return result
    }

    /// Ensure each group has a valid scorer; default to first confirmed (non-pending) player
    private func syncScorerIDs() {
        while scorerIDs.count < groups.count {
            // For a brand-new group being appended, default to the first
            // Carry user (skip guests and phone invites — they can't score).
            // If none exists, leave 0 so the missing-scorer banner surfaces
            // and prompts manual assignment.
            let defaultScorer = groups[scorerIDs.count].first(where: \.canScore)
            scorerIDs.append(defaultScorer?.id ?? 0)
        }
        while scorerIDs.count > groups.count {
            scorerIDs.removeLast()
        }
        // Validate existing scorer assignments:
        //  - scorerIDs[i] == 0              → intentionally empty (banner); don't auto-fill
        //  - scorer no longer in the group  → clear (banner); don't auto-reassign
        //  - scorer is a PERMANENT guest    → clear (banner); guests can't score
        //      (permanent = isGuest && NOT pending invite — they'll never upgrade)
        //  - Skins Group pending scorer     → advance past to next confirmed Carry user
        //                                     (existing behavior, Quick Games allow pending)
        for i in 0..<groups.count {
            if scorerIDs[i] == 0 { continue }                  // respect empty — banner will prompt

            let groupPlayerIDs = Set(groups[i].map(\.id))
            let currentScorer = groups[i].first(where: { $0.id == scorerIDs[i] })
            let isPendingScorer = currentScorer?.isPendingInvite == true
                || currentScorer?.isPendingAccept == true
            // A guest who is ALSO pending-invited will become a valid scorer
            // when they claim their invite (Carry profile replaces/links to
            // the guest profile). Only treat as a "real" non-scoring guest
            // when there's no pending invite to rescue them.
            let isPermanentGuest = (currentScorer?.isGuest == true || currentScorer?.profileId == nil)
                && !isPendingScorer

            if !groupPlayerIDs.contains(scorerIDs[i]) {
                // Scorer was removed (e.g. swipe-delete) → leave empty so
                // the creator gets prompted via the missing-scorer banner.
                #if DEBUG
                print("[syncScorerIDs] ⚠️ Wiping Group \(i+1) scorer id=\(scorerIDs[i]) — NOT IN groups[\(i)] (groupIds=\(groupPlayerIDs))")
                #endif
                scorerIDs[i] = 0
            } else if isPermanentGuest {
                // Can't score → clear, banner prompts manual pick.
                #if DEBUG
                print("[syncScorerIDs] ⚠️ Wiping Group \(i+1) scorer \(currentScorer?.name ?? "?") — PERMANENT GUEST (isGuest=\(currentScorer?.isGuest == true), profileId=\(currentScorer?.profileId?.uuidString ?? "nil"), pendingInvite=\(currentScorer?.isPendingInvite == true), pendingAccept=\(currentScorer?.isPendingAccept == true))")
                #endif
                scorerIDs[i] = 0
            } else if !isQuickGame && isPendingScorer {
                // Skins Group: advance past pending scorer to next confirmed
                // Carry user (matches prior behavior).
                let nextConfirmed = groups[i].first(where: \.canScore)
                #if DEBUG
                print("[syncScorerIDs] Advancing Group \(i+1) scorer past pending \(currentScorer?.name ?? "?") → \(nextConfirmed?.name ?? "0")")
                #endif
                scorerIDs[i] = nextConfirmed?.id ?? 0
            }
        }
        // Creator-locked-as-scorer invariant: wherever the creator sits in
        // the tee sheet, that group's scorer MUST be the creator. Applied
        // after the per-group validation above so it overrides any earlier
        // wipe/advance that would have cleared the slot. The creator can't
        // be a guest (always a Carry user), so `canScore` is implicit.
        //
        // Using `creatorId` (not `currentUserId`) makes this work on both
        // the creator's device AND any member's device — both derive the
        // same `creatorId` from the group's `created_by` UUID. Previously
        // the check was against `currentUserId`, which silently skipped on
        // member devices and also failed on the creator's side whenever
        // `currentUserId` defaulted to the init's `1` sentinel.
        for i in 0..<groups.count where groups[i].contains(where: { $0.id == creatorId }) {
            scorerIDs[i] = creatorId
        }
    }

    /// Ensure each group has a selected tee; default to "Combos"
    private func syncSelectedTees() {
        while selectedTees.count < groups.count {
            selectedTees.append("Combos")
        }
        while selectedTees.count > groups.count {
            selectedTees.removeLast()
        }
    }

    /// When the first group's tee time is set, auto-fill subsequent groups at 8-min intervals
    /// Fills ALL other tee-time slots (both before and after `index`) relative
    /// to the base time at `index`, using `teeTimeInterval`. Quick Games can
    /// place the creator in Group 2+, so a unidirectional fill-from-zero would
    /// leave Group 1's slot nil when the creator edits from their own (later)
    /// group slot.
    private func autoFillTeeTimes(from index: Int) {
        guard teeTimes.indices.contains(index), let baseTime = teeTimes[index] else { return }
        for i in 0..<teeTimes.count {
            if i == index { continue }
            let offset = Double(i - index) * teeTimeInterval
            teeTimes[i] = baseTime.addingTimeInterval(offset)
        }
    }

    /// 0-indexed tee-time slot for the current user. For creators this is the
    /// slot that Game Options / the inline date picker should write into (not
    /// hardcoded to 0), so Quick Game creators who land in Group 2+ don't
    /// overwrite a teammate's slot.
    private var currentUserSlotIndex: Int {
        let groupNum = allMembers.first(where: { $0.id == currentUserId })?.group ?? 1
        let raw = max(1, groupNum) - 1
        return max(0, min(teeTimes.count - 1, raw))
    }

    private static let teeTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let memberDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private static let headerDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, h:mm a"
        return f
    }()

    private static let headerDateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private static let teeTimeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private var selectedCount: Int { selectedIDs.count }

    /// Start Round requires: 2+ active (non-pending) members AND a course selected
    private var activePlayerCount: Int {
        allAvailable.filter {
            selectedIDs.contains($0.id) && !$0.isPendingInvite && !$0.isPendingAccept
        }.count
    }

    private var allTeeTimesSet: Bool {
        guard showTeeTimes, !groups.isEmpty else { return true }
        return groups.indices.allSatisfy { i in
            i < teeTimes.count && teeTimes[i] != nil
        }
    }

    private var needsTeeTimesSet: Bool {
        showTeeTimes && activePlayerCount >= 2 && currentCourse != nil && !allTeeTimesSet
    }

    private var isWithinTeeTimeWindow: Bool {
        if isQuickGame { return true }  // Quick games can start immediately
        guard let firstTee = teeTimes.first, let teeTime = firstTee else { return true }
        return Date() >= teeTime.addingTimeInterval(-30 * 60)  // 30 min before tee time
    }

    /// 1-indexed group numbers that have fewer than 2 players total (active +
    /// pending). A group with only one real player — even if that player is
    /// a confirmed scorer — can't play skins. Pending players still count
    /// toward the size check because they're expected to show up; the
    /// separate `pendingScorerWarnings` handles "scorer hasn't accepted yet".
    /// Surfaces in Start Round as "Add players to Group X".
    private var shortPlayerGroups: [Int] {
        groups.enumerated().compactMap { (idx, group) in
            return group.count < 2 ? (idx + 1) : nil
        }
    }

    private var canStartRound: Bool {
        // If any Group 2+ scorer hasn't accepted their invite, block start.
        // The assigned scorer is the only one who can score that group — if
        // they never join, the group can't be scored. Forcing the creator
        // to wait (or reassign) avoids starting a round that silently breaks.
        if !pendingScorerWarnings.isEmpty { return false }

        // Every group must have at least 2 active players. Single-player
        // groups (scorer alone) can't play skins — previously only Group 1
        // was validated for Quick Games and total player count for regular
        // groups, which let Group 2+ slip through with just the scorer.
        if !shortPlayerGroups.isEmpty { return false }

        if isQuickGame {
            // Quick Games need ≥2 active (non-pending) players just like Skins
            // Groups. Previously this branch only checked `currentCourse != nil`,
            // so a game with one active player and a pending invitee passed
            // `shortPlayerGroups` (counts pending) and fell through — label
            // said "Need 2+ Players" but the button was still enabled and
            // started an unscorable round when tapped.
            return activePlayerCount >= 2 && currentCourse != nil
        }
        return activePlayerCount >= 2 && currentCourse != nil && allTeeTimesSet && isWithinTeeTimeWindow
    }

    private var buttonEnabled: Bool {
        canStartRound || needsNextSchedule
    }

    /// Kept as an alias of `buttonEnabled` so the styling helper stays
    /// decoupled from any future where "tappable but looks disabled" returns.
    /// Today: no difference — missing-scorer state is fully disabled, creator
    /// taps the "Scorer" pill in the group card to fix.
    private var buttonLooksActive: Bool { buttonEnabled || isLiveRound }

    /// Quick Games require a Carry-user scorer per group. When one is missing
    /// we surface the status in the main button so the creator's thumb lands
    /// exactly where they'll try to tap. Returns the lowest zero-based group
    /// index that's missing a scorer, or nil. Skins Groups (everyone-scores)
    /// have no designated scorer to miss, so always nil there.
    private var missingScorerGroupIndex: Int? {
        guard isQuickGame, isCreator, !isLiveRound, !roundStarted else { return nil }
        for (i, _) in groups.enumerated() where !groupHasValidScorer(index: i) {
            return i
        }
        return nil
    }

    /// True when creator needs to schedule next round (non-recurring group with
    /// completed rounds and no future tee time in ANY group slot). Using "any
    /// future slot" instead of `teeTimes.first` avoids false positives when the
    /// creator is in Group 2+ (Quick Games can place them in any slot) or when
    /// Group 1's slot is a stale past time but the creator's slot is set.
    private var needsNextSchedule: Bool {
        if !isCreator { return false }
        if isLiveRound { return false }
        if roundHistory.isEmpty { return false }
        if buildRecurrence() != nil { return false }
        let now = Date()
        let hasFutureTee = teeTimes.contains { ($0.map { $0 > now }) ?? false }
        return !hasFutureTee
    }

    private var startButtonLabel: String {
        if isLiveRound { return "Back to Scorecard" }
        if let missing = missingScorerGroupIndex { return "Group \(missing + 1) needs scorer" }
        if needsNextSchedule { return "Schedule Next Round" }
        if activePlayerCount < 2 && hasPendingPlayers { return "Awaiting Invited Players..." }
        if activePlayerCount < 2 { return "Need 2+ Players" }
        if currentCourse == nil { return "Select a Course" }
        if needsTeeTimesSet { return "Set Tee Times to Start" }
        // Tell the creator which specific group is short on players — more
        // useful than a generic "Need more players" when the rest of the tee
        // sheet is already valid. Single short group → name it; multiple →
        // list. The button is disabled via canStartRound, this is just copy.
        let short = shortPlayerGroups
        if !short.isEmpty {
            if short.count == 1 {
                return "Add players to Group \(short[0])"
            }
            let groupList = short.map(String.init).joined(separator: ", ")
            return "Add players to Groups \(groupList)"
        }
        // Block until every Group 2+ scorer has accepted (they're the only
        // ones who can score their group — starting with a pending scorer
        // leaves the group unscorable if the invite is never accepted).
        if !pendingScorerWarnings.isEmpty {
            return pendingScorerWarnings.count > 1
                ? "Waiting for Scorers to Join"
                : "Waiting for Scorer to Join"
        }
        if !countdownText.isEmpty { return countdownText }
        return "Start Round"
    }

    // MARK: - Leaderboard Stats

    private var leaderboardRounds: [HomeRound] {
        leaderboardTab == 1 ? roundHistory : Array(roundHistory.suffix(1))
    }

    private var cumulativeStats: [Int: (skins: Int, won: Int)] {
        var result: [Int: (skins: Int, won: Int)] = [:]
        for round in leaderboardRounds {
            for player in round.players {
                let holesWon = round.playerWonHoles[player.id]?.count ?? 0
                let winnings = round.playerWinnings[player.id] ?? 0
                let existing = result[player.id] ?? (skins: 0, won: 0)
                result[player.id] = (skins: existing.skins + holesWon, won: existing.won + winnings)
            }
        }
        return result
    }

    private var leaderboardPlayers: [Player] {
        // Roster = players who are CURRENT members of this group (active or
        // invited). We still iterate `leaderboardRounds` to discover the union
        // of historical participants, but we filter each one against
        // `rosterById` — a former participant who isn't a member of this
        // group anymore should not appear on the leaderboard.
        //
        // The previous version included historical-only players so they'd
        // render alongside current members. That over-corrected: after a
        // Quick Game → Group conversion, every Quick Game guest who was NOT
        // ported into the new group still appeared on the leaderboard as
        // "invited" — confusing testers because those people were never
        // invited to this group at all.
        //
        // Stats aggregation is unchanged. `cumulativeStats` continues to
        // sum across all rounds (the migrated QG counts toward Daniel /
        // Emese / Ziggy's totals); we just don't render rows for players
        // who aren't in the current roster.
        let rosterById = Dictionary(uniqueKeysWithValues: allAvailable.map { ($0.id, $0) })
        var playersById: [Int: Player] = [:]
        for round in leaderboardRounds {
            for player in round.players {
                guard rosterById[player.id] != nil else { continue }
                if playersById[player.id] == nil {
                    playersById[player.id] = rosterById[player.id] ?? player
                }
            }
        }
        // Evaluate the computed property ONCE before sorting. Previously this
        // was read inside the `.sorted` comparator, which re-ran the full
        // O(rounds × players) aggregation for every pair-compare — N log N
        // recomputes of an already-O(N) dictionary build.
        let stats = cumulativeStats
        return Array(playersById.values).sorted { a, b in
            let aStats = stats[a.id] ?? (skins: 0, won: 0)
            let bStats = stats[b.id] ?? (skins: 0, won: 0)
            if aStats.won != bStats.won { return aStats.won > bStats.won }
            if aStats.skins != bStats.skins { return aStats.skins > bStats.skins }
            return a.name < b.name
        }
    }

    /// Leaderboard rows to render given the active tab. On the Last Round
    /// tab we narrow down to players who actually won skins — matches the
    /// post-round Results screen, where the leaderboard is a celebration of
    /// winners. All Time keeps every participant so standings stay complete.
    private var visibleLeaderboardPlayers: [Player] {
        guard leaderboardTab == 0 else { return leaderboardPlayers }
        let stats = cumulativeStats
        return leaderboardPlayers.filter { (stats[$0.id]?.skins ?? 0) > 0 }
    }

    private var hasPendingPlayers: Bool {
        allAvailable.contains { selectedIDs.contains($0.id) && ($0.isPendingInvite || $0.isPendingAccept) }
    }

    private var isAwaitingInvites: Bool {
        activePlayerCount < 2 && hasPendingPlayers && !isLiveRound
    }

    /// Seconds until the tee time window opens (10 min before first tee)
    private var secondsUntilTeeWindow: TimeInterval? {
        if isQuickGame { return nil }  // Quick games can start immediately
        guard let firstTee = teeTimes.first, let teeTime = firstTee else { return nil }
        let opens = teeTime.addingTimeInterval(-30 * 60)
        let remaining = opens.timeIntervalSince(Date())
        return remaining > 0 ? remaining : nil
    }

    private func countdownLabel(seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let d = total / 86400
        let h = (total % 86400) / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if d > 0 {
            return "Starts in \(d)d \(h)h \(m)m"
        } else if h > 0 {
            return "Starts in \(h)h \(m)m \(s)s"
        } else {
            return "Starts in \(m)m \(s)s"
        }
    }

    private var screenTopInset: CGFloat {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first
        else { return 59 }
        return window.safeAreaInsets.top
    }

    // MARK: - Group Data Refresh

    /// Fetches fresh group data from Supabase and updates local state.
    private func refreshGroupData() async {
        // Don't refresh while Player Groups sheet is open — user is actively editing
        guard !showPlayerGroups else { return }
        guard let groupId = supabaseGroupId else { return }
        guard let userId = try? await SupabaseManager.shared.client.auth.session.user.id else { return }

        do {
            guard let freshGroup = try await GroupService().loadSingleGroup(groupId: groupId, userId: userId) else {
                #if DEBUG
                print("[GroupManagerView] refreshGroupData: group not found")
                #endif
                return
            }

            // Raw membership rows — needed for the row-ID-based "new
            // member joined" toast baseline. Fetched outside MainActor.run
            // so the `await` doesn't break the synchronous UI block below.
            let activeMembershipRows = (try? await GroupService().fetchGroupMembers(groupId: groupId)) ?? []

            await MainActor.run {
                let hadGroups = !groups.isEmpty && !groups.allSatisfy({ $0.isEmpty })

                // Capture previous active member IDs BEFORE we overwrite
                // `allMembers` below. Used to compute which members are newly
                // active in this refresh (either brand-new joiners or
                // pending → active transitions when an invitee accepts).
                let prevActiveMemberIds = Set(
                    allMembers
                        .filter { !$0.isPendingInvite && !$0.isPendingAccept }
                        .map(\.id)
                )

                // Filter out players that were just manually removed (refresh race condition)
                let filteredFreshMembers = freshGroup.members.filter { !recentlyRemovedIds.contains($0.id) }
                allMembers = filteredFreshMembers
                let memberIds = Set(filteredFreshMembers.map(\.id))

                // Preserve the user's playing roster across refreshes, but with
                // a critical fix layered on top:
                //
                // OLD behavior — `selectedIDs.intersection(memberIds)` only.
                // Kept the user's existing selection stable and dropped IDs
                // for members who left, but had a fatal gap: newly-joined
                // active members and pending-→-active transitions were
                // never added. Result: a member viewing the group via this
                // long-lived view (no remount) never saw new joiners on
                // their tee sheet until they backed out and re-entered.
                // Pull-to-refresh appeared "broken" while navigate-away-and-
                // back worked — because the latter forced a fresh init that
                // re-seeded selectedIDs from defaultSel.
                //
                // NEW behavior — intersection (drop leavers) UNION newly-active
                // members, minus any IDs the user has explicitly persisted to
                // the deselected UserDefaults key (swipe-offs survive across
                // joiners — if you swiped someone off and they leave + rejoin,
                // they stay off until you re-add them).
                //
                // Manage Members deselections that aren't yet persisted to
                // UserDefaults are still preserved, because those deselected
                // members were already in `prevActiveMemberIds` — so they
                // don't show up as "newly active" and aren't re-added.
                let newlyActiveMemberIds = Set(
                    filteredFreshMembers
                        .filter { !$0.isPendingInvite && !$0.isPendingAccept && !prevActiveMemberIds.contains($0.id) }
                        .map(\.id)
                )
                let persistedDeselectedIds: Set<Int> = {
                    guard let gid = supabaseGroupId else { return [] }
                    let arr = UserDefaults.standard.array(forKey: "deselectedIDs_\(gid.uuidString)") as? [Int] ?? []
                    return Set(arr)
                }()
                selectedIDs = selectedIDs
                    .intersection(memberIds)
                    .union(newlyActiveMemberIds.subtracting(persistedDeselectedIds))

                if hadGroups {
                    // Rebuild groups authoritatively from server's group_num so
                    // tee-time rearrangements done by the creator propagate to
                    // every member device. Swipe-deletes pending a server commit
                    // are already filtered via recentlyRemovedIds above.
                    let existingById = Dictionary(
                        uniqueKeysWithValues: groups.flatMap { $0 }.map { ($0.id, $0) }
                    )
                    let scorerIdSet = Set(scorerIDs)
                    var newlyAcceptedScorers: [String] = []

                    for fresh in filteredFreshMembers {
                        if let prior = existingById[fresh.id] {
                            if prior.isPendingAccept && !fresh.isPendingAccept && scorerIdSet.contains(fresh.id) {
                                newlyAcceptedScorers.append(fresh.name)
                            }
                        }
                    }

                    let maxGroupNum = filteredFreshMembers.map(\.group).max() ?? 1
                    let targetCount = max(maxGroupNum, 1)
                    var rebuilt: [[Player]] = Array(repeating: [], count: targetCount)
                    // Exclude pending players from the tee sheet display — they
                    // live in the Manage sheet's Pending section. EXCEPTION:
                    // if the creator has explicitly assigned a pending player
                    // as scorer for their group, keep them visible. The
                    // assignment IS the "playing today" signal — hiding them
                    // would undo the creator's action and show "missing scorer"
                    // on every refresh.
                    //
                    // Union local + server scorer IDs: on first open, the
                    // local scorerIDs is seeded from `safeGrouped.first` (the
                    // first player in each group's initial autoGroup), which
                    // skipped pending players entirely. A pending scorer like
                    // Ziggy in Group 2 wasn't in local scorerIDs yet → got
                    // filtered out before the server sync at line 836+ could
                    // remap them in. Including server's scorer_ids here keeps
                    // the assigned-scorer exception working on first load.
                    var scorerIdSetLocal = Set(scorerIDs)
                    if let serverScorers = freshGroup.scorerIds {
                        scorerIdSetLocal.formUnion(serverScorers)
                    }
                    for fresh in filteredFreshMembers {
                        let isPending = fresh.isPendingInvite || fresh.isPendingAccept
                        let isAssignedScorer = scorerIdSetLocal.contains(fresh.id)
                        guard !isPending || isAssignedScorer else { continue }
                        // Honour the user's local swipe-deselects: only render
                        // into the tee sheet if they're still selected. Without
                        // this, the authoritative server rebuild resurrects any
                        // player the creator just swiped off the sheet (they
                        // remain an active group_members row server-side).
                        guard selectedIDs.contains(fresh.id) else { continue }
                        let idx = max(0, min(fresh.group - 1, targetCount - 1))
                        rebuilt[idx].append(fresh)
                    }
                    while rebuilt.last?.isEmpty == true && rebuilt.count > 1 {
                        rebuilt.removeLast()
                    }
                    groups = rebuilt

                    for name in newlyAcceptedScorers {
                        let first = name.components(separatedBy: " ").first ?? name
                        ToastManager.shared.success("\(first) accepted — ready to score")
                    }
                } else {
                    // First load — use autoGroup to set up initial arrangement
                    let playing = filteredFreshMembers.filter { selectedIDs.contains($0.id) }
                    let regrouped = Self.autoGroup(playing)
                    let safeGrouped: [[Player]]
                    if regrouped.isEmpty || regrouped.allSatisfy({ $0.isEmpty }) {
                        safeGrouped = filteredFreshMembers.isEmpty ? [[]] : [filteredFreshMembers]
                    } else {
                        safeGrouped = regrouped
                    }
                    groups = safeGrouped
                }

                // Cross-session "new member joined" toast. The baseline is
                // a per-group set of *membership row IDs* (not player UUIDs).
                // Because `group_members.id` is regenerated on every insert,
                // a user who leaves and rejoins gets a fresh row_id and
                // fires the toast again — even if the creator's device
                // never refreshed in the gap between leave and rejoin.
                // A player-UUID baseline would have missed that edge case,
                // since the UUID stays the same across leave/rejoin.
                // On first visit no toast fires (baseline is established).
                // Applies to both Skins Groups and Quick Games.
                do {
                    let seenKey = "seenActiveMemberRowIds_\(groupId.uuidString)"
                    let currentRowIds = Set(
                        activeMembershipRows
                            .filter { $0.status == "active" }
                            .map { $0.id.uuidString }
                    )
                    let previouslySeen = UserDefaults.standard.stringArray(forKey: seenKey).map(Set.init)
                    if let prev = previouslySeen {
                        let newlyJoinedRowIds = currentRowIds.subtracting(prev)
                        // Map row IDs back to Player objects for the toast text.
                        let newlyJoinedProfileIds = Set(
                            activeMembershipRows
                                .filter { newlyJoinedRowIds.contains($0.id.uuidString) }
                                .map { $0.playerId }
                        )
                        let newlyJoinedPlayers = filteredFreshMembers.filter {
                            guard let profileId = $0.profileId else { return false }
                            return newlyJoinedProfileIds.contains(profileId)
                        }
                        for player in newlyJoinedPlayers {
                            let first = player.name.components(separatedBy: " ").first ?? player.name
                            ToastManager.shared.success("\(first) joined — tap Manage to add to tee sheet")
                        }
                    }
                    UserDefaults.standard.set(Array(currentRowIds), forKey: seenKey)
                }

                let groupCount = max(groups.count, 1)
                startingSides = Self.defaultSides(count: groupCount)
                // Scorer ID reconciliation — preserve local edits against the
                // write-then-read race that was wiping assignments on refresh.
                // Rules:
                //  1. If a local save fired in the last 8s, trust local —
                //     Supabase may not have propagated the write back yet.
                //     Also SKIP syncScorerIDs entirely — the group rebuild
                //     above uses server's group_num, which lags behind a
                //     just-saved reorder and would falsely flag scorers as
                //     "not in their group" and wipe them.
                //  2. If server has a non-empty value, adopt it (normal case).
                //  3. If server is empty AND local has assignments, keep local
                //     (empty server almost always means "not yet saved" rather
                //     than "explicitly cleared"; we never send empty intentionally).
                //  4. If both empty, leave empty — syncScorerIDs picks defaults.
                let recentlySaved: Bool = {
                    guard let at = scorerIdsLastSavedAt else { return false }
                    return Date().timeIntervalSince(at) < 8
                }()
                if !recentlySaved {
                    if let saved = freshGroup.scorerIds, !saved.isEmpty {
                        // Self-heal positional drift: scorer_ids is a server
                        // positional array, but saveScorerIds + group_num sync
                        // can race — `scorer_ids[i]` might point to a player
                        // whose current group_num is j ≠ i. Rather than reading
                        // positionally and wiping the "wrong-slot" entries via
                        // syncScorerIDs, find each scorer's actual group and
                        // place them at that position. This reconciles any
                        // in-flight ordering inconsistency without data loss.
                        var remapped: [Int] = Array(repeating: 0, count: groups.count)
                        for scorerId in saved where scorerId != 0 {
                            for (idx, group) in groups.enumerated() {
                                if idx < remapped.count && group.contains(where: { $0.id == scorerId }) {
                                    remapped[idx] = scorerId
                                    break
                                }
                            }
                        }
                        scorerIDs = remapped
                        #if DEBUG
                        if remapped != saved {
                            print("[refreshGroupData] Remapped scorer IDs by player location: server=\(saved) → remapped=\(remapped)")
                        }
                        #endif
                    }
                    // else: keep whatever local scorerIDs has (may be empty on
                    // first load → syncScorerIDs will fill; may be populated →
                    // protect it from being stomped by stale/unset server data).
                    syncScorerIDs()
                }
                // When recentlySaved we skip syncScorerIDs — the local state
                // was just explicitly set by the user (via scorer picker /
                // PlayerGroupsSheet / tee-time reorder) and running the sync
                // against the server-derived groups rebuild would re-introduce
                // the stomp we're trying to prevent.

                // Update tee time / schedule — recompute every refresh so
                // members pick up changes the creator makes to schedule or
                // group count. Prefer the authoritative per-group array
                // (freshGroup.teeTimes) so independent/non-consecutive tee
                // times propagate exactly; fall back to deriving from
                // scheduledDate + teeTimeInterval for pre-migration groups.
                if let fresh = freshGroup.teeTimes, !fresh.isEmpty {
                    // Pad/truncate to groupCount so parallel arrays line up.
                    if fresh.count == groupCount {
                        teeTimes = fresh
                    } else if fresh.count > groupCount {
                        teeTimes = Array(fresh.prefix(groupCount))
                    } else {
                        teeTimes = fresh + Array(repeating: nil, count: groupCount - fresh.count)
                    }
                    if let first = fresh.compactMap({ $0 }).first {
                        roundDate = first
                    }
                } else if let date = freshGroup.scheduledDate {
                    roundDate = date
                    if let interval = freshGroup.teeTimeInterval, interval > 0, groupCount > 1 {
                        teeTimes = (0..<groupCount).map { i in
                            date.addingTimeInterval(Double(i) * Double(interval) * 60)
                        }
                    } else if teeTimes.count != groupCount {
                        teeTimes = [date] + Array(repeating: nil, count: max(groupCount - 1, 0))
                    }
                }

                // Update recurrence
                if let rec = freshGroup.recurrence {
                    switch rec {
                    case .weekly(let day):
                        scheduleMode = 1
                        repeatMode = 1
                        selectedDayPill = GameRecurrence.pillIndex(fromWeekday: day)
                    case .biweekly(let day):
                        scheduleMode = 1
                        repeatMode = 2
                        selectedDayPill = GameRecurrence.pillIndex(fromWeekday: day)
                    case .monthly:
                        scheduleMode = 1
                        repeatMode = 3
                        selectedDayPill = nil
                    }
                }

                // Update course if changed — but preserve holes if current course has them and fresh one doesn't
                if let course = freshGroup.lastCourse {
                    if let existingHoles = currentCourse?.teeBox?.holes, !existingHoles.isEmpty,
                       (course.teeBox?.holes == nil || course.teeBox?.holes?.isEmpty == true) {
                        // Keep existing course — it has API holes that the Supabase refresh lost
                        #if DEBUG
                        print("[GroupManagerView] refreshGroupData: keeping existing course with \(existingHoles.count) holes (fresh has none)")
                        #endif
                    } else {
                        currentCourse = course
                    }
                }

                // Update buy-in
                if freshGroup.buyInPerPlayer > 0 {
                    buyInText = "\(Int(freshGroup.buyInPerPlayer))"
                }

                // Update group name
                groupName = freshGroup.name

                // Sync winnings display preference
                winningsDisplay = freshGroup.winningsDisplay

                // Update round status
                roundStarted = freshGroup.activeRound != nil || freshGroup.concludedRound != nil

                // Notify parent so it can update its groups array
                onGroupRefreshed?(freshGroup)

                #if DEBUG
                let activeCount = freshGroup.members.filter { !$0.isPendingAccept }.count
                let pendingCount = freshGroup.members.filter { $0.isPendingAccept }.count
                print("[GroupManagerView] refreshGroupData: \(activeCount) active, \(pendingCount) pending, roundStarted=\(roundStarted)")
                #endif
            }
        } catch {
            #if DEBUG
            print("[GroupManagerView] refreshGroupData failed: \(error)")
            #endif
        }
    }

    private func startDetailAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task {
                await refreshGroupData()
            }
        }
    }

    private func saveScorerIds() {
        guard let groupId = supabaseGroupId else { return }
        // Stamp the save BEFORE the async write fires so the next poll (which
        // might land before the server acks) sees "recent save, keep local".
        scorerIdsLastSavedAt = Date()
        Task {
            try? await GroupService().updateGroup(
                groupId: groupId,
                update: SkinsGroupUpdate(scorerIds: scorerIDs)
            )
        }
    }

    private func stopDetailAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Row 1: Back button + action buttons
                HStack(spacing: 16) {
                    if let onBack {
                        Button {
                            onBack()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.textPrimary)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(.white))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Back")
                        .accessibilityHint("Returns to the previous screen")
                    }

                    Spacer()

                    // Leaderboard button
                    Button {
                        showLeaderboard = true
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(Color.goldMuted, lineWidth: 1.5)
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color.goldMuted)
                        }
                        .frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("Leaderboard")
                    .accessibilityHint("Shows round and all-time leaderboard")

                    // QR invite — creator only, Premium only, and only once
                    // the group has been persisted to Supabase (new groups get
                    // their ID on first save). Hidden entirely in the gated
                    // state; the empty-state screen handles the upsell.
                    if isCreator && supabaseGroupId != nil && storeService.isPremium {
                        Button {
                            showQRInvite = true
                        } label: {
                            Image(systemName: "qrcode")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color.textPrimary)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(.white))
                        }
                        .accessibilityLabel("QR invite")
                        .accessibilityHint("Shows a scannable QR code to invite players")
                    }

                    // Group options button. Three flavors:
                    //   Creator + Premium → full settings sheet (game options,
                    //     manage members, etc.). Unchanged from before.
                    //   Creator + gated   → compact Menu with just "Delete Group"
                    //     so exit stays accessible without the premium surface.
                    //   Member (any role) → compact Menu with just "Leave Group",
                    //     always visible. Members never need the settings sheet
                    //     — the only action they ever take from the ⋯ menu is
                    //     leaving the group, so surface that directly.
                    if isCreator && storeService.isPremium {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color.textPrimary)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(.white))
                        }
                        .accessibilityLabel("Group settings")
                        .accessibilityHint("Opens game settings")
                    } else if (isCreator && onDeleteGroup != nil) || (!isCreator && onLeaveGroup != nil) {
                        Menu {
                            Button(role: .destructive) {
                                showLeaveDeleteAlert = true
                            } label: {
                                Label(
                                    isCreator
                                        ? (isQuickGame ? "Delete Game" : "Delete Group")
                                        : (isQuickGame ? "Leave Game" : "Leave Group"),
                                    systemImage: "trash"
                                )
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color.textPrimary)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(.white))
                        }
                        .accessibilityLabel(isCreator ? "Group options" : "Leave group")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, screenTopInset - 7)
                .padding(.bottom, 20)
                .background(Color.bgPrimary)

                // Row 2: Unified header — group name (or compact date for quick games)
                if isQuickGame {
                    // Quick Game: show compact date as title (not editable)
                    Text(Self.headerDateOnlyFormatter.string(from: roundDate))
                        .font(.carry.sheetTitle)
                        .foregroundColor(Color.deepNavy)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 6)
                        .background(Color.bgPrimary)
                } else if isCreator {
                    Button {
                        editingName = groupName
                        showNameEditor = true
                    } label: {
                        Text(groupName)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(Color.deepNavy)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Game name: \(groupName)")
                    .accessibilityHint("Double tap to edit the game name")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                    .background(Color.bgPrimary)
                } else {
                    Text(groupName)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(Color.deepNavy)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 6)
                        .background(Color.bgPrimary)
                }

                // Meta info rows (both roles) — always visible
                Group {
                    VStack(alignment: .leading, spacing: 0) {
                        // Date + tee time row (hidden for quick games — date is the title)
                        if !isQuickGame {
                        HStack(spacing: 16) {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.textDark)
                                Text(Self.headerDateOnlyFormatter.string(from: roundDate))
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(Color.textDark)
                            }

                            if let date = teeTimes.first ?? nil {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color.textDark)
                                    Text(Self.teeTimeOnlyFormatter.string(from: date))
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(Color.textDark)
                                }
                            }

                            if let recurrence = buildRecurrence() {
                                HStack(spacing: 10) {
                                    Image(systemName: "repeat")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color.textDark)
                                    Text(recurrence.shortLabel)
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(Color.textDark)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }
                        .lineLimit(1)
                        .frame(minHeight: 32, alignment: .leading)
                        }

                        // Course row — always shown (mandatory field)
                        HStack(spacing: 10) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color.textDark)
                            if let course = currentCourse {
                                Text(course.courseName)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(Color.textDark)
                                    .lineLimit(1)
                                if let tee = course.teeBox {
                                    Circle()
                                        .fill(Color(hexString: tee.color))
                                        .frame(width: 5.5, height: 5.5)
                                    let pct = Int(handicapPercentage * 100)
                                    Text("\(tee.name) at \(pct)%")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(Color.textDark)
                                        .lineLimit(1)
                                        .layoutPriority(1)
                                }
                            } else {
                                Text("Select a course")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(Color.dividerMuted)
                            }
                        }
                        .frame(height: 32, alignment: .leading)
                        .onTapGesture {
                            if isCreator && currentCourse == nil {
                                showCourseChange = true
                            }
                        }

                        // Buy-in badge row
                        if let buyIn = Int(buyInText), buyIn > 0 {
                            HStack(spacing: 14) {
                                HStack(spacing: 4) {
                                    ZStack {
                                        Circle()
                                            .fill(.white.opacity(0.35))
                                            .frame(width: 18, height: 18)
                                        Text("$")
                                            .font(.carry.microSM)
                                            .foregroundColor(.white)
                                    }
                                    Text("\(buyIn) Buy-In")
                                        .font(.carry.bodySMSemibold)
                                        .foregroundColor(.white)
                                }
                                .padding(.leading, 4)
                                .padding(.trailing, 8)
                                .padding(.vertical, 3)
                                .background(Color.goldAccent)
                                .clipShape(Capsule())
                            }
                            .frame(height: 32, alignment: .leading)
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .background(Color.bgPrimary)
                    .opacity(storeService.isPremium ? 1.0 : 0.5)
                }

                if storeService.isPremium {
                // "Tee Times" header — pinned above scroll
                HStack {
                    Text("Tee Times")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(Color.deepNavy)
                    Spacer()
                    if isCreator && !isLiveRound && !roundStarted && selectedCount > 0 {
                        Button {
                            if isQuickGame {
                                showPlayerGroups = true
                            } else {
                                showManageMembers = true
                            }
                        } label: {
                            Text("Invite & Manage")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().strokeBorder(Color.textPrimary, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Invite and manage players")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                ScrollView {
                VStack(spacing: 0) {
                    // Green tip banner (admin only, dismissible)
                    if isCreator && showTipBanner && selectedCount > 0 {
                        VStack(spacing: 0) {
                            HStack(alignment: .top, spacing: 8) {
                                Text("Press a player to change the player order, or move players between groups")
                                    .font(.carry.bodySM)
                                    .foregroundColor(Color.successGreen)
                                    .lineSpacing(2)
                                Spacer()
                                Button {
                                    withAnimation { showTipBanner = false }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundColor(Color.successGreen)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Dismiss tip")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.concludedGreen)
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }

                    // Groups section
                    if selectedCount > 0 {
                        // Hide groups with zero displayable players. Empty
                        // groups happen when:
                        //   - All members assigned to that group_num are
                        //     still pending (e.g. Quick Game → Skins Group
                        //     conversion before invitees accept)
                        //   - All members in that slot were swiped off
                        //
                        // Showing an empty card looked broken — testers
                        // reported "why is Group 2 sitting there empty?"
                        // The underlying `groups` array stays intact (so
                        // `groupIdx` keeps mapping to the correct position
                        // in scorerIDs / teeTimes / round_players); we only
                        // skip rendering. As soon as a member becomes active
                        // (auto-add via the refresh union in v55), they
                        // populate `groups[groupIdx]` and the card appears.
                        ForEach(Array(groups.enumerated()).filter { !$0.element.isEmpty }, id: \.offset) { groupIdx, group in
                            groupCard(index: groupIdx, players: group)
                                .id(group.map(\.id))  // force re-render when players change
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                        }
                    } else {
                        Text("Add players above to create groups & tee times")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color.textSecondary)
                            .padding(.top, 20)
                    }

                    Spacer().frame(height: 100)
                }
            }
                }
                // Gated state renders nothing in the main VStack after the
                // meta info — the empty-state is a centered ZStack overlay
                // below so it sits at true screen center, not just in the
                // remaining space below the header.
            } // end floating header VStack
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Gated empty-state — ZStack overlay centered on the full screen.
            // Tee times are ephemeral per-round setup, so we hide them for
            // lapsed users and surface a single clear upgrade CTA. Leaderboard
            // + history remain free (read-only) via the chart button top-right.
            if !storeService.isPremium {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        Text(storeService.hadPremium ? "Your subscription has ended" : "Start your free trial")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Color.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(storeService.hadPremium
                             ? "Subscribe to start games, invite players, and keep your leaderboard going."
                             : "Try Carry Premium free for 30 days. Start games, invite players, and keep your leaderboard going.")
                            .font(.carry.bodySM)
                            .foregroundColor(Color.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        // .general (no context line) — the empty-state copy
                        // above already explains why the paywall is showing,
                        // so "Managing groups is a Premium feature" would be
                        // redundant. Inline gated buttons keep .manageGroup.
                        presentPaywall(.general)
                    } label: {
                        Text(storeService.hadPremium ? "Subscribe" : "Try It Free")
                            .font(.carry.bodyLGSemibold)
                            .foregroundColor(Color.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.textPrimary, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
            }

            // CTA button pinned to bottom — all roles. Hidden in the gated
            // state since the empty-state screen above carries the CTA.
            if storeService.isPremium {
            VStack {
                Spacer()
                if isCreator {
                    // Admin: "Start Round" or "Back to Scorecard". The Premium
                    // gate only fires when we're actually creating a new round —
                    // "Back to Scorecard" (live round) and "Needs Schedule"
                    // (opens settings) both stay free.
                    Button {
                        if isLiveRound {
                            onBack?()
                        } else if needsNextSchedule {
                            showSettings = true
                        } else {
                            // canStartRound already gates on pendingScorerWarnings,
                            // so if we reached here every Group 2+ scorer has
                            // accepted. Safe to start the round directly.
                            Task { await startRoundWithHolesSafetyNet() }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if canStartRound || isLiveRound {
                                Image(systemName: "flag.fill")
                                    .font(.carry.bodySMSemibold)
                            }
                            Text(startButtonLabel)
                                .font(.carry.bodyLGSemibold)
                        }
                        .foregroundColor(buttonLooksActive ? .white : Color.textSecondary)
                        .frame(width: 322, height: 51)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(buttonLooksActive ? Color.textPrimary : Color.borderMedium)
                        )
                    }
                    .disabled(!buttonEnabled)
                    .accessibilityLabel(startButtonLabel)
                    .accessibilityHint(isLiveRound ? "Returns to the live scorecard" : "Starts a new round")
                    .padding(.bottom, 20)
                    .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                        if let secs = secondsUntilTeeWindow {
                            countdownText = countdownLabel(seconds: secs)
                        } else {
                            countdownText = ""
                        }
                        // Poll every 30s for member status + round start
                        let now = Date().timeIntervalSince1970
                        if now.truncatingRemainder(dividingBy: 30) < 1, let groupId = supabaseGroupId {
                            Task {
                                // Check round start (member view)
                                if !isCreator && !roundStarted {
                                    if let round = try? await SupabaseManager.shared.client
                                        .from("rounds")
                                        .select("id")
                                        .eq("group_id", value: groupId.uuidString)
                                        .eq("status", value: "active")
                                        .limit(1)
                                        .execute(),
                                       round.data.count > 2 {
                                        await MainActor.run { roundStarted = true }
                                    }
                                }
                                // Refresh member statuses
                                if let members: [GroupMemberDTO] = try? await SupabaseManager.shared.client
                                    .from("group_members")
                                    .select()
                                    .eq("group_id", value: groupId.uuidString)
                                    .execute()
                                    .value {
                                    let activeMembers = members.filter { $0.status == "active" }
                                    let activeIds = Set(activeMembers.map { $0.playerId })
                                    // Check if any phone invites were claimed (invited_phone cleared + status active)
                                    let claimedMembers = activeMembers.filter { ($0.invitedPhone ?? "").isEmpty }
                                    let claimedPhones = Set(claimedMembers.map { $0.playerId })
                                    let hasClaimedInvite = allMembers.contains { $0.isPendingInvite } && !claimedPhones.isEmpty
                                    await MainActor.run {
                                        for i in allMembers.indices {
                                            if activeIds.contains(allMembers[i].profileId ?? UUID()) {
                                                allMembers[i].isPendingAccept = false
                                            }
                                        }
                                        // Full refresh if a phone invite was claimed — need to load the new profile
                                        if hasClaimedInvite {
                                            Task { await refreshGroupData() }
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else if roundStarted {
                    // Member, round started: "Join Round"
                    Button {
                        guard !isJoiningRound else { return }
                        isJoiningRound = true
                        Task {
                            var config = buildRoundConfig()
                            if let groupId = supabaseGroupId {
                                do {
                                    let client = SupabaseManager.shared.client
                                    let rounds: [RoundDTO] = try await client
                                        .from("rounds")
                                        .select()
                                        .eq("group_id", value: groupId.uuidString)
                                        .eq("status", value: "active")
                                        .limit(1)
                                        .execute()
                                        .value
                                    if let activeRound = rounds.first {
                                        config.supabaseRoundId = activeRound.id
                                        config.supabaseGroupId = groupId
                                        // Fetch tee box holes if missing
                                        if let teeBoxId = activeRound.teeBoxId,
                                           config.holes == nil || config.teeBox?.holes == nil {
                                            config = await Self.fetchAndAttachHoles(config: config, teeBoxId: teeBoxId)
                                        }
                                    }
                                } catch {
                                    await MainActor.run {
                                        isJoiningRound = false
                                        ToastManager.shared.error("Couldn't connect — check your internet")
                                    }
                                    return
                                }
                            }
                            // Safety net: if holes still missing, fetch from skins_groups
                            if config.holes == nil || config.holes?.isEmpty == true,
                               let groupId = supabaseGroupId,
                               let holesFromGroup = await GroupService().fetchPersistedHoles(groupId: groupId) {
                                config.holes = holesFromGroup
                            }
                            if config.holes == nil || config.holes?.isEmpty == true {
                                await MainActor.run {
                                    isJoiningRound = false
                                    ToastManager.shared.error("Course hole data missing — please ask the host to reselect the course")
                                }
                                return
                            }
                            await MainActor.run {
                                isJoiningRound = false
                                onConfirm(config)
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if isJoiningRound {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "flag.fill")
                                    .font(.carry.bodySMSemibold)
                            }
                            Text("Join Round")
                                .font(.carry.bodyLGSemibold)
                        }
                        .foregroundColor(.white)
                        .frame(width: 322, height: 51)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.textPrimary)
                        )
                    }
                    .disabled(isJoiningRound)
                    .padding(.bottom, 20)
                } else {
                    // Member, round not started: show countdown or "Round Not Started..."
                    HStack(spacing: 10) {
                        Image(systemName: "flag.fill")
                            .font(.carry.bodySMSemibold)
                        Text(!countdownText.isEmpty ? countdownText : "Round Not Started...")
                            .font(.carry.bodyLGSemibold)
                    }
                    .foregroundColor(Color.textSecondary)
                    .frame(width: 322, height: 51)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.borderMedium)
                    )
                    .padding(.bottom, 20)
                }
            }
            } // end isPremium CTA gate
        }
        .refreshable {
            #if DEBUG
            print("[GroupManagerView] Pull-to-refresh triggered")
            #endif
            await refreshGroupData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveGroupStateChangePush)) { notification in
            // memberJoined / memberDeclined push received while this view is on
            // screen. Refresh now instead of waiting up to 30s for the timer.
            guard let pushedGroupId = notification.object as? UUID,
                  pushedGroupId == supabaseGroupId else { return }
            #if DEBUG
            print("[GroupManagerView] memberJoined/Declined push received — refreshing")
            #endif
            Task { await refreshGroupData() }
        }
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $showAddSheet) {
            addPlayerSheet
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .sheet(isPresented: $showGuestEntry) {
            guestEntrySheet
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .sheet(isPresented: $showInviteEntry) {
            inviteEntrySheet
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .sheet(isPresented: $showSettings) {
            GroupOptionsSheet(
                isCreator: isCreator,
                isLiveRound: isLiveRound,
                isQuickGame: isQuickGame,
                groupName: groupName,
                carriesEnabled: carriesEnabled,
                scoringMode: scoringMode,
                winningsDisplay: winningsDisplay,
                handicapPercentage: handicapPercentage,
                buyInText: buyInText,
                teeTime: teeTimes.first.flatMap { $0 },
                currentCourse: currentCourse,
                recurrence: buildRecurrence(),
                onCancel: { showSettings = false },
                onSave: { result in
                    groupName = result.groupName
                    carriesEnabled = result.carriesEnabled
                    scoringMode = result.scoringMode
                    winningsDisplay = result.winningsDisplay
                    handicapPercentage = result.handicapPercentage
                    buyInText = result.buyInText
                    // Persist name + buy-in + winnings display to Supabase
                    if let groupId = supabaseGroupId {
                        Task {
                            try? await GroupService().updateGroup(
                                groupId: groupId,
                                update: SkinsGroupUpdate(
                                    name: result.groupName,
                                    buyIn: Double(result.buyInText) ?? 0,
                                    winningsDisplay: result.winningsDisplay
                                )
                            )
                        }
                    }
                    if let t = result.teeTime {
                        roundDate = t
                        if teeTimes.isEmpty { syncTeeTimes() }
                        if !teeTimes.isEmpty {
                            let slot = currentUserSlotIndex
                            teeTimes[slot] = t
                            autoFillTeeTimes(from: slot)
                        }
                        onTeeTimeChanged?(t)
                        // Persist to `tee_times_json` server-side so other
                        // devices (and a subsequent group refresh on this
                        // device) see the updated times — otherwise the next
                        // reload reverts the edit to stale Quick Game values.
                        syncTeeTimesToSupabase()
                    }
                    if let course = result.changedCourse {
                        currentCourse = course
                        // Cache API holes so they survive Supabase refreshes
                        if let holes = course.teeBox?.holes, !holes.isEmpty {
                            cachedHoles = holes
                        }
                        onCourseChanged?(course)
                    }
                    // Update recurrence
                    if let rec = result.recurrence {
                        scheduleMode = 1
                        switch rec {
                        case .weekly(let d):
                            repeatMode = 1
                            selectedDayPill = GameRecurrence.pillIndex(fromWeekday: d)
                        case .biweekly(let d):
                            repeatMode = 2
                            selectedDayPill = GameRecurrence.pillIndex(fromWeekday: d)
                        case .monthly:
                            repeatMode = 3
                            selectedDayPill = nil
                        }
                        onRecurrenceChanged?(rec)
                    } else if result.clearRecurrence {
                        scheduleMode = 0
                        repeatMode = 0
                        selectedDayPill = nil
                        onRecurrenceChanged?(nil)
                    }
                    showSettings = false
                    ToastManager.shared.success("Game options saved")
                },
                onLeaveGroup: onLeaveGroup.map { leave in {
                    showSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showLeaveDeleteAlert = true
                        }
                    }
                }},
                onDeleteGroup: onDeleteGroup.map { delete in {
                    showSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showLeaveDeleteAlert = true
                        }
                    }
                }}
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .sheet(isPresented: $showCourseChange) {
            CourseSelectionView { course in
                currentCourse = course
                // Cache API holes so they survive Supabase refreshes
                if let holes = course.teeBox?.holes, !holes.isEmpty {
                    cachedHoles = holes
                }
                // Persist full course (denormalized fields + holes JSON) in one call
                if let groupId = supabaseGroupId {
                    Task {
                        try? await GroupService().persistCourseSelection(groupId: groupId, course: course)
                    }
                }
                onCourseChanged?(course)
                showCourseChange = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.white)
        }
        .sheet(isPresented: $showLeaderboard) {
            leaderboardSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .sheet(isPresented: $showQRInvite) {
            if let groupId = supabaseGroupId {
                GroupInviteQRSheet(groupId: groupId)
                    // Fitted height matches the Figma 1222:35728 card:
                    // 55 top + 90 logo + 41 gap + 282 QR + 32 bottom = 500
                    // inside the card, plus 19 outer padding top/bottom = 538.
                    // Add a few pt of breathing room so the card doesn't
                    // squeeze and lose its horizontal margin.
                    .presentationDetents([.height(560)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.white)
            }
        }
        .fullScreenCover(isPresented: $showFullScreenQR) {
            if let groupId = supabaseGroupId {
                FullScreenQRView(groupId: groupId, groupName: groupName)
            }
        }
        #if !DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            // Release-only. In Debug the shake opens the Debug menu via
            // CarryApp's listener — presenting this fullscreen cover at the
            // same time would collide. Only trigger when we've got a real
            // group to show a QR for (skip during course selection etc).
            if supabaseGroupId != nil, !isLiveRound, isCreator {
                showFullScreenQR = true
            }
        }
        #else
        .onReceive(NotificationCenter.default.publisher(for: .debugPreviewFullScreenQR)) { _ in
            // Debug-only test hook: Debug menu → "Preview Fullscreen QR"
            // posts this notification to simulate the shake behavior that
            // ships in Release. Same guards as the Release path.
            if supabaseGroupId != nil, !isLiveRound, isCreator {
                showFullScreenQR = true
            }
        }
        #endif
        .sheet(isPresented: $showSwapPicker) {
            swapPickerSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .sheet(isPresented: $showTeeTimePicker) {
            teeTimePickerSheet
                .presentationDetents([.height(580)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .onChange(of: teeTimes) {
            // Persist first group's tee time back to SavedGroup
            onTeeTimeChanged?(teeTimes.first.flatMap { $0 })
        }
        .onChange(of: selectedIDs) { _, _ in
            persistDeselectedForToday()
        }
        .sheet(item: $scorerPickerItem) { item in
            scorerPickerSheet(groupIndex: item.id)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .sheet(isPresented: $showManageMembers) {
            manageMembersSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .sheet(isPresented: $showPlayerGroups) {
            PlayerGroupsSheet(
                initialGroups: groups,
                initialScorerIDs: scorerIDs,
                initialTeeTimes: teeTimes,
                initialStartingSides: startingSides,
                initialSelectedTees: selectedTees,
                initialAllMembers: allMembers,
                initialSelectedIDs: selectedIDs,
                initialNextGuestID: nextGuestID,
                currentUserId: currentUserId,
                supabaseGroupId: supabaseGroupId,
                isQuickGame: isQuickGame,
                handicapPercentage: handicapPercentage,
                currentCourse: currentCourse,
                onSave: { result in
                    groups = result.groups
                    scorerIDs = result.scorerIDs
                    teeTimes = result.teeTimes
                    startingSides = result.startingSides
                    selectedTees = result.selectedTees
                    allMembers = result.allMembers
                    selectedIDs = result.selectedIDs
                    nextGuestID = result.nextGuestID
                    // Clear removed IDs — user explicitly saved new group arrangement,
                    // so any prior swipe-deletes are superseded by the new state.
                    recentlyRemovedIds.removeAll()
                    // PlayerGroupsSheet persisted scorerIds to Supabase in its
                    // own save path (not via saveScorerIds()), so stamp the
                    // grace window here to protect the parent's local scorer
                    // state from being stomped by the next 30s refresh before
                    // the server write has replicated back.
                    scorerIdsLastSavedAt = Date()
                    onTeeTimeChanged?(teeTimes.first.flatMap { $0 })
                    syncTeeTimesToSupabase()
                    showPlayerGroups = false
                },
                onCancel: {
                    showPlayerGroups = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.white)
        }
        .sheet(isPresented: $showShareCardSheet) {
            VStack(spacing: 0) {
                // Scrollable results card
                ScrollView {
                    ResultsShareCard(data: shareCardData, theme: .light, showAppStoreBadge: false)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.08), radius: 16, x: 0, y: 12)
                        .shadow(color: Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.03), radius: 6, x: 0, y: 4)
                        .padding(.horizontal, 6)
                        .padding(.top, 8)
                }

                // Pinned bottom: invite CTA
                VStack(spacing: 12) {
                    Text("Join our Skins Group on Carry")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color.textPrimary)

                    Text("Copy and share the link with the players\nto join your Skins Group on Carry")
                        .font(.system(size: 15))
                        .foregroundColor(Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Button {
                    if let groupId = supabaseGroupId {
                        let link = "https://carryapp.site/invite?group=\(groupId.uuidString)"
                        UIPasteboard.general.string = link
                    }
                    showShareCardSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        ToastManager.shared.success("Invite link copied!")
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "link")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Copy Invite Link")
                            .font(.carry.bodyLGSemibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 51)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.textPrimary)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.white)
        }
        .sheet(isPresented: $showInviteShareSheet) {
            ShareSheetView(items: [inviteShareLink])
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showDatePicker) {
            TeeTimePickerSheet(
                scheduleMode: $scheduleMode,
                selectedDate: $roundDate,
                repeatMode: Binding(
                    get: { max(repeatMode - 1, 0) },
                    set: { repeatMode = $0 + 1 }
                ),
                selectedDayPill: $selectedDayPill,
                onSet: {
                    if teeTimes.isEmpty { syncTeeTimes() }
                    if !teeTimes.isEmpty {
                        let slot = currentUserSlotIndex
                        teeTimes[slot] = roundDate
                        autoFillTeeTimes(from: slot)
                    }
                    onTeeTimeChanged?(teeTimes.first.flatMap { $0 })
                    onRecurrenceChanged?(buildRecurrence())
                    syncTeeTimesToSupabase()
                    showDatePicker = false
                    ToastManager.shared.success(scheduleMode == 1 ? "Schedule updated" : "Tee time updated")
                },
                onCancel: {
                    roundDate = initialRoundDate
                    scheduleMode = initialScheduleMode
                    repeatMode = initialRepeatMode
                    selectedDayPill = initialSelectedDayPill
                    showDatePicker = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.white)
            .onAppear {
                initialRoundDate = roundDate
                initialScheduleMode = scheduleMode
                initialRepeatMode = repeatMode
                initialSelectedDayPill = selectedDayPill
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(trigger: paywallTrigger)
        }
        .alert("Edit Name", isPresented: $showNameEditor) {
            TextField("Friday Skins", text: $editingName)
            Button("Save") {
                let trimmed = editingName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    groupName = trimmed
                    if let groupId = supabaseGroupId {
                        Task {
                            try? await GroupService().updateGroup(
                                groupId: groupId,
                                update: SkinsGroupUpdate(name: trimmed)
                            )
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert(
            isCreator
                ? (isQuickGame ? "Delete Game?" : "Delete Group?")
                : (isQuickGame ? "Leave Game?" : "Leave Group?"),
            isPresented: $showLeaveDeleteAlert
        ) {
            Button("Cancel", role: .cancel) { }
            Button(isCreator ? "Delete" : "Leave", role: .destructive) {
                if isCreator {
                    onDeleteGroup?()
                } else {
                    onLeaveGroup?()
                }
            }
        } message: {
            let label = isQuickGame ? "game" : "group"
            Text(isCreator
                ? "This will remove \(groupName) for all members. This can't be undone."
                : "You'll be removed from \(groupName) and future \(label)s.")
        }
        .alert("Leave game?", isPresented: $showCloseQuickGameAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Leave", role: .destructive) {
                onBack?()
            }
        } message: {
            Text("Your game setup will be lost.")
        }
        .alert(
            "Remove \(pendingQuickGameRemoval?.player.shortName ?? "player") from game?",
            isPresented: Binding(
                get: { pendingQuickGameRemoval != nil },
                set: { if !$0 { pendingQuickGameRemoval = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingQuickGameRemoval = nil
            }
            Button("Remove", role: .destructive) {
                if let pending = pendingQuickGameRemoval {
                    removePlayer(pending.player, fromGroup: pending.groupIndex)
                }
                pendingQuickGameRemoval = nil
            }
        } message: {
            Text("They'll be removed from this Quick Game. If they were the scorer, you'll need to assign someone else.")
        }
        .onAppear {
            // Fresh load on appear and start 30s polling
            if supabaseGroupId != nil {
                // Quick Games: delay first refresh to let Supabase writes settle
                let delay: Double = isQuickGame ? 3.0 : 0
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    Task { await refreshGroupData() }
                }
                startDetailAutoRefresh()
            }
            // Pre-warm the QR code off the main thread so the first tap of
            // the QR icon presents instantly. Cold-start cost is the CIContext
            // GPU init + the initial CIQRCodeGenerator render — both ~hundreds
            // of ms on first use. Generating it now (cached by payload + colors
            // in QRCodeGenerator) means the sheet animates in with the image
            // already ready.
            if let groupId = supabaseGroupId {
                Task.detached(priority: .utility) {
                    _ = QRCodeGenerator.image(
                        for: GroupInviteLink.url(for: groupId).absoluteString,
                        foreground: UIColor(Color.successGreen),
                        background: UIColor(Color.successBgLight)
                    )
                }
            }
            // Post-conversion "bring your crew" UX lives in the convert
            // sheet's invite-crew phase in GroupsListView. When that sheet
            // dismisses and the user lands here, auto-open the group name
            // editor so they can give the auto-generated name a real name.
            if showInviteCrewOnAppear && isCreator {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    editingName = groupName
                    showNameEditor = true
                }
            }
        }
        .onDisappear {
            stopDetailAutoRefresh()
        }
        .onChange(of: groups) { _, _ in
            // Debounce: sync sort_order + group_num after user stops reordering
            orderSyncTask?.cancel()
            orderSyncTask = Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                guard !Task.isCancelled else { return }
                syncPlayerOrderToSupabase()
                syncGroupNumsToSupabase()
            }
        }
        .onChange(of: teeTimes) { _, _ in
            // Debounce: persist the full per-group tee times array so
            // independent (non-consecutive) schedules survive across
            // devices. Members read this via SavedGroup.teeTimes.
            teeTimesSyncTask?.cancel()
            teeTimesSyncTask = Task {
                try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
                guard !Task.isCancelled else { return }
                syncTeeTimesToSupabase()
            }
        }
    }

    // MARK: - Build Round Config (shared helper)

    /// Fetch tee box holes from Supabase and attach to config.
    private static func fetchAndAttachHoles(config: RoundConfig, teeBoxId: UUID) async -> RoundConfig {
        var updated = config
        do {
            let dto: TeeBoxDTO = try await SupabaseManager.shared.client
                .from("tee_boxes")
                .select()
                .eq("id", value: teeBoxId.uuidString)
                .single()
                .execute()
                .value
            let holes = dto.decodeHoles()
            updated.holes = holes
            #if DEBUG
            print("[JoinRound] Loaded tee box holes: \(holes?.count ?? 0)")
            #endif
        } catch {
            #if DEBUG
            print("[JoinRound] Failed to fetch tee box holes: \(error)")
            #endif
        }
        return updated
    }

    private func buildRoundConfig() -> RoundConfig {
        // Quick Games: include ALL players (even pending) so their groups exist in the round
        // Regular groups: only include confirmed (non-pending) players
        let roundGroups: [[Player]]
        if isQuickGame {
            roundGroups = groups
        } else {
            roundGroups = groups.map { $0.filter { !$0.isPendingInvite && !$0.isPendingAccept } }
        }
        let groupConfigs = roundGroups.enumerated().map { idx, players in
            GroupConfig(id: idx + 1, startingSide: startingSides[idx], playerIDs: players.map(\.id))
        }
        let allRoundPlayers = roundGroups.flatMap { $0 }

        // Map first group's scorer Int ID → Supabase UUID
        let scorerProfileId: UUID? = {
            guard let firstScorerId = scorerIDs.first else { return nil }
            return allRoundPlayers.first(where: { $0.id == firstScorerId })?.profileId
        }()

        #if DEBUG
        print("[buildRoundConfig] buyInText='\(buyInText)' → Int=\(Int(buyInText) ?? 0), players=\(roundGroups.flatMap { $0 }.count)")
        print("[buildRoundConfig] currentCourse=\(currentCourse?.courseName ?? "nil") teeBox.holes=\(currentCourse?.teeBox?.holes?.count ?? 0) cachedHoles=\(cachedHoles?.count ?? 0) apiTee.holes=\(currentCourse?.apiTee?.holes?.count ?? 0)")
        if let h = currentCourse?.teeBox?.holes, h.count >= 3 {
            print("[buildRoundConfig] hole pars: \(h.prefix(5).map(\.par))")
        }
        #endif
        var resolvedTeeBox = currentCourse?.teeBox ?? TeeBox(id: "default", courseId: "0", name: "Default", color: "white", courseRating: 72.0, slopeRating: 113, par: 72)
        // Restore holes from multiple fallback sources
        if resolvedTeeBox.holes == nil || resolvedTeeBox.holes?.isEmpty == true {
            // 1. Cached holes from initial load (survives Supabase refresh on same session)
            if let cached = cachedHoles, !cached.isEmpty {
                resolvedTeeBox.holes = cached
                #if DEBUG
                print("[buildRoundConfig] ⚠️ Used cachedHoles fallback")
                #endif
            }
            // 2. API tee data from course selection
            else if let apiTee = currentCourse?.apiTee,
                    let apiHoles = apiTee.holes, !apiHoles.isEmpty {
                resolvedTeeBox.holes = Hole.fromAPI(apiHoles)
                #if DEBUG
                print("[buildRoundConfig] ⚠️ Used apiTee fallback")
                #endif
            } else {
                #if DEBUG
                print("[buildRoundConfig] ❌ NO HOLES — startRoundWithHolesSafetyNet will fetch from Supabase")
                #endif
            }
        }
        // Cache holes for future use (e.g. if view is re-created)
        if cachedHoles == nil, let holes = resolvedTeeBox.holes, !holes.isEmpty {
            cachedHoles = holes
        }
        #if DEBUG
        print("[buildRoundConfig] FINAL teeBox.name=\(resolvedTeeBox.name) holes=\(resolvedTeeBox.holes?.count ?? 0)")
        if let h = resolvedTeeBox.holes, h.count >= 3 {
            print("[buildRoundConfig] FINAL hole pars: \(h.prefix(5).map(\.par))")
        }
        #endif
        var config = RoundConfig(
            id: UUID().uuidString,
            number: 1,
            course: currentCourse?.courseName ?? "Unknown Course",
            date: ISO8601DateFormatter().string(from: roundDate),
            buyIn: Int(buyInText) ?? 0,
            gameType: "skins",
            skinRules: SkinRules(
                net: true,
                carries: isQuickGame && !storeService.isPremium ? false : carriesEnabled,
                outright: true,
                handicapPercentage: handicapPercentage
            ),
            teeBox: resolvedTeeBox,
            groups: groupConfigs,
            creatorId: creatorId,
            groupName: groupName,
            players: allRoundPlayers,
            holes: resolvedTeeBox.holes
        )
        config.scorerProfileId = scorerProfileId
        config.scoringMode = scoringMode
        config.isQuickGame = isQuickGame
        config.winningsDisplay = winningsDisplay
        // Scorer's own tee time — resolved from teeTimes[] at the group index
        // containing currentUserId. The creator (who owns this view) is the
        // scorer of exactly one group; their scorecard header should show
        // THAT group's time, not the round's earliest. Member devices build
        // their own RoundConfig in RoundCoordinatorView and set this similarly.
        if let idx = groupConfigs.firstIndex(where: { $0.playerIDs.contains(currentUserId) }),
           idx < teeTimes.count {
            config.scorerTeeTime = teeTimes[idx]
        }
        return config
    }

    // MARK: - Start Round with Holes Safety Net

    /// Builds the round config and ensures holes are available before starting.
    /// If holes are missing from local state, fetches from skins_groups as a last resort.
    /// Blocks round start if no hole data is available.
    private func startRoundWithHolesSafetyNet() async {
        var config = buildRoundConfig()
        // Safety net: if holes are missing, fetch from skins_groups via the single helper.
        // Patch BOTH config.holes AND config.teeBox.holes so every downstream consumer sees them.
        if config.holes == nil || config.holes?.isEmpty == true,
           let groupId = supabaseGroupId,
           let holesFromGroup = await GroupService().fetchPersistedHoles(groupId: groupId) {
            config.holes = holesFromGroup
            if let tb = config.teeBox {
                config.teeBox = TeeBox(id: tb.id, courseId: tb.courseId, name: tb.name, color: tb.color, courseRating: tb.courseRating, slopeRating: tb.slopeRating, par: tb.par, holes: holesFromGroup)
            }
        }
        if config.holes == nil || config.holes?.isEmpty == true {
            await MainActor.run {
                ToastManager.shared.error("Course hole data missing — please reselect your course")
            }
            return
        }
        await MainActor.run { onConfirm(config) }
    }

    // MARK: - Remove Player (swipe-to-delete)

    private func removePlayer(_ player: Player, fromGroup groupIndex: Int) {
        guard groupIndex < groups.count else { return }

        // Always remove from the visible tee-sheet group immediately.
        groups[groupIndex].removeAll { $0.id == player.id }

        if isQuickGame {
            // Quick Game: the tee sheet IS the roster — removing from the tee
            // sheet means removing from the game. Hard delete from Supabase
            // and drop from local member state.
            recentlyRemovedIds.insert(player.id)
            allMembers.removeAll { $0.id == player.id }
            selectedIDs.remove(player.id)
            if let groupId = supabaseGroupId, let profileId = player.profileId {
                Task {
                    do {
                        try await SupabaseManager.shared.client
                            .from("group_members")
                            .delete()
                            .eq("group_id", value: groupId.uuidString)
                            .eq("player_id", value: profileId.uuidString)
                            .execute()
                        #if DEBUG
                        print("[removePlayer] ✅ Hard-deleted \(player.name) (\(profileId)) from \(groupId)")
                        #endif
                    } catch {
                        #if DEBUG
                        print("[removePlayer] ❌ Failed to delete \(player.name): \(error)")
                        #endif
                        await MainActor.run {
                            ToastManager.shared.error("Failed to remove player")
                        }
                    }
                }
            }
        } else {
            // Regular group: swipe-from-tee-sheet removes the player from
            // THIS round's roster only. They stay an active group member —
            // still visible under Manage Members → All Members, can be added
            // back to a later round. No server call, no allMembers mutation:
            // just deselect so the tee sheet reflects the change. The refresh
            // intersection preserves the deselection across polls. Exiting
            // the group entirely is done via Manage Members, not swipe.
            selectedIDs.remove(player.id)
        }

        // If group is now empty, remove the group
        if groups[groupIndex].isEmpty {
            groups.remove(at: groupIndex)
        }

        // Re-sync dependent arrays
        syncTeeTimes()
        let oldScorerIDs = scorerIDs
        syncScorerIDs()
        syncSelectedTees()

        // If scorer changed (because we removed the old scorer), persist to Supabase
        if oldScorerIDs != scorerIDs {
            saveScorerIds()
        }

        ToastManager.shared.success("\(player.shortName) removed")
    }

    // MARK: - Focus State (for guest entry / invite entry sheets)

    enum GMField: Hashable { case buyIn, guestName, guestHandicap, invitePhone2 }
    @FocusState private var gmFocused: GMField?

    // MARK: - Swap Picker Sheet

    private var swapPickerSheet: some View {
        VStack(spacing: 0) {
            Text("Swap Player")
                .font(.carry.labelBold)
                .foregroundColor(Color.textPrimary)
                .padding(.top, 40)
                .padding(.bottom, 6)

            if let player = pendingSwapPlayer, let destIdx = pendingSwapTo {
                Text("Group \(destIdx + 1) is full. Pick a player to swap with \(player.shortName).")
                    .font(.carry.captionLG)
                    .foregroundColor(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                // Skins Groups in everyone-scores mode treat all players
                // as equal — any of them can be swapped out. Quick Games
                // (and legacy single-scorer Skins Groups) keep the scorer
                // anchored, so the destination group's scorer is filtered
                // out of the swap-out candidates.
                let anchorScorer = isQuickGame || scoringMode != .everyone
                let destScorerId = destIdx < scorerIDs.count ? scorerIDs[destIdx] : 0
                let swapCandidates = anchorScorer
                    ? groups[destIdx].filter { $0.id != destScorerId }
                    : groups[destIdx]
                ForEach(swapCandidates) { destPlayer in
                    let destPending = destPlayer.isPendingInvite || destPlayer.isPendingAccept
                    Button {
                        guard !destPending else { return }
                        performSwap(incoming: player, outgoing: destPlayer)
                    } label: {
                        HStack(spacing: 12) {
                            PlayerAvatar(player: destPlayer, size: 36)
                                .opacity(destPending ? 0.5 : 1)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(destPlayer.isPendingInvite ? formatPhoneDisplay(destPlayer.phoneNumber) : destPlayer.name)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(destPending ? Color.textPrimary.opacity(0.5) : Color.textPrimary)
                                if destPending {
                                    Text("Pending")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color.pendingFill)
                                } else {
                                    let pops: Int = {
                                        if let tee = currentCourse?.teeBox {
                                            return tee.playingHandicap(forIndex: destPlayer.handicap, percentage: handicapPercentage)
                                        }
                                        return Int(destPlayer.handicap.rounded())
                                    }()
                                    Text(pops != 0 ? "\(formatHandicap(destPlayer.handicap)) · \(pops > 0 ? "\(pops)" : "+\(abs(pops))")" : formatHandicap(destPlayer.handicap))
                                        .font(.carry.caption)
                                        .foregroundColor(Color.textSecondary)
                                }
                            }

                            Spacer()

                            if destPending {
                                Text("Pending")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color.pendingFill)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(Color.pendingBg)
                                            .overlay(Capsule().strokeBorder(Color.pendingBorder, lineWidth: 1))
                                    )
                            } else {
                                Image(systemName: "arrow.triangle.swap")
                                    .font(.carry.bodySM)
                                    .foregroundColor(Color.borderMedium)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if destPlayer.id != swapCandidates.last?.id {
                        Rectangle()
                            .fill(Color.bgPrimary)
                            .frame(height: 1)
                            .padding(.leading, 72)
                    }
                }
            }

            Spacer()
        }
    }

    private func performSwap(incoming: Player, outgoing: Player) {
        guard let fromIdx = pendingSwapFrom, let toIdx = pendingSwapTo else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            // Remove incoming from source, add outgoing
            groups[fromIdx].removeAll { $0.id == incoming.id }
            groups[fromIdx].append(outgoing)
            // Remove outgoing from dest, add incoming
            groups[toIdx].removeAll { $0.id == outgoing.id }
            groups[toIdx].append(incoming)
            syncScorerIDs()
        }
        // Reset swap state
        showSwapPicker = false
        pendingSwapPlayer = nil
        pendingSwapFrom = nil
        pendingSwapTo = nil
    }

    // MARK: - Tee Time Picker Sheet

    // MARK: - Date Picker Sheet

    @State private var initialRoundDate = Date()

    @State private var initialScheduleMode: Int = 0
    @State private var initialRepeatMode: Int = 0
    @State private var initialSelectedDayPill: Int? = nil

    private var datePickerHasChanged: Bool {
        roundDate != initialRoundDate
        || scheduleMode != initialScheduleMode
        || repeatMode != initialRepeatMode
        || selectedDayPill != initialSelectedDayPill
    }

    /// Build a GameRecurrence from the current picker state
    private func buildRecurrence() -> GameRecurrence? {
        switch repeatMode {
        case 1:
            guard let pill = selectedDayPill else { return nil }
            return .weekly(dayOfWeek: GameRecurrence.weekday(fromPillIndex: pill))
        case 2:
            guard let pill = selectedDayPill else { return nil }
            return .biweekly(dayOfWeek: GameRecurrence.weekday(fromPillIndex: pill))
        case 3:
            let day = Calendar.current.component(.day, from: roundDate)
            return .monthly(dayOfMonth: day)
        default:
            return nil
        }
    }


    @State private var consecutiveInterval: Int = 0  // 0 = off, 8/10/12 minutes
    @State private var initialTeeTimePickerDate = Date()
    @State private var initialConsecutiveInterval: Int = 0

    private var teeTimeHasChanged: Bool {
        teeTimePickerDate != initialTeeTimePickerDate || consecutiveInterval != initialConsecutiveInterval
    }

    private var teeTimePickerSheet: some View {
        VStack(spacing: 0) {
            Text("Set Tee Time")
                .font(.carry.labelBold)
                .foregroundColor(Color.textPrimary)
                .padding(.top, 40)
                .padding(.bottom, 24)

            Spacer()

            DatePicker(
                "",
                selection: $teeTimePickerDate,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 160)
            .clipped()
            .padding(.horizontal, 40)

            // Consecutive Tee Times
            Text("Consecutive Tee Times")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color.textPrimary)
                .padding(.top, 32)
                .padding(.bottom, 16)

            HStack(spacing: 10) {
                ForEach([0, 8, 10, 12], id: \.self) { minutes in
                    Button {
                        consecutiveInterval = minutes
                    } label: {
                        Text(minutes == 0 ? "Off" : "+\(minutes) min")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(consecutiveInterval == minutes ? .white : Color.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(consecutiveInterval == minutes ? Color.textPrimary : Color.bgPrimary)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Done button
            Button {
                teeTimes[teeTimePickerGroupIndex] = teeTimePickerDate
                // Apply consecutive intervals if enabled
                if consecutiveInterval > 0 {
                    let interval = Double(consecutiveInterval) * 60
                    for i in 0..<teeTimes.count {
                        if i != teeTimePickerGroupIndex {
                            let offset = Double(i - teeTimePickerGroupIndex) * interval
                            teeTimes[i] = teeTimePickerDate.addingTimeInterval(offset)
                        }
                    }
                    teeTimesLinked = true
                } else {
                    teeTimesLinked = false
                }
                // Independent tee times may now be out of chronological order
                // — e.g. Group 2 was just set to an earlier time than Group 1.
                // Reorder all per-group parallel arrays so position 0 is
                // always the earliest tee time. No-op when already sorted,
                // so safe to call unconditionally.
                reorderGroupsByTeeTime()

                let cal = Calendar.current
                if cal.isDate(teeTimePickerDate, inSameDayAs: roundDate) {
                    roundDate = teeTimePickerDate
                }
                // Explicitly notify parent of tee time change — use the
                // NEW earliest time (position 0 after the reorder), not the
                // old first-slot time.
                onTeeTimeChanged?(teeTimes.first.flatMap { $0 })
                // Persist to `tee_times_json` so the per-cell edit survives
                // a reload. Without this, a subsequent group refresh pulls
                // stale server state back and `needsNextSchedule` flips
                // true again, causing the "Schedule Next Round" button to
                // re-appear instead of "Awaiting Invited Players…".
                syncTeeTimesToSupabase()
                showTeeTimePicker = false
                ToastManager.shared.success("Tee time updated")
            } label: {
                Text("Done")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(teeTimeHasChanged ? .white : Color.textDisabled)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 19)
                            .fill(teeTimeHasChanged ? Color.textPrimary : Color.borderSubtle)
                    )
            }
            .disabled(!teeTimeHasChanged)
            .padding(.horizontal, 24)

            Button {
                teeTimes = Array(repeating: nil, count: teeTimes.count)
                teeTimesLinked = false
                consecutiveInterval = 0
                syncTeeTimesToSupabase()
                showTeeTimePicker = false
            } label: {
                Text("Remove All Tee Times")
                    .font(.carry.bodySM)
                    .foregroundColor(Color.dividerMuted)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .onAppear {
            initialTeeTimePickerDate = teeTimePickerDate
            initialConsecutiveInterval = consecutiveInterval
        }
    }

    // MARK: - Scorer Picker Sheet

    private func scorerPickerSheet(groupIndex: Int) -> some View {
        VStack(spacing: 0) {
            Text("Assign Scorer")
                .font(.carry.labelBold)
                .foregroundColor(Color.textPrimary)
                .padding(.top, 40)
                .padding(.bottom, 6)

            Text("Pick who keeps score for Group \(groupIndex + 1).")
                .font(.carry.captionLG)
                .foregroundColor(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            if groupIndex < groups.count {
                // Only confirmed Carry users can score — guests have no profile
                // to attribute scores to, and pending users haven't accepted yet.
                // If the current group's roster has no eligible scorer, fall back
                // to the full group roster so the creator can pick someone who
                // will join later.
                let source = groups[groupIndex].isEmpty ? allAvailable : groups[groupIndex]
                let candidates = source.filter(\.canScore)
                ForEach(candidates) { player in
                    let isCurrentScorer = groupIndex < scorerIDs.count && scorerIDs[groupIndex] == player.id

                    Button {
                        // If the group is empty, add the player to it
                        if groups[groupIndex].isEmpty || !groups[groupIndex].contains(where: { $0.id == player.id }) {
                            groups[groupIndex].append(player)
                        }
                        scorerIDs[groupIndex] = player.id
                        scorerPickerItem = nil
                        saveScorerIds()
                    } label: {
                        HStack(spacing: 14) {
                            PlayerAvatar(player: player, size: 43)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.shortName)
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundColor(Color.textPrimary)
                                    .lineLimit(1)
                                let pops: Int = {
                                    if let tee = currentCourse?.teeBox {
                                        return tee.playingHandicap(forIndex: player.handicap, percentage: handicapPercentage)
                                    }
                                    return Int(player.handicap.rounded())
                                }()
                                Text(pops != 0 ? "\(formatHandicap(player.handicap)) · \(pops > 0 ? "\(pops)" : "+\(abs(pops))")" : formatHandicap(player.handicap))
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.textSecondary)
                            }

                            Spacer()

                            if isCurrentScorer {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(Color.textPrimary)
                            } else {
                                Circle()
                                    .strokeBorder(Color(hexString: "#DDDDDD"), lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    if player.id != groups[groupIndex].last?.id {
                        Rectangle()
                            .fill(Color.bgPrimary)
                            .frame(height: 1)
                            .padding(.leading, 86)
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Add Player Chip

    private var addPlayerChip: some View {
        Button {
            showAddSheet = true
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.textPrimary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    Image(systemName: "plus")
                        .font(.carry.sectionTitle)
                        .foregroundColor(Color.textPrimary)
                }
                .frame(width: 52, height: 52)

                Text("Add")
                    .font(.carry.micro)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Player Chip

    private func playerChip(_ player: Player) -> some View {
        let isSelected = selectedIDs.contains(player.id)

        return Button {
            guard isCreator else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                if isSelected {
                    selectedIDs.remove(player.id)
                } else {
                    selectedIDs.insert(player.id)
                }
            }
            regroup()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    PlayerAvatar(player: player, size: 52)
                        .opacity(isSelected ? 1 : 0.3)

                    // Checkmark — bottom-right
                    if isSelected {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                ZStack {
                                    Circle()
                                        .fill(Color(hexString: "#D4F5DC"))
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(Color.textPrimary)
                                }
                                .frame(width: 16, height: 16)
                                .offset(x: 6)
                            }
                        }
                    }
                }
                .frame(width: 52, height: 52)

                Text(player.shortName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Color.textPrimary : Color.borderMedium)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Group Card

    private let maxGroupSize = 4

    private func groupCardBorderColor(index: Int, playerCount: Int) -> Color {
        let isDragOver = dropTargetGroup == index
        if isDragOver && dragSourceGroup != index {
            let isFull = playerCount >= maxGroupSize
            return isFull
                ? Color(hexString: "#E8A820").opacity(0.5)   // amber = swap
                : Color.textPrimary.opacity(0.5)    // dark = move
        }
        return Color(hexString: "#EFEFEF")
    }

    private func groupCard(index: Int, players: [Player]) -> some View {
        let borderColor = groupCardBorderColor(index: index, playerCount: players.count)
        let borderWidth: CGFloat = dropTargetGroup == index ? 2 : 1
        let needsScorer = !groupHasValidScorer(index: index)

        return VStack(spacing: 0) {
            groupCardHeader(index: index)

            Rectangle()
                .fill(Color(hexString: "#EBEBEB"))
                .frame(height: 1)

            // Missing-scorer alert — shown when this group has no Carry user
            // assigned as scorer. Only Carry users can actually score, so a
            // group full of guests (or one whose Carry-user scorer moved to
            // another group) has no valid scorer. Tap opens the Manage
            // sheet so the creator can search or SMS-invite one.
            //
            // Skins Groups run "everyone-scores" by default — there's no
            // designated scorer to miss, so the banner would be a confusing
            // false alarm when (for example) the creator swipes themselves
            // off the sheet and only guests remain. Gate on single-scorer mode.
            //
            // Quick Games now surface this in the main CTA button text
            // (`missingScorerGroupIndex` → "Group N needs scorer"), which is
            // where the creator's thumb goes — so the pink banner would be
            // redundant. Keep the banner only for single-scorer Skins Groups.
            if needsScorer && isCreator && !isLiveRound && !roundStarted && scoringMode != .everyone && !isQuickGame {
                missingScorerBanner(forGroup: index)
            }

            ForEach(players) { player in
                // Self-swipe is only blocked for Quick Games (where swipe
                // hard-deletes from group_members). In Skins Groups swipe
                // just deselects from today's tee sheet — fully reversible
                // via the member pool, so creator self-removal is safe.
                SwipeToDeleteRow(enabled: isCreator && !isLiveRound && !roundStarted && !(isQuickGame && player.id == currentUserId)) {
                    if isQuickGame {
                        // Quick Game swipe hard-deletes — confirm first.
                        pendingQuickGameRemoval = (player, index)
                    } else {
                        // Regular group swipe is non-destructive (deselect
                        // from today's tee sheet only) — fire immediately.
                        removePlayer(player, fromGroup: index)
                    }
                } content: {
                    VStack(spacing: 0) {
                        groupPlayerRow(player: player, groupIndex: index, isLast: player.id == players.last?.id)
                    }
                    .background(.white)
                }
            }

            Spacer().frame(height: 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .overlay(
            GeometryReader { geo in
                if dropTargetGroup == index,
                   let targetIdx = dropTargetIndex,
                   dragSourceGroup == index {
                    // Measurements reflect the actual layout:
                    //   Header: Menu button frame 29 + vertical padding 14×2 = 57pt
                    //   + 1pt divider below header = 58pt to first row's top
                    //   Row: avatar 38 + vertical padding 12×2 = 62pt
                    // Previously 50 / 63 caused the drop line to sit ~8pt
                    // above where it should, visually off-register with rows.
                    let headerHeight: CGFloat = 58
                    let rowHeight: CGFloat = 62
                    let y = headerHeight + CGFloat(targetIdx) * rowHeight
                    Capsule()
                        .fill(Color(hexString: "#4A90D9"))
                        .frame(width: geo.size.width - 38, height: 2.5)
                        .position(x: geo.size.width / 2, y: y)
                }
            }
            .allowsHitTesting(false)
        )
        .applyIf(isCreator) { view in
            view.onDrop(of: [.text], delegate: GroupDropDelegate(
                groupIndex: index,
                playerCount: players.count,
                maxGroupSize: maxGroupSize,
                // "Scorers are anchored" + full-group swap sheet only
                // apply when scorers are structurally meaningful — i.e.
                // Quick Games (one scorer per tee time) or legacy Skins
                // Groups still on single-scorer mode. In everyone-scores
                // mode (default for all v1 Skins Groups), every player is
                // functionally equal and should drag freely.
                scorerAnchored: isQuickGame || scoringMode != .everyone,
                dragSourceGroup: $dragSourceGroup,
                dropTargetGroup: $dropTargetGroup,
                dropTargetIndex: $dropTargetIndex,
                dragPlayer: $dragPlayer,
                groups: $groups,
                startingSides: $startingSides,
                teeTimes: $teeTimes,
                scorerIDs: $scorerIDs,
                showSwapPicker: $showSwapPicker,
                pendingSwapPlayer: $pendingSwapPlayer,
                pendingSwapFrom: $pendingSwapFrom,
                pendingSwapTo: $pendingSwapTo,
                syncTeeTimes: syncTeeTimes,
                syncScorerIDs: syncScorerIDs,
                syncSelectedTees: syncSelectedTees
            ))
        }
    }

    // MARK: - Missing Scorer Banner
    //
    // Shown inside a group card when that group has no Carry-user scorer.
    // Layout per Figma 716:5949 — pink background, dark-red text, justified.
    // Tap routes to the appropriate Manage sheet so the creator can assign
    // a scorer via search or SMS invite.
    private func missingScorerBanner(forGroup groupIndex: Int) -> some View {
        Button {
            // Route to the same Manage sheet the "Invite & Manage" button uses.
            // Quick Game → PlayerGroupsSheet; Skins Group → ManageMembersSheet.
            if isQuickGame {
                showPlayerGroups = true
            } else {
                showManageMembers = true
            }
        } label: {
            HStack {
                Text("Tee time needs scorer")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hexString: "#AC1010"))
                Spacer()
                Text("Add Scorer")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hexString: "#AC1010"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hexString: "#FFD2D2"))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Returns true when `scorerIDs[index]` points to a real Carry user who
    /// is still in the group's player list. Guests (no `profileId`) and
    /// empty assignments both return false — they can't actually score.
    private func groupHasValidScorer(index: Int) -> Bool {
        guard index < scorerIDs.count, index < groups.count else { return false }
        let scorerId = scorerIDs[index]
        guard scorerId != 0 else { return false }
        guard let scorerPlayer = groups[index].first(where: { $0.id == scorerId }) else {
            return false
        }
        // Must be a Carry user — guests don't have a profile and can't score.
        return scorerPlayer.profileId != nil
    }

    private func groupCardHeader(index: Int) -> some View {
        HStack(spacing: 10) {
            // Left: group label / tee time
            if showTeeTimes, index < teeTimes.count, let time = teeTimes[index] {
                if isCreator && !isLiveRound {
                    Button {
                        teeTimePickerGroupIndex = index
                        teeTimePickerDate = time
                        showTeeTimePicker = true
                    } label: {
                        HStack(spacing: 5) {
                            Text(Self.teeTimeFormatter.string(from: time))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(Color.textPrimary)
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.dividerMuted)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(Self.teeTimeFormatter.string(from: time))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.textPrimary)
                }
            } else {
                Text("Group \(index + 1)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.textPrimary)
            }

            Spacer()

            // Edit / Add time button — creator only, not during live round
            if isCreator && showTeeTimes && !isLiveRound {
                Button {
                    teeTimePickerGroupIndex = index
                    teeTimePickerDate = teeTimes[index] ?? defaultFirstTeeTime()
                    showTeeTimePicker = true
                } label: {
                    if index < teeTimes.count, teeTimes[index] != nil {
                        Text("Edit")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.textSecondary)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Tee time")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(Color.textSecondary)
                    }
                }
            }

            // Move group icon — creator only
            if isCreator && groups.count > 1 {
                Menu {
                    ForEach(0..<groups.count, id: \.self) { pos in
                        if pos != index {
                            Button {
                                moveGroup(from: index, to: pos)
                            } label: {
                                Label("Position \(pos + 1)", systemImage: pos < index ? "arrow.up" : "arrow.down")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.borderMedium)
                        .frame(width: 29, height: 29)
                }
            }
        }
        .padding(.horizontal, 19)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func groupPlayerRow(player: Player, groupIndex: Int, isLast: Bool) -> some View {
        // In Quick Games, guests are physically present — treat them as active
        let showAsPending = isQuickGame
            ? (player.isPendingInvite || player.isPendingAccept)
            : (player.isPendingInvite || player.isPendingAccept || player.isGuest)
        let isPendingPlayer = showAsPending

        let pops: Int = {
            if let tee = currentCourse?.teeBox {
                return tee.playingHandicap(forIndex: player.handicap, percentage: handicapPercentage)
            }
            return Int(player.handicap.rounded())
        }()

        HStack(spacing: 12) {
            PlayerAvatar(player: player, size: 38)

            VStack(alignment: .leading, spacing: 5) {
                Text(player.isPendingInvite ? formatPhoneDisplay(player.phoneNumber) : player.shortName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.textPrimary)
                    .opacity(isPendingPlayer ? 0.7 : 1)
                    .lineLimit(1)

                Text(pops != 0 ? "\(formatHandicap(player.handicap)) · \(pops > 0 ? "\(pops)" : "+\(abs(pops))")" : formatHandicap(player.handicap))
                    .font(.system(size: 14))
                    .foregroundColor(Color.textSecondary)
                    .opacity(isPendingPlayer ? 0.7 : 1)
            }

            Spacer()

            // Invite button for guests / Pending pill for Carry users
            if isPendingPlayer {
                if player.isGuest && isCreator {
                    // Guest — show "Invite" button with link icon (Scorer pill style)
                    Button {
                        if let groupId = supabaseGroupId {
                            let link = "https://carryapp.site/invite?group=\(groupId.uuidString)"
                            inviteShareLink = "Join our skins group on Carry!\n\(link)"
                            UIPasteboard.general.string = link
                            showInviteShareSheet = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Invite")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(Color.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().strokeBorder(Color.textPrimary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else if player.isPendingAccept && !(groupIndex < scorerIDs.count && scorerIDs[groupIndex] == player.id) {
                    // Carry user who hasn't accepted yet (hidden for scorers — orange avatar + opacity is enough)
                    Text("Pending")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hexString: "#E38049"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color(hexString: "#FFE7CA"))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color(hexString: "#FFD4BE"), lineWidth: 0.88)
                        )
                }
            }



            if groupIndex < scorerIDs.count && scorerIDs[groupIndex] == player.id {
                // Hide the Scorer pill for Skins Groups when "everyone can
                // score" is on — the pill implies a restriction that doesn't
                // exist (any player can enter scores). Quick Games always
                // show it (scorer is structurally the one with the app for
                // that group). If the creator flips scoringMode back to
                // .single, the pill returns.
                let shouldShowPill = isQuickGame || scoringMode != .everyone
                if shouldShowPill {
                    let isCreatorRow = player.id == currentUserId
                    if isCreator && !isQuickGame && !isCreatorRow {
                        Button {
                            scorerPickerItem = SheetItem(id: groupIndex)
                        } label: {
                            Text("Scorer")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().strokeBorder(Color.textPrimary, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Creator's own scorer pill is locked — add a lock icon
                        // on the right to signal it can't be reassigned. The
                        // creator always scores whichever group they're in.
                        HStack(spacing: 5) {
                            Text("Scorer")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.textPrimary)
                            if isCreatorRow {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color.textPrimary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().strokeBorder(Color.textPrimary, lineWidth: 1))
                    }
                }
            }

            if isCreator {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.borderMedium)
                    .frame(width: 34, height: 34)
            }
        }
        .padding(.horizontal, 19)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .opacity(1.0)
        // Only creators can drag players between groups / reorder. Members
        // see a static tee sheet — no drag affordance, no accidental
        // rearrangement that would confuse the creator's source-of-truth.
        .applyIf(isCreator) { view in
            view.onDrag {
                dragPlayer = player
                dragSourceGroup = groupIndex
                return NSItemProvider(object: String(player.id) as NSString)
            }
        }

        if !isLast {
            Rectangle()
                .fill(Color.borderFaint)
                .frame(height: 1)
                .frame(height: 1)
                .padding(.leading, 69)
        }
    }

    // MARK: - Invite Share Card Sheet

    private var shareCardData: ShareCardData {
        let lastRound = roundHistory.last
        // Use ALL members (across all groups) for the share card
        let players = allMembers.filter { !$0.name.isEmpty }

        // Sort by winnings descending
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

        let buyIn = lastRound?.buyIn ?? (Int(buyInText) ?? 0)

        return ShareCardData(
            courseName: lastRound?.courseName ?? currentCourse?.courseName ?? groupName,
            date: lastRound?.completedAt ?? Date(),
            teeName: lastRound?.teeBox?.name,
            handicapPct: Int(handicapPercentage * 100),
            entries: entries,
            potTotal: buyIn * players.count,
            buyIn: buyIn
        )
    }

    private var inviteShareCardSheet: some View {
        VStack(spacing: 0) {
            ResultsShareCard(data: shareCardData, theme: .light, showAppStoreBadge: false)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.08), radius: 16, x: 0, y: 12)
                .shadow(color: Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.03), radius: 6, x: 0, y: 4)
                .padding(.horizontal, 6)

            // Invite copy
            VStack(spacing: 8) {
                Text("Join our skins group on Carry")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color.textPrimary)

                Text("Track your scores, see who won,\nand settle up — all in one place.")
                    .font(.system(size: 15))
                    .foregroundColor(Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.top, 24)
            .padding(.bottom, 28)

            // Copy Invite Link button
            Button {
                if let groupId = supabaseGroupId {
                    let link = "https://carryapp.site/invite?group=\(groupId.uuidString)"
                    UIPasteboard.general.string = link
                }
                showShareCardSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    ToastManager.shared.success("Invite link copied!")
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Copy Invite Link")
                        .font(.carry.bodyLGSemibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 51)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.textPrimary)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .padding(.top, 8)
    }

    // MARK: - Drop Delegate (defined below)

    // Settings sheet is extracted to GroupOptionsSheet struct for performance

    // MARK: - Leaderboard Sheet

    private var leaderboardSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leaderboard")
                        .font(Font.system(size: 24, weight: .bold))
                        .foregroundColor(Color.textPrimary)
                    let subtitle = [groupName, currentCourse?.courseName]
                        .compactMap { $0 }.joined(separator: " · ")
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Font.system(size: 16, weight: .medium))
                            .foregroundColor(Color.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .font(Font.system(size: 22, weight: .medium))
                    .foregroundColor(Color.goldMuted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 24)

            // Last Round | All Time tabs (skins groups only — quick games have a single round).
            // All Time is free for everyone — reading historical data should never be paywalled.
            if !isQuickGame {
                HStack(spacing: 16) {
                    ForEach(Array(["Last Round", "All Time"].enumerated()), id: \.offset) { idx, label in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                leaderboardTab = idx
                            }
                        } label: {
                            Text(label)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(leaderboardTab == idx ? .white : Color.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(
                                    Capsule().fill(leaderboardTab == idx ? Color.textPrimary : Color.bgPrimary)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
            }

            if roundHistory.isEmpty {
                // Empty state — no rounds played yet
                Spacer()
                VStack(spacing: 8) {
                    Text("No rounds played yet")
                        .font(Font.system(size: 17, weight: .medium))
                        .foregroundColor(Color.textSecondary)
                    Text("Stats will appear here after your first round.")
                        .font(Font.system(size: 14, weight: .medium))
                        .foregroundColor(Color.borderMedium)
                }
                Spacer()
            } else {
                // Column headers
                HStack(spacing: 0) {
                    Text("Player")
                        .font(Font.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.textSecondary)
                    Spacer()
                    Text("Skins")
                        .font(Font.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.textSecondary)
                        .frame(width: 60, alignment: .center)
                    Text("Won")
                        .font(Font.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.textSecondary)
                        .frame(width: 72, alignment: .trailing)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

                Rectangle()
                    .fill(Color.bgPrimary)
                    .frame(height: 1)
                    .padding(.horizontal, 24)

                // Player rows — filtered to winners on Last Round tab
                ScrollView {
                    VStack(spacing: 0) {
                        let visible = visibleLeaderboardPlayers
                        ForEach(Array(visible.enumerated()), id: \.element.id) { idx, player in
                            leaderboardRow(player: player)

                            if idx < visible.count - 1 {
                                Rectangle()
                                    .fill(Color.borderFaint)
                                    .frame(height: 1)
                                    .padding(.leading, 82)
                                    .padding(.trailing, 24)
                            }
                        }

                        // Inline Round Stats — Last Round tab only. Shows
                        // every active player (including those with 0 skins)
                        // so folks can see their handicap, pops and score
                        // context even when they didn't win anything.
                        if leaderboardTab == 0, let lastRound = roundHistory.last {
                            leaderboardStatsSection(lastRound: lastRound)
                        }
                    }
                }

                Spacer()
            }

        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(trigger: paywallTrigger)
        }
    }

    /// Open the paywall with a specific trigger so the sheet shows the
    /// contextual subtitle ("Starting rounds is a Premium feature" etc.).
    /// Keeps the two-step "set trigger then flip sheet flag" dance in one
    /// place so call sites don't forget to set one.
    private func presentPaywall(_ trigger: PaywallTrigger) {
        paywallTrigger = trigger
        showPaywall = true
    }

    /// Inline per-player stats block shown under the Last Round leaderboard.
    /// Deliberately omits the hole-by-hole score line (birdies/bogeys) — that
    /// would require fetching round scores which aren't cached on HomeRound.
    /// Full parity with the post-round Results screen can be added later by
    /// fetching scores when the sheet opens.
    private func leaderboardStatsSection(lastRound: HomeRound) -> some View {
        let statsPlayers = leaderboardPlayers  // all active, unfiltered
        return VStack(spacing: 0) {
            // Section separator — visually divides leaderboard from stats
            Rectangle()
                .fill(Color.bgPrimary)
                .frame(height: 8)

            Text("Stats")
                .font(Font.system(size: 24, weight: .bold))
                .foregroundColor(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(statsPlayers.enumerated()), id: \.element.id) { idx, player in
                    leaderboardStatsRow(player: player, lastRound: lastRound)

                    if idx < statsPlayers.count - 1 {
                        Rectangle()
                            .fill(Color.borderFaint)
                            .frame(height: 1)
                            .padding(.leading, 82)
                            .padding(.trailing, 24)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    /// One player's inline stats row. Layout mirrors the post-round Results
    /// screen: avatar, name + (HC · pops), skins-count + won-holes list,
    /// money on the right. Pops math falls back to rounded raw index when
    /// the tee box lacks a usable slope/rating (Quick Games, older data).
    private func leaderboardStatsRow(player: Player, lastRound: HomeRound) -> some View {
        let skins = lastRound.playerWonHoles[player.id]?.count ?? 0
        let holesWon = lastRound.playerWonHoles[player.id] ?? []
        let money = lastRound.playerWinnings[player.id] ?? 0
        let pops = leaderboardPops(handicap: player.handicap, teeBox: lastRound.teeBox)
        let hcLabel = leaderboardHandicapLabel(player.handicap)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 12) {
                PlayerAvatar(player: player, size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.shortName)
                        .font(.carry.bodySemibold)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(hcLabel) · \(pops) pops")
                        .font(.carry.bodySM)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(moneyLabel(money))
                    .font(Font.system(size: 17, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(
                        money > 0 ? Color.goldMuted
                        : money < 0 ? Color.textDisabled
                        : Color.borderSoft
                    )
                    .frame(width: 72, alignment: .trailing)
            }

            Group {
                if skins > 0 {
                    let holesList = holesWon.sorted().map { "\($0)" }.joined(separator: ", ")
                    HStack(spacing: 4) {
                        Text("\(skins) Skin\(skins == 1 ? "" : "s")")
                            .foregroundColor(Color.textSecondary)
                        Text("\u{00B7}")
                            .foregroundColor(Color.textDisabled)
                        Text("Holes \(holesList)")
                            .foregroundColor(Color.textPrimary)
                    }
                } else {
                    Text("No Skins")
                        .foregroundColor(Color.textSecondary)
                }
            }
            .font(.carry.bodySM)
            .padding(.leading, 50) // align under the name (38 avatar + 12 spacing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func leaderboardPops(handicap: Double, teeBox: TeeBox?) -> Int {
        let playingHcp: Int
        if let teeBox, teeBox.slopeRating > 0, teeBox.courseRating > 0 {
            playingHcp = teeBox.playingHandicap(
                forIndex: handicap,
                percentage: handicapPercentage
            )
        } else {
            playingHcp = Int(handicap.rounded())
        }
        return max(playingHcp, 0)
    }

    private func leaderboardHandicapLabel(_ hcp: Double) -> String {
        if hcp.sign == .minus {
            return String(format: "+%.1f", -hcp)
        }
        return String(format: "%.1f", hcp)
    }

    private func moneyLabel(_ amount: Int) -> String {
        if amount > 0 { return "$\(amount)" }
        if amount < 0 { return "-$\(-amount)" }
        return "$0"
    }

    private func leaderboardRow(player: Player) -> some View {
        HStack(spacing: 12) {
            // Avatar
            PlayerAvatar(player: player, size: 38)

            // Name + HCP
            VStack(alignment: .leading, spacing: 1) {
                Text(player.isPendingInvite ? formatPhoneDisplay(player.phoneNumber) : player.shortName)
                    .font(Font.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                if !isQuickGame && (player.isPendingInvite || player.isGuest) {
                    Text("Invited")
                        .font(Font.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.debugOrange)
                } else if player.isPendingAccept {
                    Text("Pending")
                        .font(Font.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.debugOrange)
                } else {
                    Text(formatHandicap(player.handicap))
                        .font(Font.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.borderMedium)
                }
            }

            Spacer()

            let stats = cumulativeStats[player.id] ?? (skins: 0, won: 0)

            // Skins won
            Text("\(stats.skins)")
                .font(Font.system(size: 17, weight: .medium))
                .foregroundColor(stats.skins > 0 ? Color.textPrimary : Color.textSecondary)
                .frame(width: 60, alignment: .center)

            // Winnings
            Text("$\(stats.won)")
                .font(Font.system(size: 17, weight: .medium))
                .foregroundColor(stats.won > 0 ? Color.goldMuted : Color.textSecondary)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func defaultFirstTeeTime() -> Date {
        Date()
    }

    // MARK: - Add Player Sheet

    private var addPlayerSheet: some View {
        VStack(spacing: 0) {
            Text("Add Player")
                .font(.carry.labelBold)
                .foregroundColor(Color.textPrimary)
                .padding(.top, 40)
                .padding(.bottom, 20)

            // Guest option
            Button {
                showAddSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showGuestEntry = true
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.bgPrimary)
                        Image(systemName: "person.badge.plus")
                            .font(.carry.bodyLG)
                            .foregroundColor(Color.textPrimary)
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Guest")
                            .font(.carry.body)
                            .foregroundColor(Color.textPrimary)
                        Text("Temporary player for this round")
                            .font(.carry.caption)
                            .foregroundColor(Color.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.carry.captionLG)
                        .foregroundColor(Color.borderMedium)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.bgPrimary)
                .frame(height: 1)
                .padding(.leading, 74)

            // Invite by phone option
            Button {
                showAddSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showInviteEntry = true
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.bgPrimary)
                        Image(systemName: "phone.fill")
                            .font(.carry.bodyLG)
                            .foregroundColor(Color.textPrimary)
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Invite via SMS")
                            .font(.carry.body)
                            .foregroundColor(Color.textPrimary)
                        Text("Send a link to download the app")
                            .font(.carry.caption)
                            .foregroundColor(Color.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.carry.captionLG)
                        .foregroundColor(Color.borderMedium)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Guest Entry Sheet

    private var guestEntrySheet: some View {
        VStack(spacing: 0) {
            Text("Add Guest")
                .font(.carry.labelBold)
                .foregroundColor(Color.textPrimary)
                .padding(.top, 40)
                .padding(.bottom, 24)

            VStack(spacing: 16) {
                // Name field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)
                        .padding(.leading, 4)

                    TextField("Guest name", text: $guestName)
                        .font(.carry.bodyLG)
                        .focused($gmFocused, equals: .guestName)
                        .carryInput(focused: gmFocused == .guestName)
                }

                // Index field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Index")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)
                        .padding(.leading, 4)

                    TextField("e.g. 12.4 or +1.2", text: $guestHandicap)
                        .font(.carry.bodyLG)
                        .focused($gmFocused, equals: .guestHandicap)
                        .keyboardType(.numbersAndPunctuation)
                        .onChange(of: guestHandicap) {
                            let filtered = filterHandicapInput(guestHandicap)
                            if filtered != guestHandicap {
                                DispatchQueue.main.async { guestHandicap = filtered }
                            }
                        }
                        .carryInput(focused: gmFocused == .guestHandicap)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Add button
            Button {
                addGuest()
            } label: {
                Text("Add Guest")
                    .font(.carry.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(!guestName.trimmingCharacters(in: .whitespaces).isEmpty
                                  ? Color.textPrimary
                                  : Color.borderSubtle)
                    )
            }
            .disabled(guestName.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .background(Color.bgPrimary)
    }

    // MARK: - Invite Entry Sheet

    private var inviteEntrySheet: some View {
        VStack(spacing: 0) {
            Text("Invite via SMS")
                .font(.carry.labelBold)
                .foregroundColor(Color.textPrimary)
                .padding(.top, 40)
                .padding(.bottom, 6)

            Text("They'll appear as pending until they sign up.")
                .font(.carry.captionLG)
                .foregroundColor(Color.textSecondary)
                .padding(.bottom, 24)

            if inviteSent {
                // Success state
                Spacer()

                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color(hexString: "#34C759").opacity(0.2))
                            .frame(width: 72, height: 72)
                        Image(systemName: "checkmark")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(Color.textPrimary.opacity(0.7))
                    }

                    Text("Invite Sent!")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.textPrimary)
                }
                .padding(.horizontal, 24)

                Spacer()

                Button {
                    inviteSent = false
                    invitePhone = ""
                    showInviteEntry = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showManageMembers = true
                    }
                } label: {
                    Text("Done")
                        .font(.carry.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.textPrimary))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            } else {
                // Phone input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Phone Number")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)
                        .padding(.leading, 4)

                    TextField("(555) 123-4567", text: $invitePhone)
                        .font(.carry.bodyLG)
                        .focused($gmFocused, equals: .invitePhone2)
                        .keyboardType(.phonePad)
                        .onChange(of: invitePhone) {
                            invitePhone = invitePhone.filter { $0.isNumber || $0 == "+" }
                        }
                        .carryInput(focused: gmFocused == .invitePhone2)
                }
                .padding(.horizontal, 24)

                Spacer()

                Button {
                    sendInvite()
                } label: {
                    Text("Send Invite")
                        .font(.carry.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(invitePhone.filter({ $0.isNumber }).count >= 10
                                      ? Color.textPrimary
                                      : Color.borderSubtle)
                        )
                }
                .disabled(invitePhone.filter({ $0.isNumber }).count < 10)
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
        .background(Color.bgPrimary)
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: inviteSent)
    }

    private func sendInvite() {
        let digits = invitePhone.filter { $0.isNumber }
        guard digits.count >= 10 else { return }

        let guestColors = ["#E67E22", "#9B59B6", "#1ABC9C", "#C0392B", "#2980B9", "#27AE60"]
        let colorIdx = (nextGuestID - 100) % guestColors.count

        let invited = Player(
            id: nextGuestID,
            name: "Invited",
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

        guests.append(invited)
        selectedIDs.insert(invited.id)
        nextGuestID += 1

        withAnimation {
            inviteSent = true
        }

        // Create Supabase invite record + send SMS with deep link
        if let groupId = supabaseGroupId {
            Task {
                guard let userId = try? await SupabaseManager.shared.client.auth.session.user.id else { return }
                let groupService = GroupService()
                do {
                    try await groupService.inviteMemberByPhone(groupId: groupId, phone: digits, invitedBy: userId)
                    // Open native SMS with deep link
                    let encodedLink = "https://carryapp.site/invite?group=\(groupId.uuidString)"
                    if let smsURL = URL(string: "sms:\(digits)&body=Join%20my%20skins%20game%20on%20Carry!%20\(encodedLink)") {
                        await MainActor.run { UIApplication.shared.open(smsURL) }
                    }
                } catch {
                    #if DEBUG
                    print("[Carry] Failed to create SMS invite record: \(error)")
                    #endif
                    // Still open SMS even if Supabase fails
                    let encodedLink = "https://carryapp.site/invite?group=\(groupId.uuidString)"
                    if let smsURL = URL(string: "sms:\(digits)&body=Join%20my%20skins%20game%20on%20Carry!%20\(encodedLink)") {
                        await MainActor.run { UIApplication.shared.open(smsURL) }
                    }
                }
            }
        } else {
            // No Supabase group yet — send basic SMS
            if let smsURL = URL(string: "sms:\(digits)&body=Join%20my%20skins%20game%20on%20Carry!%20Download%20here%3A%20https%3A%2F%2Fcarryapp.site") {
                UIApplication.shared.open(smsURL)
            }
        }
        #if DEBUG
        print("[Carry] Invite SMS sent to \(formatPhoneDisplay(digits))")
        #endif

        regroup()
        ToastManager.shared.success("Invite sent to \(formatPhoneDisplay(digits))")
    }

    /// Filter handicap/index input: digits + one decimal, max 1 decimal place, capped at 54.0
    /// Allows 0…54.0 or +0.1…+10.0 (plus handicap) with one decimal place.
    // Uses shared filterHandicapInput() from Player.swift

    /// Formats a phone number for display: (555) 123-4567
    private func formatPhoneDisplay(_ phone: String?) -> String {
        guard let phone = phone else { return "Invited" }
        let digits = phone.filter { $0.isNumber }
        if digits.count == 10 {
            let area = digits.prefix(3)
            let mid = digits.dropFirst(3).prefix(3)
            let last = digits.suffix(4)
            return "(\(area)) \(mid)-\(last)"
        } else if digits.count == 11 && digits.first == "1" {
            let area = digits.dropFirst(1).prefix(3)
            let mid = digits.dropFirst(4).prefix(3)
            let last = digits.suffix(4)
            return "(\(area)) \(mid)-\(last)"
        }
        return phone
    }

    // MARK: - Add Guest

    private func addGuest() {
        let trimmedName = guestName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let hcp = guestHandicap.hasPrefix("+")
            ? -(Double(String(guestHandicap.dropFirst())) ?? 0.0)
            : Double(guestHandicap) ?? 0.0
        let guestColors = ["#E67E22", "#9B59B6", "#1ABC9C", "#C0392B", "#2980B9", "#27AE60"]
        let guestAvatars = ["👤", "🎩", "🧢", "🕶️", "⛳", "🏌️"]
        let colorIdx = (nextGuestID - 100) % guestColors.count
        let avatarIdx = (nextGuestID - 100) % guestAvatars.count

        let guest = Player(
            id: nextGuestID,
            name: trimmedName,
            initials: String(trimmedName.prefix(2)).uppercased(),
            color: guestColors[colorIdx],
            handicap: hcp,
            avatar: guestAvatars[avatarIdx],
            group: 1,
            ghinNumber: nil,
            venmoUsername: nil
        )

        guests.append(guest)
        selectedIDs.insert(guest.id)
        nextGuestID += 1

        // Reset form
        guestName = ""
        guestHandicap = ""
        showGuestEntry = false

        regroup()
        ToastManager.shared.success("\(guest.name) added to \(groupName)")
    }

    // MARK: - Move Group (reorder)

    private func moveGroup(from source: Int, to target: Int) {
        guard source != target, source < groups.count, target < groups.count else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            let group = groups.remove(at: source)
            groups.insert(group, at: target)

            let side = startingSides.remove(at: source)
            startingSides.insert(side, at: target)

            let teeTime = teeTimes.remove(at: source)
            teeTimes.insert(teeTime, at: target)

            let scorer = scorerIDs.remove(at: source)
            scorerIDs.insert(scorer, at: target)

            let tee = selectedTees.remove(at: source)
            selectedTees.insert(tee, at: target)
        }
    }

    // MARK: - Reorder Groups by Tee Time
    //
    // When a creator edits an individual group's tee time and breaks the
    // consecutive-interval pattern (independent tee times), the displayed
    // group order can fall out of chronological order — e.g. Group 2 now
    // has an earlier tee time than Group 1. This helper reorders ALL
    // per-group parallel arrays (groups, teeTimes, scorerIDs, startingSides,
    // selectedTees) together so that position 0 is always the earliest tee
    // time. Groups without a tee time (nil) sort to the end; ties preserve
    // their prior order for stability. "Group N" labels are derived from
    // position, so they update automatically.
    private func reorderGroupsByTeeTime() {
        let n = groups.count
        guard n > 1, teeTimes.count == n else { return }

        let currentOrder = Array(0..<n)
        let sortedOrder = currentOrder.sorted { a, b in
            switch (teeTimes[a], teeTimes[b]) {
            case (nil, nil): return a < b            // stable for nil/nil ties
            case (nil, _):   return false            // nil goes last
            case (_, nil):   return true             // nil goes last
            case (let ta?, let tb?):
                if ta == tb { return a < b }         // stable for time ties
                return ta < tb
            }
        }
        guard sortedOrder != currentOrder else { return }

        // Apply the permutation to every per-group parallel array in lock-step.
        withAnimation(.easeOut(duration: 0.2)) {
            groups = sortedOrder.map { groups[$0] }
            teeTimes = sortedOrder.map { teeTimes[$0] }
            if scorerIDs.count == n {
                scorerIDs = sortedOrder.map { scorerIDs[$0] }
                // Persist the new scorer order + stamp the grace window so a
                // poll landing before the server write ack doesn't stomp the
                // reorder with the old scorer-to-group mapping.
                saveScorerIds()
            }
            if startingSides.count == n { startingSides = sortedOrder.map { startingSides[$0] } }
            if selectedTees.count == n { selectedTees = sortedOrder.map { selectedTees[$0] } }
        }
    }

    // MARK: - Sync Player Order to Supabase

    private func syncPlayerOrderToSupabase() {
        guard let groupId = supabaseGroupId else { return }
        var order: [(playerId: UUID, sortOrder: Int)] = []
        var index = 0
        for group in groups {
            for player in group {
                if let profileId = player.profileId {
                    order.append((playerId: profileId, sortOrder: index))
                }
                index += 1
            }
        }
        Task {
            do {
                try await GroupService().savePlayerOrder(groupId: groupId, order: order)
            } catch {
                #if DEBUG
                print("[GroupManager] Failed to sync player order: \(error)")
                #endif
            }
        }
    }

    /// Persist group_num assignments to Supabase (Quick Games only).
    private func syncTeeTimesToSupabase() {
        // Only the creator owns tee-time edits. Members observe the array
        // via refresh but must not write it back (RLS would reject anyway,
        // but this saves a round trip).
        guard isCreator, let groupId = supabaseGroupId else { return }
        let snapshot = teeTimes
        Task {
            do {
                try await GroupService().saveTeeTimes(groupId: groupId, teeTimes: snapshot)
            } catch {
                #if DEBUG
                print("[GroupManager] Failed to sync tee times: \(error)")
                #endif
            }
        }
    }

    private func syncGroupNumsToSupabase() {
        guard let groupId = supabaseGroupId else { return }
        var assignments: [(playerId: UUID, groupNum: Int)] = []
        for (gi, group) in groups.enumerated() {
            for player in group {
                if let profileId = player.profileId {
                    assignments.append((playerId: profileId, groupNum: gi + 1))
                }
            }
        }
        Task {
            do {
                try await GroupService().saveGroupNums(groupId: groupId, assignments: assignments)
                // Keep round_players in lockstep so active/concluded-round
                // scorecards reflect tee-time rearrangements (e.g. after
                // reorderGroupsByTeeTime swaps groups).
                try? await RoundService().syncRoundPlayersGroupNums(
                    groupId: groupId,
                    assignments: assignments
                )
            } catch {
                #if DEBUG
                print("[GroupManager] Failed to sync group nums: \(error)")
                #endif
            }
        }
    }
}

// MARK: - Empty Slot Row (isolated for typing performance)

// MARK: - Group Options Sheet (extracted for performance)

struct GroupOptionsSheet: View {
    @EnvironmentObject var storeService: StoreService
    // All plain values — no @Binding to parent
    let isCreator: Bool
    let isLiveRound: Bool
    let isQuickGame: Bool
    let onCancel: () -> Void
    let onSave: (GroupOptionsResult) -> Void
    let onLeaveGroup: (() -> Void)?
    let onDeleteGroup: (() -> Void)?

    struct GroupOptionsResult {
        let groupName: String
        let carriesEnabled: Bool
        let scoringMode: ScoringMode
        let handicapPercentage: Double
        let buyInText: String
        let teeTime: Date?
        let changedCourse: SelectedCourse?
        let recurrence: GameRecurrence?
        let clearRecurrence: Bool
        let winningsDisplay: String
    }

    // All local state
    @State private var localGroupName: String
    @State private var localTeeTime: Date?
    @State private var localCarries: Bool
    @State private var localScoringMode: ScoringMode
    @State private var localWinningsDisplay: String
    @State private var localHandicap: Double
    @State private var localBuyIn: String
    @State private var showCarriesInfo = false
    @State private var showLeaveDeleteConfirm = false
    @State private var showPaywall = false
    @State private var localCourse: SelectedCourse?
    @State private var showCourseSelector = false
    @State private var showOptTeeTimePicker = false
    @State private var optScheduleMode: Int = 0  // 0=Single, 1=Recurring
    @State private var optRepeatMode: Int = 0    // 0=Weekly, 1=Biweekly, 2=Monthly
    @State private var optSelectedDay: Int? = nil // pill index 0=Mon..6=Sun
    @State private var optScheduleDate: Date = Date()
    @FocusState private var sheetFocused: Bool
    private static let optDayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    init(
        isCreator: Bool,
        isLiveRound: Bool = false,
        isQuickGame: Bool = false,
        groupName: String,
        carriesEnabled: Bool,
        scoringMode: ScoringMode = .single,
        winningsDisplay: String = "gross",
        handicapPercentage: Double,
        buyInText: String,
        teeTime: Date?,
        currentCourse: SelectedCourse?,
        recurrence: GameRecurrence? = nil,
        onCancel: @escaping () -> Void,
        onSave: @escaping (GroupOptionsResult) -> Void,
        onLeaveGroup: (() -> Void)?,
        onDeleteGroup: (() -> Void)?
    ) {
        self.isCreator = isCreator
        self.isLiveRound = isLiveRound
        self.isQuickGame = isQuickGame
        self.onCancel = onCancel
        self.onSave = onSave
        self.onLeaveGroup = onLeaveGroup
        self.onDeleteGroup = onDeleteGroup
        _localGroupName = State(initialValue: groupName)
        _localCarries = State(initialValue: carriesEnabled)
        _localScoringMode = State(initialValue: scoringMode)
        _localWinningsDisplay = State(initialValue: winningsDisplay)
        _localHandicap = State(initialValue: handicapPercentage)
        _localBuyIn = State(initialValue: buyInText)
        _localTeeTime = State(initialValue: teeTime)
        _localCourse = State(initialValue: currentCourse)
        _optScheduleDate = State(initialValue: teeTime ?? Date())
        // Pre-fill schedule from recurrence
        if let rec = recurrence {
            _optScheduleMode = State(initialValue: 1)
            switch rec {
            case .weekly(let d):
                _optRepeatMode = State(initialValue: 0)
                _optSelectedDay = State(initialValue: GameRecurrence.pillIndex(fromWeekday: d))
            case .biweekly(let d):
                _optRepeatMode = State(initialValue: 1)
                _optSelectedDay = State(initialValue: GameRecurrence.pillIndex(fromWeekday: d))
            case .monthly:
                _optRepeatMode = State(initialValue: 2)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with Cancel + Title + Save
                ZStack {
                    Text("Game Options")
                        .font(.carry.headline)
                        .foregroundColor(Color.textPrimary)

                    HStack {
                        Button {
                            onCancel()
                        } label: {
                            Text("Cancel")
                                .font(.carry.body)
                                .foregroundColor(Color.textTertiary)
                        }
                        Spacer()
                        // Non-premium creators can tap fields and explore,
                        // but Save routes through the paywall instead of
                        // persisting — keeps the group data model clean and
                        // surfaces the upgrade at the moment of intent.
                        Button {
                            if isCreator && !storeService.isPremium {
                                showPaywall = true
                                return
                            }
                            let rec: GameRecurrence? = {
                                guard optScheduleMode == 1 else { return nil }
                                switch optRepeatMode {
                                case 0:
                                    guard let pill = optSelectedDay else { return nil }
                                    return .weekly(dayOfWeek: GameRecurrence.weekday(fromPillIndex: pill))
                                case 1:
                                    guard let pill = optSelectedDay else { return nil }
                                    return .biweekly(dayOfWeek: GameRecurrence.weekday(fromPillIndex: pill))
                                case 2:
                                    let day = Calendar.current.component(.day, from: optScheduleDate)
                                    return .monthly(dayOfMonth: day)
                                default: return nil
                                }
                            }()
                            onSave(GroupOptionsResult(
                                groupName: localGroupName,
                                carriesEnabled: localCarries,
                                scoringMode: localScoringMode,
                                handicapPercentage: localHandicap,
                                buyInText: localBuyIn,
                                teeTime: optScheduleDate,
                                changedCourse: localCourse,
                                recurrence: rec,
                                clearRecurrence: optScheduleMode == 0,
                                winningsDisplay: localWinningsDisplay
                            ))
                        } label: {
                            HStack(spacing: 5) {
                                Text("Save")
                                    .font(.carry.bodySemibold)
                                    .foregroundColor(Color.textPrimary)
                                if isCreator && !storeService.isPremium {
                                    Image("premium-crown")
                                        .resizable()
                                        .renderingMode(.template)
                                        .scaledToFit()
                                        .frame(width: 11, height: 11)
                                        .foregroundColor(Color.goldAccent)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 20)

                if isCreator {
                    creatorContent
                } else {
                    memberContent
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { sheetFocused = false }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { sheetFocused = false }
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showPaywall) {
                PaywallView(trigger: .manageGroup)
                    .environmentObject(storeService)
            }
        }
    }

    // MARK: - Member

    private var memberContent: some View {
        VStack(spacing: 0) {
            // Leave Group (hidden for quick games)
            if !isQuickGame, let leave = onLeaveGroup {
                Button {
                    leave()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Leave Group")
                                .font(.carry.bodyLG)
                                .foregroundColor(Color.textPrimary)
                            Text("You'll be removed from this game")
                                .font(.carry.captionLG)
                                .foregroundColor(Color.textSecondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }

            Spacer()
        }
    }

    // MARK: - Creator

    private var creatorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Premium banner — surfaces above all editable fields when a
                // non-premium creator opens the sheet. Tap jumps straight to
                // the paywall so they don't have to fiddle then be blocked.
                // Delete Group below is intentionally OUTSIDE this gated
                // section and stays accessible.
                if !storeService.isPremium {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack(spacing: 10) {
                            Image("premium-crown")
                                .resizable()
                                .renderingMode(.template)
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .foregroundColor(Color.goldAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Editing requires Premium")
                                    .font(.carry.bodySMBold)
                                    .foregroundColor(Color.textPrimary)
                                Text("Upgrade to change group settings")
                                    .font(.carry.caption)
                                    .foregroundColor(Color.textSecondary)
                            }
                            Spacer()
                            Text("Upgrade")
                                .font(.carry.captionLG)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.goldAccent))
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.bgSecondary)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .accessibilityLabel("Upgrade to Premium to edit group settings")
                }

                // Group Name (hidden for quick games)
                if !isQuickGame {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Group Name")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)
                        .padding(.leading, 4)
                    TextField("Friday Skins", text: $localGroupName)
                        .font(.carry.bodyLG)
                        .focused($sheetFocused)
                        .carryInput(focused: sheetFocused)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                }

                // Tee Time / Schedule
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Tee Time")
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.textPrimary)
                        Text("Tee times can be updated")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.textSecondary)
                    }
                    .padding(.leading, 4)

                    Button {
                        showOptTeeTimePicker = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                let df = DateFormatter()
                                Text({
                                    df.dateFormat = "EEE, MMM d · h:mm a"
                                    return df.string(from: optScheduleDate)
                                }())
                                    .font(.carry.bodyLG)
                                    .foregroundColor(Color.textPrimary)

                                if optScheduleMode == 1 {
                                    let freqLabel = optRepeatMode == 0 ? "Weekly" : optRepeatMode == 1 ? "Every 2 weeks" : "Monthly"
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
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.borderLight, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .sheet(isPresented: $showOptTeeTimePicker) {
                    if isQuickGame {
                        // Quick game: simple date/time picker, no recurrence
                        VStack(spacing: 0) {
                            Text("Set Tee Time")
                                .font(.carry.labelBold)
                                .foregroundColor(Color.textPrimary)
                                .padding(.top, 40)
                                .padding(.bottom, 24)
                            Spacer()
                            DatePicker("", selection: $optScheduleDate, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(height: 160)
                                .clipped()
                                .padding(.horizontal, 40)
                            Spacer()
                            Button {
                                showOptTeeTimePicker = false
                            } label: {
                                Text("Set Tee Time")
                                    .font(.carry.sectionTitle)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .background(RoundedRectangle(cornerRadius: 19).fill(Color.textPrimary))
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                        }
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                    } else {
                        TeeTimePickerSheet(
                            scheduleMode: $optScheduleMode,
                            selectedDate: $optScheduleDate,
                            repeatMode: $optRepeatMode,
                            selectedDayPill: $optSelectedDay,
                            onSet: { showOptTeeTimePicker = false },
                            onCancel: { showOptTeeTimePicker = false }
                        )
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                        .presentationBackground(.white)
                    }
                }

                // Course
                VStack(alignment: .leading, spacing: 8) {
                    Text("Course")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)
                        .padding(.leading, 4)

                    Button {
                        guard !isLiveRound else { return }
                        showCourseSelector = true
                    } label: {
                        if let course = localCourse {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(course.courseName)
                                        .font(.carry.bodySemibold)
                                        .foregroundColor(Color.textPrimary)
                                    if let tee = course.teeBox {
                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill(Color(hexString: tee.color))
                                                .frame(width: 6, height: 6)
                                            Text(tee.name)
                                                .font(.carry.caption)
                                                .foregroundColor(Color.textSecondary)
                                            Text("·")
                                                .foregroundColor(Color.textDisabled)
                                            Text(String(format: "%.1f / %d", tee.courseRating, tee.slopeRating))
                                                .font(.carry.caption)
                                                .foregroundColor(Color.textSecondary)
                                        }
                                    }
                                }
                                Spacer()
                                Text(isLiveRound ? "Locked" : "Change")
                                    .font(.carry.bodySM)
                                    .foregroundColor(Color.textTertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.borderLight, lineWidth: 1)
                            )
                        } else {
                            HStack {
                                Text("Select a course")
                                    .font(.carry.bodyLG)
                                    .foregroundColor(Color.textDisabled)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color.borderMedium)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.borderLight, lineWidth: 1)
                            )
                        }
                    }
                    .buttonStyle(.plain)

                    // Handicap Allowance (only when course is selected)
                    if localCourse != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Handicap Allowance")
                                    .font(.carry.bodySMBold)
                                    .foregroundColor(Color.textPrimary)
                                if isQuickGame && !storeService.isPremium {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color.textDisabled)
                                }
                                Spacer()
                                Text("\(Int(localHandicap * 100))%")
                                    .font(.carry.captionLGSemibold)
                                    .foregroundColor(Color.textPrimary)
                            }
                            if isQuickGame && !storeService.isPremium {
                                HStack(spacing: 4) {
                                    Image("premium-crown")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 11)
                                        .foregroundColor(Color.goldDark)
                                    Text("Premium feature")
                                        .font(.carry.caption)
                                        .foregroundColor(Color.textDisabled)
                                }
                            } else if isLiveRound {
                                Text("Locked during active round")
                                    .font(.carry.caption)
                                    .foregroundColor(Color.textDisabled)
                            }
                            Slider(value: $localHandicap, in: 0.1...1.0, step: 0.05)
                                .tint(Color.textPrimary)
                                .disabled(isLiveRound || (isQuickGame && !storeService.isPremium))
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 12)
                        .opacity(isLiveRound ? 0.5 : 1)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .sheet(isPresented: $showCourseSelector) {
                    CourseSelectionView { course in
                        localCourse = course
                        showCourseSelector = false
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.white)
                }

                // Buy-In per Player
                VStack(alignment: .leading, spacing: 6) {
                    Text("Buy-In per Player")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)
                        .padding(.leading, 4)

                    VStack(spacing: 8) {
                        HStack {
                            Text("$\(Int(Double(localBuyIn) ?? 0))")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(Color.textPrimary)
                            Spacer()
                        }
                        Slider(
                            value: Binding(
                                get: { Double(localBuyIn) ?? 0 },
                                set: { localBuyIn = "\(Int($0))" }
                            ),
                            in: 0...500,
                            step: 5
                        )
                        .tint(Color.goldAccent)
                        .disabled(isLiveRound)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.borderLight, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .opacity(isLiveRound ? 0.5 : 1)

                // Carries
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Carries")
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.textPrimary)
                        if isQuickGame && !storeService.isPremium {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color.textDisabled)
                        }
                    }
                    .padding(.leading, 4)

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Skins carry to the next hole")
                                .font(.carry.bodySM)
                                .foregroundColor(Color.textPrimary)
                            if isQuickGame && !storeService.isPremium {
                                HStack(spacing: 4) {
                                    Image("premium-crown")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 11)
                                        .foregroundColor(Color.goldDark)
                                    Text("Premium feature")
                                        .font(.carry.caption)
                                        .foregroundColor(Color.textDisabled)
                                }
                            } else if isLiveRound {
                                Text("Locked during active round")
                                    .font(.carry.caption)
                                    .foregroundColor(Color.textDisabled)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: $localCarries)
                            .labelsHidden()
                            .tint(Color.textPrimary)
                            .disabled(isLiveRound || (isQuickGame && !storeService.isPremium))
                    }
                    .padding(.leading, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .opacity(isLiveRound ? 0.5 : 1)
                .alert("What are Carries?", isPresented: $showCarriesInfo) {
                    Button("Got it", role: .cancel) {}
                } message: {
                    Text("When no one wins a hole outright, the skin carries over and adds to the next hole's value. The next outright winner takes all accumulated skins.\n\nWhen off, tied holes are dead — no carryover.")
                }

                // Scoring Mode (hidden for launch — we're shipping with
                // "everyone can score" as the only Skins Group model. Quick
                // Games still use single-scorer structurally. Leaving the
                // underlying enum + state in place so the toggle can return
                // later without a migration, but the UI is gone for v1.
                if false, !isQuickGame {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Everyone Can Score")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)
                        .padding(.leading, 4)

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Any player can enter and verify scores")
                                .font(.carry.bodySM)
                                .foregroundColor(Color.textPrimary)
                            if isLiveRound {
                                Text("Locked during active round")
                                    .font(.carry.caption)
                                    .foregroundColor(Color.textDisabled)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { localScoringMode == .everyone },
                            set: { localScoringMode = $0 ? .everyone : .single }
                        ))
                            .labelsHidden()
                            .tint(Color.textPrimary)
                            .disabled(isLiveRound)
                    }
                    .padding(.leading, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .opacity(isLiveRound ? 0.5 : 1)
                }

                // Winnings Display (Gross / Net)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Winnings Display")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)
                        .padding(.leading, 4)

                    Picker("", selection: $localWinningsDisplay) {
                        Text("Gross").tag("gross")
                        Text("Net").tag("net")
                    }
                    .pickerStyle(.segmented)
                    .disabled(isLiveRound)

                    Text(isLiveRound
                         ? "Locked during active round"
                         : (localWinningsDisplay == "net"
                            ? "Shows profit/loss after subtracting buy-in"
                            : "Shows total skins won (never negative)"))
                        .font(.carry.caption)
                        .foregroundColor(isLiveRound ? Color.textDisabled : Color.textSecondary)
                        .padding(.leading, 4)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .opacity(isLiveRound ? 0.5 : 1)

                // Delete Group / Game
                if let delete = onDeleteGroup {
                    Button {
                        delete()
                    } label: {
                        Text(isQuickGame ? "Delete Game" : "Delete Group")
                            .font(.carry.bodySMBold)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }

                Spacer().frame(height: 40)
            }
        }
    }


    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(Color.bgPrimary)
            .frame(height: 1)
            .padding(.horizontal, 20)
    }

    private func row<Trailing: View>(title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.carry.bodyLG)
                    .foregroundColor(Color.textPrimary)
                Text(subtitle)
                    .font(.carry.captionLG)
                    .foregroundColor(Color.textSecondary)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

}

// MARK: - Group Drop Delegate

struct GroupDropDelegate: DropDelegate {
    let groupIndex: Int
    let playerCount: Int
    let maxGroupSize: Int
    /// When true, scorers can't be dragged between groups and full-group
    /// drops trigger the swap picker. When false, all players are
    /// interchangeable — any drag lands freely, full groups reject drops
    /// with a toast (no swap UI). v1 Skins Groups use everyone-scores so
    /// this is false; Quick Games still have structural scorers.
    let scorerAnchored: Bool
    @Binding var dragSourceGroup: Int?
    @Binding var dropTargetGroup: Int?
    @Binding var dropTargetIndex: Int?
    @Binding var dragPlayer: Player?
    @Binding var groups: [[Player]]
    @Binding var startingSides: [String]
    @Binding var teeTimes: [Date?]
    @Binding var scorerIDs: [Int]
    @Binding var showSwapPicker: Bool
    @Binding var pendingSwapPlayer: Player?
    @Binding var pendingSwapFrom: Int?
    @Binding var pendingSwapTo: Int?
    let syncTeeTimes: () -> Void
    let syncScorerIDs: () -> Void
    let syncSelectedTees: () -> Void

    // Layout constants for drop position calculation
    private let headerHeight: CGFloat = 41
    private let rowHeight: CGFloat = 49

    func dropEntered(info: DropInfo) {
        withAnimation(.easeOut(duration: 0.15)) {
            dropTargetGroup = groupIndex
        }
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeOut(duration: 0.15)) {
            if dropTargetGroup == groupIndex {
                dropTargetGroup = nil
                dropTargetIndex = nil
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Calculate target row index for same-group reorder
        if dragSourceGroup == groupIndex {
            let y = info.location.y - headerHeight
            let idx = max(0, min(groups[groupIndex].count, Int(round(y / rowHeight))))
            withAnimation(.easeOut(duration: 0.1)) {
                dropTargetIndex = idx
            }
        } else {
            dropTargetIndex = nil
        }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let player = dragPlayer, let sourceGroup = dragSourceGroup else {
            resetDrag()
            return false
        }

        // Same group — reorder to drop position
        if sourceGroup == groupIndex {
            withAnimation(.easeOut(duration: 0.2)) {
                if let sourceIdx = groups[sourceGroup].firstIndex(where: { $0.id == player.id }) {
                    // Calculate target from drop position
                    let y = info.location.y - headerHeight
                    var targetIdx = max(0, min(groups[groupIndex].count, Int(round(y / rowHeight))))

                    let p = groups[sourceGroup].remove(at: sourceIdx)
                    // Adjust target since removal shifted indices
                    if targetIdx > sourceIdx { targetIdx -= 1 }
                    targetIdx = max(0, min(targetIdx, groups[sourceGroup].count))
                    groups[sourceGroup].insert(p, at: targetIdx)
                }
            }
            resetDrag()
            return true
        }

        // Scorer anchoring — only applies when scorers are structurally
        // meaningful (Quick Games, or legacy single-scorer Skins Groups).
        // In everyone-scores mode (v1 default) every player is equal and
        // can move freely between groups.
        if scorerAnchored,
           sourceGroup < scorerIDs.count,
           scorerIDs[sourceGroup] == player.id {
            ToastManager.shared.error("Scorers are anchored — change scorers in Manage Members.")
            resetDrag()
            return false
        }

        // Single-player source drags are allowed — the not-full path
        // below collapses the emptied source group via
        // `groups.removeAll { $0.isEmpty }` and re-syncs parallel arrays.

        // Full-group handling — open the swap picker so the user
        // explicitly chooses who to bump out. The picker itself filters
        // candidates based on `scorerAnchored`: Skins Groups (everyone
        // equal) show all players, Quick Games exclude the anchored
        // scorer from the swap-out list.
        if playerCount >= maxGroupSize {
            pendingSwapPlayer = player
            pendingSwapFrom = sourceGroup
            pendingSwapTo = groupIndex
            showSwapPicker = true
            resetDrag()
            return true
        }

        // Not full — move directly
        withAnimation(.easeOut(duration: 0.2)) {
            groups[sourceGroup].removeAll { $0.id == player.id }
            groups[groupIndex].append(player)

            // Remove empty groups
            groups.removeAll { $0.isEmpty }

            // Sync arrays
            while startingSides.count < groups.count {
                startingSides.append(startingSides.count % 2 == 0 ? "front" : "back")
            }
            while startingSides.count > groups.count {
                startingSides.removeLast()
            }
            syncTeeTimes()
            syncScorerIDs()
            syncSelectedTees()
        }
        resetDrag()
        return true
    }

    private func resetDrag() {
        dragPlayer = nil
        dragSourceGroup = nil
        dropTargetGroup = nil
        dropTargetIndex = nil
    }
}

// MARK: - Swipe-to-Delete Row Wrapper

/// Custom swipe-to-reveal-delete row. Works alongside drag-and-drop (no List required).
private struct SwipeToDeleteRow<Content: View>: View {
    let enabled: Bool
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var isRevealed = false

    private let deleteWidth: CGFloat = 80
    private let triggerThreshold: CGFloat = 60

    var body: some View {
        if enabled {
            ZStack(alignment: .trailing) {
                // Delete button behind the row — only rendered while the row
                // is revealed or actively swiping. Previously it sat behind
                // every row full-time; when the user picked a row up via
                // onDrag, SwiftUI lifts the content view off its slot and the
                // trash button briefly showed through as a red flash on drop.
                if isRevealed || offset < 0 {
                HStack {
                    Spacer()
                    Button {
                        // Collapse the swipe state immediately. The parent
                        // owns whether the row actually goes away (regular
                        // groups remove from the list; Quick Games confirm
                        // first and may cancel). Previously we slid the row
                        // off-screen before calling onDelete, which left the
                        // cell stuck at offset=-500 when a Quick Game cancel
                        // kept the player in place. Resetting to 0 on tap
                        // avoids that stuck state and lets ForEach's natural
                        // transition handle the disappearance on real delete.
                        withAnimation(.easeInOut(duration: 0.2)) {
                            offset = 0
                            isRevealed = false
                        }
                        onDelete()
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 52, height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(hexString: "#D94444"))
                            )
                    }
                    .frame(width: deleteWidth)
                    .frame(maxHeight: .infinity)
                }
                }

                // Main content — slides left on drag
                content()
                    .offset(x: offset)
                    .gesture(
                        DragGesture(minimumDistance: 20, coordinateSpace: .local)
                            .onChanged { value in
                                let horizontal = value.translation.width
                                // Only allow left swipe
                                if horizontal < 0 {
                                    offset = isRevealed
                                        ? max(-deleteWidth + horizontal, -deleteWidth * 1.3)
                                        : max(horizontal, -deleteWidth * 1.3)
                                } else if isRevealed {
                                    offset = min(-deleteWidth + horizontal, 0)
                                }
                            }
                            .onEnded { value in
                                let horizontal = value.translation.width
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if isRevealed {
                                        // If revealed and swiped right, close
                                        if horizontal > triggerThreshold / 2 {
                                            offset = 0
                                            isRevealed = false
                                        } else {
                                            offset = -deleteWidth
                                        }
                                    } else {
                                        // If swiped left past threshold, reveal
                                        if -horizontal > triggerThreshold {
                                            offset = -deleteWidth
                                            isRevealed = true
                                        } else {
                                            offset = 0
                                        }
                                    }
                                }
                            }
                    )
            }
            .clipped()
        } else {
            content()
        }
    }
}

// MARK: - Group Invite QR Code

/// Canonical invite-link builder. Same URL shape as the Copy Link / SMS /
/// Share Sheet flows — Universal Link opens the app for installed users,
/// falls through to `invite.html` → App Store for non-installed users.
enum GroupInviteLink {
    static func url(for groupId: UUID) -> URL {
        URL(string: "https://carryapp.site/invite?group=\(groupId.uuidString)")!
    }
}

/// Pure QR-code rasterizer. Returns a pixel-perfect UIImage at the requested
/// scale. Uses CoreImage's `CIQRCodeGenerator` with medium error correction
/// (good balance of compactness and scan tolerance) and optional tinting
/// via `CIFalseColor` so the code can match brand colors.
enum QRCodeGenerator {
    /// Shared CIContext — creating one per call is hundreds of ms of cold-start
    /// overhead and was causing the QR sheet to feel laggy on present. A single
    /// global instance is the standard CoreImage pattern.
    private static let ciContext = CIContext()

    /// In-memory cache keyed on (payload, scale, fg, bg) so repeated body
    /// re-evaluations for the same QR don't re-rasterize. SwiftUI calls the
    /// view's body multiple times during layout/animation.
    private static var cache: [String: UIImage] = [:]

    /// - Parameters:
    ///   - string: the payload to encode (URL string, text, etc.)
    ///   - scale: pixel multiplier per QR module (10 is crisp at 240pt display size)
    ///   - foreground: color of the dark modules (default black)
    ///   - background: color of the light modules / quiet zone (default white)
    static func image(
        for string: String,
        scale: CGFloat = 10,
        foreground: UIColor = .black,
        background: UIColor = .white
    ) -> UIImage? {
        let cacheKey = "\(string)|\(scale)|\(foreground.cgColor.components ?? [])|\(background.cgColor.components ?? [])"
        if let cached = cache[cacheKey] { return cached }

        guard let data = string.data(using: .utf8) else { return nil }
        let generator = CIFilter(name: "CIQRCodeGenerator")
        generator?.setValue(data, forKey: "inputMessage")
        generator?.setValue("M", forKey: "inputCorrectionLevel")
        guard let raw = generator?.outputImage else { return nil }

        let scaled = raw.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Tint via CIFalseColor: black → foreground, white → background.
        let tint = CIFilter(name: "CIFalseColor")
        tint?.setValue(scaled, forKey: "inputImage")
        tint?.setValue(CIColor(color: foreground), forKey: "inputColor0")
        tint?.setValue(CIColor(color: background), forKey: "inputColor1")
        guard let tinted = tint?.outputImage else { return nil }

        guard let cgImage = ciContext.createCGImage(tinted, from: tinted.extent) else {
            return nil
        }
        let image = UIImage(cgImage: cgImage)
        cache[cacheKey] = image
        return image
    }
}

/// Reusable QR code view. Renders any string as a scannable square.
/// Uses `.interpolation(.none)` to keep the modules pixel-sharp when scaled.
struct QRCodeView: View {
    let string: String
    var size: CGFloat = 240
    var foreground: UIColor = .black
    var background: UIColor = .white

    var body: some View {
        if let image = QRCodeGenerator.image(
            for: string,
            foreground: foreground,
            background: background
        ) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel("QR code")
                .accessibilityHint("Scan to open in Carry")
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.borderSubtle)
                .frame(width: size, height: size)
                .overlay(
                    Text("QR unavailable")
                        .font(.carry.bodySM)
                        .foregroundColor(Color.textSecondary)
                )
        }
    }
}

// MARK: - Group Invite QR Sheet

/// Bottom sheet that displays a scannable QR code for joining a group.
/// The QR encodes the same Universal Link the Copy Link / Share Sheet
/// flows use, so scanning it opens Carry directly for installed users
/// (and falls through to the App Store page for non-installed users).
///
/// Layout per Figma `1222:35728`: light-green rounded card with the Carry
/// brand mark on top, a 282pt dark-green QR below, 41pt gap. No title, no
/// group name — the brand + QR carry the moment. Users dismiss by swiping
/// the sheet down (drag indicator visible).
struct GroupInviteQRSheet: View {
    let groupId: UUID

    var body: some View {
        VStack(spacing: 41) {
            Image("carry-logo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 128.669, height: 90.137)
                .foregroundColor(Color.successGreen)
                .accessibilityLabel("Carry")

            QRCodeView(
                string: GroupInviteLink.url(for: groupId).absoluteString,
                size: 282,
                foreground: UIColor(Color.successGreen),
                background: UIColor(Color.successBgLight)
            )
        }
        .padding(.top, 55)
        .padding(.bottom, 32)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 38).fill(Color.successBgLight)
        )
        .padding(19)
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Group Invite QR") {
    GroupInviteQRSheet(groupId: UUID())
        .presentationDetents([.large])
}
#endif

/// Fullscreen QR — triggered by shake-phone inside a group detail (Release
/// only). Designed for the "multiple people crowd around my phone to scan"
/// moment: Carry-branded light-green surface with the full-size QR centered,
/// tap-anywhere to dismiss. No group name or "Scan to Join" text — the
/// brand + QR do the job. Matches Figma node 1171:9486.
struct FullScreenQRView: View {
    let groupId: UUID
    let groupName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.successBgLight.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 60)

                // Carry logo (glyph + wordmark), tinted successGreen (#064102)
                // to match the brand's darkest-green-on-light-green palette.
                Image("carry-logo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 146)
                    .foregroundColor(Color.successGreen)
                    .accessibilityLabel("Carry")

                Spacer()

                // Big QR — centered, sized to the narrower dimension with a
                // margin. `.interpolation(.none)` in QRCodeView keeps modules
                // sharp at any size. Green-on-green matches the brand surface.
                GeometryReader { geo in
                    let side = min(geo.size.width - 80, 320)
                    QRCodeView(
                        string: GroupInviteLink.url(for: groupId).absoluteString,
                        size: side,
                        foreground: UIColor(Color.successGreen),
                        background: UIColor(Color.successBgLight)
                    )
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                }
                .aspectRatio(1, contentMode: .fit)

                Spacer()

                Text("Tap anywhere to close")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.successGreen)
                    .padding(.bottom, 48)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        // Request the screen stays bright & awake so the QR doesn't dim out
        // while friends are scanning.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

#if DEBUG
#Preview("Fullscreen QR") {
    FullScreenQRView(groupId: UUID(), groupName: "Midweek Warriors")
}
#endif
