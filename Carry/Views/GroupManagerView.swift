import SwiftUI

/// Identifiable wrapper for item-based sheets (avoids stale state with .sheet(isPresented:))
private struct SheetItem: Identifiable {
    let id: Int
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
    @State private var carriesEnabled = false  // carries toggle (off by default for multi-group)
    @State private var scoringMode: ScoringMode = .everyone  // .single or .everyone (on by default)
    @State private var handicapPercentage: Double = 1.0  // 1.0 = 100%, 0.7 = 70%
    @State private var buyInText: String = ""  // per-player buy-in amount
    @State private var showManageMembers = false
    @State private var showTipBanner = true  // green tip banner, dismissible
    @State private var roundDate: Date = Date()  // mandatory round date (defaults to today)
    @State private var showDatePicker = false  // date picker sheet
    @State private var showLeaveDeleteAlert = false
    @State private var showCloseQuickGameAlert = false
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

    /// Only the group creator can manage settings, players and tee times.
    private var isCreator: Bool { currentUserId == creatorId }

    init(allMembers: [Player], selectedCourse: SelectedCourse? = nil, onCourseChanged: ((SelectedCourse) -> Void)? = nil, onTeeTimeChanged: ((Date?) -> Void)? = nil, onRecurrenceChanged: ((GameRecurrence?) -> Void)? = nil, initialTeeTime: Date? = nil, initialTeeTimes: [Date?]? = nil, initialBuyIn: Double = 0, initialDate: Date? = nil, initialRecurrence: GameRecurrence? = nil, preselected: Set<Int>? = nil, groupName: String = "The Friday Skins", currentUserId: Int = 1, creatorId: Int = 1, isLiveRound: Bool = false, roundStarted: Bool = false, roundHistory: [HomeRound] = [], onLeaveGroup: (() -> Void)? = nil, onDeleteGroup: (() -> Void)? = nil, scheduledLabel: String? = nil, onBack: (() -> Void)? = nil, supabaseGroupId: UUID? = nil, isQuickGame: Bool = false, showInviteCrewOnAppear: Bool = false, onGroupRefreshed: ((SavedGroup) -> Void)? = nil, onConfirm: @escaping (RoundConfig) -> Void) {
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
        let sel = preselected ?? Set(allMembers.map(\.id))
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
            // Remove trailing empty groups
            while result.last?.isEmpty == true { result.removeLast() }
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
        allMembers + guests
    }

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
                selectedIDs = result.selectedIDs
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

    private func syncTeeTimes() {
        while teeTimes.count < groups.count {
            teeTimes.append(nil)
        }
        while teeTimes.count > groups.count {
            teeTimes.removeLast()
        }
    }

