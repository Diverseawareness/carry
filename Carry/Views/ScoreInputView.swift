import SwiftUI

struct ScoreInputView: View {
    let hole: Hole
    let player: Player
    @ObservedObject var vm: RoundViewModel
    let isLandscape: Bool
    let onScore: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        let strokes = vm.strokes(for: player, hole: hole)

        ZStack {
            Color.white.opacity(0.98)

            VStack(spacing: 0) {
                Text("HOLE \(hole.num)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "D0D0D0"))
                    .tracking(1.5)
                    .padding(.bottom, 3)

                Text("Par \(hole.par)")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "D8D8D8"))
                    .padding(.bottom, 4)

                Text("You get \(strokes) stroke\(strokes != 1 ? "s" : "")")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "E0E0E0"))
                    .padding(.bottom, 24)

                let columns = isLandscape
                    ? Array(repeating: GridItem(.flexible(), spacing: 10), count: 7)
                    : Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(scoreOptions, id: \.value) { option in
                        Button {
                            onScore(option.value)
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(option.value)")
                                    .font(.system(size: isLandscape ? 24 : 30, weight: .bold).monospacedDigit())
                                    .foregroundColor(option.color)
                                Text(option.label)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color(hex: "C8C8C8"))
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, isLandscape ? 14 : 20)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(option.value == hole.par ? Color(hex: "FAFAFA") : .white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(option.value == hole.par ? Color(hex: "E0E0E0") : Color(hex: "F0F0F0"),
                                            lineWidth: option.value == hole.par ? 1.5 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: isLandscape ? 500 : 300)

                Button("Cancel") {
                    onCancel()
                }
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "C8C8C8"))
                .padding(.top, 24)
                .padding(.bottom, 10)
            }
        }
    }

    private var scoreOptions: [(value: Int, label: String, color: Color)] {
        var options: [(value: Int, label: String, color: Color)] = []
        if hole.par <= 4 {
            let ace = hole.par - 3
            if ace >= 1 {
                options.append((ace, "Ace", Color(hex: "D4A017")))
            }
        }
        options.append(contentsOf: [
            (hole.par - 2, "Eagle", Color(hex: "D4A017")),
            (hole.par - 1, "Birdie", Color(hex: "2ECC71")),
            (hole.par, "Par", Color(hex: "1A1A1A")),
            (hole.par + 1, "Bogey", Color(hex: "B0B0B0")),
            (hole.par + 2, "Dbl", Color(hex: "E05555")),
            (hole.par + 3, "Trpl+", Color(hex: "E05555")),
        ])
        return options.filter { $0.value >= 1 }
    }
}
