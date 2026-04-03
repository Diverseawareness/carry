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
        onCreateGroup: (() -> Void)? = nil
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
        // Determine starting phase and initial course
        self._selectedCourse = State(initialValue: preselectedCourse)
        if initialRoundConfig != nil {
            // Active round exists — start directly in scorecard with pre-built config
            self._phase = State(initialValue: .active)
            self._hasStartedRound = State(initialValue: true)
            self._roundConfig = State(initialValue: initialRoundConfig)
        } else if startInActiveMode {
            self._phase = State(initialValue: .active)
            self._hasStartedRound = State(initialValue: true)
        } else if skipCourseSelection {
            self._phase = State(initialValue: .setup)
        } else {
            self._phase = State(initialValue: .courseSelection)
        }
    }

    @State private var phase: Phase
    @State private var roundConfig: RoundConfig?
    @State private var roundCreationTask: Task<Void, Never>?
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
                GroupManagerView(allMembers: initialMembers, selectedCourse: selectedCourse, onCourseChanged: { course in
                    self.selectedCourse = course
                    self.onCourseSelected?(course)
                }, onTeeTimeChanged: onTeeTimeChanged, onRecurrenceChanged: onRecurrenceChanged, initialTeeTime: initialTeeTime, initialTeeTimes: initialTeeTimes, initialBuyIn: initialBuyIn, initialRecurrence: initialRecurrence, groupName: groupName, currentUserId: currentUserId, creatorId: creatorId, isLiveRound: hasStartedRound, roundHistory: roundHistory, onLeaveGroup: onLeaveGroup, onDeleteGroup: onDeleteGroup, scheduledLabel: scheduledLabel, onBack: {
                    if hasStartedRound {
                        // Return to scorecard without rebuilding config
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                            phase = .active
                        }
                    } else if skipCourseSelection {
                        // Came from Skin Games tab — just exit
                        onExit?()
                    } else {
                        // Go back to course selection
                        withAnimation(.easeInOut(duration: 0.3)) {
                            phase = .courseSelection
                        }
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
                        withAnimation(.easeInOut(duration: 0.4)) {
                            phase = .starting
                        }
                        // Stagger the splash animations
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
                .transition(.opacity)

            case .starting:
                roundStartedSplash
                    .transition(.opacity)

            case .active:
                if let activeConfig = roundConfig {
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
                    // Creator declined — just exit
                }, isQuickGame: isQuickGame, currentUserId: currentUserId, demoMode: initialDemoMode, isViewer: isViewer)
                .transition(.move(edge: .bottom))
                } else {
                    // Round still being created — show spinner until roundConfig is ready
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Setting up round...")
                            .font(.carry.bodySM)
                            .foregroundColor(Color.textSecondary)
                    }
                    .onAppear {
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
                holes: config.holes ?? config.teeBox?.holes ?? Hole.allHoles,
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

        // 3. Map players to Supabase UUIDs with group numbers
        var playerTuples: [(userId: UUID, group: Int)] = []
        for gc in config.groups {
            for playerId in gc.playerIDs {
                guard let player = config.players.first(where: { $0.id == playerId }),
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
                buyIn: config.buyIn,
                net: config.skinRules.net,
                carries: config.skinRules.carries,
                outright: config.skinRules.outright,
                handicapPercentage: config.skinRules.handicapPercentage,
                groupId: config.supabaseGroupId,
                scorerId: config.scorerProfileId ?? userId,
                scoringMode: config.scoringMode.rawValue,
                players: playerTuples
            )
            guard !Task.isCancelled else { return }

            // Set roundConfig WITH the round ID so ScorecardView gets it at init
            var configWithRoundId = config
            configWithRoundId.supabaseRoundId = roundDTO.id
            await MainActor.run {
                self.roundConfig = configWithRoundId
            }
            #if DEBUG
            print("[RoundCoordinator] Round created in Supabase: \(roundDTO.id)")
            #endif
            Analytics.roundStarted(groupName: config.groupName, playerCount: config.players.count, buyIn: config.buyIn, courseName: config.course)
        } catch {
            guard !Task.isCancelled else { return }
            #if DEBUG
            print("[RoundCoordinator] Failed to create round: \(error)")
            #endif
            await MainActor.run {
                self.roundConfig = config
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

                    // Back to groups
                    Button {
                        showFlag = false
                        showTitle = false
                        showDetails = false
                        showStats = false
                        pulseFlag = false
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                            phase = .setup
                        }
                    } label: {
                        Text("Back to Groups")
                            .font(.carry.bodySM)
                            .foregroundColor(Color.textPrimary.opacity(0.4))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
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
