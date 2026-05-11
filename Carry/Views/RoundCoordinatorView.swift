import SwiftUI

struct RoundCoordinatorView: View {
    @EnvironmentObject var authService: AuthService

    let initialMembers: [Player]
    let currentUserId: Int
    let creatorId: Int
    var groupId: UUID? = nil  // Supabase group ID for linking rounds
    var onExit: (() -> Void)?
    var onLeaveGroup: (() -> Void)?
    var onDeleteGroup: (() -> Void)?
    var onCreateGroup: (() -> Void)?
    var onDeclineGroup: (() -> Void)?
    var onPhaseChanged: ((Bool) -> Void)?
    var startInActiveMode: Bool
    var skipCourseSelection: Bool
    var preselectedCourse: SelectedCourse?
    var onCourseSelected: ((SelectedCourse) -> Void)?
    var onTeeTimeChanged: ((Date?) -> Void)?
    var onRecurrenceChanged: ((GameRecurrence?) -> Void)?
    var initialTeeTime: Date?
    var initialTeeTimes: [Date?]? = nil
    var initialRecurrence: GameRecurrence? = nil
    var initialBuyIn: Double
    var initialCarriesEnabled: Bool = false
    var initialHandicapPercentage: Double = 1.0
    var initialRoundConfig: RoundConfig?
    var initialDemoMode: RoundViewModel.DemoMode
    var roundHistory: [HomeRound]
    var isViewer: Bool = false
    var scheduledLabel: String? = nil
    var isQuickGame: Bool = false
    var showInviteCrewOnAppear: Bool = false
    var onGroupRefreshed: ((SavedGroup) -> Void)?

    enum Phase: Equatable {
        case courseSelection
        case setup
        case starting
        case active
    }

