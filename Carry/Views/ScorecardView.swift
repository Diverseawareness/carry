import SwiftUI

struct ScorecardView: View {
    @EnvironmentObject var storeService: StoreService
    @EnvironmentObject var appRouter: AppRouter

    let config: RoundConfig
    @State private var isViewer: Bool
    var onBack: (() -> Void)?
    var onEditPlayers: (() -> Void)?
    var onCourseChanged: ((SelectedCourse) -> Void)?
    var onCreateGroup: (() -> Void)?
    var onDeclineGroup: (() -> Void)?
    var isQuickGame: Bool = false
    @StateObject private var viewModel: RoundViewModel
    @State private var showInput = false
    @State private var inputHole: Int?
    @State private var inputPlayer: Player?
    @State private var showLabels = true
    @State private var sheetDrag: CGFloat = 0
    @State private var suppressDetection = false
    @State private var showRoundComplete = false
    @State private var roundCompleteCollapsed = false
    @State private var showOptionsMenu = false
    // Cancel Round (non-destructive black style): quiet hard-delete, no explicit push.
    @State private var showCancelRoundAlert = false
    // End Game (destructive): deletes scores, marks round cancelled, notifies all.
    @State private var showEndGameAlert = false
    // End Game & Save Results: force-concludes with partial scores for all groups.
    @State private var showEndGameSaveAlert = false
    // Shown to non-creators when the creator destructively ended the game.
    @State private var showGameEndedAlert = false
    // Generic failure alert for End Game network/server errors (offline, auth, etc.)
    @State private var showEndGameFailedAlert = false
    /// Set to a short status string while a destructive menu action (Cancel
    /// Round / End Game / End & Save Results) is in flight. Drives a full-
    /// screen blocking overlay so the user gets feedback that something's
    /// happening — and can't re-tap — on flaky networks where the Supabase
    /// call might take several seconds to either succeed or fail.
    @State private var menuActionInFlight: String? = nil
    @State private var showCourseSelector = false
    @State private var showScorerPicker = false
    @State private var activeToast: GameEvent?
    // Share sheet removed — sharing handled in RoundCompleteView
    @State private var showScoringInfo = false
    @State private var showPaywall = false

    private static let scoringInfoKeyPrefix = "scoringInfoShownCount"

    /// Time-only formatter for the scorer's tee time in the header subtitle.
    /// Matches the "12:28 PM" format used elsewhere (group detail meta info).
    static let teeTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    /// Truncate long course names so the header subtitle doesn't wrap or
    /// crowd the tee time + tee box elements. "Ruby Hill GC" = 12 chars is
    /// the reference width; anything longer gets an ellipsis.
    private static func truncatedCourse(_ name: String, max: Int = 12) -> String {
        name.count <= max ? name : String(name.prefix(max)) + "…"
    }

    let currentUserId: Int

    init(config: RoundConfig, onBack: (() -> Void)? = nil, onEditPlayers: (() -> Void)? = nil, onCourseChanged: ((SelectedCourse) -> Void)? = nil, onCreateGroup: (() -> Void)? = nil, onDeclineGroup: (() -> Void)? = nil, isQuickGame: Bool = false, currentUserId: Int = 1, demoScores: Bool = false, demoMode: RoundViewModel.DemoMode = .none, isViewer: Bool = false) {
        self.config = config
        // In "everyone scores" mode, nobody is a viewer — all players can enter scores
        self._isViewer = State(initialValue: config.scoringMode == .everyone ? false : isViewer)
        self.onBack = onBack
        self.onEditPlayers = onEditPlayers
        self.onCourseChanged = onCourseChanged
        self.onCreateGroup = onCreateGroup
        self.onDeclineGroup = onDeclineGroup
        self.isQuickGame = isQuickGame
        self.currentUserId = currentUserId
        let mode: RoundViewModel.DemoMode = demoScores ? .midGame : demoMode
        _viewModel = StateObject(wrappedValue: RoundViewModel(config: config, currentUserId: currentUserId, demoMode: mode))
    }

    /// Init with an externally-owned viewmodel (keeps state across navigation)
    init(viewModel: RoundViewModel, onBack: (() -> Void)? = nil, onEditPlayers: (() -> Void)? = nil, onCourseChanged: ((SelectedCourse) -> Void)? = nil, isQuickGame: Bool = false) {
        self.config = viewModel.config
        self._isViewer = State(initialValue: false)
        self.onBack = onBack
        self.onEditPlayers = onEditPlayers
        self.onCourseChanged = onCourseChanged
        self.isQuickGame = isQuickGame
        self.currentUserId = viewModel.currentUserId
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var safeAreaInsets: (top: CGFloat, bottom: CGFloat) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first
        else { return (59, 34) }
        return (window.safeAreaInsets.top, window.safeAreaInsets.bottom)
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let insets = safeAreaInsets
                let topPad = insets.top - 7
                let collapsedBarH: CGFloat = (showRoundComplete && roundCompleteCollapsed) ? 90 : 0
                let contentH = UIScreen.main.bounds.height - topPad - insets.bottom - collapsedBarH
                let stableSize = CGSize(width: geo.size.width, height: contentH)
                let layout = LayoutMetrics(size: stableSize, playerCount: viewModel.groupPlayers.count)
                mainContent(layout: layout)
                    .padding(.top, topPad)
            }

