import SwiftUI
import AudioToolbox

/// Compact dial score entry for the bottom-drawer presentation.
/// Contains no background — the drawer container provides it.
struct ScoreInputSheet: View {
    let player: Player
    let holeNum: Int
    let holes: [Hole]
    let strokesGiven: Int
    let currentScore: Int?
    let onSelect: (Int) -> Void
    let onScoreNext: (Int) -> Void
    var extraBottomPadding: CGFloat = 0

    @State private var selectedIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var liveDragIndex: Int = 0   // tracks ticks during drag

    private let dialFeedback = UIImpactFeedbackGenerator(style: .medium)

    // Figma: gap-[29px] between items, band py-[18px], w-[334px], rounded-[20px]
    private let itemH: CGFloat = 96        // center-to-center pitch between dial items
    private let bandH: CGFloat = 96        // selected band visible height
    private let bandW: CGFloat = 334       // Figma: w-[334px]

    private var hole: Hole? { holes.first { $0.num == holeNum } }
    private var par: Int { hole?.par ?? 4 }

    private var scoreOptions: [(val: Int, label: String, color: Color)] {
        let gold  = Color.goldStandard
        let dGold = Color.gold
        var o: [(val: Int, label: String, color: Color)] = []
        o.append((1,       "Hole In One", gold))
        if par >= 5 { o.append((par - 3, "Albatross", gold)) }
        if par - 2 > 1 { o.append((par - 2, "Eagle", dGold)) }
        o.append((par - 1, "Birdie",   Color.birdieGreen))
        o.append((par,     "Par",      Color.textPrimary))
        o.append((par + 1, "Bogey",    Color.textMid))
        o.append((par + 2, "Double",   Color.bogeyRed))
        o.append((par + 3, "Triple+",  Color.bogeyRed))
        return o
    }

    private var current: (val: Int, label: String, color: Color) {
        scoreOptions[max(0, min(scoreOptions.count - 1, selectedIndex))]
    }

    private var totalH: CGFloat { itemH * 3 }

    var body: some View {
        VStack(spacing: 0) {
            // Header — Figma: gap-16 between handle and header, then gap-48 to dial
            header
                .padding(.top, 16)

            // Equal spacers center the dial between header and buttons
            Spacer(minLength: 24)

            dial

            Spacer(minLength: 24)

            // Footer — Figma: pb-[50px]
            bottomActions
                .padding(.bottom, 30 + extraBottomPadding)
        }
        .onAppear {
            dialFeedback.prepare()
            let target = currentScore ?? par
            selectedIndex = scoreOptions.firstIndex { $0.val == target }
                         ?? scoreOptions.firstIndex { $0.val == par }
                         ?? 0
            liveDragIndex = selectedIndex
        }
    }

    // MARK: - Header (Figma: centered, w-337, gap-10, items-center)

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            PlayerAvatar(player: player, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.shortName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.deepNavy)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    Text("Hole \(holeNum) · Par \(par)")
                        .font(.system(size: 16))
                        .foregroundColor(Color.textDark)
                    if strokesGiven > 0 {
                        Text("  · \(strokesGiven) Stroke\(strokesGiven == 1 ? "" : "s")")
                            .font(.system(size: 16))
                            .foregroundColor(Color.textDark)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Dial (Figma: w-354, gap-29, band py-18 w-334 rounded-20, border-2)

    private var dial: some View {
        ZStack {
            // ── Layer 1: ghost items outside the band ──────────────────
            ZStack {
                ForEach(0..<scoreOptions.count, id: \.self) { dialCell(idx: $0) }
            }
            .frame(height: totalH)
            .clipped()

            // ── Layer 2: selected item inside band ─────────────────────
            ZStack {
                ForEach(0..<scoreOptions.count, id: \.self) { dialCell(idx: $0) }
            }
            .frame(width: bandW, height: bandH)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            // ── Layer 3: stroke border on top ──────────────────────────
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.textPrimary, lineWidth: 2)
                .frame(width: bandW, height: bandH)
        }
        .frame(width: 354, height: totalH)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { v in
                    dragOffset = v.translation.height
                    let steps    = -Int((v.translation.height / itemH).rounded())
                    let liveIdx  = max(0, min(scoreOptions.count - 1, selectedIndex + steps))
                    if liveIdx != liveDragIndex {
                        liveDragIndex = liveIdx
                        dialFeedback.impactOccurred()
                        AudioServicesPlaySystemSound(1104)
                    }
                }
                .onEnded { v in
                    let boost  = v.predictedEndTranslation.height - v.translation.height
                    let total  = v.translation.height + boost * 0.18
                    let steps  = -Int((total / itemH).rounded())
                    let newIdx = max(0, min(scoreOptions.count - 1, selectedIndex + steps))
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        selectedIndex = newIdx
                        liveDragIndex = newIdx
                        dragOffset = 0
                    }
                }
        )
    }

    // Figma: number 55px bold, label 14px medium, gap-8 between them
    @ViewBuilder
    private func dialCell(idx: Int) -> some View {
        let rawY     = CGFloat(idx - selectedIndex) * itemH + dragOffset
        let dist     = abs(rawY / itemH)
        let isCtr    = idx == selectedIndex
        let opt      = scoreOptions[idx]
        let numColor: Color = isCtr ? Color.deepNavy : Color(hexString: "#E2E2E2")
        let lblColor: Color = isCtr ? Color(hexString: "#7A7A7E") : Color(hexString: "#E2E2E2")

        VStack(spacing: 4) {
            Text("\(opt.val)")
                .font(.system(size: 55, weight: .bold))
                .monospacedDigit()
                .foregroundColor(numColor)
                .frame(height: 52)
            Text(opt.label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(lblColor)
        }
        .opacity(isCtr ? 1.0 : max(0.08, 1.0 - dist * 0.4))
        .offset(y: rawY)
    }

    // MARK: - Actions

    private var bottomActions: some View {
        HStack(spacing: 10) {
            // Save — filled black
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onSelect(current.val)
            } label: {
                Text("Save")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(RoundedRectangle(cornerRadius: 19).fill(Color.textPrimary))
            }
            .buttonStyle(.plain)

            // Score next — stroke outline
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onScoreNext(current.val)
            } label: {
                Text("Score Next")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 19)
                            .strokeBorder(Color.textPrimary, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }
}
