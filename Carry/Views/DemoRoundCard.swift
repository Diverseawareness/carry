import SwiftUI

/// Home-tab card for the first-launch Demo Round.
///
/// Visual variant of the standard Active Round card with a `DEMO · LIVE` badge,
/// the demo's pre-played leaderboard preview (Ryan leading, 3 carried skins),
/// and a "Continue Round" CTA. Top-right ✕ dismisses without playing.
///
/// Renders only when `DemoRoundController.isDismissed == false` AND the user
/// has zero groups AND no real active round (gating done by HomeView).
///
/// See `~/.claude/skills/demo-round/SKILL.md` for the full feature spec.
struct DemoRoundCard: View {
    let displayName: String?
    var onTap: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
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
                        .padding(.trailing, 30)  // leaves room for ✕ button
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.concludedGreen))
                    }

                    // Subtitle: course detail + carry hook
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pebble Beach Golf Links")
                            .font(.carry.bodySM)
                            .foregroundColor(Color(hexString: "#7A7A7E"))
                            .padding(.top, 6)
                        Text("3 skins carried · ~$13 on the table")
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
                            playerPill(name: "Tom", money: -19, avatarAsset: "demo_03")
                        }
                    }
                    .padding(.top, 8)

                    // CTA — match the LIVE Scorecard button style
                    HStack(spacing: 6) {
                        Text("Try the Demo")
                            .font(.carry.bodySMBold)
                            .foregroundColor(.white)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.pureBlack))
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

            // ✕ dismiss — top-right corner overlay, doesn't trigger card tap
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.textTertiary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.bgSecondary.opacity(0.9)))
            }
            .buttonStyle(.plain)
            .padding(12)
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
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(isLeader ? Color.pureBlack : Color.textTertiary))
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
