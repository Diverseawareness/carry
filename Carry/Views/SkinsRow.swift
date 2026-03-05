import SwiftUI

struct SkinsRow: View {
    @ObservedObject var viewModel: RoundViewModel
    let holes: [Hole]
    let activeHole: Int?
    let cellWidth: CGFloat
    let sumWidth: CGFloat
    let skinsHeight: CGFloat

    private var skins: [Int: SkinStatus] {
        viewModel.calculateSkins()
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(holes) { hole in
                let sk = skins[hole.num]
                let isActive = hole.num == activeHole
                let badgeSize = max(16, skinsHeight * 0.55)
                let isNineBoundary = hole.num == 9

                ZStack {
                    skinContent(status: sk, isActive: isActive, badgeSize: badgeSize)
                }
                .frame(width: cellWidth, height: skinsHeight)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(isNineBoundary ? Color(hex: "#E0E0E0") : Color(hex: "#F0F0F0"))
                        .frame(width: isNineBoundary ? 2 : 1)
                }
            }

            // Empty summary columns
            ForEach(0..<3, id: \.self) { i in
                Color.clear
                    .frame(width: sumWidth, height: skinsHeight)
                    .overlay(alignment: .leading) {
                        if i == 0 {
                            Rectangle()
                                .fill(Color(hex: "#E0E0E0"))
                                .frame(width: 2)
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func skinContent(status: SkinStatus?, isActive: Bool, badgeSize: CGFloat) -> some View {
        switch status {
        case .won(let winner, _, _, let carry):
            ZStack(alignment: .topTrailing) {
                PlayerAvatar(player: winner, size: badgeSize, showTrophy: true)
                if carry > 1 {
                    Text("\(carry)x")
                        .font(.system(size: max(7, skinsHeight * 0.22), weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color(hex: "#C4A450"))
                        )
                        .offset(x: 4, y: -4)
                }
            }

        case .squashed:
            SplashIcon(size: max(14, skinsHeight * 0.5), color: Color(hex: "#CCCCCC"))

        case .carried:
            Image(systemName: "arrow.right")
                .font(.system(size: max(10, skinsHeight * 0.3), weight: .medium))
                .foregroundColor(Color(hex: "#C4A450").opacity(0.5))

        case .provisional(let leaders, _, let bestGross, _, _):
            if let leader = leaders.first {
                PlayerAvatar(player: leader, size: badgeSize, showPulse: true, badgeNumber: bestGross)
            }

        case .pending:
            if isActive {
                PulsingDot()
            } else {
                Circle()
                    .fill(Color(hex: "#EAEAEA"))
                    .frame(width: 4, height: 4)
            }

        case .none:
            Circle()
                .fill(Color(hex: "#EAEAEA"))
                .frame(width: 4, height: 4)
        }
    }
}

struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color(hex: "#C4A450"))
            .frame(width: 6, height: 6)
            .scaleEffect(isPulsing ? 1.6 : 1.0)
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

struct PulsingDashedCircle: View {
    let count: Int
    let size: CGFloat
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .foregroundColor(Color(hex: "#CCCCCC"))
            Text("\(count)")
                .font(.system(size: max(6, size * 0.38), weight: .semibold))
                .foregroundColor(Color(hex: "#CCCCCC"))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(isPulsing ? 0.06 : 0), radius: isPulsing ? 3 : 0)
        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isPulsing)
        .onAppear { isPulsing = true }
    }
}