    init(
        initialMembers: [Player] = Player.allPlayers,
        groupName: String = "The Friday Skins",
        currentUserId: Int = 1,
        creatorId: Int = 1,
        groupId: UUID? = nil,
        startInActiveMode: Bool = false,
        preselectedCourse: SelectedCourse? = nil,
        skipCourseSelection: Bool = false,
        onCourseSelected: ((SelectedCourse) -> Void)? = nil,
        onTeeTimeChanged: ((Date?) -> Void)? = nil,
        onRecurrenceChanged: ((GameRecurrence?) -> Void)? = nil,
        initialTeeTime: Date? = nil,
        initialTeeTimes: [Date?]? = nil,
        initialRecurrence: GameRecurrence? = nil,
        initialBuyIn: Double = 0,
        initialCarriesEnabled: Bool = false,
        initialHandicapPercentage: Double = 1.0,
        initialRoundConfig: RoundConfig? = nil,
        initialDemoMode: RoundViewModel.DemoMode = .none,
        roundHistory: [HomeRound] = [],
        onExit: (() -> Void)? = nil,
        onLeaveGroup: (() -> Void)? = nil,
        onDeleteGroup: (() -> Void)? = nil,
        isViewer: Bool = false,
        scheduledLabel: String? = nil,
        isQuickGame: Bool = false,
        showInviteCrewOnAppear: Bool = false,
        onGroupRefreshed: ((SavedGroup) -> Void)? = nil,
        onCreateGroup: (() -> Void)? = nil,
        onDeclineGroup: (() -> Void)? = nil,
        onPhaseChanged: ((Bool) -> Void)? = nil  // Bool = isInSetupPhase. Lets parent overlays pick dismiss-edge based on current phase, not entry phase.
    ) {
        self.initialMembers = initialMembers
        self._groupName = State(initialValue: groupName)
        self.currentUserId = currentUserId
        self.creatorId = creatorId
        self.groupId = groupId
        self.startInActiveMode = startInActiveMode
        self.preselectedCourse = preselectedCourse
        self.skipCourseSelection = skipCourseSelection
        self.onCourseSelected = onCourseSelected
        self.onTeeTimeChanged = onTeeTimeChanged
        self.onRecurrenceChanged = onRecurrenceChanged
        self.initialTeeTime = initialTeeTime
        self.initialTeeTimes = initialTeeTimes
        self.initialRecurrence = initialRecurrence
        self.initialBuyIn = initialBuyIn
        self.initialCarriesEnabled = initialCarriesEnabled
        self.initialHandicapPercentage = initialHandicapPercentage
        self.initialRoundConfig = initialRoundConfig
        self.initialDemoMode = initialDemoMode
        self.roundHistory = roundHistory
        self.onExit = onExit
        self.onLeaveGroup = onLeaveGroup
        self.onDeleteGroup = onDeleteGroup
        self.isViewer = isViewer
        self.scheduledLabel = scheduledLabel
        self.isQuickGame = isQuickGame
        self.showInviteCrewOnAppear = showInviteCrewOnAppear
        self.onGroupRefreshed = onGroupRefreshed
        self.onCreateGroup = onCreateGroup
        self.onDeclineGroup = onDeclineGroup
        self.onPhaseChanged = onPhaseChanged
        // Determine starting phase and initial course
        self._selectedCourse = State(initialValue: preselectedCourse)
        // Wiring guard (locked 2026-05-10): an existing-group entry MUST
        // pass at least one of `skipCourseSelection`, `startInActiveMode`,
        // or `initialRoundConfig`. Otherwise the coordinator launches into
        // `.courseSelection` — a full-screen course search the user
        // can only escape via the X button — even though the group already
        // has all the context needed for setup. This was the root cause of
        // the Home-tab Restart Round trap (2026-05-10). Force-fix in production
        // by promoting `skipCourseSelection` to true; trap in DEBUG so the
        // wiring mistake is caught at the call site instead of landing on
        // users.
        let effectiveSkipCourseSelection: Bool = {
            if skipCourseSelection { return true }
            if groupId != nil && initialRoundConfig == nil && !startInActiveMode {
                #if DEBUG
                assertionFailure("RoundCoordinatorView: existing-group entry (groupId != nil) must pass skipCourseSelection: true OR startInActiveMode: true OR initialRoundConfig. Forcing skipCourseSelection to avoid the courseSelection trap. See phase-transitions.md.")
                #endif
                print("[RoundCoordinator] WARNING: forcing skipCourseSelection=true — caller passed groupId without skipCourseSelection/startInActiveMode/initialRoundConfig")
                return true
            }
            return false
        }()
        if initialRoundConfig != nil {
            // Active round exists — start directly in scorecard with pre-built config
            self._phase = State(initialValue: .active)
            self._hasStartedRound = State(initialValue: true)
            self._roundConfig = State(initialValue: initialRoundConfig)
        } else if startInActiveMode {
            self._phase = State(initialValue: .active)
            self._hasStartedRound = State(initialValue: true)
        } else if effectiveSkipCourseSelection {
            self._phase = State(initialValue: .setup)
        } else {
            self._phase = State(initialValue: .courseSelection)
        }
    }

    @State private var phase: Phase
    @State private var roundConfig: RoundConfig?
    @State private var roundCreationTask: Task<Void, Never>?
    /// Captures the just-played roster (incl. Quick Game guests) when the
    /// user taps Cancel Round on the scorecard. Falling back to the
    /// statically-captured `initialMembers` would drop guests added during
    /// setup or in QuickStartSheet, since the server roster doesn't store
    /// ephemeral guests.
    @State private var postCancelMembers: [Player]? = nil
    @State private var groups: [[Player]] = []
    @State private var startingSides: [String] = []
    @State private var groupName: String = "The Friday Skins"
    @State private var showSplashLeaderboard = false

    // Course selection state
    @State private var selectedCourse: SelectedCourse?

    // Track whether a round has been started (to distinguish setup vs returning from scorecard)
    @State private var hasStartedRound = false

    // Splash animation states
    @State private var showFlag = false
    @State private var showTitle = false
    @State private var showDetails = false
    @State private var showStats = false
    @State private var pulseFlag = false

