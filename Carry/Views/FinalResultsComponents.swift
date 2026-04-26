import SwiftUI

// MARK: - Shared layout primitives for the "Final Results" / "Pending Results" sheets
//
// RoundCompleteView (shown inline on the scorecard when the round finishes) and
// ResultsSheet (shown from the Home active card) both render the same conceptual
// content: a hero featuring the current user, a list of other winners with their
// skin counts and money, and a primary action button. These components are the
// single source of truth for that layout so the two sheets always stay in sync.

/// Hero section — the current user's avatar, name, and earnings/status line.
///
/// Three display modes:
///   - No skins won: "No Skins Won" (muted)
///   - Skins won + final: "N Skins Won · $X" (with gold currency)
///   - Skins won + pending: "N Skins Won" (no money, round still in progress)
struct FinalResultsHero: View {
    let player: Player
    let skinsWon: Int
    let winAmount: Int
    let isFinal: Bool

    var body: some View {
        VStack(spacing: 12) {
            PlayerAvatar(player: player, size: 86)

            Text(player.shortName)
                .font(Font.system(size: 24, weight: .bold))
                .foregroundColor(Color.textPrimary)
                .lineLimit(1)

            if skinsWon == 0 {
                Text("No Skins Won")
                    .font(Font.system(size: 20, weight: .semibold))
                    .foregroundColor(Color.textSecondary)
            } else if isFinal {
                (Text("\(skinsWon) Skin\(skinsWon == 1 ? "" : "s") Won · ")
                    .foregroundColor(Color.textPrimary)
                + Text(moneyText(winAmount))
                    .foregroundColor(Color.goldMuted))
                    .font(Font.system(size: 20, weight: .semibold))
            } else {
                Text("\(skinsWon) Skin\(skinsWon == 1 ? "" : "s") Won")
                    .font(Font.system(size: 20, weight: .semibold))
                    .foregroundColor(Color.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        if skinsWon == 0 { return "\(player.shortName), no skins won" }
        if isFinal {
            return "\(player.shortName), \(skinsWon) skin\(skinsWon == 1 ? "" : "s") won, \(moneyText(winAmount))"
        }
        return "\(player.shortName), \(skinsWon) skin\(skinsWon == 1 ? "" : "s") won"
    }

    private func moneyText(_ amount: Int) -> String {
        if amount < 0 { return "-$\(-amount)" }
        return "$\(amount)"
    }
}

/// One row for a player who won skins — avatar + name + skin count + $ amount.
/// Used below the hero for other winners (not the current user).
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
        .background(isYou ? Color.gold.opacity(0.03) : .clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isYou ? "You" : player.shortName), \(skins) skin\(skins == 1 ? "" : "s"), \(moneyText(amount))")
    }

    private func moneyText(_ amount: Int) -> String {
        if amount > 0 { return "$\(amount)" }
        if amount < 0 { return "-$\(-amount)" }
        return "$0"
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
