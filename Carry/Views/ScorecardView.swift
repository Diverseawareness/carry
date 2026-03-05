import SwiftUI

// Reference type so UIKit coordinator and SwiftUI closures share the same flag
private final class ScrollSuppression {
    var isSuppressed = false
}

struct ScorecardView: View {
    let config: RoundConfig
    var onBack: (() -> Void)?
    @StateObject private var viewModel: RoundViewModel
    @State private var showInput = false
    @State private var inputHole: Int?
    @State private var inputPlayer: Player?
    @State private var showLabels = true
    private let scrollSuppression = ScrollSuppression()

    let currentUserId: Int

    init(config: RoundConfig = .default, onBack: (() -> Void)? = nil, currentUserId: Int = 1) {
        self.config = config
        self.onBack = onBack
        self.currentUserId = currentUserId
        _viewModel = StateObject(wrappedValue: RoundViewModel(config: config, currentUserId: currentUserId))
    }

    private var screenTopInset: CGFloat {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first
        else { return 59 }
        return window.safeAreaInsets.top
    }

    var body: some View {
        GeometryReader { geo in
            let layout = LayoutMetrics(size: geo.size, playerCount: viewModel.groupPlayers.count)
            mainContent(layout: layout)
                .padding(.top, screenTopInset - 7)
        }
        .ignoresSafeArea(.container, edges: .top)
        .ignoresSafeArea(.keyboard)
    }

    @ViewBuilder
    private func mainContent(layout: LayoutMetrics) -> some View {
        let players = viewModel.groupPlayers
        let active = viewModel.activeHole

        ZStack {
            Color(hex: "#F0F0F0").ignoresSafeArea()

            VStack(spacing: 6) {
                headerBar()

                CashGamesBar(viewModel: viewModel)
                    .padding(.horizontal, layout.cardM)
                    .padding(.vertical, 4)

                scorecardSection(layout: layout, players: players, active: active)
            }

            scoreInputOverlay()
        }
    }

