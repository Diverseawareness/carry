import SwiftUI

// MARK: - Round Stats — Pure Logic (testable)

/// Pure computation for the per-player score stats line shown in
/// `RoundStatsView`. Separated from the view so it can be unit-tested.
/// Example output: `"38 · 38 76, 3 Birdies, 1 Bogey"`
enum RoundStatsLine {
    /// Builds the stats line for a player's gross scores.
    /// - Parameters:
    ///   - playerScores: `[holeNum: grossScore]`. 0 / missing values are ignored.
    ///   - parsByHole: `[holeNum: par]`. Holes with no par are ignored.
    /// - Returns: `nil` if no usable scores exist, otherwise the formatted line.
    ///
    /// Pars are intentionally omitted from the display — they're the implied
    /// default and just add visual noise. Only notable holes (eagles, birdies,
    /// bogeys, doubles+) are surfaced.
    static func make(
        playerScores: [Int: Int],
        parsByHole: [Int: Int]
    ) -> String? {
        guard !playerScores.isEmpty else { return nil }

        var frontStrokes = 0
        var backStrokes = 0
        var eagles = 0, birdies = 0, bogeys = 0, doubleBogeysOrWorse = 0

        for (holeNum, gross) in playerScores {
            guard gross > 0 else { continue }           // skip 0/unscored sentinels
            guard let par = parsByHole[holeNum] else { continue }

            if holeNum <= 9 {
                frontStrokes += gross
            } else {
                backStrokes += gross
            }

            let diff = gross - par
            switch diff {
            case ..<(-1):               eagles += 1     // eagle or better
            case -1:                    birdies += 1
            case 1:                     bogeys += 1
            case let d where d >= 2:    doubleBogeysOrWorse += 1
            default:                    break           // par — not surfaced
            }
        }

        let total = frontStrokes + backStrokes
        guard total > 0 else { return nil }

        var parts: [String] = []
        parts.append("\(frontStrokes) \u{00B7} \(backStrokes) \(total)")

        if eagles > 0 { parts.append("\(eagles) Eagle\(eagles == 1 ? "" : "s")") }
        if birdies > 0 { parts.append("\(birdies) Birdie\(birdies == 1 ? "" : "s")") }
        if bogeys > 0 { parts.append("\(bogeys) Bogey\(bogeys == 1 ? "" : "s")") }
        if doubleBogeysOrWorse > 0 {
            parts.append("\(doubleBogeysOrWorse) Double Bogey\(doubleBogeysOrWorse == 1 ? "" : "s")+")
        }

        return parts.joined(separator: ", ")
    }
}

/// Bottom sheet overlay shown when all group players finish 18 holes.
/// Sheet slides up with "Final Results", then transitions to results leaderboard.
/// Can be collapsed to a bottom bar to allow scorecard editing, then expanded again.
struct RoundCompleteView: View {
    @EnvironmentObject var storeService: StoreService
    @ObservedObject var viewModel: RoundViewModel
    let onDismiss: () -> Void
    var onExitRound: (() -> Void)?
    var isCreator: Bool = false
    var isQuickGame: Bool = false
    var onCreateGroup: (() -> Void)?
    var onDeclineGroup: (() -> Void)?

    // MARK: - Animation state

    @State private var showSheet = false
    @State private var showCheckmark = false
    @State private var goldFlash = false
    @State private var showResults = false    // crossfade from celebration → results
    @State private var showWinner = false
    @State private var showLeaderboard = false
    @State private var showActions = false
    @Binding var isCollapsed: Bool
    @State private var shareCardImage: UIImage? = nil
    @State private var showShareSheet = false
    @State private var venmoIndex: Int = 0
    @State private var showCreateGroupCard = false
    @State private var showPaywall = false

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-screen frame keeper (clear, non-interactive)
            Color.clear.ignoresSafeArea()

