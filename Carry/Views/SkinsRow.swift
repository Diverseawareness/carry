import SwiftUI

struct SkinsRow: View {
    @ObservedObject var viewModel: RoundViewModel
    let holes: [Hole]
    let activeHole: Int?
    let cellWidth: CGFloat
    let sumWidth: CGFloat
    let skinsHeight: CGFloat

    @State private var activeCelebrations: Set<Int> = []

    private var skins: [Int: SkinStatus] {
        viewModel.cachedSkins
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(holes) { hole in
                let sk = skins[hole.num]
                let isActive = hole.num == activeHole
                let badgeSize: CGFloat = 40  // match CashGamesBar pill avatar
                let isNineBoundary = hole.num == 9

                ZStack {
                    skinContent(status: sk, isActive: isActive, badgeSize: badgeSize)
                }
                .frame(width: cellWidth, height: skinsHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel({
                    switch sk {
                    case .won(let winner, _, _, let carry):
                        let carryLabel = carry > 1 ? ", \(carry) skins carried" : ""
                        return "Hole \(hole.num), skin won by \(winner.name)\(carryLabel)"
                    case .squashed:
                        return "Hole \(hole.num), skin squashed"
                    case .carried:
                        return "Hole \(hole.num), skin carried forward"
                    case .provisional(let leaders, _, _, _, _):
                        if leaders.count == 1, let leader = leaders.first {
                            return "Hole \(hole.num), \(leader.name) leading"
                        } else if leaders.count > 1 {
                            return "Hole \(hole.num), \(leaders.count) players tied"
                        }
                        return "Hole \(hole.num), provisional"
                    case .pending:
                        return "Hole \(hole.num), pending"
                    case .none:
                        return "Hole \(hole.num), no skin"
                    }
                }())
                .overlay {
                    // Confetti burst — larger frame so particles are visible
                    if activeCelebrations.contains(hole.num),
                       case .won(let winner, _, _, _) = sk {
                        SkinConfettiBurst(playerColor: winner.swiftColor) {
                            activeCelebrations.remove(hole.num)
                        }
                        .frame(width: 160, height: 160)
                    }
                }
                .allowsHitTesting(false)
                .zIndex(activeCelebrations.contains(hole.num) ? 1 : 0)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.gridLine)
                        .frame(width: isNineBoundary ? 2 : 1)
                        .accessibilityHidden(true)
                }
            }

            // Empty summary columns
            ForEach(0..<3, id: \.self) { i in
                Color.clear
                    .frame(width: sumWidth, height: skinsHeight)
                    .accessibilityHidden(true)
                    .overlay(alignment: .leading) {
                        if i > 0 {
                            Rectangle()
                                .fill(Color.gridLine)
                                .frame(width: 1)
                                .accessibilityHidden(true)
                        }
                    }
            }
        }
        .onReceive(viewModel.$pendingSkinCelebrations) { celebrations in
            guard !celebrations.isEmpty else { return }
            for (index, celebration) in celebrations.enumerated() {
                let delay = 0.15 + Double(index) * 0.5
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    activeCelebrations.insert(celebration.holeNum)
                }
                viewModel.consumeSkinCelebration(celebration)
            }
        }
    }

    @ViewBuilder
    private func skinContent(status: SkinStatus?, isActive: Bool, badgeSize: CGFloat) -> some View {
        switch status {
        case .won(let winner, _, _, let carry):
            ZStack(alignment: .topTrailing) {
                PlayerAvatar(player: winner, size: badgeSize, showCheckBadge: true)
                if carry > 1 {
                    Text("\(carry)x")
                        .font(.system(size: max(7, skinsHeight * 0.22), weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color.goldMuted)
                        )
                        .offset(x: 4, y: -4)
                }
            }

        case .squashed:
            SplashIcon(size: max(14, skinsHeight * 0.5), color: Color.borderMedium)

        case .carried:
            Image(systemName: "arrow.right")
                .font(.system(size: max(10, skinsHeight * 0.3), weight: .medium))
                .foregroundColor(Color.goldMuted.opacity(0.5))

        case .provisional(let leaders, let bestNet, _, _, _):
            if let leader = leaders.last {
                // Show the most recent leader (even if tied) — pulsing with net score to beat
                PlayerAvatar(player: leader, size: badgeSize, showPulse: true, badgeNumber: bestNet)
            }

        case .pending:
            if isActive {
                PulsingDot()
            } else {
                Circle()
                    .fill(Color(hexString: "#EAEAEA"))
                    .frame(width: 4, height: 4)
            }

        case .none:
            Circle()
                .fill(Color(hexString: "#EAEAEA"))
                .frame(width: 4, height: 4)
        }
    }
}

struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.goldMuted)
            .frame(width: 6, height: 6)
            .scaleEffect(isPulsing ? 1.6 : 1.0)
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
            .accessibilityHidden(true)
    }
}

