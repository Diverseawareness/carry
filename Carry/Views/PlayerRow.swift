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
                            .foregroundColor(Color(hex: "#CCCCCC"))
                    }

                    // Pop dot — top right
                    if pops > 0 {
                        Circle()
                            .fill(Color(hex: "#1A1A1A"))
                            .frame(width: max(4, cellWidth * 0.1), height: max(4, cellWidth * 0.1))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, max(3, cellWidth * 0.08))
                            .padding(.trailing, max(3, cellWidth * 0.08))
                    }
                }
                .frame(width: cellWidth, height: rowHeight)
                .contentShape(Rectangle())
                .onTapGesture { onTapCell(hole.num, player) }
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(isNineBoundary ? Color(hex: "#E0E0E0") : Color(hex: "#F0F0F0"))
                        .frame(width: isNineBoundary ? 2 : 1)
                }
            }

            // Summary columns
            summaryCell(value: viewModel.hasFrontScores(for: player.id) ? viewModel.frontTotal(for: player.id) : nil, width: sumWidth, isFirst: true)
            summaryCell(value: viewModel.hasBackScores(for: player.id) ? viewModel.backTotal(for: player.id) : nil, width: sumWidth)
            summaryCell(value: (viewModel.hasFrontScores(for: player.id) || viewModel.hasBackScores(for: player.id)) ? viewModel.total(for: player.id) : nil, width: sumWidth, isBold: true)
        }
    }

    @ViewBuilder
    private func scoreContent(score: Int, hole: Hole, isActive: Bool) -> some View {
        let diff = score - hole.par  // negative = under par
        let isOver = diff > 0

        // Under-par colors by level
        let underColor: Color = {
            switch diff {
            case ...(-3): return Color(hex: "#FFD700") // Albatross / HIO — gold
            case -2:      return Color(hex: "#E5451F") // Eagle — red-orange
            case -1:      return Color(hex: "#2ECC71") // Birdie — green
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
                    .strokeBorder(Color(hex: "#DDDDDD"), lineWidth: 1.5)
                    .frame(width: circleSize, height: circleSize)
            }
            Text("\(score)")
                .font(.system(size: scoreFont, weight: isYou ? .semibold : .medium))
                .monospacedDigit()
                .foregroundColor(diff < 0 ? underColor : Color(hex: "#1A1A1A"))
        }
    }

    @ViewBuilder
    private func summaryCell(value: Int?, width: CGFloat, isFirst: Bool = false, isBold: Bool = false) -> some View {
        Group {
            if let v = value {
                Text("\(v)")
                    .font(.system(size: isBold ? scoreFont : scoreFont - 1, weight: isYou ? (isBold ? .heavy : .bold) : (isBold ? .semibold : .medium)))
                    .monospacedDigit()
                    .foregroundColor(Color(hex: "#1A1A1A"))
            }
        }
        .frame(width: width, height: rowHeight)
        .overlay(alignment: .leading) {
            if isFirst {
                Rectangle()
                    .fill(Color(hex: "#E0E0E0"))
                    .frame(width: 2)
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
            .strokeBorder(Color(hex: "#CCCCCC"), lineWidth: 2)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(hex: "#F5F5F5")))
            .scaleEffect(isPulsing ? 1.06 : 1.0)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
