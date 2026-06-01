import SwiftUI

// MARK: - Shared layout primitives for the "Final Results" / "Pending Results" sheets
//
// RoundCompleteView (shown inline on the scorecard when the round finishes) and
// ResultsSheet (shown from the Home active card) both render the same conceptual
// content: a single ranked list of players with skin counts + money (the current
// user appears at their natural rank with a "You" label, NOT pinned/featured),
// and a primary action button. These components are the single source of truth
// so the two sheets stay in sync.
//
// (1.2.x) The centered `FinalResultsHero` (big avatar + "No Skins Won" subtitle)
// was removed — players, including the current user, are all `FinalResultsWinnerRow`.

/// One row for a player who won skins — avatar + name (+ "You" pill for the
/// current user) + skin count + $ amount. Used for ALL players in the list.
struct FinalResultsWinnerRow: View {
    let player: Player
    let skins: Int
    let amount: Int
    var isYou: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            PlayerAvatar(player: player, size: 38)

            HStack(spacing: 5) {
                Text(player.shortName)
                    .font(Font.system(size: 17, weight: isYou ? .bold : .semibold))
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                if isYou {
                    Text("You")
                        .font(Font.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.textDark)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.textDark.opacity(0.10)))
                }
            }

            Spacer()

            Text("\(skins)")
                .font(Font.system(size: 17, weight: .medium))
                .foregroundColor(skins > 0 ? Color.textPrimary : Color.borderMedium)
                .frame(width: 36, alignment: .center)

            Text(moneyText(amount))
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
                .foregroundColor(moneyColor(amount))
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        // (1.2.x) No gold/cream "You" row tint — the "You" pill alone marks the
        // current user; the row background stays clear like every other row.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isYou ? "You" : player.shortName), \(skins) skin\(skins == 1 ? "" : "s"), \(moneyText(amount))")
    }

    private func moneyColor(_ amount: Int) -> Color {
        if amount > 0 { return Color.goldMuted }
        if amount < 0 { return Color.textDisabled }
        return Color.borderSoft
    }
}

/// Faint divider line that separates winner rows.
struct FinalResultsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.borderFaint)
            .frame(height: 1)
            .padding(.leading, 82)
            .padding(.trailing, 24)
    }
}

/// Primary action button for results sheets — "Save Round Results" style.
struct FinalResultsPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Font.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(RoundedRectangle(cornerRadius: 19).fill(Color.textPrimary))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.bottom, 34)
    }
}
