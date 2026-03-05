import SwiftUI

struct CashGamesBar: View {
    @ObservedObject var viewModel: RoundViewModel

    private var totals: [Int: Int] {
        viewModel.moneyTotals()
    }

    private var hasSkinsAwarded: Bool {
        let skins = viewModel.calculateSkins()
        return skins.values.contains { if case .won = $0 { return true }; return false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasSkinsAwarded {
                // Player pills — sorted by net $, scrollable
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.allPlayers.sorted(by: { (totals[$0.id] ?? 0) > (totals[$1.id] ?? 0) })) { player in
                            let isYou = player.id == viewModel.currentUserId
                            let amount = totals[player.id] ?? 0

                            HStack(spacing: 8) {
                                PlayerAvatar(player: player, size: 32)
                                Text(player.truncatedName)
                                    .font(.system(size: 13, weight: isYou ? .semibold : .regular))
                                    .foregroundColor(isYou ? Color(hex: "#1A1A1A") : Color(hex: "#888888"))
                                Text(moneyText(amount))
                                    .font(.system(size: 14, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundColor(moneyColor(amount))
                            }
                            .padding(.leading, 6)
                            .padding(.trailing, 16)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 40)
                                    .fill(isYou ? Color(hex: "#D4A017").opacity(0.06) : Color(hex: "#FAFAFA"))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 40)
                                    .strokeBorder(isYou ? Color(hex: "#D4A017").opacity(0.15) : .clear, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.bottom, 4)
                }
            } else {
                // Pot summary — before any skins are won
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: "#C4A450"))
                        Text("$\(viewModel.pot)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                    }
                    Text("\u{00B7}")
                        .foregroundColor(Color(hex: "#CCCCCC"))
                    Text("18 skins")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#999999"))
                    Text("\u{00B7}")
                        .foregroundColor(Color(hex: "#CCCCCC"))
                    Text("~$\(Int((Double(viewModel.pot) / 18.0).rounded()))/skin")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#999999"))
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
        )
    }

    private func moneyText(_ amount: Int) -> String {
        if amount == 0 { return "–" }
        let sign = amount > 0 ? "+" : ""
        return "\(sign)$\(abs(amount))"
    }

    private func moneyColor(_ amount: Int) -> Color {
        if amount > 0 { return Color(hex: "#2ECC71") }
        if amount < 0 { return Color(hex: "#E05555") }
        return Color(hex: "#CCCCCC")
    }
}
