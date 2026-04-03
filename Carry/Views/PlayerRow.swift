import SwiftUI

struct PlayerRow: View {
    let player: Player
    let holes: [Hole]
    @ObservedObject var viewModel: RoundViewModel
    let activeHole: Int?
    let cellWidth: CGFloat
    let sumWidth: CGFloat
    let rowHeight: CGFloat
    let scoreFont: CGFloat
    let circleSize: CGFloat
    let isYou: Bool
    let onTapCell: (Int, Player) -> Void  // (holeNum, player)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(holes) { hole in
                let score = viewModel.scores[player.id]?[hole.num]
                let isActive = hole.num == activeHole
                let pops = viewModel.strokes(for: player, hole: hole)
                let isNineBoundary = hole.num == 9

                ZStack {
                    // Score content
                    if let s = score {
                        scoreContent(score: s, hole: hole, isActive: isActive)
                    } else if isActive {
                        // Pulsing empty circle for active hole
                        PulsingCircle(size: circleSize)
                    } else {
                        Text("–")
                            .font(.system(size: scoreFont - 2))
                            .foregroundColor(Color.borderMedium)
                    }

                    // Pop dot — top right
                    if pops > 0 {
                        Circle()
                            .fill(Color.textPrimary)
                            .frame(width: max(4, cellWidth * 0.1), height: max(4, cellWidth * 0.1))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, max(3, cellWidth * 0.08))
                            .padding(.trailing, max(3, cellWidth * 0.08))
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: cellWidth, height: rowHeight)
                .contentShape(Rectangle())
                .onTapGesture { onTapCell(hole.num, player) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel({
                    let name = isYou ? "You" : player.shortName
                    if let s = score {
                        let diff = s - hole.par
                        let desc: String
                        switch diff {
                        case _ where s == 1: desc = "hole in one"
                        case ...(-3): desc = "albatross"
                        case -2: desc = "eagle"
                        case -1: desc = "birdie"
                        case 0: desc = "par"
                        case 1: desc = "bogey"
                        case 2: desc = "double bogey"
                        default: desc = "\(diff) over par"
                        }
                        return "\(name), Hole \(hole.num), \(s), \(desc)"
                    } else {
                        return "\(name), Hole \(hole.num), no score"
                    }
                }())
                .accessibilityHint("Double tap to enter score")
                .accessibilityAddTraits(.isButton)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.gridLine)
                        .frame(width: isNineBoundary ? 2 : 1)
                        .accessibilityHidden(true)
                }
            }

            // Summary columns: Out (front 9), In (back 9), Tot (combined)
            let hasFront = viewModel.hasFrontScores(for: player.id)
            let hasBack = viewModel.hasBackScores(for: player.id)

            summaryCell(value: hasFront ? viewModel.frontTotal(for: player.id) : nil, width: sumWidth, isFirst: true)
                .accessibilityLabel(hasFront ? "\(player.shortName) front nine, \(viewModel.frontTotal(for: player.id))" : "\(player.shortName) front nine, no score")
            summaryCell(value: hasBack ? viewModel.backTotal(for: player.id) : nil, width: sumWidth)
                .accessibilityLabel(hasBack ? "\(player.shortName) back nine, \(viewModel.backTotal(for: player.id))" : "\(player.shortName) back nine, no score")
            summaryCell(value: (hasFront && hasBack) ? viewModel.total(for: player.id) : nil, width: sumWidth, isBold: true, isLast: true)
                .accessibilityLabel((hasFront && hasBack) ? "\(player.shortName) total, \(viewModel.total(for: player.id))" : "\(player.shortName) total, incomplete")
        }
    }

    @ViewBuilder
    private func scoreContent(score: Int, hole: Hole, isActive: Bool) -> some View {
        let diff = score - hole.par  // negative = under par
        let isOver = diff > 0

        // Under-par colors by level
        let underColor: Color = {
            switch diff {
            case ...(-3): return Color.goldStandard // Albatross / HIO — gold
            case -2:      return Color(hexString: "#E5451F") // Eagle — red-orange
            case -1:      return Color.birdieGreen // Birdie — green
            default:      return .clear
            }
        }()

        ZStack {
            if diff < 0 {
                Circle()
                    .strokeBorder(underColor, lineWidth: 2)
                    .frame(width: circleSize, height: circleSize)
            }
            if isOver {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color(hexString: "#DDDDDD"), lineWidth: 1.5)
                    .frame(width: circleSize, height: circleSize)
            }
            Text("\(score)")
                .font(.system(size: scoreFont, weight: isYou ? .semibold : .medium))
                .monospacedDigit()
                .foregroundColor(diff < 0 ? underColor : Color.textPrimary)
        }
    }

    @ViewBuilder
    private func summaryCell(value: Int?, width: CGFloat, isFirst: Bool = false, isBold: Bool = false, isLast: Bool = false) -> some View {
        Group {
            if let v = value {
                Text("\(v)")
                    .font(.system(size: isBold ? scoreFont : scoreFont - 1, weight: isYou ? (isBold ? .heavy : .bold) : (isBold ? .semibold : .medium)))
                    .monospacedDigit()
                    .foregroundColor(Color.textPrimary)
            }
        }
        .frame(width: width, height: rowHeight)
        .overlay(alignment: .leading) {
            if !isFirst {
                Rectangle()
                    .fill(Color.gridLine)
                    .frame(width: 1)
                    .accessibilityHidden(true)
            }
        }
    }
}

// Pulsing circle for active empty cells
struct PulsingCircle: View {
    let size: CGFloat
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .strokeBorder(Color.borderMedium, lineWidth: 2)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.bgSecondary))
            .scaleEffect(isPulsing ? 1.06 : 1.0)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
