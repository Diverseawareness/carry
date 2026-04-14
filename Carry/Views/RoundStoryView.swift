import SwiftUI

// MARK: - Round Story + Stats View

/// Displayed in RoundCompleteView after the leaderboard, before action buttons.
/// Shows a narrative recap and per-player stats breakdown.
struct RoundStoryView: View {
    let story: RoundStory
    let cachedSkins: [Int: SkinStatus]
    let allPlayers: [Player]
    let moneyTotals: [Int: Int]
    let skinsWonByPlayer: [Int: Int]
    let skinValue: Double
    let currentUserId: Int

    @State private var showStats = true

    var body: some View {
        VStack(spacing: 20) {
            recapSection
            statsSection
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Round Recap

    private var recapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Round Recap")
                .font(.carry.headline)
                .foregroundColor(Color.textPrimary)

            Text(story.fullText)
                .font(.carry.body)
                .foregroundColor(Color.textTertiary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.bgSecondary))
    }

    // MARK: - Player Stats

    private var statsSection: some View {
        VStack(spacing: 0) {
            // Header with toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showStats.toggle()
                }
            } label: {
                HStack {
                    Text("Round Stats")
                        .font(.carry.headline)
                        .foregroundColor(Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.textSecondary)
                        .rotationEffect(.degrees(showStats ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if showStats {
                VStack(spacing: 0) {
                    ForEach(Array(sortedPlayers.enumerated()), id: \.element.id) { index, player in
                        playerStatRow(player)

                        if index < sortedPlayers.count - 1 {
                            Rectangle()
                                .fill(Color.borderFaint)
                                .frame(height: 1)
                                .padding(.leading, 62)
                                .padding(.trailing, 16)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.bgSecondary))
    }

    // MARK: - Player Stat Row

    private func playerStatRow(_ player: Player) -> some View {
        let skins = skinsWonByPlayer[player.id] ?? 0
        let money = moneyTotals[player.id] ?? 0
        let holesWon = wonHoles(for: player.id)
        let biggest = biggestSkin(for: player.id)
        let frontBack = frontBackSplit(for: player.id)
        let isYou = player.id == currentUserId

        return VStack(alignment: .leading, spacing: 8) {
            // Name row
            HStack(spacing: 10) {
                PlayerAvatar(player: player, size: 34)

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

                Spacer()

                Text(moneyText(money))
                    .font(.carry.bodyLGBold)
                    .monospacedDigit()
                    .foregroundColor(money > 0 ? Color.goldMuted : money < 0 ? Color.textDisabled : Color.borderSoft)
            }

            // Stats details
            VStack(alignment: .leading, spacing: 4) {
                if skins > 0 {
                    let holesList = holesWon.map { "\($0)" }.joined(separator: ", ")
                    statLine(
                        label: "\(skins) skin\(skins == 1 ? "" : "s")",
                        detail: "Holes \(holesList)"
                    )
                } else {
                    statLine(label: "No skins", detail: nil)
                }

                if let biggest = biggest, biggest.carry > 1 {
                    statLine(
                        label: "Biggest skin",
                        detail: "Hole \(biggest.hole) (\(biggest.carry)x carry)"
                    )
                }

                if skins > 0 {
                    statLine(
                        label: "Front 9",
                        detail: "\(frontBack.front) · Back 9: \(frontBack.back)"
                    )
                }
            }
            .padding(.leading, 44) // align with name (34 avatar + 10 spacing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func statLine(label: String, detail: String?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.carry.bodySM)
                .foregroundColor(Color.textSecondary)
            if let detail = detail {
                Text("·")
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

    private func wonHoles(for playerId: Int) -> [Int] {
        cachedSkins.compactMap { (holeNum, status) in
            if case .won(let winner, _, _, _) = status, winner.id == playerId {
                return holeNum
            }
            return nil
        }.sorted()
    }

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

    private func frontBackSplit(for playerId: Int) -> (front: Int, back: Int) {
        let holes = wonHoles(for: playerId)
        let front = holes.filter { $0 <= 9 }.count
        let back = holes.filter { $0 > 9 }.count
        return (front, back)
    }

    private func moneyText(_ amount: Int) -> String {
        if amount > 0 { return "+$\(amount)" }
        if amount < 0 { return "-$\(-amount)" }
        return "$0"
    }
}