    var body: some View {
        ZStack {
            if initialMembers.isEmpty {
                // Safety: don't render if no members (prevents index-out-of-range in GroupManagerView)
                Color.clear
            } else {
            switch phase {
            case .courseSelection:
                CourseSelectionView(onBack: onExit) { course in
                    self.selectedCourse = course
                    self.onCourseSelected?(course)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        phase = .setup
                    }
                }
                .transition(.opacity)

            case .setup:
                GroupManagerView(allMembers: postCancelMembers ?? initialMembers, selectedCourse: selectedCourse, onCourseChanged: { course in
                    self.selectedCourse = course
                    self.onCourseSelected?(course)
                }, onTeeTimeChanged: onTeeTimeChanged, onRecurrenceChanged: onRecurrenceChanged, initialTeeTime: initialTeeTime, initialTeeTimes: initialTeeTimes, initialBuyIn: initialBuyIn, initialRecurrence: initialRecurrence, initialCarriesEnabled: initialCarriesEnabled, initialHandicapPercentage: initialHandicapPercentage, groupName: groupName, currentUserId: currentUserId, creatorId: creatorId, isLiveRound: hasStartedRound, roundHistory: roundHistory, onLeaveGroup: onLeaveGroup, onDeleteGroup: onDeleteGroup, scheduledLabel: scheduledLabel, onBack: {
                    if hasStartedRound {
                        // Return to scorecard without rebuilding config
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                            phase = .active
                        }
                    } else {
                        // Architectural invariant (locked 2026-05-10): pressing
                        // Back from the setup view always dismisses the
                        // coordinator. It NEVER navigates to `.courseSelection`.
                        //
                        // Why: `.courseSelection` is only entered via the
                        // constructor (and only when `initialRoundConfig` is nil
                        // AND `startInActiveMode` is false AND `skipCourseSelection`
                        // is false — a combination no production caller uses).
                        // If a user wants to change the course mid-setup, the
                        // in-setup sheet at GroupManagerView:5157 covers that
                        // path without a phase transition. The previous
                        // "fall back to courseSelection" branch was dead code
                        // in well-formed callers, but became a TRAP whenever
                        // any caller's prop wiring drifted (HomeView regression
                        // 2026-05-10) — user lands on a full-screen course
                        // search with no escape but the X button.
                        //
                        // See [bug-archive 2026-05-10 "Home-tab Quick Game
                        // entry: Restart Round breaks drag + back navigation"]
                        // and [phase-transitions.md].
                        onExit?()
                    }
                }, supabaseGroupId: groupId, isQuickGame: isQuickGame, showInviteCrewOnAppear: showInviteCrewOnAppear, onGroupRefreshed: onGroupRefreshed) { config in
                    var mutableConfig = config
                    mutableConfig.supabaseGroupId = self.groupId
                    self.groups = config.groups.map { gc in
                        gc.playerIDs.compactMap { pid in config.players.first(where: { $0.id == pid }) }
                    }
                    self.startingSides = config.groups.map(\.startingSide)

                    if hasStartedRound {
                        // Returning from settings during live round — preserve supabaseRoundId.
                        // If roundConfig is nil (round creation still in flight), don't overwrite —
                        // let createSupabaseRound set it with the round ID when it completes.
                        if self.roundConfig != nil {
                            mutableConfig.supabaseRoundId = self.roundConfig?.supabaseRoundId
                            self.roundConfig = mutableConfig
                        }
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                            phase = .active
                        }
                    } else {
                        hasStartedRound = true

                        // Create round in Supabase during splash — ONLY if creator starting a new round.
                        // Non-creator "Join Round" already has supabaseRoundId; if their fetch failed,
                        // they should NOT create a duplicate round.
                        let isCreator = currentUserId == creatorId
                        #if DEBUG
                        print("[RoundCoordinator] currentUserId=\(currentUserId) creatorId=\(creatorId) isCreator=\(isCreator) hasRoundId=\(mutableConfig.supabaseRoundId != nil)")
                        #endif
                        if mutableConfig.supabaseRoundId == nil,
                           isCreator,
                           authService.isAuthenticated,
                           let userId = authService.currentUser?.id {
                            roundCreationTask = Task {
                                await self.createSupabaseRound(config: mutableConfig, userId: userId)
                            }
                        } else {
                            // Non-creator, already has roundId, or unauthenticated — set config as-is
                            self.roundConfig = mutableConfig
                        }

                        NotificationService.shared.notifyGameStarted(
                            groupName: mutableConfig.groupName,
                            courseName: mutableConfig.course
                        )
                        // The "Round Started" splash is a creator-only celebratory
                        // moment — they're the one who built the roster and tapped
                        // Start. Non-creators reach this code path only via
                        // anomalous flows (the normal join path enters with
                        // `initialRoundConfig != nil` and inits straight to
                        // `.active`, see line 106). When they do land here, jump
                        // straight to the scorecard — no splash, no wasted
                        // staggered-reveal `@State` writes on an invisible view.
                        withAnimation(.easeInOut(duration: 0.4)) {
                            phase = isCreator ? .starting : .active
                        }
                        if isCreator {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { showFlag = true }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                withAnimation(.easeOut(duration: 0.4)) { showTitle = true }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                withAnimation(.easeOut(duration: 0.4)) { showDetails = true }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                withAnimation(.easeOut(duration: 0.4)) { showStats = true }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                                    pulseFlag = true
                                }
                            }
                        }
                    }
                }
                .transition(.opacity)

            case .starting:
                roundStartedSplash
                    .transition(.opacity)

            case .active:
                if let baseConfig = roundConfig, !((baseConfig.holes ?? baseConfig.teeBox?.holes ?? []).isEmpty) {
                // Defense in depth: if @State.roundConfig was hydrated by
                // GroupManagerView's onStart (which historically didn't set
                // scorerPlayerIds), fall back to the parent-supplied
                // initialRoundConfig which is built directly from the SavedGroup.
                // The Quick Game scorer-only tap gate hard-fails when these are
                // nil — a non-creator scorer of group 2+ can't score at all.
                let activeConfig: RoundConfig = {
                    var merged = baseConfig
                    if merged.scorerPlayerIds == nil, let fromParent = initialRoundConfig?.scorerPlayerIds {
                        merged.scorerPlayerIds = fromParent
                    }
                    if merged.scorerPlayerId == nil, let fromParent = initialRoundConfig?.scorerPlayerId {
                        merged.scorerPlayerId = fromParent
                    }
                    return merged
                }()
                ScorecardView(config: activeConfig, onBack: {
                    // Only mark as completed if the round is actually done (all groups finished)
                    // Mid-round exits keep the round as "active" so the active card stays
                    onExit?()
                }, onEditPlayers: {
                    // Go back to setup phase to edit players
                    showFlag = false
                    showTitle = false
                    showDetails = false
                    showStats = false
                    pulseFlag = false
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                        phase = .setup
                    }
                }, onCourseChanged: { course in
                    selectedCourse = course
                    onCourseSelected?(course)
                }, onCreateGroup: {
                    // Creator wants to convert Quick Game to a group — exit to trigger conversion flow
                    onCreateGroup?()
                }, onDeclineGroup: {
                    // Creator declined — surface to parent so it can hide the
                    // Quick Game from the Games tab immediately (before async reload).
                    onDeclineGroup?()
                }, onCancelToSetup: {
                    // Restart-in-place. Order matters:
                    //   1. Snapshot the roster BEFORE any state mutation —
                    //      `roundConfig?.players` is the only source of guests
                    //      after the round is deleted.
                    //   2. Animate the phase change FIRST. Mutating
                    //      `roundConfig = nil` before the phase swap leaves
                    //      one frame where (phase=.active, roundConfig=nil)
                    //      renders the `.active` branch's fallback "Setting
                    //      up round..." view, whose onAppear schedules the
                    //      offline-timeout that surfaces a misleading
                    //      "Couldn't connect — starting offline" toast.
                    //      Following `onEditPlayers`'s established pattern
                    //      (phase change only, no roundConfig mutation
                    //      inside the closure) keeps the transition clean.
                    //   3. Defer the cleanup to the next runloop. By then
                    //      `phase` has propagated and the `.active` branch
                    //      is no longer evaluated, so clearing `roundConfig`
                    //      can't trigger the fallback view.
                    if let players = roundConfig?.players {
                        postCancelMembers = players
                    }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                        phase = .setup
                    }
                    DispatchQueue.main.async {
                        hasStartedRound = false
                        roundConfig = nil
                        roundCreationTask?.cancel()
                        roundCreationTask = nil
                        showFlag = false
                        showTitle = false
                        showDetails = false
                        showStats = false
                        pulseFlag = false
                    }
                }, isQuickGame: isQuickGame, currentUserId: currentUserId, demoMode: initialDemoMode, isViewer: isViewer)
                .transition(.move(edge: .bottom))
                } else {
                    // Either round is still being created, or its config has no holes.
                    // If config exists but holes are empty, GroupService.buildHomeRound's
                    // safety net already tried — there's no real data anywhere. Tell the
                    // user to re-select the course (which writes the JSON via persistCourseSelection).
                    VStack(spacing: 16) {
                        ProgressView()
                        Text(roundConfig == nil ? "Setting up round..." : "Loading course data...")
                            .font(.carry.bodySM)
                            .foregroundColor(Color.textSecondary)
                    }
                    .onAppear {
                        if let cfg = roundConfig,
                           (cfg.holes ?? cfg.teeBox?.holes ?? []).isEmpty {
                            ToastManager.shared.error("Course hole data missing — please re-select the course in Game Options")
                            onExit?()
                            return
                        }
                        // Safety timeout: if round creation hangs, cancel and start offline
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                            guard roundConfig == nil else { return }
                            roundCreationTask?.cancel()
                            roundCreationTask = nil
                            ToastManager.shared.error("Couldn't connect — starting offline")
                            withAnimation { phase = .setup }
                        }
                    }
                }
            }
            } // end if initialMembers.isEmpty else
        }
        .animation(.easeInOut(duration: 0.4), value: phase)
        .onChange(of: phase) { _, newPhase in
            // Surface "is in setup phase" to parent overlays so they can pick
            // the right dismiss-edge for the wrapper transition. Without this,
            // a parent that opened the overlay with a vertical entry (because
            // the round was active) would also dismiss vertically post-Restart-
            // Round — even though the user is now in setup, where horizontal
            // is the convention. (Locked 2026-05-10.)
            onPhaseChanged?(newPhase == .setup)
        }
        .onAppear {
            // Initial state — fire so parent can set its baseline.
            onPhaseChanged?(phase == .setup)
        }
    }

    // MARK: - Supabase Round Creation

    private func createSupabaseRound(config: RoundConfig, userId: UUID) async {
        let roundService = RoundService()

        // 1. Create or find the course in Supabase
        let courseId: UUID
        do {
            let course = try await roundService.createCourse(
                name: config.course,
                clubName: nil,
                holes: config.holes ?? config.teeBox?.holes ?? [],
                userId: userId
            )
            courseId = course.id
        } catch {
            guard !Task.isCancelled else { return }
            #if DEBUG
            print("[RoundCoordinator] Failed to create course: \(error)")
            #endif
            await MainActor.run {
                self.roundConfig = config
                ToastManager.shared.error("Failed to set up course")
            }
            return
        }

        // 2. Save tee box if selected
        var teeBoxId: UUID? = nil
        if let teeBox = config.teeBox {
            do {
                let teeBoxDTO = try await roundService.createTeeBox(courseId: courseId, teeBox: teeBox)
                teeBoxId = teeBoxDTO.id
            } catch {
                #if DEBUG
                print("[RoundCoordinator] Failed to save tee box: \(error)")
                #endif
                // Non-fatal — continue without tee box
            }
        }

        // 3a. Reconcile guest profiles. Per the ephemeral-guest invariant
        // ([guest-lifecycle.md]), guest profiles only exist for the lifetime
        // of a round. After Restart Round / End Game / End-and-Save / convert,
        // `delete_quick_game_guests` deletes them server-side, leaving the
        // local Player.profileId pointing at a non-existent row. If we use
        // those stale profileIds when creating `round_players`, the new
        // round renders all guests as "Guest" + 0.0 (the wiped-guest
        // fallback in `buildHomeRound`) because the profile fetch comes
        // back empty. Fix: at every round-start, check which guests'
        // profileIds still exist server-side. For any that don't, recreate
        // fresh guest profiles via `createGuestProfiles` and remap the
        // local Player.profileId before inserting round_players. (Bug 2026-05-10.)
        var configForRound = config
        let guestPlayers = configForRound.players.enumerated().compactMap { (idx, p) -> (idx: Int, player: Player)? in
            guard p.isGuest, !p.name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return (idx, p)
        }
        if !guestPlayers.isEmpty {
            let candidateIds = guestPlayers.compactMap(\.player.profileId)
            // Find which candidate ids actually exist server-side as guest profiles.
            let existingIds: Set<UUID> = await {
                guard !candidateIds.isEmpty else { return [] }
                let dtos: [ProfileDTO] = (try? await SupabaseManager.shared.client
                    .from("profiles")
                    .select("id")
                    .in("id", values: candidateIds.map(\.uuidString))
                    .eq("is_guest", value: true)
                    .execute()
                    .value) ?? []
                return Set(dtos.map(\.id))
            }()
            let missing = guestPlayers.filter { entry in
                guard let pid = entry.player.profileId else { return true }
                return !existingIds.contains(pid)
            }
            if !missing.isEmpty {
                // Pull canonical names/handicaps from the QuickGameGuestStorage
                // snapshot (matched by profileId, falling back to id). The
                // in-memory roster's `name` may already be "Guest" if a prior
                // `buildHomeRound` wiped-fallback corrupted it (see
                // GroupService.swift:1599). The snapshot preserves the
                // user-typed names from the original Quick Start sheet.
                let snapshotById: [Int: Player] = {
                    guard let gid = configForRound.supabaseGroupId else { return [:] }
                    let loaded = QuickGameGuestStorage.load(groupId: gid)
                    return Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
                }()
                let snapshotByProfileId: [UUID: Player] = {
                    guard let gid = configForRound.supabaseGroupId else { return [:] }
                    let loaded = QuickGameGuestStorage.load(groupId: gid)
                    return Dictionary(loaded.compactMap { p in p.profileId.map { ($0, p) } }, uniquingKeysWith: { a, _ in a })
                }()
                func canonicalName(for entry: (idx: Int, player: Player)) -> String {
                    if let pid = entry.player.profileId, let snap = snapshotByProfileId[pid], !snap.name.trimmingCharacters(in: .whitespaces).isEmpty, snap.name != "Guest" {
                        return snap.name
                    }
                    if let snap = snapshotById[entry.player.id], !snap.name.trimmingCharacters(in: .whitespaces).isEmpty, snap.name != "Guest" {
                        return snap.name
                    }
                    return entry.player.name
                }
                func canonicalHandicap(for entry: (idx: Int, player: Player)) -> Double {
                    if let pid = entry.player.profileId, let snap = snapshotByProfileId[pid], snap.handicap != 0.0 {
                        return snap.handicap
                    }
                    if let snap = snapshotById[entry.player.id], snap.handicap != 0.0 {
                        return snap.handicap
                    }
                    return entry.player.handicap
                }
                #if DEBUG
                print("[RoundCoordinator] \(missing.count) guest profile(s) missing — recreating before round_players insert: \(missing.map { canonicalName(for: $0) })")
                #endif
                do {
                    let names = missing.map { canonicalName(for: $0) }
                    let initials = missing.map(\.player.initials)
                    let handicaps = missing.map { canonicalHandicap(for: $0) }
                    let colors = missing.map(\.player.color)
                    let newUUIDs = try await GuestProfileService().createGuestProfiles(
                        names: names,
                        initials: initials,
                        handicaps: handicaps,
                        colors: colors,
                        creatorId: userId
                    )
                    guard newUUIDs.count == missing.count else {
                        throw NSError(domain: "RoundCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Guest profile recreate count mismatch: expected \(missing.count), got \(newUUIDs.count)"])
                    }
                    // Apply new profileIds + canonical name/handicap to configForRound.players
                    var updatedPlayers = configForRound.players
                    for (i, entry) in missing.enumerated() {
                        var p = updatedPlayers[entry.idx]
                        p.profileId = newUUIDs[i]
                        p.name = names[i]
                        p.handicap = handicaps[i]
                        updatedPlayers[entry.idx] = p
                    }
                    configForRound.players = updatedPlayers
                } catch {
                    #if DEBUG
                    print("[RoundCoordinator] Failed to recreate guest profiles: \(error)")
                    #endif
                    await MainActor.run {
                        self.roundConfig = config
                        ToastManager.shared.error("Couldn't set up guest players. Try again.")
                    }
                    return
                }
            }
        }

        // 3b. Map players to Supabase UUIDs with group numbers
        var playerTuples: [(userId: UUID, group: Int)] = []
        for gc in configForRound.groups {
            for playerId in gc.playerIDs {
                guard let player = configForRound.players.first(where: { $0.id == playerId }),
                      let profileId = player.profileId else { continue }
                playerTuples.append((userId: profileId, group: gc.id))
            }
        }

        guard !playerTuples.isEmpty else {
            #if DEBUG
            print("[RoundCoordinator] No players with Supabase profiles — skipping round creation")
            #endif
            await MainActor.run { self.roundConfig = config }
            return
        }

        guard !Task.isCancelled else { return }

        // 4. Create the round
        do {
            let roundDTO = try await roundService.createRound(
                courseId: courseId,
                createdBy: userId,
                teeBoxId: teeBoxId,
                buyIn: configForRound.buyIn,
                net: configForRound.skinRules.net,
                carries: configForRound.skinRules.carries,
                outright: configForRound.skinRules.outright,
                handicapPercentage: configForRound.skinRules.handicapPercentage,
                groupId: configForRound.supabaseGroupId,
                scorerId: configForRound.scorerProfileId ?? userId,
                scoringMode: configForRound.scoringMode.rawValue,
                players: playerTuples
            )
            guard !Task.isCancelled else { return }

            // Set roundConfig WITH the round ID + any recreated guest profileIds
            // so ScorecardView gets the up-to-date player list at init.
            var configWithRoundId = configForRound
            configWithRoundId.supabaseRoundId = roundDTO.id
            await MainActor.run {
                self.roundConfig = configWithRoundId
            }
            #if DEBUG
            print("[RoundCoordinator] Round created in Supabase: \(roundDTO.id)")
            #endif
            Analytics.roundStarted(groupName: configForRound.groupName, playerCount: configForRound.players.count, buyIn: configForRound.buyIn, courseName: configForRound.course)
        } catch {
            guard !Task.isCancelled else { return }
            #if DEBUG
            print("[RoundCoordinator] Failed to create round: \(error)")
            #endif
            await MainActor.run {
                self.roundConfig = configForRound
                ToastManager.shared.error("Failed to create round")
            }
        }
    }

    // MARK: - All Players

    private var allPlayers: [Player] {
        groups.flatMap { $0 }
    }

    // MARK: - Round Started Splash

    private var roundStartedSplash: some View {
        let totalPlayers = allPlayers.count
        let groupCount = groups.count

        return ZStack {
            // Background
            Color.white
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Centered content — flag, title, pills
                Spacer()

                // Flag icon with pulse — matches Skins Game Complete gold style
                ZStack {
                    // Pulsing outer glow
                    Circle()
                        .fill(Color.gold.opacity(pulseFlag ? 0.15 : 0.0))
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseFlag ? 1.3 : 0.8)

                    Circle()
                        .fill(Color.gold.opacity(0.12))
                        .frame(width: 80, height: 80)

                    Image(systemName: "flag.fill")
                        .font(.system(size: 36))
                        .foregroundColor(Color.gold)
                }
                .scaleEffect(showFlag ? 1.0 : 0.3)
                .opacity(showFlag ? 1 : 0)

                Spacer().frame(height: 32)

                // "Round Started"
                Text("Round Started")
                    .font(.carry.displaySM)
                    .foregroundColor(Color.textPrimary)
                    .opacity(showTitle ? 1 : 0)
                    .offset(y: showTitle ? 0 : 12)

                Spacer().frame(height: 8)

                // Player + group count
                Text("\(totalPlayers) players \u{00B7} \(groupCount) group\(groupCount == 1 ? "" : "s")")
                    .font(.carry.bodyLG)
                    .foregroundColor(Color.textPrimary.opacity(0.5))
                    .opacity(showDetails ? 1 : 0)
                    .offset(y: showDetails ? 0 : 8)

                Spacer().frame(height: 24)

                // Player pills (max 14 visible, "+X players" overflow)
                let maxVisible = 14
                let visiblePlayers = Array(allPlayers.prefix(maxVisible))
                let overflow = allPlayers.count - maxVisible

                let columns = [
                    GridItem(.adaptive(minimum: 150), spacing: 10)
                ]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(visiblePlayers) { player in
                        HStack(spacing: 8) {
                            PlayerAvatar(player: player, size: 32)
                            Text(player.shortName)
                                .font(.carry.body)
                                .foregroundColor(Color.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text("$0")
                                .font(.carry.bodySemibold)
                                .monospacedDigit()
                                .foregroundColor(Color.textSecondary)
                        }
                        .padding(.leading, 6)
                        .padding(.trailing, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.bgSecondary)
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color(hexString: "#E8E8E8"), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 24)
                .opacity(showStats ? 1 : 0)
                .offset(y: showStats ? 0 : 16)

                if overflow > 0 {
                    Text("+\(overflow) players")
                        .font(.carry.bodySemibold)
                        .foregroundColor(Color.textSecondary)
                        .padding(.top, 8)
                        .opacity(showStats ? 1 : 0)
                }

                Spacer()

                // "Go to Scorecard" button — pinned at bottom
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                            phase = .active
                        }
                    } label: {
                        Text("Go to Scorecard")
                            .font(.carry.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.textPrimary)
                            )
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 18)
                .opacity(showStats ? 1 : 0)
            }
        }
        .sheet(isPresented: $showSplashLeaderboard) {
            splashLeaderboardSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
    }

    // MARK: - Splash Leaderboard Sheet

    private var splashLeaderboardSheet: some View {
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

            // Season label
            HStack {
                Text("ALL TIME")
                    .font(.carry.micro)
                    .tracking(CarryTracking.wider)
                    .foregroundColor(Color.borderSoft)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

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
                Text("Net")
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

            // Player rows
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(allPlayers.enumerated()), id: \.element.id) { idx, player in
                        leaderboardRow(player: player)

                        if idx < allPlayers.count - 1 {
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

            // Empty state (only when no players)
            if allPlayers.isEmpty {
                VStack(spacing: 8) {
                    Text("No rounds played yet")
                        .font(Font.system(size: 17, weight: .medium))
                        .foregroundColor(Color.textSecondary)
                    Text("Stats will appear here after your first round.")
                        .font(Font.system(size: 14, weight: .medium))
                        .foregroundColor(Color.borderMedium)
                }
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Leaderboard Row

    private func leaderboardRow(player: Player) -> some View {
        HStack(spacing: 12) {
            PlayerAvatar(player: player, size: 38)

            VStack(alignment: .leading, spacing: 1) {
                Text(player.shortName)
                    .font(Font.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                Text(formatHandicap(player.handicap))
                    .font(Font.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.borderMedium)
            }

            Spacer()

            Text("0")
                .font(Font.system(size: 17, weight: .medium))
                .foregroundColor(Color.borderSoft)
                .frame(width: 60, alignment: .center)

            Text("$0")
                .font(Font.system(size: 17, weight: .medium))
                .foregroundColor(Color.borderSoft)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    // MARK: - Stat Card

    private func statCard(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Color.textPrimary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.carry.bodySemibold)
                    .foregroundColor(Color.textPrimary)
                Text(subtitle)
                    .font(.carry.caption)
                    .foregroundColor(Color.textPrimary.opacity(0.4))
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.bgLight, lineWidth: 1)
        )
    }

}