            if showScoringInfo {
                ScoringInfoModal(isQuickGame: isQuickGame) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        showScoringInfo = false
                    }
                }
                .transition(.opacity)
                .zIndex(100)
            }

            // Score dispute modal (Everyone Scores mode)
            if let proposal = viewModel.activeProposal {
                scoreDisputeOverlay(proposal: proposal)
                    .transition(.opacity)
                    .zIndex(200)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .ignoresSafeArea(.keyboard)
        .onAppear {
            // Only show scoring info when scorecard opens to hole 1 (not from final results)
            guard viewModel.activeHole == 1 else { return }
            // Quick Games: only the dedicated scorer sees the "Keeping Score" coachmark.
            // Non-scorers (other Carry users in the group) can't enter scores, so the
            // "You're the Scorer" copy doesn't apply to them.
            if isQuickGame && !viewModel.isCurrentUserScorerForOwnGroup { return }
            let perUserKey = "\(Self.scoringInfoKeyPrefix)_\(currentUserId)"
            let count = UserDefaults.standard.integer(forKey: perUserKey)
            if count < 5 {
                UserDefaults.standard.set(count + 1, forKey: perUserKey)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        showScoringInfo = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mainContent(layout: LayoutMetrics) -> some View {
        let players = viewModel.groupPlayers
        let active = viewModel.activeHole

        ZStack(alignment: .top) {
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar()

                CashGamesBar(viewModel: viewModel)
                    .padding(.horizontal, layout.cardM)
                    .padding(.top, layout.gapAbovePills)
                    .padding(.bottom, layout.gapBelowPills)

                scorecardSection(layout: layout, players: players, active: active)
            }

            scoreInputOverlay()

            // Toast notification overlay
            VStack {
                if let toast = activeToast {
                    GameToastView(event: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .zIndex(5)
                }
                Spacer()
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: activeToast?.id)
            .allowsHitTesting(false)

            // Round complete overlay
            if showRoundComplete {
                RoundCompleteView(viewModel: viewModel, onDismiss: {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        showRoundComplete = false
                    }
                }, onExitRound: {
                    // DO NOT mark the round as completed here. RoundCompleteView's individual
                    // buttons mark their own status (Save Round Results / Skip / Create Group
                    // → completed; "Done — Waiting on others" → keeps round active).
                    // This wrapper is JUST an exit shortcut now.
                    onBack?()
                }, isCreator: currentUserId == config.creatorId,
                   isQuickGame: isQuickGame,
                   onCreateGroup: onCreateGroup,
                   onDeclineGroup: onDeclineGroup,
                   isCollapsed: $roundCompleteCollapsed)
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .overlay {
            if let label = menuActionInFlight {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.1)
                        Text(label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.textPrimary)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                    )
                }
                .transition(.opacity)
                .zIndex(20)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: menuActionInFlight)
        .onReceive(viewModel.$myGroupFinished) { finished in
            if finished && !showRoundComplete {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    showRoundComplete = true
                }
            }
        }
        .onReceive(viewModel.$gameEvents) { events in
            guard !events.isEmpty, activeToast == nil else { return }
            showNextToast()
        }
        .alert("Cancel Round?", isPresented: $showCancelRoundAlert) {
            Button("Keep Playing", role: .cancel) { }
            Button("Cancel Round", role: .destructive) {
                Task {
                    await MainActor.run { menuActionInFlight = "Cancelling round…" }
                    if let roundId = viewModel.config.supabaseRoundId {
                        try? await RoundService().deleteRound(roundId: roundId)
                    }
                    await MainActor.run {
                        menuActionInFlight = nil
                        NotificationCenter.default.post(name: .didCancelRound, object: nil)
                        onBack?()
                    }
                }
            }
        } message: {
            Text("This will delete the round and all scores. Your game setup will be preserved.")
        }
        .alert("End Game?", isPresented: $showEndGameAlert) {
            Button("Keep Playing", role: .cancel) { }
            Button("End Game", role: .destructive) {
                Task {
                    guard let roundId = viewModel.config.supabaseRoundId else {
                        await MainActor.run { showEndGameFailedAlert = true }
                        return
                    }
                    await MainActor.run { menuActionInFlight = "Ending game…" }
                    do {
                        try await RoundService().endGameDestructively(roundId: roundId)
                        // Quick Games have no life beyond the current round —
                        // ending the game should also remove the skins_groups
                        // row so it stops showing in everyone's Games tab.
                        // Skins Groups keep their group entity; only the round
                        // is cancelled.
                        if isQuickGame, let groupId = viewModel.config.supabaseGroupId {
                            try? await GroupService().deleteGroup(groupId: groupId)
                        }
                        await MainActor.run {
                            menuActionInFlight = nil
                            NotificationCenter.default.post(name: .didCancelRound, object: nil)
                            onBack?()
                        }
                    } catch {
                        await MainActor.run {
                            menuActionInFlight = nil
                            showEndGameFailedAlert = true
                        }
                    }
                }
            }
        } message: {
            Text(isQuickGame
                ? "This will delete the Quick Game and all scores for everyone. All participants will be notified."
                : "This will delete the round and all scores for everyone. All participants will be notified.")
        }
        .alert("End Game & Save Results?", isPresented: $showEndGameSaveAlert) {
            Button("Keep Playing", role: .cancel) { }
            Button("End & Save", role: .destructive) {
                Task {
                    guard let roundId = viewModel.config.supabaseRoundId else {
                        await MainActor.run { showEndGameFailedAlert = true }
                        return
                    }
                    await MainActor.run { menuActionInFlight = "Saving results…" }
                    do {
                        try await RoundService().forceEndRoundWithResults(roundId: roundId)
                        if let groupId = viewModel.config.supabaseGroupId {
                            await GroupService().advanceScheduledDateIfRecurring(groupId: groupId)
                        }
                        await MainActor.run {
                            menuActionInFlight = nil
                            viewModel.forceCompleted = true
                            viewModel.calculateSkins()
                            NotificationCenter.default.post(name: .didEndRound, object: nil)
                            viewModel.isRoundComplete = true
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                showRoundComplete = true
                            }
                        }
                    } catch {
                        await MainActor.run {
                            menuActionInFlight = nil
                            showEndGameFailedAlert = true
                        }
                    }
                }
            }
        } message: {
            Text(viewModel.allGroupsFinished
                 ? "This will end the game and save final results for everyone. All participants will be notified."
                 : "This will end the game for all groups and save results with whatever scores exist. Skins will be calculated from completed holes. All participants will be notified.")
        }
        .alert(
            viewModel.roundCancellationKind == .cancelled ? "Round Cancelled" : "Game Ended",
            isPresented: $showGameEndedAlert
        ) {
            Button("OK") {
                // After a cancel (round deleted, group preserved), route
                // members straight to the Quick Game detail view so they
                // land somewhere useful instead of the Home tab with a
                // vanished card. End Game (group removed) and creator
                // actions keep the normal exit path — the group no longer
                // exists / they're the one who chose to leave.
                let isMember = viewModel.config.creatorId.map { $0 != currentUserId } ?? false
                if viewModel.roundCancellationKind == .cancelled,
                   isMember,
                   isQuickGame,
                   let groupId = viewModel.config.supabaseGroupId {
                    appRouter.navigateToTab = "skinGames"
                    appRouter.pendingRoundGroupId = groupId
                }
                onBack?()
            }
        } message: {
            Text({
                switch viewModel.roundCancellationKind {
                case .cancelled:
                    return isQuickGame
                        ? "The host cancelled this round. No scores were saved — they can start a new round anytime."
                        : "The host cancelled this round. No scores were saved."
                case .ended:
                    return isQuickGame
                        ? "The host ended this game. The Quick Game was removed and no scores were saved."
                        : "The host ended this game. No scores were saved."
                case .none:
                    return "The round has ended."
                }
            }())
        }
        .alert("Couldn't End Game", isPresented: $showEndGameFailedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Check your connection and try again.")
        }
        .onReceive(viewModel.$roundWasCancelled) { cancelled in
            if cancelled {
                showGameEndedAlert = true
            }
        }
        .fullScreenCover(isPresented: $showCourseSelector) {
            CourseSelectionView { course in
                onCourseChanged?(course)
                showCourseSelector = false
            }
            .presentationBackground(.white)
        }
        .sheet(isPresented: $showScorerPicker) {
            scorerPickerSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(trigger: .scoreRound)
                .environmentObject(storeService)
        }
    }

    // MARK: - Scorer Picker

    @ViewBuilder
    private func scorerPickerSheet() -> some View {
        VStack(spacing: 0) {
            Text("Change Scorer")
                .font(.carry.headline)
                .foregroundColor(Color.textPrimary)
                .padding(.top, 24)
                .padding(.bottom, 4)

            Text("Select who enters scores")
                .font(.carry.caption)
                .foregroundColor(Color.textSecondary)
                .padding(.bottom, 20)

            ForEach(config.players) { player in
                let isCurrentScorer = player.id == (viewModel.config.scorerProfileId.map { Player.stableId(from: $0) } ?? config.creatorId)

                Button {
                    changeScorer(to: player)
                } label: {
                    HStack(spacing: 14) {
                        PlayerAvatar(player: player, size: 43)

                        Text(player.shortName)
                            .font(.carry.bodySemibold)
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        if isCurrentScorer {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Color.goldAccent)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                if player.id != config.players.last?.id {
                    Divider().padding(.leading, 81)
                }
            }

            Spacer()
        }
    }

    private func changeScorer(to player: Player) {
        guard let roundId = config.supabaseRoundId,
              let profileId = player.profileId else {
            showScorerPicker = false
            return
        }

        // Update locally
        if config.scoringMode == .everyone {
            isViewer = false
        } else {
            let isCreator = currentUserId == config.creatorId
            let isNewScorer = player.id == currentUserId
            isViewer = !isCreator && !isNewScorer
        }

        showScorerPicker = false

        // Update Supabase
        Task {
            do {
                try await RoundService().updateScorer(roundId: roundId, scorerId: profileId)
                await MainActor.run {
                    ToastManager.shared.success("\(player.shortName) is now the scorer")
                }
            } catch {
                #if DEBUG
                print("[ScorecardView] Failed to update scorer: \(error)")
                #endif
            }
        }
    }

    @ViewBuilder
    private func headerBar() -> some View {
        ZStack {
            // Centered title + subtitle
            VStack(spacing: 2) {
                Spacer().frame(height: 4)
                HStack(spacing: 6) {
                    Text(config.groupName)
                        .font(.carry.headline)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !SyncQueue.shared.isOnline {
                        Image(systemName: "icloud.slash")
                            .font(.system(size: 11))
                            .foregroundColor(Color.textDisabled)
                    } else if SyncQueue.shared.pendingCount > 0 {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                            .foregroundColor(Color.goldMuted)
                    }
                }
                HStack(spacing: 4) {
                    if let teeTime = config.scorerTeeTime {
                        Text(Self.teeTimeFormatter.string(from: teeTime))
                            .font(.carry.caption)
                            .foregroundColor(Color.textSecondary)
                        Text("·")
                            .font(.carry.caption)
                            .foregroundColor(Color.textDisabled)
                    }
                    Text(Self.truncatedCourse(config.course))
                        .font(.carry.caption)
                        .foregroundColor(Color.textSecondary)
                    if let tee = config.teeBox {
                        Circle()
                            .fill(Color(hexString: tee.color))
                            .frame(width: 6, height: 6)
                        Text(tee.name)
                            .font(.carry.caption)
                            .foregroundColor(Color.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 56)

            // Leading close button + trailing options
            HStack {
                if let onBack {
                    Button {
                        onBack()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.white))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Close scorecard")
                    .accessibilityHint("Returns to the previous screen")
                }

                Spacer()

                // Options button — creator only
                if currentUserId == config.creatorId {
                Menu {
                    let isRoundCreator = true

                    // Group Settings intentionally omitted mid-round — it flips the
                    // whole flow back to setup phase which is a footgun while scores
                    // exist. onEditPlayers prop kept for future lighter edit paths.

                    // Change Scorer is meaningless in "everyone scores" mode —
                    // there's no single designated scorer to swap. Only surface
                    // it for Skins Groups running the single-scorer variant.
                    if isRoundCreator && !isQuickGame && config.scoringMode != .everyone {
                        Button {
                            showScorerPicker = true
                        } label: {
                            Label("Change Scorer", systemImage: "person.badge.key")
                        }
                    }

                    if isRoundCreator {
                        Divider()

                        Button {
                            showCancelRoundAlert = true
                        } label: {
                            Label("Cancel Round", systemImage: "trash")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showEndGameAlert = true
                        } label: {
                            Label("End Game", systemImage: "trash")
                        }

                        Button(role: .destructive) {
                            showEndGameSaveAlert = true
                        } label: {
                            Label("End Game & Save Results", systemImage: "checkmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.white))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Round options")
                .accessibilityHint("Shows group settings and round options")
                } // end if creator
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func scorecardSection(layout: LayoutMetrics, players: [Player], active: Int?) -> some View {
        ZStack(alignment: .topLeading) {
            scrollableContent(layout: layout, players: players, active: active)
            if showLabels {
                stickyLeftColumn(layout: layout, players: players)
                    .transition(.move(edge: .leading))
            }
        }
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, layout.cardM)
    }

    @ViewBuilder
    private func scrollableContent(layout: LayoutMetrics, players: [Player], active: Int?) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Detector must be INSIDE VStack (not .background) to guarantee
                    // it's in the UIScrollView's content hierarchy on first load.
                    ScrollDirectionDetector(suppressDetection: $suppressDetection) { shouldShow in
                        guard shouldShow != showLabels else { return }
                        withAnimation(.easeOut(duration: shouldShow ? 0.1 : 0.15)) {
                            showLabels = shouldShow
                        }
                    }
                    .frame(height: 0)

                    SkinsRow(
                        viewModel: viewModel,
                        holes: viewModel.holes,
                        activeHole: active,
                        cellWidth: layout.cellW,
                        sumWidth: layout.sumW,
                        skinsHeight: layout.skinsH
                    )
                    .background(Color.bgCard)

                    Rectangle().fill(Color.gridLine).frame(height: 1)
                        .accessibilityHidden(true)

                    HoleHeaderRow(
                        holes: viewModel.holes,
                        activeHole: active,
                        cellWidth: layout.cellW,
                        sumWidth: layout.sumW,
                        rowHeight: layout.holeRowH,
                        numFont: layout.numFont
                    )

                    Rectangle().fill(Color.gridLine).frame(height: 1)
                        .accessibilityHidden(true)

                    playerRows(layout: layout, players: players, active: active)
                }
                .overlay(alignment: .topLeading) {
                    // Single continuous stroke around the active hole column
                    ActiveHoleStroke(
                        activeHole: active,
                        cellWidth: layout.cellW
                    )
                }
                .padding(.leading, layout.labelW)
            }
            .onAppear {
                if let num = active, num != viewModel.playOrder.first?.num {
                    suppressDetection = true
                    proxy.scrollTo("hole_\(num)", anchor: .center)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        suppressDetection = false
                    }
                }
            }
            .onChange(of: active) { _, newActive in
                if let num = newActive {
                    suppressDetection = true
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        proxy.scrollTo("hole_\(num)", anchor: .center)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        suppressDetection = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func playerRows(layout: LayoutMetrics, players: [Player], active: Int?) -> some View {
        let minRows = 4
        ForEach(players) { player in
            let isYou = player.id == viewModel.currentUserId

            PlayerRow(
                player: player,
                holes: viewModel.holes,
                viewModel: viewModel,
                activeHole: active,
                cellWidth: layout.cellW,
                sumWidth: layout.sumW,
                rowHeight: layout.rowH,
                scoreFont: layout.scoreFont,
                circleSize: layout.circleSize,
                isYou: isYou,
                onTapCell: { holeNum, p in
                    if isViewer {
                        #if DEBUG
                        print("[Scorecard.tap] BLOCKED isViewer=true scoringMode=\(config.scoringMode) passedIsViewer=unknown hole=\(holeNum) player=\(p.id)")
                        #endif
                        return
                    }
                    if viewModel.isScoringBlocked {
                        #if DEBUG
                        print("[Scorecard.tap] BLOCKED isScoringBlocked activeProposal=\(String(describing: viewModel.activeProposal)) hole=\(holeNum) player=\(p.id)")
                        #endif
                        return
                    }
                    if showRoundComplete && !roundCompleteCollapsed {
                        #if DEBUG
                        print("[Scorecard.tap] BLOCKED showRoundComplete=true collapsed=\(roundCompleteCollapsed) hole=\(holeNum) player=\(p.id)")
                        #endif
                        return
                    }
                    if !viewModel.canScore(holeNum: holeNum) {
                        #if DEBUG
                        print("[Scorecard.tap] BLOCKED canScore=false hole=\(holeNum) player=\(p.id)")
                        #endif
                        return
                    }
                    if config.isQuickGame && !viewModel.isCurrentUserScorerForOwnGroup {
                        #if DEBUG
                        print("[Scorecard.tap] BLOCKED Quick Game scorer-only — current user is not designated scorer for their group")
                        #endif
                        return
                    }
                    #if DEBUG
                    print("[Scorecard.tap] OK hole=\(holeNum) player=\(p.id) scoringMode=\(config.scoringMode)")
                    #endif
                    inputHole = holeNum
                    inputPlayer = p
                    sheetDrag = 0
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                        showInput = true
                    }
                }
            )
            .background(isYou ? Color.gold.opacity(0.03) : .clear)

            Rectangle()
                .fill(Color.gridLine)
                .frame(height: 1)
                .accessibilityHidden(true)
        }

        // Empty placeholder rows to fill to minRows
        if players.count < minRows {
            ForEach(0..<(minRows - players.count), id: \.self) { _ in
                Color.clear
                    .frame(height: layout.rowH)

                Rectangle()
                    .fill(Color.gridLine)
                    .frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private func stickyLeftColumn(layout: LayoutMetrics, players: [Player]) -> some View {
        VStack(spacing: 0) {
            stickyLabel(text: "Skins", height: layout.skinsH, font: layout.labelFont, bg: Color.bgCard, layout: layout)
                .accessibilityAddTraits(.isHeader)

            Rectangle().fill(Color.gridLine).frame(height: 1)
                .accessibilityHidden(true)

            stickyLabel(text: "Hole", height: layout.holeRowH, font: layout.labelFont, bg: .white, layout: layout)
                .accessibilityAddTraits(.isHeader)

            Rectangle().fill(Color.gridLine).frame(height: 1)
                .accessibilityHidden(true)

            stickyPlayerLabels(layout: layout, players: players)
        }
        .frame(width: layout.labelW)
        .background(.white)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 0, topTrailingRadius: 0))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.gridLine)
                .frame(width: 1)
                .accessibilityHidden(true)
        }
        .shadow(color: .black.opacity(0.04), radius: 4, x: 4)
    }

    @ViewBuilder
    private func stickyPlayerLabels(layout: LayoutMetrics, players: [Player]) -> some View {
        let minRows = 4
        ForEach(players) { player in
            let isYou = player.id == viewModel.currentUserId
            let bg = isYou ? Color(hexString: "#FFFDF7") : Color.white

            Text(player.shortName)
                .font(.system(size: layout.labelFont, weight: isYou ? .bold : .medium))
                .foregroundColor(isYou ? Color.textPrimary : Color.textMid)
                .lineLimit(1)
                .padding(.leading, layout.labelPad)
            .frame(width: layout.labelW, height: layout.rowH, alignment: .leading)
            .background(bg)

            Rectangle().fill(Color.gridLine).frame(height: 1)
                .background(bg)
        }

        // Empty placeholder rows to fill to minRows
        if players.count < minRows {
            ForEach(0..<(minRows - players.count), id: \.self) { _ in
                Color.white
                    .frame(width: layout.labelW, height: layout.rowH)

                Rectangle().fill(Color.gridLine).frame(height: 1)
            }
        }
    }

    /// Next unscored player on the current hole, or first unscored player on the next hole.
    /// Returns (player, hole) — hole may differ from input when advancing to the next hole.
    private func nextUnscoredTarget(after player: Player, hole: Int) -> (Player, Int)? {
        let group = viewModel.groupPlayers
        guard let idx = group.firstIndex(where: { $0.id == player.id }) else { return nil }

        // First: find next unscored player on the SAME hole
        for offset in 1..<group.count {
            let next = group[(idx + offset) % group.count]
            if viewModel.scores[next.id]?[hole] == nil {
                return (next, hole)
            }
        }

        // All players scored this hole — advance to next hole's first unscored player
        let order = viewModel.playOrder
        guard let holeIdx = order.firstIndex(where: { $0.num == hole }) else { return nil }
        for hOffset in 1..<order.count {
            let nextHole = order[(holeIdx + hOffset) % order.count]
            if let first = group.first(where: { viewModel.scores[$0.id]?[nextHole.num] == nil }) {
                return (first, nextHole.num)
            }
        }

        return nil
    }

    // MARK: - Toast Queue

    private func showNextToast() {
        guard let event = viewModel.gameEvents.first, activeToast == nil else { return }
        viewModel.consumeGameEvent(event)
        withAnimation {
            activeToast = event
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                activeToast = nil
            }
            // Check for more queued events after brief gap
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showNextToast()
            }
        }
    }

    // MARK: - Score Dispute Modal (Everyone Scores)

    @ViewBuilder
    private func scoreDisputeOverlay(proposal: (playerId: Int, holeNum: Int, original: Int, proposed: Int, proposedByUUID: UUID)) -> some View {
        let playerName = viewModel.allPlayers.first(where: { $0.id == proposal.playerId })?.name ?? "Player"
        // Reserved for future dispute UI enhancement:
        // let proposerName = viewModel.allPlayers.first(where: { viewModel.playerUUIDs[$0.id] == proposal.proposedByUUID })?.name ?? "Someone"
        // let originalEnteredBy = viewModel.allPlayers.first(where: { viewModel.playerUUIDs[$0.id] != proposal.proposedByUUID && $0.id != proposal.playerId })?.name ?? "Scorer"

        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Title
                Text("Score Conflict")
                    .font(.carry.label)
                    .foregroundColor(Color.deepNavy)
                    .padding(.top, 26)

                // Hole & player
                Text("Hole \(proposal.holeNum) - \(playerName)")
                    .font(.carry.sectionTitle)
                    .foregroundColor(Color.textPrimary)
                    .padding(.top, 22)

                // Current → Proposed
                HStack(spacing: 54) {
                    VStack(spacing: 14) {
                        Text("Current")
                            .font(.carry.bodySM)
                            .foregroundColor(Color.textSecondary)
                        Text("\(proposal.original)")
                            .font(.carry.displaySM)
                            .foregroundColor(Color.textPrimary)
                    }

                    Image(systemName: "arrow.right")
                        .font(.carry.bodyLG)
                        .foregroundColor(Color.textSecondary)

                    VStack(spacing: 14) {
                        Text("Proposed")
                            .font(.carry.bodySM)
                            .foregroundColor(Color.textSecondary)
                        Text("\(proposal.proposed)")
                            .font(.carry.displaySM)
                            .foregroundColor(Color.textPrimary)
                    }
                }
                .padding(.top, 33)

                // Action buttons
                HStack(spacing: 10) {
                    Button {
                        viewModel.resolveActiveProposal(accept: false)
                    } label: {
                        Text("Keep \(proposal.original)")
                            .font(.carry.bodyLGSemibold)
                            .foregroundColor(Color.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 13)
                                    .strokeBorder(Color.textPrimary, lineWidth: 1)
                            )
                    }

                    Button {
                        viewModel.resolveActiveProposal(accept: true)
                    } label: {
                        Text("Accept \(proposal.proposed)")
                            .font(.carry.bodyLGSemibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 13)
                                    .fill(Color.textPrimary)
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 33)
                .padding(.bottom, 35)
            }
            .background(
                RoundedRectangle(cornerRadius: 21)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            )
            .padding(.horizontal, 32)
        }
    }

    @ViewBuilder
    private func scoreInputOverlay() -> some View {
        if showInput, let hole = inputHole, let player = inputPlayer {
            let existingScore = viewModel.scores[player.id]?[hole]
            let strokes: Int = {
                if let h = viewModel.holes.first(where: { $0.num == hole }) {
                    return viewModel.strokes(for: player, hole: h)
                }
                return 0
            }()
            let dismiss: () -> Void = {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    showInput = false; inputPlayer = nil
                }
            }
            // Scoring is gated at the UI layer — we don't write the score,
            // we open the paywall with the .scoreRound trigger and dismiss
            // the input so the user returns to the scorecard cleanly.
            let onSelect: (Int) -> Void = { score in
                guard storeService.isPremium else {
                    dismiss()
                    showPaywall = true
                    return
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    viewModel.enterScore(playerId: player.id, holeNum: hole, score: score)
                }
                dismiss()
            }
            let nextTarget = nextUnscoredTarget(after: player, hole: hole)
            let onScoreNext: ((Int) -> Void) = { score in
                guard storeService.isPremium else {
                    dismiss()
                    showPaywall = true
                    return
                }
                viewModel.enterScore(playerId: player.id, holeNum: hole, score: score)
                if let (nextP, nextH) = nextTarget, nextH == hole {
                    // Same hole — rotate to next unscored player
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        inputPlayer = nextP
                    }
                } else {
                    // All players scored this hole (or round complete) — dismiss
                    dismiss()
                }
            }

            ZStack(alignment: .bottom) {
                // ── Dim backdrop ─────────────────────────────────────────
                Color.black.opacity(0.30)
                    .ignoresSafeArea()
                    .onTapGesture { sheetDrag = 0; dismiss() }
                    .transition(.opacity)

                // ── Sheet card ───────────────────────────────────────────
                VStack(spacing: 0) {
                    // Drag handle
                    Capsule()
                        .fill(Color.gridLine)
                        .frame(width: 36, height: 4)
                        .padding(.top, 17)
                        .padding(.bottom, 0)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(Rectangle())
                        .accessibilityHidden(true)

                    ScoreInputSheet(
                        player: player,
                        holeNum: hole,
                        holes: viewModel.holes,
                        strokesGiven: strokes,
                        currentScore: existingScore,
                        onSelect: onSelect,
                        onScoreNext: onScoreNext,
                        extraBottomPadding: roundCompleteCollapsed ? 88 : 0
                    )
                    .id(player.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
                .clipped()
                // Fixed 62% of screen — matches Figma score sheet proportions
                .frame(height: UIScreen.main.bounds.height * 0.62 + (roundCompleteCollapsed ? 90 : 0))
                .offset(y: max(0, sheetDrag))
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            if v.translation.height > 0 {
                                sheetDrag = v.translation.height
                            }
                        }
                        .onEnded { v in
                            let velocity = v.predictedEndTranslation.height
                            if v.translation.height > 80 || velocity > 300 {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                    sheetDrag = UIScreen.main.bounds.height * 0.5
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    showInput = false; inputPlayer = nil; sheetDrag = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    sheetDrag = 0
                                }
                            }
                        }
                )
                .background(
                    Group {
                        if roundCompleteCollapsed {
                            // Flat bottom — fills seamlessly into the collapsed bar
                            UnevenRoundedRectangle(
                                topLeadingRadius: 48,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 48,
                                style: .continuous
                            )
                            .fill(Color.white)
                        } else {
                            RoundedRectangle(cornerRadius: 48, style: .continuous)
                                .fill(Color.white)
                                .ignoresSafeArea(edges: .bottom)
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func stickyLabel(text: String, height: CGFloat, font: CGFloat, bg: Color, layout: LayoutMetrics) -> some View {
        Text(text)
            .font(.system(size: font, weight: .semibold))
            .foregroundColor(Color.textPrimary)
            .padding(.leading, layout.labelPad)
            .frame(width: layout.labelW, height: height, alignment: .leading)
            .background(bg)
    }
}

// MARK: - Scroll Direction Detection

/// Placed inside ScrollView content VStack. Uses CADisplayLink to poll
/// for the parent UIScrollView every frame until found (handles SwiftUI's
/// deferred UIScrollView creation on first app launch).
private struct ScrollDirectionDetector: UIViewRepresentable {
    @Binding var suppressDetection: Bool
    var onDirectionChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDirectionChange: onDirectionChange)
    }

    func makeUIView(context: Context) -> ProbeView {
        let v = ProbeView()
        v.coordinator = context.coordinator
        return v
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.onDirectionChange = onDirectionChange
        context.coordinator.isSuppressed = suppressDetection
    }

    /// Zero-size, touch-transparent view that polls for its parent UIScrollView.
    class ProbeView: UIView {
        weak var coordinator: Coordinator?
        private var displayLink: CADisplayLink?
        private var frameCount = 0

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                startPolling()
            } else {
                stopPolling()
            }
        }

        private func startPolling() {
            guard displayLink == nil else { return }
            frameCount = 0
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func stopPolling() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func tick() {
            frameCount += 1
            guard let coordinator else { stopPolling(); return }
            if coordinator.isAttached { stopPolling(); return }

            // Walk up superview chain
            coordinator.tryAttachUp(from: self)

            // If walk-up failed, search entire window hierarchy as fallback
            if !coordinator.isAttached, let window {
                coordinator.tryAttachFromWindow(window)
            }

            // Stop after ~2 seconds (120 frames at 60fps)
            if coordinator.isAttached || frameCount > 120 {
                stopPolling()
            }
        }

        deinit { stopPolling() }
    }

    class Coordinator: NSObject {
        var onDirectionChange: (Bool) -> Void
        var isSuppressed = false
        private weak var scrollView: UIScrollView?

        var isAttached: Bool { scrollView != nil }

        init(onDirectionChange: @escaping (Bool) -> Void) {
            self.onDirectionChange = onDirectionChange
        }

        /// Walk up the superview chain looking for a UIScrollView.
        func tryAttachUp(from view: UIView) {
            guard scrollView == nil else { return }
            var current: UIView? = view.superview
            while let v = current {
                if let sv = v as? UIScrollView {
                    attach(to: sv)
                    return
                }
                current = v.superview
            }
        }

        /// Search the entire window hierarchy for the first horizontal UIScrollView.
        func tryAttachFromWindow(_ window: UIWindow) {
            guard scrollView == nil else { return }
            if let sv = Self.findHorizontalScrollView(in: window) {
                attach(to: sv)
            }
        }

        private static func findHorizontalScrollView(in view: UIView) -> UIScrollView? {
            for sub in view.subviews {
                if let sv = sub as? UIScrollView, sv.alwaysBounceHorizontal || sv.contentSize.width > sv.bounds.width {
                    return sv
                }
                if let found = findHorizontalScrollView(in: sub) {
                    return found
                }
            }
            return nil
        }

        private func attach(to sv: UIScrollView) {
            scrollView = sv
            sv.delaysContentTouches = false
            sv.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard !isSuppressed else { return }
            guard gesture.state == .ended || gesture.state == .cancelled else { return }
            let vx = gesture.velocity(in: gesture.view).x
            if vx > 150 {
                DispatchQueue.main.async { self.onDirectionChange(true) }
            } else if vx < -150 {
                DispatchQueue.main.async { self.onDirectionChange(false) }
            }
        }

        deinit {
            if let sv = scrollView {
                sv.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
            }
        }
    }
}

// MARK: - Active Hole Column Stroke

private struct ActiveHoleStroke: View {
    let activeHole: Int?
    let cellWidth: CGFloat

    private var columnIndex: Int {
        guard let num = activeHole else { return 0 }
        // Holes are always numbered 1-18 in order
        return max(0, num - 1)
    }

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.textPrimary, lineWidth: 1.5)
                .frame(width: cellWidth, height: geo.size.height)
                .offset(x: CGFloat(columnIndex) * cellWidth)
                .opacity(activeHole != nil ? 1 : 0)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: activeHole)
        .allowsHitTesting(false)
    }
}

