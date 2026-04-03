import SwiftUI

struct PlayerAvatar: View {
    let player: Player
    var size: CGFloat = 20
    var showPulse: Bool = false
    var badgeNumber: Int? = nil
    var showCheckBadge: Bool = false

    @State private var isPulsing = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Main avatar circle
            Group {
                if let urlString = player.avatarUrl, let url = URL(string: urlString) {
                    // Remote photo avatar
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: size, height: size)
                                .clipShape(Circle())
                        default:
                            initialsView
                        }
                    }
                } else if player.hasPhoto, let imgName = player.avatarImageName {
                    // Local asset photo avatar
                    Image(imgName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else {
                    initialsView
                }
            }
            .opacity(isPending ? 0.5 : (showPulse && !isPending ? (isPulsing ? 1 : 0.5) : 1))
            .animation(showPulse && !isPending ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : .default, value: isPulsing)
            .onAppear {
                if showPulse { isPulsing = true }
            }

            // Badge: checkmark (won) or number (provisional/leading)
            if showCheckBadge {
                let badgeSize = size * 0.5
                let bgSize = badgeSize * 1.12
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: bgSize, height: bgSize)
                    Circle()
                        .fill(Color.goldAccent)
                        .frame(width: badgeSize, height: badgeSize)
                    Image(systemName: "checkmark")
                        .font(.system(size: badgeSize * 0.5, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: bgSize, height: bgSize)
                .offset(x: 2, y: 2)
            } else if let num = badgeNumber {
                let badgeSize = size * 0.5
                let bgSize = badgeSize * 1.12
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: bgSize, height: bgSize)
                    Circle()
                        .strokeBorder(Color.borderMedium, lineWidth: 1)
                        .frame(width: badgeSize, height: badgeSize)
                    Text("\(num)")
                        .font(.system(size: badgeSize * 0.6, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(Color.textPrimary)
                }
                .frame(width: bgSize, height: bgSize)
                .offset(x: 2, y: 2)
            }
        }
    }

    private var isPending: Bool {
        player.isPendingInvite || player.isPendingAccept
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(Color(hexString: isPending ? "#FFE9D0" : "#BCF0B5"))
            Circle()
                .strokeBorder(Color(hexString: isPending ? "#F8D6C4" : "#A3E09C"), lineWidth: 1.5)
            if player.isPendingInvite {
                Image(systemName: "message.fill")
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundColor(Color.pendingFill)
            } else {
                Text(player.initials)
                    .font(.custom("ANDONESI-Regular", size: size * 0.48))
                    .foregroundColor(Color(hexString: isPending ? "#CB895D" : "#064102"))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

#Preview {
    HStack(spacing: 12) {
        // Photo avatar (if image exists in assets)
        PlayerAvatar(
            player: Player.allPlayers[0],  // Daniel
            size: 40
        )

        // Emoji fallback
        PlayerAvatar(
            player: Player(
                id: 99,
                name: "Sam",
                initials: "S",
                color: "#3366FF",
                handicap: 8.1,
                avatar: "🏌️",
                group: 1,
                ghinNumber: nil,
                venmoUsername: nil,
                avatarImageName: nil
            ),
            size: 40,
            showPulse: true
        )

        // With badge
        PlayerAvatar(
            player: Player.allPlayers[2],  // Adi
            size: 40,
            badgeNumber: 3
        )
    }
    .padding()
}
