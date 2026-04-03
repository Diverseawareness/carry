import SwiftUI

/// Dark pill toast for in-app skins notifications.
/// Shows player avatar + message, auto-dismissed by parent.
struct GameToastView: View {
    let event: GameEvent

    var body: some View {
        HStack(spacing: 10) {
            // Left accent for carry events
            if event.type == .carryBuilding {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.goldMuted)
                    .frame(width: 3, height: 28)
            }

            // Player avatar (if available)
            if let player = event.player {
                PlayerAvatar(player: player, size: 28)
            } else if event.type == .carryBuilding {
                // Gold carry icon
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.goldMuted)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.goldMuted.opacity(0.15)))
            }

            Text(event.message)
                .font(.carry.bodySM)
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            // Hole badge
            if let hole = event.holeNum {
                Text("H\(hole)")
                    .font(.carry.microSM)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.textPrimary.opacity(0.95))
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}
