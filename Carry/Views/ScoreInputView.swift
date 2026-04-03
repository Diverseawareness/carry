import SwiftUI

struct ScoreInputView: View {
    let player: Player
    let holeNum: Int
    let holes: [Hole]
    let strokesGiven: Int
    let currentScore: Int?       // nil = new entry; non-nil = editing existing score
    let onSelect: (Int) -> Void
    let onClear: (() -> Void)?   // non-nil when a score can be cleared
    let onCancel: () -> Void

    private var hole: Hole? {
        holes.first(where: { $0.num == holeNum })
    }

    private var par: Int {
        hole?.par ?? 4
    }

    private var scoreOptions: [(val: Int, label: String, color: Color)] {
        let gold     = Color.goldStandard
        let darkGold = Color.gold
        var opts: [(val: Int, label: String, color: Color)] = []

        opts.append((1, "HIO", gold))

        if par >= 5 {
            opts.append((par - 3, "Albatross", gold))
        }

        if par - 2 > 1 {
            opts.append((par - 2, "Eagle", darkGold))
        }

        opts.append((par - 1, "Birdie", Color.birdieGreen))
        opts.append((par,     "Par",    Color.textPrimary))
        opts.append((par + 1, "Bogey",  Color.textSecondary))
        opts.append((par + 2, "Double", Color.bogeyRed))
        opts.append((par + 3, "Triple+",Color.bogeyRed))

        return opts
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Player + hole header ─────────────────────────────────
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        PlayerAvatar(player: player, size: 36)
                        Text(player.shortName)
                            .font(.carry.sectionTitle)
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.top, 36)

                    Text("HOLE \(holeNum)  ·  PAR \(par)")
                        .font(.carry.captionLGSemibold)
                        .tracking(CarryTracking.wide)
                        .foregroundColor(Color.dividerMuted)

                    if strokesGiven > 0 {
                        Text("+\(strokesGiven) stroke\(strokesGiven != 1 ? "s" : "")")
                            .font(.carry.caption)
                            .foregroundColor(Color.successGreen)
                    }
                }
                .padding(.bottom, 28)

                // ── Score grid ───────────────────────────────────────────
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                    spacing: 12
                ) {
                    ForEach(Array(scoreOptions.enumerated()), id: \.offset) { _, option in
                        let isSelected = currentScore == option.val

                        Button {
                            onSelect(option.val)
                        } label: {
                            VStack(spacing: 6) {
                                Text("\(option.val)")
                                    .font(.carry.displayMD)
                                    .monospacedDigit()
                                    .foregroundColor(isSelected ? .white : option.color)

                                Text(option.label.uppercased())
                                    .font(.carry.microSM)
                                    .tracking(CarryTracking.wide)
                                    .foregroundColor(
                                        isSelected
                                            ? Color.white.opacity(0.65)
                                            : Color.dividerMuted
                                    )
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(isSelected
                                          ? Color.textPrimary
                                          : Color(hexString: "#F2F2F2"))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)

                // ── Actions ──────────────────────────────────────────────
                VStack(spacing: 2) {
                    // Clear — only visible when editing an existing score
                    if let onClear {
                        Button {
                            onClear()
                        } label: {
                            Text("Clear Score")
                                .font(.carry.bodySM)
                                .foregroundColor(Color.bogeyRed)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }

                    Button {
                        onCancel()
                    } label: {
                        Text("Cancel")
                            .font(.carry.bodySM)
                            .foregroundColor(Color.borderSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .padding(.top, 12)

                Spacer()
            }
        }
    }
}