            // Scrim (only when expanded — removed entirely when collapsed for touch passthrough)
            if showSheet && !isCollapsed {
                Color.black.opacity(0.40)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            isCollapsed = true
                        }
                    }
            }

            // Bottom sheet
            if showSheet {
                VStack(spacing: 0) {
                    // Rounded content area
                    sheetContainer
                        .background(Color.white)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 24,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 24,
                                style: .continuous
                            )
                        )

                    // Plain white fill extending into bottom safe area
                    Color.white
                        .frame(height: 50)
                }
                .shadow(color: isCollapsed ? .black.opacity(0.08) : .clear, radius: 12, y: -4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .gesture(sheetDragGesture)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear {
            startAnimationSequence()
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareCardImage {
                ShareSheet(activityItems: [
                    image,
                    "Check out our skins game results! Get Carry: https://carryapp.site" as String
                ])
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(storeService)
                .onDisappear {
                    // If user subscribed during paywall, proceed with group creation
                    if storeService.isPremium {
                        showCreateGroupCard = false
                        onCreateGroup?()
                    }
                }
        }
        .overlay {
            if showCreateGroupCard {
                createGroupCardOverlay
            }
        }
    }

    // MARK: - Create Group Card

    private var createGroupCardOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Icon
                Image("carry-glyph")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(Color(hexString: "#BCF0B5"))
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .padding(.top, 36)
                    .padding(.bottom, 16)

                // Title
                Text("Create a Group")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Color.textPrimary)
                    .padding(.bottom, 24)

                // Benefits
                VStack(alignment: .leading, spacing: 16) {
                    benefitRow("Manage players & who's playing today")
                    benefitRow("Set up recurring tee times")
                    benefitRow("Track stats over time")
                }
                .padding(.horizontal, 28)

                Spacer().frame(height: 40)

                // Buttons
                VStack(spacing: 12) {
                    Button {
                        if storeService.isPremium {
                            // Mark round as completed before converting to group
                            if let roundId = viewModel.config.supabaseRoundId {
                                Task {
                                    try? await RoundService().updateRoundStatus(roundId: roundId, status: "completed")
                                    if let groupId = viewModel.config.supabaseGroupId {
                                        await GroupService().advanceScheduledDateIfRecurring(groupId: groupId)
                                    }
                                }
                            }
                            showCreateGroupCard = false
                            onCreateGroup?()
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        Text("Create Group")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.textPrimary)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showCreateGroupCard = false
                        // Mark round as completed — removes the active card
                        if let roundId = viewModel.config.supabaseRoundId {
                            Task {
                                try? await RoundService().updateRoundStatus(roundId: roundId, status: "completed")
                                if let groupId = viewModel.config.supabaseGroupId {
                                    await GroupService().advanceScheduledDateIfRecurring(groupId: groupId)
                                }
                            }
                        }
                        onDeclineGroup?()
                        if let onExitRound { onExitRound() } else { onDismiss() }
                    } label: {
                        Text("Skip")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.systemRedColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.systemRedColor.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.white)
            )
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    private func benefitRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.textPrimary)
            Text(text)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Color.textPrimary)
        }
    }

    // MARK: - Sheet Container

    private var sheetContainer: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.gridLine)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, isCollapsed ? 12 : 8)
                .accessibilityHidden(true)

            if isCollapsed {
                collapsedContent
            } else {
                expandedContent
            }
        }
        .contentShape(Rectangle())
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isCollapsed)
    }

    // MARK: - Collapsed Content

    private var collapsedContent: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(pendingHoles.isEmpty ? "Final Results" : "Pending Results")
                    .font(.carry.bodySemibold)
                    .foregroundColor(Color.textPrimary)
                Text(viewModel.config.course)
                    .font(.carry.caption)
                    .foregroundColor(Color.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.up")
                .font(.carry.bodySMSemibold)
                .foregroundColor(Color.textSecondary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                isCollapsed = false
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pendingHoles.isEmpty ? "Final Results" : "Pending Results")
        .accessibilityHint("Double tap to expand results")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(spacing: 0) {
            ZStack {
                // Phase 1: "Final Results" celebration (visible until results fade in)
                celebrationContent
                    .opacity(showResults ? 0 : 1)

                // Phase 2: Results (fades in over celebration)
                resultsContent
                    .opacity(showResults ? 1 : 0)
            }

            // Action buttons (appear after results)
            actionButtons
                .opacity(showActions ? 1 : 0)
                .offset(y: showActions ? 0 : 10)
                .padding(.top, 16)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Drag Gesture

    private var sheetDragGesture: some Gesture {
        DragGesture()
            .onEnded { value in
                if isCollapsed {
                    // Swipe up to expand
                    if value.translation.height < -40 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            isCollapsed = false
                        }
                    }
                } else {
                    // Swipe down to collapse
                    if value.translation.height > 80 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            isCollapsed = true
                        }
                    }
                }
            }
    }

    // MARK: - Celebration (initial sheet content)

    private var celebrationContent: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 30)

            ZStack {
                Circle()
                    .fill(Color.gold.opacity(goldFlash ? 0.15 : 0.0))
                    .frame(width: 120, height: 120)
                    .scaleEffect(goldFlash ? 1.3 : 0.8)

                Circle()
                    .fill(Color.gold.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(Color.gold)
                    .scaleEffect(showCheckmark ? 1.0 : 0.2)
                    .opacity(showCheckmark ? 1 : 0)
            }

            Text(pendingHoles.isEmpty ? "Final Results" : "Pending Results")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color.textPrimary)
                .opacity(showCheckmark ? 1 : 0)
                .offset(y: showCheckmark ? 0 : 8)
                .padding(.top, 12)

            Spacer().frame(height: 30)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results Content

    private var resultsContent: some View {
        VStack(spacing: 0) {
            // Sticky header with white background
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 5) {
                    Text(pendingHoles.isEmpty ? "Final Results" : "Pending Results")
                        .font(Font.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.textPrimary)
                    Text(viewModel.config.course)
                        .font(Font.system(size: 16, weight: .medium))
                        .foregroundColor(Color.textSecondary)
                }
                .frame(maxWidth: .infinity)

                // Share button (top-right) — always visible
                Button {
                    generateAndShareCard()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(Font.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.textSecondary)
                        .frame(width: 43, height: 43)
                        .background(Circle().fill(Color.bgSecondary))
                }
                .padding(.trailing, 24)
            }
            .padding(.bottom, 14)
            .background(Color.white)

            // Scrollable content: user hero + won skins + pending skins
            let currentUserEntry = leaderboard.first { $0.player.id == viewModel.currentUserId }
            let wonEntries = wonSkinEntries
            let winners = leaderboard.filter { $0.skinsWon > 0 && $0.player.id != viewModel.currentUserId }
            ScrollView {
                VStack(spacing: 0) {
                    // Hero — always the current user
                    if let entry = currentUserEntry {
                        userHeroSection(entry: entry)
                            .opacity(showWinner ? 1 : 0)
                            .offset(y: showWinner ? 0 : 12)
                            .padding(.bottom, 24)
                    }

                    if !pendingSkins.isEmpty {
                        // PENDING STATE: per-hole won skin rows
                        if !wonEntries.isEmpty {
                            HStack {
                                Text("\(wonEntries.count) Won Skin\(wonEntries.count == 1 ? "" : "s")")
                                    .font(Font.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color.textPrimary)
                                Spacer()
                                Text("Hole")
                                    .font(Font.system(size: 14, weight: .medium))
                                    .foregroundColor(Color.textSecondary)
                                    .frame(width: 72, alignment: .trailing)
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 10)
                        }

                        ForEach(Array(wonEntries.enumerated()), id: \.element.id) { index, entry in
                            wonSkinRow(entry: entry)
                                .opacity(showLeaderboard ? 1 : 0)
                                .offset(y: showLeaderboard ? 0 : 8)
                                .animation(
                                    .spring(response: 0.38, dampingFraction: 0.82)
                                        .delay(Double(index) * 0.04),
                                    value: showLeaderboard
                                )

                            if index < wonEntries.count - 1 {
                                Rectangle()
                                    .fill(Color.borderFaint)
                                    .frame(height: 1)
                                    .frame(height: 1)
                                    .padding(.leading, 82)
                                    .padding(.trailing, 24)
                            }
                        }
                    } else {
                        // FINAL STATE: leaderboard with money
                        ForEach(Array(winners.enumerated()), id: \.element.id) { index, entry in
                            leaderboardRow(entry: entry)
                                .opacity(showLeaderboard ? 1 : 0)
                                .offset(y: showLeaderboard ? 0 : 8)
                                .animation(
                                    .spring(response: 0.38, dampingFraction: 0.82)
                                        .delay(Double(index) * 0.04),
                                    value: showLeaderboard
                                )

                            if index < winners.count - 1 {
                                Rectangle()
                                    .fill(Color.borderFaint)
                                    .frame(height: 1)
                                    .frame(height: 1)
                                    .padding(.leading, 82)
                                    .padding(.trailing, 24)
                            }
                        }
                    }

                    // Round Stats — per-player breakdown. Shown only once
                    // all holes are resolved (no pending) so the numbers
                    // match the leaderboard above.
                    if pendingSkins.isEmpty {
                        RoundStatsView(
                            cachedSkins: viewModel.cachedSkins,
                            allPlayers: viewModel.allPlayers,
                            moneyTotals: viewModel.moneyTotals(),
                            skinsWonByPlayer: viewModel.skinsWonByPlayer(),
                            scores: viewModel.scores,
                            holes: viewModel.holes,
                            currentUserId: viewModel.currentUserId,
                            teeBox: viewModel.config.teeBox,
                            handicapPercentage: viewModel.config.skinRules.handicapPercentage
                        )
                        .padding(.top, 24)
                        .opacity(showLeaderboard ? 1 : 0)
                        .offset(y: showLeaderboard ? 0 : 8)
                        .animation(
                            .spring(response: 0.38, dampingFraction: 0.82)
                                .delay(Double(winners.count) * 0.04 + 0.1),
                            value: showLeaderboard
                        )
                    }

                    // "Pending" section
                    if !pendingSkins.isEmpty {
                        HStack(spacing: 7) {
                            PulsatingDot(color: Color.successGreen)
                            Text("Pending")
                                .font(Font.system(size: 18, weight: .semibold))
                                .foregroundColor(Color.textPrimary)
                            Spacer()
                            Text("Hole")
                                .font(Font.system(size: 14, weight: .medium))
                                .foregroundColor(Color.textSecondary)
                                .frame(width: 72, alignment: .trailing)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 35)
                        .padding(.bottom, 10)

                        ForEach(pendingSkins) { skin in
                            pendingSkinRow(skin)

                            if skin.holeNum != pendingSkins.last?.holeNum {
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
            }
        }
    }

    // MARK: - Winner Section

    /// Hero section — uses the shared FinalResultsHero so this view matches ResultsSheet.
    private func userHeroSection(entry: LeaderboardEntry) -> some View {
        FinalResultsHero(
            player: entry.player,
            skinsWon: entry.skinsWon,
            winAmount: entry.netMoney,
            isFinal: pendingSkins.isEmpty
        )
    }

    // MARK: - Won Skins (per-hole)

    private struct WonSkinEntry: Identifiable {
        let id: String  // "playerID-holeNum"
        let player: Player
        let holeNum: Int
        let isYou: Bool
    }

    private var shareResultsText: String {
        let config = viewModel.config
        let totals = viewModel.moneyTotals()
        let sorted = viewModel.allPlayers.sorted { (totals[$0.id] ?? 0) > (totals[$1.id] ?? 0) }
        var lines = ["⛳️ \(config.groupName) — \(config.course)"]
        lines.append("")
        for (i, player) in sorted.enumerated() {
            let amount = totals[player.id] ?? 0
            let prefix = i == 0 ? "🏆" : "  "
            lines.append("\(prefix) \(player.shortName): $\(amount)")
        }
        lines.append("")
        lines.append("Tracked with Carry")
        return lines.joined(separator: "\n")
    }

    private func generateAndShareCard() {
        let config = viewModel.config
        let totals = viewModel.moneyTotals()
        let skinsMap = viewModel.skinsWonByPlayer()
        let sorted = viewModel.allPlayers.sorted { (totals[$0.id] ?? 0) > (totals[$1.id] ?? 0) }
        #if DEBUG
        print("[ShareCard] players=\(sorted.count) totals=\(totals) skinsMap=\(skinsMap)")
        #endif

        Task {
            // Download avatar photos in parallel
            let avatarImages = await withTaskGroup(of: (Int, UIImage?).self) { group in
                for player in sorted {
                    group.addTask {
                        guard let urlString = player.avatarUrl,
                              let url = URL(string: urlString),
                              let (data, _) = try? await URLSession.shared.data(from: url),
                              let image = UIImage(data: data) else {
                            return (player.id, nil)
                        }
                        return (player.id, image)
                    }
                }
                var result: [Int: UIImage] = [:]
                for await (id, image) in group {
                    if let image { result[id] = image }
                }
                return result
            }

            let entries = sorted.map { player in
                ShareCardEntry(
                    name: player.shortName,
                    initials: player.initials,
                    color: player.color,
                    skinsWon: skinsMap[player.id] ?? 0,
                    moneyAmount: totals[player.id] ?? 0,
                    avatarImage: avatarImages[player.id]
                )
            }

            let cardData = ShareCardData(
                courseName: config.course,
                date: Date(),
                teeName: config.teeBox?.name,
                handicapPct: Int((config.skinRules.handicapPercentage) * 100),
                entries: entries,
                potTotal: viewModel.pot,
                buyIn: config.buyIn
            )

            await MainActor.run {
                if let image = ShareCardRenderer.render(data: cardData) {
                    shareCardImage = image
                    showShareSheet = true
                }
            }
        }
    }

    private var wonSkinEntries: [WonSkinEntry] {
        let skins = viewModel.cachedSkins
        var entries: [WonSkinEntry] = []
        let currentId = viewModel.currentUserId
        for (hole, status) in skins {
            if case .won(let winner, _, _, _) = status {
                entries.append(WonSkinEntry(
                    id: "\(winner.id)-\(hole)",
                    player: winner,
                    holeNum: hole,
                    isYou: winner.id == currentId
                ))
            }
        }
        return entries.sorted { $0.holeNum < $1.holeNum }
    }

    private func wonSkinRow(entry: WonSkinEntry) -> some View {
        HStack(spacing: 12) {
            PlayerAvatar(player: entry.player, size: 38)

            HStack(spacing: 5) {
                Text(entry.player.shortName)
                    .font(Font.system(size: 17, weight: entry.isYou ? .bold : .semibold))
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                if entry.isYou {
                    Text("You")
                        .font(Font.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.gold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.gold.opacity(0.10)))
                }
            }

            Spacer()

            Text("\(entry.holeNum)")
                .font(Font.system(size: 16, weight: .medium))
                .foregroundColor(Color.textPrimary)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(entry.isYou ? Color.gold.opacity(0.03) : .clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.isYou ? "You" : entry.player.shortName) won skin on Hole \(entry.holeNum)")
    }

    // MARK: - Leaderboard Row (final results)

    /// Shared winner row — delegates to FinalResultsWinnerRow so this sheet stays in
    /// sync with ResultsSheet's rendering.
    private func leaderboardRow(entry: LeaderboardEntry) -> some View {
        FinalResultsWinnerRow(
            player: entry.player,
            skins: entry.skinsWon,
            amount: entry.netMoney,
            isYou: entry.player.id == viewModel.currentUserId
        )
    }

    // MARK: - Pending Skin Row

    private func pendingSkinRow(_ skin: PendingSkin) -> some View {
        HStack(spacing: 12) {
            // Leader (avatar + name)
            if let leader = skin.leaders.first {
                PlayerAvatar(player: leader, size: 38, showPulse: true, badgeNumber: skin.bestNet)

                Text(leader.shortName)
                    .font(Font.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.textPrimary.opacity(0.55))
                    .lineLimit(1)
            } else {
                ZStack {
                    Circle()
                        .fill(Color(hexString: "#F5F3EE"))
                        .frame(width: 38, height: 38)
                    PulsingDot()
                }
            }

            Spacer()

            // Hole number
            Text("\(skin.holeNum)")
                .font(Font.system(size: 16, weight: .medium))
                .foregroundColor(Color.textPrimary.opacity(0.55))
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.clear)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Venmo buttons hidden for launch — can re-enable post-launch
            // See appstore_compliance.md for Guideline 5.3 context

            let _ = {
                #if DEBUG
                print("[RoundComplete] pendingHoles=\(pendingHoles.count) isRoundComplete=\(viewModel.isRoundComplete) allGroupsFinished=\(viewModel.allGroupsFinished)")
                #endif
            }()
            if !pendingHoles.isEmpty {
                // Still waiting on other groups — exit to Games tab but keep round active
                Button {
                    if let onExitRound { onExitRound() } else { onDismiss() }
                } label: {
                    Text("Done — Waiting on others")
                        .font(Font.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 19)
                                .fill(Color.textPrimary)
                        )
                }
                .buttonStyle(.plain)
            } else {
                // Final results — exit round
                Button {
                    if isCreator && isQuickGame {
                        // Show create group card instead of exiting immediately
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            showCreateGroupCard = true
                        }
                    } else {
                        // Mark round as completed so it moves from active to recent
                        if let roundId = viewModel.config.supabaseRoundId {
                            Task {
                                try? await RoundService().updateRoundStatus(roundId: roundId, status: "completed")
                            }
                        }
                        if let onExitRound { onExitRound() } else { onDismiss() }
                    }
                } label: {
                    Text("Save Round Results")
                        .font(Font.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 19)
                                .fill(Color.textPrimary)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Animation Sequence

    private func startAnimationSequence() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Sheet slides up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                showSheet = true
            }
        }

        // Checkmark pops in on the sheet
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                showCheckmark = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeOut(duration: 0.6)) {
                goldFlash = true
            }
        }

        // Crossfade celebration → results
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.4)) {
                showResults = true
            }
        }

        // Winner fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                showWinner = true
            }
        }

        // Leaderboard cascades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                showLeaderboard = true
            }
        }

        // Buttons appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation(.easeOut(duration: 0.3)) {
                showActions = true
            }
        }
    }

    // MARK: - Data

    private var leaderboard: [LeaderboardEntry] {
        buildLeaderboard()
    }

    private var pendingHoles: [Int] {
        pendingSkins.map(\.holeNum)
    }

    struct PendingSkin: Identifiable {
        let id: Int
        let holeNum: Int
        let leaders: [Player]
        let bestNet: Int
        let scored: Int
        let total: Int
    }

    private var pendingSkins: [PendingSkin] {
        let skins = viewModel.cachedSkins
        return skins.compactMap { (hole, status) in
            switch status {
            case .provisional(let leaders, let bestNet, _, let scored, let total):
                return PendingSkin(id: hole, holeNum: hole, leaders: leaders, bestNet: bestNet, scored: scored, total: total)
            case .pending:
                let total = viewModel.allPlayers.count
                return PendingSkin(id: hole, holeNum: hole, leaders: [], bestNet: 0, scored: 0, total: total)
            default:
                return nil
            }
        }.sorted { $0.holeNum < $1.holeNum }
    }

    private func buildLeaderboard() -> [LeaderboardEntry] {
        let money = viewModel.moneyTotals()
        let skinsWon = viewModel.skinsWonByPlayer()

        var entries = viewModel.allPlayers.map { player in
            LeaderboardEntry(
                id: player.id,
                player: player,
                netMoney: money[player.id] ?? 0,
                skinsWon: skinsWon[player.id] ?? 0,
                rank: 0
            )
        }

        entries.sort {
            if $0.netMoney != $1.netMoney { return $0.netMoney > $1.netMoney }
            return $0.skinsWon > $1.skinsWon
        }

        for i in entries.indices {
            if i > 0 && entries[i].netMoney == entries[i - 1].netMoney
                     && entries[i].skinsWon == entries[i - 1].skinsWon {
                entries[i].rank = entries[i - 1].rank
            } else {
                entries[i].rank = i + 1
            }
        }

        return entries
    }

    private func moneyText(_ amount: Int) -> String {
        if amount == 0 { return "$0" }
        return "$\(abs(amount))"
    }

    // MARK: - Venmo

    struct VenmoSettlement {
        let player: Player
        let amount: Int
        let txnType: String  // "pay" or "charge"
    }

    private var venmoSettlements: [VenmoSettlement] {
        guard let myEntry = leaderboard.first(where: { $0.player.id == viewModel.currentUserId }) else { return [] }
        let myNet = myEntry.netMoney

        if myNet < 0 {
            // I lost — pay each winner proportionally
            let winners = leaderboard.filter { $0.netMoney > 0 && $0.player.venmoUsername != nil }
            let totalWinnings = winners.reduce(0) { $0 + $1.netMoney }
            guard totalWinnings > 0 else { return [] }
            return winners.map { entry in
                let share = Int((Double(abs(myNet)) * Double(entry.netMoney) / Double(totalWinnings)).rounded())
                return VenmoSettlement(player: entry.player, amount: max(1, share), txnType: "pay")
            }
        } else if myNet > 0 {
            // I won — request from each loser proportionally
            let losers = leaderboard.filter { $0.netMoney < 0 && $0.player.venmoUsername != nil }
            let totalLosses = losers.reduce(0) { $0 + abs($1.netMoney) }
            guard totalLosses > 0 else { return [] }
            return losers.map { entry in
                let share = Int((Double(myNet) * Double(abs(entry.netMoney)) / Double(totalLosses)).rounded())
                return VenmoSettlement(player: entry.player, amount: max(1, share), txnType: "charge")
            }
        }
        return []
    }

    private func openVenmo(_ settlement: VenmoSettlement) {
        guard let username = settlement.player.venmoUsername else { return }
        let note = "Carry Skins – \(viewModel.config.course)"

        // Build Venmo deep link
        var components = URLComponents()
        components.scheme = "venmo"
        components.host = "paycharge"
        components.queryItems = [
            URLQueryItem(name: "txn", value: settlement.txnType),
            URLQueryItem(name: "recipients", value: username),
            URLQueryItem(name: "amount", value: "\(settlement.amount)"),
            URLQueryItem(name: "note", value: note),
        ]

        if let deepLink = components.url {
            UIApplication.shared.open(deepLink) { success in
                if !success {
                    // Fallback: open Venmo profile on web
                    if let webURL = URL(string: "https://venmo.com/\(username)") {
                        UIApplication.shared.open(webURL)
                    }
                }
            }
        }

        // Advance to next settlement (cycles)
        if !venmoSettlements.isEmpty {
            venmoIndex = (venmoIndex + 1) % venmoSettlements.count
        }
    }

    // MARK: - Types

    struct LeaderboardEntry: Identifiable {
        let id: Int
        let player: Player
        let netMoney: Int
        let skinsWon: Int
        var rank: Int
    }

    // MARK: - Share Sheet

    private struct ShareSheet: UIViewControllerRepresentable {
        let activityItems: [Any]
        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        }
        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    }
}

