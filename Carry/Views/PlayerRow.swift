import SwiftUI

struct PlayerRow: View {
    let player: Player
    @ObservedObject var vm: RoundViewModel
    let cellWidth: CGFloat
    let rowHeight: CGFloat
    let onTapHole: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Name column
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "C0C0C0"))
                Text("hcp \(player.handicap)")
                    .font(.system(size: 7))
                    .foregroundColor(Color(hex: "E0E0E0"))
            }
            .frame(width: 52, alignment: .leading)
            .padding(.leading, 14)

            // Score cells
            ForEach(vm.holes) { hole in
                ScoreCell(
                    player: player,
                    hole: hole,
                    vm: vm,
                    cellWidth: cellWidth,
                    rowHeight: rowHeight,
                    onTap: { onTapHole(hole.num) }
                )
            }
        }
        .frame(height: rowHeight)
    }
}

struct ScoreCell: View {
    let player: Player
    let hole: Hole
    @ObservedObject var vm: RoundViewModel
    let cellWidth: CGFloat
    let rowHeight: CGFloat
    let onTap: () -> Void

    var body: some View {
        let score = vm.scores[player.id]?[hole.num] ?? nil
        let isActive = hole.num == vm.activeHole && player.id == 1
        let strokes = vm.strokes(for: player, hole: hole)

        ZStack {
            if let s = score {
                let label = ScoreLabel.from(score: s, par: hole.par)
                let net = s - strokes

                VStack(spacing: 3) {
                    Text("\(s)")
                        .font(.system(size: min(20, rowHeight * 0.35), weight: label.isMoment ? .bold : label == .par ? .medium : .regular).monospacedDigit())
                        .foregroundColor(label.color)

                    if strokes > 0 {
                        Text("\(net)n")
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundColor(Color(hex: "D0D0D0"))
                            .opacity(0.55)
                    }
                }
            } else if isActive {
                Circle()
                    .fill(Color(hex: "D4A017"))
                    .frame(width: 7, height: 7)
            } else {
                Text("–")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "EBEBEB"))
            }
        }
        .frame(width: cellWidth, height: rowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            if isActive && score == nil {
                onTap()
            }
        }
    }
}
