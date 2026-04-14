import SwiftUI
import AudioToolbox

// MARK: - Pill Position Preference Key

private struct PillCenterKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGPoint>] = [:]
    static func reduce(value: inout [Int: Anchor<CGPoint>], nextValue: () -> [Int: Anchor<CGPoint>]) {
        value.merge(nextValue()) { $1 }
    }
}

struct CashGamesBar: View {
    @ObservedObject var viewModel: RoundViewModel

    // MARK: - Celebration State
    @State private var celebratingPlayerIds: Set<Int> = []
    /// Tracks hole → winner ID so we detect both new wins AND winner changes from score edits.
    @State private var knownWonHoles: [Int: Int] = [:]

    private var skins: [Int: SkinStatus] {
        viewModel.cachedSkins
    }

    private var hasSkinsAwarded: Bool {
        skins.values.contains { if case .won = $0 { return true }; return false }
    }

    /// Positive skin earnings for a player: (skins won × current skin value).
    /// Always ≥ 0 — we never show negative amounts in this bar.
    private func skinEarnings(for player: Player) -> Int {
        let skinsWon = skins.values.reduce(0) { total, status in
            if case .won(let winner, _, _, let carry) = status, winner.id == player.id {
                return total + carry
            }
            return total
        }
        let gross = Int((Double(skinsWon) * viewModel.skinValue).rounded())
        if viewModel.config.winningsDisplay == "net" {
            return gross - viewModel.config.buyIn
        }
        return gross
    }

    /// All players sorted by: earnings first, then current hole leaders break ties, then original order.
    private var sortedPlayers: [Player] {
        let original = viewModel.allPlayers
        let leaders = currentProvisionalLeaderIds
        return original.sorted { a, b in
            let ea = skinEarnings(for: a)
            let eb = skinEarnings(for: b)
            if ea != eb { return ea > eb }
            // Break ties: provisional leader on current hole ranks higher
            let aLeads = leaders.contains(a.id)
            let bLeads = leaders.contains(b.id)
            if aLeads != bLeads { return aLeads }
            // Preserve original order for remaining ties
            let ia = original.firstIndex(where: { $0.id == a.id }) ?? 0
            let ib = original.firstIndex(where: { $0.id == b.id }) ?? 0
            return ia < ib
        }
    }

    /// Player IDs currently leading any provisional (unsettled) hole.
    private var currentProvisionalLeaderIds: Set<Int> {
        var ids = Set<Int>()
        for (_, status) in skins {
            if case .provisional(let leaders, _, _, _, _) = status {
                for leader in leaders { ids.insert(leader.id) }
            }
        }
        return ids
    }

    /// Map of hole → winner for all currently won skins.
    private var currentWonHoles: [Int: Player] {
        var result: [Int: Player] = [:]
        for (hole, status) in skins {
            if case .won(let winner, _, _, _) = status {
                result[hole] = winner
            }
        }
        return result
    }

    /// Total number of individual scores entered — changes whenever any score is entered.
    private var totalScores: Int {
        viewModel.scores.values.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Player pills — all players, always visible, reflecting current earnings
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(sortedPlayers) { player in
                        pillView(for: player)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: sortedPlayers.map(\.id))
            }
        }
        .padding(.vertical, 10)
        // Confetti overlay — positioned at pill center via anchor preferences
        .overlayPreferenceValue(PillCenterKey.self) { positions in
            GeometryReader { geo in
                ForEach(Array(celebratingPlayerIds), id: \.self) { playerId in
                    if let anchor = positions[playerId],
                       let player = viewModel.allPlayers.first(where: { $0.id == playerId }) {
                        SkinConfettiBurst(playerColor: player.swiftColor) {
                            // Hold gold state a bit longer after confetti, then morph back
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                    _ = celebratingPlayerIds.remove(playerId)
                                }
                            }
                        }
                        .frame(width: 200, height: 200)
                        .position(geo[anchor])
                        .allowsHitTesting(false)
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            knownWonHoles = currentWonHoles.mapValues { $0.id }
        }
        .onChange(of: totalScores) { _, _ in
            checkForNewPillCelebrations()
        }
    }

    // MARK: - Pill View

    @ViewBuilder
    private func pillView(for player: Player) -> some View {
        let isYou = player.id == viewModel.currentUserId
        let amount = skinEarnings(for: player)
        let isCelebrating = celebratingPlayerIds.contains(player.id)

        HStack(spacing: 10) {
            PlayerAvatar(player: player, size: 40)

            if isCelebrating {
                // Gold state — "Skin Won!" text
                Text("Skin Won!")
                    .font(.carry.bodyLGBold)
                    .foregroundColor(.white)
                    .transition(.opacity)
            } else {
                // Normal state — name + earnings
                HStack(spacing: 10) {
                    Text(player.shortName)
                        .font(isYou ? Font.carry.bodyLGSemibold : Font.carry.bodyLG)
                        .foregroundColor(isYou ? Color.textPrimary : Color.textMid)
                        .lineLimit(1)
                    Text(moneyText(amount))
                        .font(.carry.headlineBold)
                        .monospacedDigit()
                        .foregroundColor(moneyColor(amount))
                        .contentTransition(.numericText())
                }
                .transition(.opacity)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 18)
        .padding(.vertical, 8)
        .fixedSize()
        .background(isCelebrating ? Color.goldMuted : .white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(isCelebrating ? 0.12 : 0.06), radius: isCelebrating ? 8 : 6, y: 2)
        .overlay(
            Capsule()
                .strokeBorder(
                    isCelebrating ? Color.gold.opacity(0.4) : .clear,
                    lineWidth: isCelebrating ? 2 : 1
                )
        )
        .scaleEffect(isCelebrating ? 1.08 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: isCelebrating)
        .anchorPreference(key: PillCenterKey.self, value: .center) { anchor in
            [player.id: anchor]
        }
        .zIndex(isCelebrating ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isYou ? "You" : player.shortName)\(isCelebrating ? ", Skin won!" : ", \(moneyText(amount))")")
        .accessibilityValue(isCelebrating ? "Celebrating" : "\(amount) dollars")
    }

    // MARK: - Celebration Detection

    private func checkForNewPillCelebrations() {
        let won = currentWonHoles
        // Find holes that are newly won OR where the winner changed (score edit)
        var celebrationWinners: [(hole: Int, winner: Player)] = []
        for (hole, winner) in won {
            if knownWonHoles[hole] != winner.id {
                celebrationWinners.append((hole, winner))
            }
        }
        guard !celebrationWinners.isEmpty else { return }
        // Update known state
        for entry in celebrationWinners {
            knownWonHoles[entry.hole] = entry.winner.id
        }
        // Also update any holes that became un-won (score edit reverted a win)
        for hole in knownWonHoles.keys where won[hole] == nil {
            knownWonHoles.removeValue(forKey: hole)
        }
        // Stagger celebrations; 0.7s initial delay lets pill reorder animation finish first
        for (index, entry) in celebrationWinners.sorted(by: { $0.hole < $1.hole }).enumerated() {
            let delay = 0.7 + Double(index) * 1.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    _ = celebratingPlayerIds.insert(entry.winner.id)
                }
            }
        }
    }

    // MARK: - Helpers

    private func moneyText(_ amount: Int) -> String {
        if amount < 0 { return "-$\(-amount)" }
        return "$\(amount)"
    }

    private func moneyColor(_ amount: Int) -> Color {
        if amount > 0 { return Color.textPrimary }
        if amount < 0 { return .red }
        return Color.textSecondary
    }
}