// MARK: - Round Stats View

/// Per-player round stats shown below the leaderboard on the post-round
/// Results screen. For each player displays: money won/lost, total skins,
/// holes won, biggest skin (with carry count), and front/back-nine split.
/// Players are sorted by money total (winners first). Extracted from the
/// larger Round Story feature on the experimental branch — this is the
/// stats portion only, without the narrative recap or pattern detection.
struct RoundStatsView: View {
    let cachedSkins: [Int: SkinStatus]
    let allPlayers: [Player]
    let moneyTotals: [Int: Int]
    let skinsWonByPlayer: [Int: Int]
    let scores: [Int: [Int: Int]]  // [playerID: [holeNum: gross]]
    let holes: [Hole]
    let currentUserId: Int
    let teeBox: TeeBox?
    let handicapPercentage: Double

    @State private var isExpanded = true

    /// par per hole number (built once per render)
    private var parsByHole: [Int: Int] {
        Dictionary(uniqueKeysWithValues: holes.map { ($0.num, $0.par) })
    }

    /// Total handicap strokes received by a player across the round
    /// ("pops" in golf vernacular). Uses USGA playing-handicap math when a
    /// tee box with valid slope+rating is available; falls back to the
    /// rounded raw index otherwise (Quick Games, pre-migration rounds, or
    /// any round whose tee box lost its rating/slope data).
    /// Plus handicaps (negative playing hcp) give strokes back, not receive
    /// them — shown as 0 pops.
    private func pops(for player: Player) -> Int {
        let playingHcp: Int
        if let teeBox, teeBox.slopeRating > 0, teeBox.courseRating > 0 {
            playingHcp = teeBox.playingHandicap(
                forIndex: player.handicap,
                percentage: handicapPercentage
            )
        } else {
            playingHcp = Int(player.handicap.rounded())
        }
        return max(playingHcp, 0)
    }