    @ViewBuilder
    private func headerBar() -> some View {
        ZStack {
            // Centered title + subtitle
            VStack(spacing: 1) {
                Text("Skins Game")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Text("Friday Meetings")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color(hex: "#999999"))
            }

            // Leading back button
            HStack {
                if let onBack {
                    Button {
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.white))
                            .clipShape(Circle())
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func scorecardSection(layout: LayoutMetrics, players: [Player], active: Int?) -> some View {
        ZStack(alignment: .topLeading) {
            scrollableContent(layout: layout, players: players, active: active)
            if showLabels {
                stickyLeftColumn(layout: layout, players: players)
                    .transition(.move(edge: .leading))
            }
        }
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, layout.cardM)
    }

    @ViewBuilder
    private func scrollableContent(layout: LayoutMetrics, players: [Player], active: Int?) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    SkinsRow(
                        viewModel: viewModel,
                        holes: Hole.allHoles,
                        activeHole: active,
                        cellWidth: layout.cellW,
                        sumWidth: layout.sumW,
                        skinsHeight: layout.skinsH
                    )
                    .background(Color(hex: "#FAFAFA"))

                    Divider()

                    HoleHeaderRow(
                        holes: Hole.allHoles,
                        activeHole: active,
                        cellWidth: layout.cellW,
                        sumWidth: layout.sumW,
                        rowHeight: layout.holeRowH,
                        numFont: layout.numFont
                    )

                    Divider()

                    playerRows(layout: layout, players: players, active: active)
                }
                .overlay(alignment: .topLeading) {
                    // Single continuous stroke around the active hole column
                    ActiveHoleStroke(
                        activeHole: active,
                        cellWidth: layout.cellW
                    )
                }
                .padding(.leading, showLabels ? layout.labelW : 0)
                .overlay(alignment: .topLeading) {
                    ScrollDirectionDetector(suppression: scrollSuppression) { scrollingLeft in
                        if scrollingLeft && showLabels {
                            withAnimation(.easeOut(duration: 0.15)) { showLabels = false }
                        } else if !scrollingLeft && !showLabels {
                            withAnimation(.easeOut(duration: 0.1)) { showLabels = true }
                        }
                    }
                    .frame(width: 1, height: 1)
                }
            }
            .onAppear {
                if let num = active {
                    // First hole in play order is already visible — no scroll needed
                    guard num != viewModel.playOrder.first?.num else { return }
                    scrollSuppression.isSuppressed = true
                    proxy.scrollTo("hole_\(num)", anchor: .center)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [scrollSuppression] in
                        scrollSuppression.isSuppressed = false
                    }
                }
            }
            .onChange(of: active) { newActive in
                if let num = newActive {
                    scrollSuppression.isSuppressed = true
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        proxy.scrollTo("hole_\(num)", anchor: .center)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [scrollSuppression] in
                        scrollSuppression.isSuppressed = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func playerRows(layout: LayoutMetrics, players: [Player], active: Int?) -> some View {
        ForEach(players) { player in
            let isYou = player.id == viewModel.currentUserId
            let isLast = player.id == players.last?.id

            PlayerRow(
                player: player,
                holes: Hole.allHoles,
                viewModel: viewModel,
                activeHole: active,
                cellWidth: layout.cellW,
                sumWidth: layout.sumW,
                rowHeight: layout.rowH,
                scoreFont: layout.scoreFont,
                circleSize: layout.circleSize,
                isYou: isYou,
                onTapCell: { holeNum, p in
                    guard viewModel.canScore(holeNum: holeNum) else { return }
                    inputHole = holeNum
                    inputPlayer = p
                    showInput = true
                }
            )
            .background(isYou ? Color(hex: "#D4A017").opacity(0.03) : .clear)

            if !isLast {
                Rectangle()
                    .fill(Color(hex: "#F0F0F0"))
                    .frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private func stickyLeftColumn(layout: LayoutMetrics, players: [Player]) -> some View {
        VStack(spacing: 0) {
            stickyLabel(text: "Skins", height: layout.skinsH, font: layout.labelFont, bg: Color(hex: "#FAFAFA"), layout: layout)

            Rectangle().fill(Color(hex: "#EAEAEA")).frame(height: 0.5)

            stickyLabel(text: "Hole", height: layout.holeRowH, font: layout.labelFont, bg: .white, layout: layout)

            Rectangle().fill(Color(hex: "#EAEAEA")).frame(height: 0.5)

            stickyPlayerLabels(layout: layout, players: players)
        }
        .frame(width: layout.labelW)
        .background(.white)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 0, topTrailingRadius: 0))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(hex: "#EAEAEA"))
                .frame(width: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 4, x: 4)
    }

    @ViewBuilder
    private func stickyPlayerLabels(layout: LayoutMetrics, players: [Player]) -> some View {
        ForEach(players) { player in
            let isYou = player.id == viewModel.currentUserId
            let isLast = player.id == players.last?.id
            let bg = isYou ? Color(hex: "#FFFDF7") : Color.white

            Text(player.truncatedName)
                .font(.system(size: layout.labelFont, weight: isYou ? .bold : .medium))
                .foregroundColor(isYou ? Color(hex: "#1A1A1A") : Color(hex: "#888888"))
                .lineLimit(1)
                .padding(.leading, layout.labelPad)
            .frame(width: layout.labelW, height: layout.rowH, alignment: .leading)
            .background(bg)

            if !isLast {
                Rectangle().fill(Color(hex: "#F0F0F0")).frame(height: 1)
                    .background(bg)
            }
        }
    }

    @ViewBuilder
    private func scoreInputOverlay() -> some View {
        if showInput, let hole = inputHole, let player = inputPlayer {
            ScoreInputView(
                player: player,
                holeNum: hole,
                holes: Hole.allHoles,
                strokesGiven: {
                    if let h = Hole.allHoles.first(where: { $0.num == hole }) {
                        return viewModel.strokes(for: player, hole: h)
                    }
                    return 0
                }(),
                onSelect: { score in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        viewModel.enterScore(playerId: player.id, holeNum: hole, score: score)
                    }
                    showInput = false
                    inputPlayer = nil
                },
                onCancel: {
                    showInput = false
                    inputPlayer = nil
                }
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: showInput)
        }
    }

    @ViewBuilder
    private func stickyLabel(text: String, height: CGFloat, font: CGFloat, bg: Color, layout: LayoutMetrics) -> some View {
        Text(text)
            .font(.system(size: font, weight: .semibold))
            .foregroundColor(Color(hex: "#1A1A1A"))
            .padding(.leading, layout.labelPad)
            .frame(width: layout.labelW, height: height, alignment: .leading)
            .background(bg)
    }
}

// MARK: - Active Hole Column Stroke

private struct ActiveHoleStroke: View {
    let activeHole: Int?
    let cellWidth: CGFloat

