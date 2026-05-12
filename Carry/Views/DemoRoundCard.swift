import SwiftUI

/// Home-tab card for the first-launch Demo Round.
///
/// Visual variant of the standard Active Round card with a `DEMO · LIVE` badge,
/// the demo's pre-played leaderboard preview (Ryan leading, 3 carried skins),
/// and a "Try the Demo" CTA. Long-press the card to dismiss (no visible X —
/// keeps the card clean and matches the swipe/long-press patterns used by
/// other Home cards).
///
/// Renders only when `DemoRoundController.isDismissed == false` AND the user
/// has zero groups AND no real active round (gating done by HomeView).
///
/// See `~/.claude/skills/demo-round/SKILL.md` for the full feature spec.
struct DemoRoundCard: View {
    let displayName: String?
    var onTap: () -> Void
    var onDismiss: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Header: course/hole label + DEMO badge
                HStack {
                    Text("Pebble Beach")
                        .font(.carry.bodyLGBold)
                        .foregroundColor(Color.pureBlack)

                    Spacer()

                    // DEMO LIVE badge — distinguishable from real LIVE
                    HStack(spacing: 5) {
                        PulsatingDot(color: Color.successGreen, size: 6)
                        Text("DEMO")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(Color.successGreen)
                        Text("Hole 16")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(Color.successGreen)
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 11)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.concludedGreen))
                }

                // Subtitle: course detail + carry hook
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pebble Beach Golf Links")
                        .font(.carry.bodySM)
                        .foregroundColor(Color(hexString: "#7A7A7E"))
                        .padding(.top, 6)
                    Text("3 skins carried · ~$80 on the table")
                        .font(.carry.bodySM)
                        .foregroundColor(Color.successGreen)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)

                // Player pills — pre-state through hole 15
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        playerPill(name: "Ryan", money: 23, avatarAsset: "demo_01", isLeader: true)
                        playerPill(name: displayName ?? "You", money: 8, avatarAsset: nil)
                        playerPill(name: "Mike", money: -12, avatarAsset: "demo_02")
                        playerPill(name: "Zoe", money: -19, avatarAsset: "demo_03")
                    }
                }
                .padding(.top, 8)

                // CTA — matches the Active Round card's "LIVE Scorecard"
                // button shape (RoundedRectangle 13pt corner radius, 40pt
                // height), with primary black fill since this is the
                // call-to-action.
                HStack(spacing: 6) {
                    Text("Try the Demo")
                        .font(.carry.bodySMBold)
                        .foregroundColor(.white)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 13).fill(Color.pureBlack))
                .padding(.top, 12)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.successGreen.opacity(0.4), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        // Long-press to dismiss. minimumDuration 0.6s + a confirm alert
        // prevents accidental dismissal from prolonged taps. Haptic on
        // gesture recognition gives clear feedback that long-press is the
        // dismiss affordance (vs the tap which opens the demo).
        .onLongPressGesture(minimumDuration: 0.6) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showDeleteConfirm = true
        }
        .alert("Remove Demo Round?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) { onDismiss() }
        } message: {
            Text("You can replay the demo from the debug menu (sign-out + reinstall in production).")
        }
    }

    @ViewBuilder
    private func playerPill(name: String, money: Int, avatarAsset: String?, isLeader: Bool = false) -> some View {
        HStack(spacing: 6) {
            // Real face avatar when available; initial circle fallback for
            // the user's slot (their real avatar gets used inside the
            // scorecard from RoundViewModel, but the card preview is
            // rendered before the VM exists).
            if let asset = avatarAsset, UIImage(named: asset) != nil {
                Image(asset)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
            } else {
                // Carry-branded default avatar — matches PlayerAvatar's
                // initialsView (mint fill + ANDONESI font + dark green text).
                ZStack {
                    Circle().fill(Color(hexString: "#BCF0B5"))
                    Circle().strokeBorder(Color(hexString: "#A3E09C"), lineWidth: 1.5)
                    Text(String(name.prefix(1)).uppercased())
                        .font(.custom("ANDONESI-Regular", size: 28 * 0.48))
                        .foregroundColor(Color(hexString: "#064102"))
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())
            }

            Text(name)
                .font(.carry.captionLG)
                .foregroundColor(Color.textPrimary)
                .lineLimit(1)

            let prefix = money > 0 ? "+" : (money < 0 ? "-" : "")
            Text("\(prefix)$\(abs(money))")
                .font(.carry.captionLGSemibold)
                .monospacedDigit()
                .foregroundColor(money > 0 ? Color.successGreen : (money < 0 ? Color.textSecondary : Color.textTertiary))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.bgSecondary))
    }
}