    /// Formatted handicap index for display ("6.5", "+2.0", "36"). Plus
    /// handicaps show a leading + so readers can tell at a glance that the
    /// player gives strokes rather than receiving them. Uses `.sign` so
    /// negative zero (reachable via the +HC picker at 0.0) is also caught.
    private func handicapLabel(for player: Player) -> String {
        let hcp = player.handicap
        if hcp.sign == .minus {
            return String(format: "+%.1f", -hcp)
        }
        return String(format: "%.1f", hcp)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header strip — tinted gray, tap to collapse/expand
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Round Stats")
                        .font(.carry.headline)
                        .foregroundColor(Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Color.bgSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Body — white, rows with thin separators
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(sortedPlayers.enumerated()), id: \.element.id) { index, player in
                        playerStatRow(player)

                        if index < sortedPlayers.count - 1 {
                            Rectangle()
                                .fill(Color.borderFaint)
                                .frame(height: 1)
                                .padding(.leading, 68) // row 18 + avatar 38 + spacing 12 = 68 (under the name)
                                .padding(.trailing, 18)
                        }
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity)
                .background(Color.white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.borderFaint, lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }

    // MARK: - Row

    private func playerStatRow(_ player: Player) -> some View {
        let skins = skinsWonByPlayer[player.id] ?? 0
        let money = moneyTotals[player.id] ?? 0
        let holesWon = wonHoles(for: player.id)
        let isYou = player.id == currentUserId

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 12) {
                PlayerAvatar(player: player, size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(player.shortName)
                            .font(.carry.bodySemibold)
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(1)
                        if isYou {
                            Text("You")
                                .font(.carry.micro)
                                .foregroundColor(Color.gold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.gold.opacity(0.10)))
                        }
                    }

                    // Handicap index · total pops for the round
                    Text("\(handicapLabel(for: player)) · \(pops(for: player)) pops")
                        .font(.carry.bodySM)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(moneyText(money))
                    .font(.carry.bodyLGBold)
                    .monospacedDigit()
                    .foregroundColor(
                        money > 0 ? Color.goldMuted
                        : money < 0 ? Color.textDisabled
                        : Color.borderSoft
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                // Line 1 — skins count + holes won
                if skins > 0 {
                    let holesList = holesWon.map { "\($0)" }.joined(separator: ", ")
                    statLine(
                        label: "\(skins) Skin\(skins == 1 ? "" : "s")",
                        detail: "Holes \(holesList)"
                    )
                } else {
                    statLine(label: "No Skins", detail: nil)
                }

                // Line 2 — score stats. Example:
                // "38 · 38 76, 3 Birdies, 14 Pars, 1 Bogey"
                if let line = scoreStatsLine(for: player.id) {
                    Text(line)
                        .font(.carry.bodySM)
                        .foregroundColor(Color.textSecondary)
                }
            }
            .padding(.leading, 50) // align under the name (38 avatar + 12 spacing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    private func statLine(label: String, detail: String?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.carry.bodySM)
                .foregroundColor(Color.textSecondary)
            if let detail = detail {
                Text("\u{00B7}")
                    .font(.carry.bodySM)
                    .foregroundColor(Color.textDisabled)
                Text(detail)
                    .font(.carry.bodySM)
                    .foregroundColor(Color.textTertiary)
            }
        }
    }

    // MARK: - Data Helpers

    private var sortedPlayers: [Player] {
        allPlayers.sorted { (moneyTotals[$0.id] ?? 0) > (moneyTotals[$1.id] ?? 0) }
    }

    /// Biggest skin (largest carry) won by a given player — kept for future
    /// use when round stats surface elsewhere (e.g. the Profile tab). Not
    /// currently rendered in the Round Stats section but safe to keep on
    /// the type.
    private func biggestSkin(for playerId: Int) -> (hole: Int, carry: Int)? {
        var best: (hole: Int, carry: Int)?
        for (holeNum, status) in cachedSkins {
            if case .won(let winner, _, _, let carry) = status, winner.id == playerId {
                if best == nil || carry > best!.carry {
                    best = (holeNum, carry)
                }
            }
        }
        return best
    }

    private func wonHoles(for playerId: Int) -> [Int] {
        cachedSkins.compactMap { (holeNum, status) in
            if case .won(let winner, _, _, _) = status, winner.id == playerId {
                return holeNum
            }
            return nil
        }.sorted()
    }

    /// Thin wrapper — all the formatting logic lives in `RoundStatsLine.make`
    /// so it can be unit-tested. Returns nil if the player has no usable scores.
    private func scoreStatsLine(for playerId: Int) -> String? {
        RoundStatsLine.make(
            playerScores: scores[playerId] ?? [:],
            parsByHole: parsByHole
        )
    }

    private func moneyText(_ amount: Int) -> String {
        if amount > 0 { return "$\(amount)" }
        if amount < 0 { return "-$\(-amount)" }
        return "$0"
    }
}
