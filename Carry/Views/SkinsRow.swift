import SwiftUI

struct SkinsRow: View {
    @ObservedObject var vm: RoundViewModel
    let cellWidth: CGFloat

    var body: some View {
        let skins = vm.calculateSkins()

        HStack(spacing: 0) {
            Text("Skins")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color(hex: "E0E0E0"))
                .textCase(.uppercase)
                .tracking(0.8)
                .frame(width: 52, alignment: .leading)
                .padding(.leading, 14)

            ForEach(vm.holes) { hole in
                Group {
                    if let skin = skins[hole.num] {
                        SkinStatusView(skin: skin)
                    }
                }
                .frame(width: cellWidth, height: 28)
            }
        }
        .frame(height: 28)
    }
}

struct SkinStatusView: View {
    let skin: SkinResult

    var body: some View {
        switch skin.status {
        case .won(let winner):
            Circle()
                .fill(winner.color.opacity(0.06))
                .frame(width: 18, height: 18)
                .overlay(
                    Text(winner.initials)
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(winner.color)
                )

        case .carry:
            Text("→")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "D4A017"))
                .opacity(0.2 + Double(skin.carryCount) * 0.2)

        case .pending(let leaders):
            if leaders.count == 1, let leader = leaders.first {
                Circle()
                    .strokeBorder(leader.color.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Text(leader.initials)
                            .font(.system(size: 6, weight: .semibold))
                            .foregroundColor(leader.color.opacity(0.5))
                    )
            } else if leaders.count > 1 {
                Text("tie")
                    .font(.system(size: 7))
                    .foregroundColor(Color(hex: "D4A017"))
                    .opacity(0.3)
            } else {
                Circle()
                    .fill(Color(hex: "F0F0F0"))
                    .frame(width: 3, height: 3)
            }
        }
    }
}
