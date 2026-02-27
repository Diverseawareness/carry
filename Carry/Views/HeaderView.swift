import SwiftUI

struct HeaderView: View {
    @ObservedObject var vm: RoundViewModel
    let isLandscape: Bool

    var body: some View {
        let totals = vm.moneyTotals()

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("Carry")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "D4A017"))
                Text("·")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "E8E8E8"))
                Text("$5 Skins · Net")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "B0B0B0"))
                if isLandscape {
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "E8E8E8"))
                    Text("Blackhawk CC")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "B0B0B0"))
                }
            }

            if !isLandscape {
                Text("Blackhawk CC")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "1A1A1A"))
                    .tracking(-0.3)
            }

            HStack(spacing: 10) {
                ForEach(vm.players) { p in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(totals[p.id] != 0 ? p.color : Color(hex: "E8E8E8"))
                            .frame(width: 4, height: 4)
                        Text(p.name)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "C0C0C0"))
                        Text(moneyText(totals[p.id] ?? 0))
                            .font(.system(size: 11, weight: totals[p.id] != 0 ? .semibold : .regular).monospacedDigit())
                            .foregroundColor(moneyColor(totals[p.id] ?? 0))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isLandscape ? 6 : 10)
    }

    private func moneyText(_ amount: Int) -> String {
        if amount == 0 { return "–" }
        let sign = amount > 0 ? "+" : ""
        return "\(sign)$\(abs(amount))"
    }

    private func moneyColor(_ amount: Int) -> Color {
        if amount > 0 { return Color(hex: "2ECC71") }
        if amount < 0 { return Color(hex: "E05555") }
        return Color(hex: "D8D8D8")
    }
}