    private var columnIndex: Int {
        guard let num = activeHole else { return 0 }
        return Hole.allHoles.firstIndex(where: { $0.num == num }) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(hex: "#1A1A1A"), lineWidth: 1.5)
                .frame(width: cellWidth, height: geo.size.height)
                .offset(x: CGFloat(columnIndex) * cellWidth)
                .opacity(activeHole != nil ? 1 : 0)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: activeHole)
        .allowsHitTesting(false)
    }
}

// MARK: - Layout Metrics

private struct LayoutMetrics {
    let cardM: CGFloat
    let headerH: CGFloat
    let gap: CGFloat
    let rowH: CGFloat
    let holeRowH: CGFloat
    let skinsH: CGFloat
    let labelFont: CGFloat
    let avatarSize: CGFloat
    let labelPad: CGFloat
    let labelW: CGFloat
    let cellW: CGFloat
    let sumW: CGFloat
    let scoreFont: CGFloat
    let circleSize: CGFloat
    let numFont: CGFloat

    init(size: CGSize, playerCount: Int) {
        let h = size.height
        cardM = 12
        headerH = 34
        let gamesBarH: CGFloat = 80
        gap = 4
        let homeIndicator: CGFloat = 34

        // Fixed base for sizing text/cells (as if 6 rows)
        let baseRow = max(32, floor((h - headerH - gamesBarH - gap * 2 - cardM) / 6))

        // Compact header rows based on baseRow
        skinsH = max(28, floor(baseRow * 0.7))
        holeRowH = max(24, floor(baseRow * 0.6))

        // Player rows grow to fill remaining space to the safe line
        let n = CGFloat(max(1, playerCount))
        let dividers: CGFloat = 3
        let playerDividers = CGFloat(max(0, playerCount - 1))
        let cardH = h - headerH - gamesBarH - gap - homeIndicator
        let fixedH = skinsH + holeRowH + dividers + playerDividers
        rowH = max(baseRow, floor((cardH - fixedH) / n))

        // Fonts and element sizes stay based on baseRow (don't grow)
        labelFont = 18
        avatarSize = max(18, baseRow * 0.4)
        labelPad = 12
        let fontSize: CGFloat = labelFont
        let textW = CGFloat(MAX_NAME_CHARS) * fontSize * 0.5
        labelW = ceil(labelPad + textW + 10)
        cellW = max(36, floor(baseRow * 1.1))
        sumW = max(38, floor(cellW * 1.05))
        scoreFont = max(14, floor(baseRow * 0.38))
        circleSize = max(24, floor(baseRow * 0.55))
        numFont = max(12, floor(baseRow * 0.3))
    }
}

// MARK: - UIKit Scroll Direction Observer

private struct ScrollDirectionDetector: UIViewRepresentable {
    let suppression: ScrollSuppression
    let onDirectionChange: (Bool) -> Void  // true = scrolling left

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .init(x: 0, y: 0, width: 1, height: 1))
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            if let scrollView = view.findParentScrollView() {
                context.coordinator.observe(scrollView)
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(suppression: suppression, onDirectionChange: onDirectionChange)
    }

    class Coordinator: NSObject {
        let suppression: ScrollSuppression
        let onDirectionChange: (Bool) -> Void
        private var lastOffset: CGFloat = 0
        private var observation: NSKeyValueObservation?
        private var ignoreUntil: Date = .distantPast

        init(suppression: ScrollSuppression, onDirectionChange: @escaping (Bool) -> Void) {
            self.suppression = suppression
            self.onDirectionChange = onDirectionChange
        }

        func observe(_ scrollView: UIScrollView) {
            lastOffset = scrollView.contentOffset.x
            observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                guard let self else { return }

                // Check suppression via reference type (always up-to-date)
                if self.suppression.isSuppressed {
                    self.lastOffset = sv.contentOffset.x
                    return
                }

                let now = Date()
                let current = sv.contentOffset.x

                // Skip offset jumps caused by padding animation
                if now < self.ignoreUntil {
                    self.lastOffset = current
                    return
                }

                let delta = current - self.lastOffset
                if delta > 3 {
                    self.ignoreUntil = now.addingTimeInterval(0.3)
                    DispatchQueue.main.async { self.onDirectionChange(true) }
                } else if delta < -3 {
                    self.ignoreUntil = now.addingTimeInterval(0.5)
                    DispatchQueue.main.async { self.onDirectionChange(false) }
                }
                self.lastOffset = current
            }
        }
    }
}

private extension UIView {
    func findParentScrollView() -> UIScrollView? {
        var current: UIView? = superview
        while let view = current {
            if let sv = view as? UIScrollView { return sv }
            current = view.superview
        }
        return nil
    }
}

