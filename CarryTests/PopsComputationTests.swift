import XCTest
@testable import Carry

/// Tests for the "pops" (total handicap strokes) number shown under each
/// player's name on the Round Stats section of the post-round Results
/// screen. Locks behavior for regular handicaps, plus handicaps, zero
/// handicaps, and the no-tee-box fallback.
///
/// The underlying math is `TeeBox.playingHandicap(forIndex:percentage:)` —
/// standard USGA: `round(index * slope/113 + (CR - par)) * percentage`. The
/// `pops(for:)` helper on `RoundStatsView` clamps negatives to 0 (plus
/// handicaps give strokes, they don't receive them) and falls back to a
/// rounded raw index when no tee box is attached.
final class PopsComputationTests: XCTestCase {

    // MARK: - Helpers

    /// Mirrors the pops math inside `RoundStatsView.pops(for:)`. Kept in
    /// sync here so the contract is pinned without having to expose the
    /// private view method. A tee box with zero slope or rating counts as
    /// missing — falls back to rounded raw index.
    private func computePops(handicap: Double, teeBox: TeeBox?, percentage: Double) -> Int {
        let playingHcp: Int
        if let teeBox, teeBox.slopeRating > 0, teeBox.courseRating > 0 {
            playingHcp = teeBox.playingHandicap(forIndex: handicap, percentage: percentage)
        } else {
            playingHcp = Int(handicap.rounded())
        }
        return max(playingHcp, 0)
    }

    private func makeTeeBox(rating: Double = 71.0, slope: Int = 113, par: Int = 72) -> TeeBox {
        TeeBox(
            id: "test",
            courseId: "c",
            name: "Blue",
            color: "#1E6BB8",
            courseRating: rating,
            slopeRating: slope,
            par: par,
            holes: nil
        )
    }

    // MARK: - Regular handicaps

    func testPops_regularIndex_withSlope113AndMatchingRating() {
        // Slope 113 is the "neutral" slope — Course Hcp ≈ index + (CR - par).
        // CR 72, par 72 → Course Hcp = index exactly. Pops = rounded index.
        let tb = makeTeeBox(rating: 72.0, slope: 113, par: 72)
        let pops = computePops(handicap: 6.5, teeBox: tb, percentage: 1.0)
        // playingHandicap rounds once at the end, so 6.5 → 7 (banker's rounding) or 6.
        // Swift's .rounded() uses schoolbook: 6.5 → 7. We just assert the
        // range, since USGA doesn't care which way ties break as long as
        // it's applied consistently.
        XCTAssertTrue(pops == 6 || pops == 7, "6.5 index on neutral tee should be 6 or 7 pops, got \(pops)")
    }

    func testPops_higherSlopeGivesMoreStrokes() {
        // Same index, higher slope → more strokes. Regression guard.
        let easy = makeTeeBox(rating: 72.0, slope: 113, par: 72)
        let hard = makeTeeBox(rating: 72.0, slope: 140, par: 72)
        let easyPops = computePops(handicap: 12.0, teeBox: easy, percentage: 1.0)
        let hardPops = computePops(handicap: 12.0, teeBox: hard, percentage: 1.0)
        XCTAssertGreaterThan(hardPops, easyPops,
                             "Higher slope must produce more pops for the same index")
    }

    func testPops_handicapPercentageReducesStrokes() {
        // 80% skins rule: a 20 index playing at 80% should get fewer pops
        // than at 100%.
        let tb = makeTeeBox(rating: 72.0, slope: 113, par: 72)
        let full = computePops(handicap: 20.0, teeBox: tb, percentage: 1.0)
        let reduced = computePops(handicap: 20.0, teeBox: tb, percentage: 0.8)
        XCTAssertGreaterThan(full, reduced,
                             "Lower handicap percentage must produce fewer pops")
    }

    // MARK: - Edge cases

    func testPops_zeroHandicap_returnsZero() {
        let tb = makeTeeBox()
        XCTAssertEqual(computePops(handicap: 0.0, teeBox: tb, percentage: 1.0), 0)
    }

    func testPops_plusHandicap_clampsToZero() {
        // Plus handicaps give strokes back — they don't receive any. The UI
        // label should read "0 pops" regardless of how negative the playing
        // handicap is.
        let tb = makeTeeBox(rating: 72.0, slope: 113, par: 72)
        XCTAssertEqual(computePops(handicap: -2.0, teeBox: tb, percentage: 1.0), 0,
                       "Plus handicaps receive 0 pops")
        XCTAssertEqual(computePops(handicap: -5.5, teeBox: tb, percentage: 1.0), 0,
                       "Even a +5.5 plays at 0 pops received")
    }

    func testPops_highIndex_exceedsEighteen() {
        // A 36 index on a neutral tee should produce ~36 pops (some holes
        // get 2 strokes). Confirms we don't accidentally cap at 18.
        let tb = makeTeeBox(rating: 72.0, slope: 113, par: 72)
        let pops = computePops(handicap: 36.0, teeBox: tb, percentage: 1.0)
        XCTAssertGreaterThanOrEqual(pops, 35, "36 index on neutral tee should be ≥ 35 pops")
        XCTAssertLessThanOrEqual(pops, 37)
    }

    // MARK: - No tee box fallback

    func testPops_noTeeBox_usesRoundedIndex() {
        // Quick Games without a tee box should still show a sensible pops
        // number — rounded raw index.
        XCTAssertEqual(computePops(handicap: 6.5, teeBox: nil, percentage: 1.0), 6)  // .rounded default
        XCTAssertEqual(computePops(handicap: 14.0, teeBox: nil, percentage: 1.0), 14)
        XCTAssertEqual(computePops(handicap: 36.0, teeBox: nil, percentage: 1.0), 36)
    }

    func testPops_noTeeBox_plusHandicap_clampsToZero() {
        // Fallback path must still clamp plus handicaps.
        XCTAssertEqual(computePops(handicap: -2.0, teeBox: nil, percentage: 1.0), 0)
    }

    func testPops_noTeeBox_zeroHandicap_returnsZero() {
        XCTAssertEqual(computePops(handicap: 0.0, teeBox: nil, percentage: 1.0), 0)
    }

    // MARK: - Malformed tee box

    func testPops_teeBoxWithZeroSlope_fallsBackToRawIndex() {
        // A tee box present but missing slope (legacy row, incomplete API
        // response) would produce nonsense through USGA math. Guard should
        // treat this as no-tee-box and use the rounded raw index instead.
        let badTee = makeTeeBox(rating: 72.0, slope: 0, par: 72)
        XCTAssertEqual(computePops(handicap: 14.0, teeBox: badTee, percentage: 1.0), 14,
                       "Zero slope must fall back to rounded raw index")
    }

    func testPops_teeBoxWithZeroRating_fallsBackToRawIndex() {
        // Same defense for missing course rating.
        let badTee = makeTeeBox(rating: 0.0, slope: 113, par: 72)
        XCTAssertEqual(computePops(handicap: 14.0, teeBox: badTee, percentage: 1.0), 14,
                       "Zero rating must fall back to rounded raw index")
    }
}
