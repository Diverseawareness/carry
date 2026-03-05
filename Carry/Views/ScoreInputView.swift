import SwiftUI

struct ScoreInputView: View {
    let player: Player
    let holeNum: Int
    let holes: [Hole]
    let strokesGiven: Int  // pre-computed by caller using tee box data
    let onSelect: (Int) -> Void
    let onCancel: () -> Void

    private var hole: Hole? {
        holes.first(where: { $0.num == holeNum })
    }

    private var par: Int {
        hole?.par ?? 4
    }

    private var scoreOptions: [(val: Int, label: String, color: Color)] {
        let gold = Color(hex: "#FFD700")
        let darkGold = Color(hex: "#D4A017")
        var opts: [(val: Int, label: String, color: Color)] = []

        // HIO (1) — always available
        opts.append((1, "HIO", gold))

        // Albatross (par-3) — only on par 5+ where it's distinct from HIO
        if par >= 5 {
            opts.append((par - 3, "Albatross", gold))
        }

        // Eagle (par-2) — skip if it would be 1 (already shown as HIO)
        if par - 2 > 1 {
            opts.append((par - 2, "Eagle", darkGold))
        }

        opts.append((par - 1, "Birdie", Color(hex: "#2ECC71")))
        opts.append((par, "Par", Color(hex: "#1A1A1A")))
        opts.append((par + 1, "Bogey", Color(hex: "#999999")))
        opts.append((par + 2, "Double", Color(hex: "#E05555")))
        opts.append((par + 3, "Triple+", Color(hex: "#E05555")))

        return opts
    }

    var body: some View {
        ZStack {
            // Blurred white background
            Color.white.opacity(0.97)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)

            VStack(spacing: 0) {
                Spacer()

                // Player indicator
                HStack(spacing: 8) {
                    PlayerAvatar(player: player, size: 28)
                    Text(player.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                }
                .padding(.bottom, 12)

                // Hole info
                Text("HOLE \(holeNum)")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(Color(hex: "#999999"))
                    .padding(.bottom, 4)

                Text("Par \(par)")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "#BBBBBB"))
                    .padding(.bottom, 6)

                // Strokes info
                Text("\(player.id == 1 ? "You get" : "\(player.name) gets") \(strokesGiven) stroke\(strokesGiven != 1 ? "s" : "")")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#CCCCCC"))
                    .padding(.bottom, 28)

                // Score grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(Array(scoreOptions.enumerated()), id: \.offset) { _, option in
                        Button {
                            onSelect(option.val)
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(option.val)")
                                    .font(.system(size: 28, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundColor(option.color)
                                Text(option.label.uppercased())
                                    .font(.system(size: 10, weight: .medium))
                                    .tracking(0.5)
                                    .foregroundColor(Color(hex: "#BBBBBB"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(option.val == par ? Color(hex: "#FAFAFA") : .white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(option.val == par ? Color(hex: "#DDDDDD") : Color(hex: "#EFEFEF"), lineWidth: option.val == par ? 1.5 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 280)
                .padding(.horizontal, 40)

                // Cancel
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#BBBBBB"))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .padding(.top, 28)

                Spacer()
            }
        }
    }
}