    /// Ensure each group has a valid scorer; default to first confirmed (non-pending) player
    private func syncScorerIDs() {
        while scorerIDs.count < groups.count {
            let firstConfirmed = groups[scorerIDs.count].first(where: { !$0.isPendingInvite && !$0.isPendingAccept })
            scorerIDs.append(firstConfirmed?.id ?? groups[scorerIDs.count].first?.id ?? 0)
        }
        while scorerIDs.count > groups.count {
            scorerIDs.removeLast()
        }
        // Validate: if scorer was moved out of group or is pending, reassign to first confirmed player
        // Quick Games: allow pending scorers — they'll become active when they accept
        for i in 0..<groups.count {
            let groupPlayerIDs = Set(groups[i].map(\.id))
            let currentScorer = groups[i].first(where: { $0.id == scorerIDs[i] })
            let isPendingScorer = currentScorer?.isPendingInvite == true || currentScorer?.isPendingAccept == true
            if !groupPlayerIDs.contains(scorerIDs[i]) || (!isQuickGame && isPendingScorer) {
                let firstConfirmed = groups[i].first(where: { !$0.isPendingInvite && !$0.isPendingAccept })
                scorerIDs[i] = firstConfirmed?.id ?? groups[i].first?.id ?? 0
            }
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
    private func autoFillTeeTimes(from index: Int) {
        guard let baseTime = teeTimes[index] else { return }
        for i in (index + 1)..<teeTimes.count {
            let offset = Double(i - index) * teeTimeInterval
            teeTimes[i] = baseTime.addingTimeInterval(offset)
        }
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

    private var canStartRound: Bool {
        if isQuickGame {
            // Quick Games: only need creator's group (group 1) ready — other groups start when their scorer accepts
            let group1Active = groups.first?.filter { !$0.isPendingInvite && !$0.isPendingAccept }.count ?? 0
            return group1Active >= 2 && currentCourse != nil
        }
        return activePlayerCount >= 2 && currentCourse != nil && allTeeTimesSet && isWithinTeeTimeWindow
    }

    private var buttonEnabled: Bool {
        canStartRound || needsNextSchedule
    }

    /// True when creator needs to schedule next round (non-recurring group with past tee time and completed rounds)
    private var needsNextSchedule: Bool {
        if !isCreator { return false }
        if isLiveRound { return false }
        if roundHistory.isEmpty { return false }
        if buildRecurrence() != nil { return false }
        if let firstTee = teeTimes.first, let t = firstTee {
            return t < Date()
        }
        return true
    }

    private var startButtonLabel: String {
        if isLiveRound { return "Back to Scorecard" }
        if needsNextSchedule { return "Schedule Next Round" }
        if activePlayerCount < 2 && hasPendingPlayers { return "Awaiting Invited Players..." }
        if activePlayerCount < 2 { return "Need 2+ Players" }
        if currentCourse == nil { return "Select a Course" }
        if needsTeeTimesSet { return "Set Tee Times to Start" }
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
        // Only show players who actually participated (exclude pending)
        let activePlayers = allAvailable.filter { !$0.isPendingAccept }
        return activePlayers.sorted { a, b in
            let aStats = cumulativeStats[a.id] ?? (skins: 0, won: 0)
            let bStats = cumulativeStats[b.id] ?? (skins: 0, won: 0)
            if aStats.won != bStats.won { return aStats.won > bStats.won }
            if aStats.skins != bStats.skins { return aStats.skins > bStats.skins }
            return a.name < b.name
        }
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
        guard let groupId = supabaseGroupId else { return }
        guard let userId = try? await SupabaseManager.shared.client.auth.session.user.id else { return }

        do {
            guard let freshGroup = try await GroupService().loadSingleGroup(groupId: groupId, userId: userId) else {
                #if DEBUG
                print("[GroupManagerView] refreshGroupData: group not found")
                #endif
                return
            }

            await MainActor.run {
                // Update member statuses in-place if groups already exist (preserves order)
                let freshById = Dictionary(uniqueKeysWithValues: freshGroup.members.compactMap { m -> (Int, Player)? in
                    return (m.id, m)
                })
                let hadGroups = !groups.isEmpty && !groups.allSatisfy({ $0.isEmpty })

                allMembers = freshGroup.members
                let sel = Set(freshGroup.members.map(\.id))
                selectedIDs = sel

                if hadGroups {
                    // In-place update: update player statuses without reshuffling
                    for gi in groups.indices {
                        for pi in groups[gi].indices {
                            if let fresh = freshById[groups[gi][pi].id] {
                                groups[gi][pi].isPendingAccept = fresh.isPendingAccept
                                groups[gi][pi].isPendingInvite = fresh.isPendingInvite
                            }
                        }
                    }
                    // Add any new members that weren't in existing groups
                    let existingIds = Set(groups.flatMap { $0 }.map(\.id))
                    let newPlayers = freshGroup.members.filter { !existingIds.contains($0.id) }
                    if !newPlayers.isEmpty {
                        for p in newPlayers {
                            let targetGroup = max(0, min(p.group - 1, groups.count - 1))
                            groups[targetGroup].append(p)
                        }
                    }
                } else {
                    // First load — do a full regroup
                    let playing = freshGroup.members.filter { sel.contains($0.id) }
                    let regrouped = Self.autoGroup(playing)
                    let safeGrouped: [[Player]]
                    if regrouped.isEmpty || regrouped.allSatisfy({ $0.isEmpty }) {
                        safeGrouped = freshGroup.members.isEmpty ? [[]] : [freshGroup.members]
                    } else {
                        safeGrouped = regrouped
                    }
                    groups = safeGrouped
                }

                let groupCount = max(groups.count, 1)
                startingSides = Self.defaultSides(count: groupCount)
                // Use saved scorer IDs from Supabase if available, otherwise default to first player
                if let saved = freshGroup.scorerIds, !saved.isEmpty {
                    scorerIDs = saved
                    // Pad if fewer scorer IDs than groups
                    while scorerIDs.count < groups.count {
                        scorerIDs.append(groups[scorerIDs.count].first?.id ?? 0)
                    }
                } else {
                    scorerIDs = groups.map { $0.first?.id ?? 0 }
                }

                // Update tee time / schedule
                if let date = freshGroup.scheduledDate {
                    roundDate = date
                    if teeTimes.isEmpty || teeTimes.allSatisfy({ $0 == nil }) {
                        if let interval = freshGroup.teeTimeInterval, interval > 0, groupCount > 1 {
                            // Compute consecutive tee times from interval
                            teeTimes = (0..<groupCount).map { i in
                                date.addingTimeInterval(Double(i) * Double(interval) * 60)
                            }
                        } else {
                            teeTimes = [date] + Array(repeating: nil, count: max(groupCount - 1, 0))
                        }
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

                    // Leaderboard button (hidden for quick games — no history yet)
                    if !isQuickGame {
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
                    }

                    // Group options button — creator only
                    if isCreator {
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
                }

                ScrollView {
                VStack(spacing: 0) {
                    if !isQuickGame {
                    // "Playing" section header + "Invite & Manage" (admin only)
                    HStack {
                        Text("Playing")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundColor(Color.deepNavy)
                        Spacer()
                        if isCreator && activePlayerCount > 0 {
                            Button {
                                showManageMembers = true
                            } label: {
                                Text("Invite & Manage")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.textPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().strokeBorder(Color.textPrimary, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    // Horizontal scrolling player pills — only confirmed (non-pending) players
                    if activePlayerCount == 0 {
                        Button {
                            showManageMembers = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Add Players")
                                    .font(.carry.bodySMBold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.textPrimary))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(allAvailable.filter { selectedIDs.contains($0.id) && !$0.isPendingInvite && !$0.isPendingAccept }) { player in
                                    HStack(spacing: 6) {
                                        PlayerAvatar(player: player, size: 32)
                                        Text(player.shortName)
                                            .font(.carry.bodySMSemibold)
                                            .foregroundColor(Color.deepNavy)
                                            .lineLimit(1)
                                    }
                                    .padding(.leading, 6)
                                    .padding(.trailing, 15)
                                    .padding(.vertical, 6)
                                    .background(.white)
                                    .clipShape(Capsule())
                                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 3)
                        }
                        .padding(.bottom, 16)
                    }
                    } // end if !isQuickGame (Playing section)

                    // "Tee Times" section header
                    HStack {
                        Text("Tee Times")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundColor(Color.deepNavy)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

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
                        ForEach(Array(groups.enumerated()), id: \.offset) { groupIdx, group in
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
            } // end floating header VStack

            // CTA button pinned to bottom — all roles
            VStack {
                Spacer()
                if isCreator {
                    // Admin: "Start Round" or "Back to Scorecard"
                    Button {
                        if isLiveRound {
                            onBack?()
                        } else if needsNextSchedule {
                            showSettings = true
                        } else {
                            let config = buildRoundConfig()
                            onConfirm(config)
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
                        .foregroundColor(buttonEnabled ? .white : Color.textSecondary)
                        .frame(width: 322, height: 51)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(buttonEnabled ? Color.textPrimary : Color.borderMedium)
                        )
                    }
                    .disabled(!buttonEnabled)
                    .accessibilityLabel(startButtonLabel)
                    .accessibilityHint(isLiveRound ? "Returns to the live scorecard" : "Starts a new round")
                    .padding(.bottom, 40)
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
                                    let activeIds = Set(members.filter { $0.status == "active" }.map { $0.playerId })
                                    // Check if any phone invites were claimed (invited_phone cleared + status active)
                                    let claimedPhones = Set(members.filter { $0.status == "active" && ($0.invitedPhone == nil || ($0.invitedPhone ?? "").isEmpty) }.map { $0.playerId })
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
                    .padding(.bottom, 40)
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
                    .padding(.bottom, 40)
                }
            }
        }
        .refreshable {
            #if DEBUG
            print("[GroupManagerView] Pull-to-refresh triggered")
            #endif
            await refreshGroupData()
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
                    handicapPercentage = result.handicapPercentage
                    buyInText = result.buyInText
                    if let t = result.teeTime {
                        roundDate = t
                        if teeTimes.isEmpty { syncTeeTimes() }
                        if !teeTimes.isEmpty { teeTimes[0] = t }
                        autoFillTeeTimes(from: 0)
                        onTeeTimeChanged?(t)
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
                    if !teeTimes.isEmpty { teeTimes[0] = roundDate }
                    autoFillTeeTimes(from: 0)
                    onTeeTimeChanged?(teeTimes.first.flatMap { $0 })
                    onRecurrenceChanged?(buildRecurrence())
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
        .alert("Edit Name", isPresented: $showNameEditor) {
            TextField("Friday Skins", text: $editingName)
            Button("Save") {
                let trimmed = editingName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    groupName = trimmed
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert(
            isCreator ? "Delete Group?" : "Leave Group?",
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
            Text(isCreator
                ? "This will remove \(groupName) for all members. This can't be undone."
                : "You'll be removed from \(groupName) and future games.")
        }
        .alert("Leave game?", isPresented: $showCloseQuickGameAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Leave", role: .destructive) {
                onBack?()
            }
        } message: {
            Text("Your game setup will be lost.")
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
            // Show share card sheet after quick game → group conversion
            // Delayed to after first refreshGroupData so round history + winnings are loaded
            if showInviteCrewOnAppear && allMembers.filter({ !$0.name.isEmpty }).count > 1 {
                let refreshDelay: Double = isQuickGame ? 3.0 : 0
                DispatchQueue.main.asyncAfter(deadline: .now() + refreshDelay + 1.5) {
                    showShareCardSheet = true
                }
            }
        }
        .onDisappear {
            stopDetailAutoRefresh()
        }
        .onChange(of: groups) { _, _ in
            // Debounce: only sync after user stops reordering
            orderSyncTask?.cancel()
            orderSyncTask = Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                guard !Task.isCancelled else { return }
                syncPlayerOrderToSupabase()
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
                print("[buildRoundConfig] ❌ NO HOLES — will fall back to Hole.allHoles in RoundViewModel")
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
                net: isQuickGame && !storeService.isPremium ? false : true,
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
        return config
    }

    // MARK: - Remove Player (swipe-to-delete)

    private func removePlayer(_ player: Player, fromGroup groupIndex: Int) {
        guard groupIndex < groups.count else { return }

        // Remove from this group
        groups[groupIndex].removeAll { $0.id == player.id }

        if isQuickGame {
            // Quick Game: remove entirely
            allMembers.removeAll { $0.id == player.id }
            selectedIDs.remove(player.id)

            // Persist to Supabase
            if let groupId = supabaseGroupId, let profileId = player.profileId {
                Task {
                    try? await SupabaseManager.shared.client
                        .from("group_members")
                        .delete()
                        .eq("group_id", value: groupId.uuidString)
                        .eq("player_id", value: profileId.uuidString)
                        .execute()
                }
            }
        } else {
            // Regular group: just deselect from tee sheet (stays in allMembers for re-add)
            selectedIDs.remove(player.id)
        }

        // If group is now empty, remove the group
        if groups[groupIndex].isEmpty {
            groups.remove(at: groupIndex)
        }

        // Re-sync dependent arrays
        syncTeeTimes()
        syncScorerIDs()
        syncSelectedTees()
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

                ForEach(groups[destIdx]) { destPlayer in
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
                                    Text(pops > 0 ? "\(formatHandicap(destPlayer.handicap)) · \(pops) pop\(pops == 1 ? "" : "s")" : formatHandicap(destPlayer.handicap))
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

                    if destPlayer.id != groups[destIdx].last?.id {
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
                let cal = Calendar.current
                if cal.isDate(teeTimePickerDate, inSameDayAs: roundDate) {
                    roundDate = teeTimePickerDate
                }
                // Explicitly notify parent of tee time change
                onTeeTimeChanged?(teeTimes.first.flatMap { $0 })
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
                ForEach(groups[groupIndex]) { player in
                    let isCurrentScorer = groupIndex < scorerIDs.count && scorerIDs[groupIndex] == player.id
                    let isPending = player.isPendingInvite || player.isPendingAccept

                    Button {
                        guard !isPending else { return }
                        scorerIDs[groupIndex] = player.id
                        scorerPickerItem = nil
                        saveScorerIds()
                    } label: {
                        HStack(spacing: 14) {
                            PlayerAvatar(player: player, size: 43)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.isPendingInvite ? formatPhoneDisplay(player.phoneNumber) : player.shortName)
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundColor(isPending ? Color.textPrimary.opacity(0.5) : Color.textPrimary)
                                    .lineLimit(1)
                                if isPending {
                                    Text("Pending")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color.pendingFill)
                                } else {
                                    let pops: Int = {
                                        if let tee = currentCourse?.teeBox {
                                            return tee.playingHandicap(forIndex: player.handicap, percentage: handicapPercentage)
                                        }
                                        return Int(player.handicap.rounded())
                                    }()
                                    Text(pops > 0 ? "\(formatHandicap(player.handicap)) · \(pops) pop\(pops == 1 ? "" : "s")" : formatHandicap(player.handicap))
                                        .font(.system(size: 14))
                                        .foregroundColor(Color.textSecondary)
                                }
                            }

                            Spacer()

                            if isPending {
                                Text("Pending")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color.pendingFill)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(Color.pendingBg)
                                            .overlay(Capsule().strokeBorder(Color.pendingBorder, lineWidth: 1))
                                    )
                            } else if isCurrentScorer {
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

        return VStack(spacing: 0) {
            groupCardHeader(index: index)

            Rectangle()
                .fill(Color(hexString: "#EBEBEB"))
                .frame(height: 1)

            ForEach(players) { player in
                SwipeToDeleteRow(enabled: isCreator && !isLiveRound && !roundStarted) {
                    removePlayer(player, fromGroup: index)
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
                    let headerHeight: CGFloat = 50
                    let rowHeight: CGFloat = 63
                    let y = headerHeight + CGFloat(targetIdx) * rowHeight
                    Capsule()
                        .fill(Color(hexString: "#4A90D9"))
                        .frame(width: geo.size.width - 38, height: 2.5)
                        .position(x: geo.size.width / 2, y: y)
                }
            }
            .allowsHitTesting(false)
        )
        .onDrop(of: [.text], delegate: GroupDropDelegate(
            groupIndex: index,
            playerCount: players.count,
            maxGroupSize: maxGroupSize,
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
                        Text("edit")
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

                Text(pops > 0 ? "\(formatHandicap(player.handicap)) · \(pops) pop\(pops == 1 ? "" : "s")" : formatHandicap(player.handicap))
                    .font(.system(size: 14))
                    .foregroundColor(Color(hexString: "#BFC0C2"))
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
                } else if player.isPendingAccept {
                    // Carry user who hasn't accepted yet
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



            if groupIndex < scorerIDs.count && scorerIDs[groupIndex] == player.id && !isPendingPlayer {
                if isCreator && !isQuickGame {
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
                    Text("Scorer")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().strokeBorder(Color.textPrimary, lineWidth: 1))
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
        .onDrag(isCreator ? {
            dragPlayer = player
            dragSourceGroup = groupIndex
            return NSItemProvider(object: String(player.id) as NSString)
        } : { NSItemProvider() })

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
                    Text(groupName)
                        .font(Font.system(size: 16, weight: .medium))
                        .foregroundColor(Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .font(Font.system(size: 22, weight: .medium))
                    .foregroundColor(Color.goldMuted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 24)

            // Last Round | All Time tabs
            HStack(spacing: 16) {
                ForEach(Array(["Last Round", "All Time"].enumerated()), id: \.offset) { idx, label in
                    Button {
                        if idx == 1 && !storeService.isPremium {
                            showPaywall = true
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) {
                                leaderboardTab = idx
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(label)
                                .font(.system(size: 14, weight: .semibold))
                            if idx == 1 && !storeService.isPremium {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color.goldMuted)
                            }
                        }
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

                // Player rows — sorted by net winnings
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(leaderboardPlayers.enumerated()), id: \.element.id) { idx, player in
                            leaderboardRow(player: player)

                            if idx < leaderboardPlayers.count - 1 {
                                Rectangle()
                                    .fill(Color.borderFaint)
                                    .frame(height: 1)
                                    .padding(.leading, 82)
                                    .padding(.trailing, 24)
                            }
                        }
                    }
                }

                Spacer()
            }

        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
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
    private func filterHandicapInput(_ input: String) -> String {
        var filtered = ""
        var hasDecimal = false
        var hasPlus = false
        var decimalDigits = 0
        for ch in input {
            if ch == "+" && filtered.isEmpty && !hasPlus {
                hasPlus = true
                filtered.append(ch)
            } else if (ch == "." || ch == ",") && !hasDecimal {
                hasDecimal = true
                filtered.append(ch)
            } else if ch.isNumber {
                if hasDecimal {
                    guard decimalDigits < 1 else { continue }
                    filtered.append(ch)
                    decimalDigits += 1
                } else {
                    filtered.append(ch)
                }
            }
        }
        let numericStr = filtered.hasPrefix("+") ? String(filtered.dropFirst()) : filtered
        if let value = Double(numericStr) {
            if hasPlus && value > 10.0 { filtered = "+10.0" }
            else if !hasPlus && value > 54.0 { filtered = "54.0" }
        }
        return filtered
    }

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

    // MARK: - Move Player

    private func movePlayer(_ player: Player, from sourceGroup: Int, to destGroup: Int) {
        withAnimation(.easeOut(duration: 0.2)) {
            guard sourceGroup < groups.count, destGroup < groups.count else { return }
            groups[sourceGroup].removeAll { $0.id == player.id }
            groups[destGroup].append(player)
            // Remove empty groups
            groups.removeAll { $0.isEmpty }
            // Adjust starting sides array
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
}

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
    }

    // All local state
    @State private var localGroupName: String
    @State private var localTeeTime: Date?
    @State private var localCarries: Bool
    @State private var localScoringMode: ScoringMode
    @State private var localHandicap: Double
    @State private var localBuyIn: String
    @State private var showCarriesInfo = false
    @State private var showLeaveDeleteConfirm = false
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
                        Button {
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
                                clearRecurrence: optScheduleMode == 0
                            ))
                        } label: {
                            Text("Save")
                                .font(.carry.bodySemibold)
                                .foregroundColor(Color.textPrimary)
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
                                Spacer()
                                Text("\(Int(localHandicap * 100))%")
                                    .font(.carry.captionLGSemibold)
                                    .foregroundColor(Color.textPrimary)
                            }
                            if isLiveRound {
                                Text("Locked during active round")
                                    .font(.carry.caption)
                                    .foregroundColor(Color.textDisabled)
                            }
                            Slider(value: $localHandicap, in: 0.1...1.0, step: 0.05)
                                .tint(Color.textPrimary)
                                .disabled(isLiveRound)
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
                            in: 0...1000,
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
                                Text("Premium feature")
                                    .font(.carry.caption)
                                    .foregroundColor(Color.textDisabled)
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
                .opacity(isLiveRound || (isQuickGame && !storeService.isPremium) ? 0.5 : 1)
                .alert("What are Carries?", isPresented: $showCarriesInfo) {
                    Button("Got it", role: .cancel) {}
                } message: {
                    Text("When no one wins a hole outright, the skin carries over and adds to the next hole's value. The next outright winner takes all accumulated skins.\n\nWhen off, tied holes are dead — no carryover.")
                }

                // Scoring Mode (hidden for quick games — single scorer only)
                if !isQuickGame {
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

        // Full group — show swap picker, no move yet
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
                // Delete button behind the row
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            offset = -500 // slide off screen
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onDelete()
                        }
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: deleteWidth, height: .infinity)
                    }
                    .frame(width: deleteWidth)
                    .background(Color.red)
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
