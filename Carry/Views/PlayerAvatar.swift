import SwiftUI

struct PlayerAvatar: View {
    let player: Player
    var size: CGFloat = 20
    var showPulse: Bool = false
    var showTrophy: Bool = false
    var badgeNumber: Int? = nil

    @State private var isPulsing = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Main avatar circle
            ZStack {
                Circle()
                    .fill(player.swiftColor.opacity(0.09))
                Circle()
                    .strokeBorder(player.swiftColor.opacity(0.25), lineWidth: 1.5)
                Text(player.avatar)
                    .font(.system(size: size * 0.55))
            }
            .frame(width: size, height: size)
            .opacity(showPulse ? (isPulsing ? 1 : 0.5) : 1)
            .animation(showPulse ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : .default, value: isPulsing)
            .onAppear {
                if showPulse { isPulsing = true }
            }

            // Trophy badge
            if showTrophy {
                let badgeSize = size * 0.5
                ZStack {
                    Circle()
                        .fill(.white)
                    Circle()
                        .strokeBorder(Color(hex: "#EAEAEA"), lineWidth: 1)
                    Text("🏆")
                        .font(.system(size: badgeSize * 0.7))
                }
                .frame(width: badgeSize, height: badgeSize)
                .offset(x: 2, y: 2)
            }

            // Number badge (net score to beat)
            if let num = badgeNumber {
                let badgeSize = size * 0.5
                ZStack {
                    Circle()
                        .fill(.white)
                    Circle()
                        .strokeBorder(Color(hex: "#CCCCCC"), lineWidth: 1)
                    Text("\(num)")
                        .font(.system(size: badgeSize * 0.6, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(Color(hex: "#1A1A1A"))
                }
                .frame(width: badgeSize, height: badgeSize)
                .offset(x: 2, y: 2)
            }
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        PlayerAvatar(
            player: Player(
                id: 1,
                name: "Alex",
                initials: "A",
                color: "#FF5733",
                handicap: 5.2,
                avatar: "⛳",
                group: 1,
                ghinNumber: nil
            ),
            size: 24
        )

        PlayerAvatar(
            player: Player(
                id: 2,
                name: "Sam",
                initials: "S",
                color: "#3366FF",
                handicap: 8.1,
                avatar: "🏌️",
                group: 1,
                ghinNumber: nil
            ),
            size: 24,
            showPulse: true
        )

        PlayerAvatar(
            player: Player(
                id: 3,
                name: "Jordan",
                initials: "J",
                color: "#33FF66",
                handicap: 2.5,
                avatar: "🎯",
                group: 1,
                ghinNumber: nil
            ),
            size: 24,
            showTrophy: true
        )
    }
    .padding()
}
