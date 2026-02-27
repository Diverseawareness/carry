import SwiftUI

struct ScorecardView: View {
    @StateObject private var vm = RoundViewModel()
    @State private var showInput = false
    @State private var inputHole: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            VStack(spacing: 0) {
                // Header
                HeaderView(vm: vm, isLandscape: isLandscape)

                Divider().foregroundColor(Color(hex: "F0F0F0"))

                // Scorecard grid
                ZStack {
                    VStack(spacing: 0) {
                        HoleHeaderRow(holes: vm.holes, activeHole: vm.activeHole, cellWidth: cellWidth(geo))
                        Divider().padding(.horizontal, 14)

                        ForEach(vm.players) { player in
                            PlayerRow(
                                player: player,
                                vm: vm,
                                cellWidth: cellWidth(geo),
                                rowHeight: rowHeight(geo, isLandscape: isLandscape),
                                onTapHole: { hole in
                                    inputHole = hole
                                    showInput = true
                                }
                            )
                        }

                        Divider().padding(.horizontal, 14)
                        SkinsRow(vm: vm, cellWidth: cellWidth(geo))
                    }

                    if showInput, let hole = inputHole {
                        ScoreInputView(
                            hole: vm.holes.first { $0.num == hole }!,
                            player: vm.players[0],
                            vm: vm,
                            isLandscape: isLandscape,
                            onScore: { score in
                                vm.enterScore(score, forHole: hole)
                                showInput = false
                            },
                            onCancel: { showInput = false }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3), value: showInput)

                Spacer(minLength: 0)

                // Bottom bar
                if let active = vm.activeHole, !showInput {
                    BottomBar(hole: vm.holes.first { $0.num == active }!) {
                        inputHole = active
                        showInput = true
                    }
                }
            }
        }
        .background(Color.white)
        .ignoresSafeArea()
    }

    private func cellWidth(_ geo: GeometryProxy) -> CGFloat {
        (geo.size.width - 52) / CGFloat(vm.holes.count)
    }

    private func rowHeight(_ geo: GeometryProxy, isLandscape: Bool) -> CGFloat {
        let headerH: CGFloat = isLandscape ? 60 : 90
        let available = geo.size.height - headerH - 40 - 32 - 56
        return available / CGFloat(vm.players.count)
    }
}

#Preview {
    ScorecardView()
}
