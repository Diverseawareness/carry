import XCTest
import SwiftUI
@testable import Carry

/// Visual proof for the 1.1.2 Bug 2 fix (score-sheet Save buttons clipped on
/// short devices). Renders the REAL `ScoreInputSheet` inside a faithful copy
/// of the ScorecardView drawer wrapper at iPhone SE size (375×667), with the
/// OLD fixed-0.62 height (reproduces the clip) and the NEW max() height (fix).
/// PNGs are written to /tmp so they can be eyeballed without auth or a live round.
@MainActor
final class ScoreSheetClipSnapshotTests: XCTestCase {

    // iPhone SE (3rd gen) — the short device class where the bug shows.
    private let screen = CGSize(width: 375, height: 667)

    private func holes() -> [Hole] {
        (1...18).map { Hole(id: $0, num: $0, par: 4, hcp: $0) }
    }

    /// Faithful copy of the ScorecardView drawer: dim backdrop + bottom-anchored
    /// white card containing the grab handle + the real ScoreInputSheet, with
    /// `.clipped()` and a parameterized height — exactly the production modifier
    /// order. `useFix` toggles old (0.62 only) vs new (max with content floor).
    private func drawer(useFix: Bool) -> some View {
        let player = Player.allPlayers[0]
        let oldHeight = screen.height * 0.62
        let newHeight = max(
            screen.height * 0.62,
            ScoreInputSheet.minimumContentHeight(extraBottomPadding: 0) + 36
        )
        let h = useFix ? newHeight : oldHeight

        return ZStack(alignment: .bottom) {
            Color.black.opacity(0.30)
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.gridLine)
                    .frame(width: 36, height: 4)
                    .padding(.top, 17)
                    .frame(maxWidth: .infinity, minHeight: 36)
                ScoreInputSheet(
                    player: player,
                    holeNum: 1,
                    holes: holes(),
                    strokesGiven: 0,
                    currentScore: 4,
                    onSelect: { _ in },
                    onScoreNext: { _ in }
                )
            }
            .clipped()
            .frame(height: h)
            .background(
                RoundedRectangle(cornerRadius: 48, style: .continuous).fill(Color.white)
            )
        }
        .frame(width: screen.width, height: screen.height)
        .background(Color(white: 0.9))
    }

    private func render(_ view: some View, to name: String) {
        let renderer = ImageRenderer(content: view.frame(width: screen.width, height: screen.height))
        renderer.scale = 2
        guard let img = renderer.uiImage, let data = img.pngData() else {
            XCTFail("render failed for \(name)"); return
        }
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        try? data.write(to: url)
        print("WROTE \(url.path) (\(data.count) bytes, \(img.size.width)x\(img.size.height)pt)")
    }

    func testRenderOldVsNew() {
        render(drawer(useFix: false), to: "score_sheet_SE_OLD_clipped.png")
        render(drawer(useFix: true),  to: "score_sheet_SE_NEW_fixed.png")
    }
}