// MARK: - Layout Metrics

private struct LayoutMetrics {
    let cardM: CGFloat
    let headerH: CGFloat
    let gap: CGFloat
    let gapAbovePills: CGFloat
    let gapBelowPills: CGFloat
    let rowH: CGFloat
    let holeRowH: CGFloat
    let skinsH: CGFloat
    let labelFont: CGFloat
    let avatarSize: CGFloat
    let labelPad: CGFloat
    let labelW: CGFloat
    let cellW: CGFloat
    let sumW: CGFloat
    let scoreFont: CGFloat
    let circleSize: CGFloat
    let numFont: CGFloat

    init(size: CGSize, playerCount: Int) {
        // size.height is the usable content height (safe areas already subtracted)
        let h = size.height
        cardM = 12
        headerH = 34
        let gamesBarH: CGFloat = 110
        gap = 4
        // Split vertical breathing room around the CashGamesBar:
        // 10% less above pills, 40% less below (tighter layout)
        gapAbovePills = 2
        gapBelowPills = 0   // scorecard sits tight against pills

        // Fixed base for sizing text/cells (as if 6 rows)
        let baseRow = max(32, floor((h - headerH - gamesBarH - gap * 2 - cardM) / 6))

        // Compact header rows based on baseRow
        skinsH = 48  // match CashGamesBar pill avatar (40px) + padding
        holeRowH = max(24, floor(baseRow * 0.6))

        // Player rows grow to fill remaining space — always size for at least 4 rows
        let displayRows = CGFloat(max(4, playerCount))
        let dividers: CGFloat = 3
        let playerDividers = CGFloat(max(0, Int(displayRows) - 1))
        let cardH = h - headerH - gamesBarH - gap + 4  // reclaimed 4px from pill gap
        let fixedH = skinsH + holeRowH + dividers + playerDividers
        rowH = max(baseRow, floor((cardH - fixedH) / displayRows))

        // Fonts and element sizes stay based on baseRow (don't grow)
        labelFont = 18
        avatarSize = max(18, baseRow * 0.4)
        labelPad = 12
        let fontSize: CGFloat = labelFont
        let textW = CGFloat(MAX_NAME_CHARS) * fontSize * 0.5
        labelW = ceil(labelPad + textW + 10)
        cellW = max(36, floor(baseRow * 1.1))
        sumW = max(38, floor(cellW * 1.05))
        scoreFont = max(14, floor(baseRow * 0.38))
        circleSize = max(24, floor(baseRow * 0.55))
        numFont = max(12, floor(baseRow * 0.3))
    }
}


