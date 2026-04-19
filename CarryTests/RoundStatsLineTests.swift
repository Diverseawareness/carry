import XCTest
@testable import Carry

/// Tests for `RoundStatsLine.make` — the per-player score stats line shown
/// below the leaderboard on the Round Complete results screen.
///
/// Expected format: `"38 · 38 76, 3 Birdies, 1 Bogey"`
/// - Front 9 strokes · Back 9 strokes  Total
/// - Comma-separated categories in order: Eagles, Birdies, Bogeys, Doubles+
/// - Pars are intentionally omitted (they're the dominant, uninteresting case)
final class RoundStatsLineTests: XCTestCase {

    // Standard 18-hole par map: 4-4-5-3-4-3-4-5-4 / 5-4-4-3-4-4-5-3-4 = 72
    private let pars18: [Int: Int] = [
        1: 4, 2: 4, 3: 5, 4: 3, 5: 4, 6: 3, 7: 4, 8: 5, 9: 4,
        10: 5, 11: 4, 12: 4, 13: 3, 14: 4, 15: 4, 16: 5, 17: 3, 18: 4
    ]

    // MARK: - Nil cases

    func testEmptyScoresReturnsNil() {
        XCTAssertNil(RoundStatsLine.make(playerScores: [:], parsByHole: pars18))
    }

    func testAllZeroScoresReturnsNil() {
        // Zero is our sentinel for "unscored" — not a legit stroke count
        let scores = Dictionary(uniqueKeysWithValues: (1...18).map { ($0, 0) })
        XCTAssertNil(RoundStatsLine.make(playerScores: scores, parsByHole: pars18))
    }

    func testScoresWithNoMatchingParReturnsNil() {
        // All scores for holes that aren't in the par map → nothing to count
        let scores = [100: 4, 101: 5, 102: 3]
        XCTAssertNil(RoundStatsLine.make(playerScores: scores, parsByHole: pars18))
    }

    // MARK: - All pars (clean baseline)

    func testAllPars_showsOnlyTotals() {
        // Every hole played at par → totals only, no categories surfaced
        let scores = pars18   // score == par on every hole
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "36 \u{00B7} 36 72")
    }

    // MARK: - Front/back split

    func testFrontNineOnly() {
        // Player walked off after 9. Front = 36 (par), back = 0, total = 36.
        let scores = Dictionary(uniqueKeysWithValues: pars18.filter { $0.key <= 9 })
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "36 \u{00B7} 0 36")
    }

    func testBackNineOnly() {
        let scores = Dictionary(uniqueKeysWithValues: pars18.filter { $0.key > 9 })
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "0 \u{00B7} 36 36")
    }

    // MARK: - Categories — singular vs plural

    func testSingleBirdie_pluralization() {
        // All pars except hole 1 where player made birdie (3 on a par 4)
        var scores = pars18
        scores[1] = 3
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "35 \u{00B7} 36 71, 1 Birdie")
    }

    func testMultipleBirdies_pluralization() {
        var scores = pars18
        scores[1] = 3   // birdie on par 4
        scores[2] = 3   // birdie on par 4
        scores[3] = 4   // birdie on par 5
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "33 \u{00B7} 36 69, 3 Birdies")
    }

    func testSingleBogey_pluralization() {
        var scores = pars18
        scores[1] = 5   // bogey on par 4
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "37 \u{00B7} 36 73, 1 Bogey")
    }

    func testMultipleBogeys_pluralization() {
        var scores = pars18
        scores[1] = 5
        scores[2] = 5
        scores[3] = 6
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "39 \u{00B7} 36 75, 3 Bogeys")
    }

    func testSingleEagle_pluralization() {
        var scores = pars18
        scores[3] = 3   // eagle on par 5
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "34 \u{00B7} 36 70, 1 Eagle")
    }

    func testMultipleEagles_pluralization() {
        // Par front 9 = 36. Hole 3 eagle saves 2, hole 8 eagle saves 2 → front 32.
        var scores = pars18
        scores[3] = 3   // eagle on par 5
        scores[8] = 3   // eagle on par 5
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "32 \u{00B7} 36 68, 2 Eagles")
    }

    // MARK: - Eagle bucket (includes albatross)

    func testAlbatrossCountsAsEagle() {
        // Albatross: 3 under par. On a par 5 → score of 2. Should bucket as "Eagle".
        var scores = pars18
        scores[3] = 2   // albatross on par 5
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "33 \u{00B7} 36 69, 1 Eagle")
    }

    // MARK: - Double bogey+

    func testDoubleBogey_singular() {
        var scores = pars18
        scores[1] = 6   // double bogey on par 4
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "38 \u{00B7} 36 74, 1 Double Bogey+")
    }

    func testDoubleBogey_plural() {
        var scores = pars18
        scores[1] = 6
        scores[2] = 6
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "40 \u{00B7} 36 76, 2 Double Bogeys+")
    }

    func testTripleBogeyBucketsWithDoubleBogeyPlus() {
        // Triple bogey (+3) lands in the same bucket as double bogey
        var scores = pars18
        scores[1] = 7   // triple bogey on par 4
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "39 \u{00B7} 36 75, 1 Double Bogey+")
    }

    // MARK: - Mixed categories & ordering

    func testMixedRound_allCategoriesInOrder() {
        // Front: 2 birdies (−2) + 1 eagle (−2) = 36 − 4 = 32
        // Back: par back = 36, hole 10 DB+ (+2), hole 18 bogey (+1) = 36 + 3 = 39
        // Total: 32 + 39 = 71
        var scores = pars18
        scores[3] = 3   // eagle on par 5
        scores[1] = 3   // birdie on par 4
        scores[2] = 3   // birdie on par 4
        scores[18] = 5  // bogey on par 4
        scores[10] = 7  // double bogey+ on par 5
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(
            line,
            "32 \u{00B7} 39 71, 1 Eagle, 2 Birdies, 1 Bogey, 1 Double Bogey+"
        )
    }

    func testMixedRound_userExample() {
        // Mirrors the user's example: "38 · 38 76, 3 Birdies, 1 Bogey"
        // Build a round that produces exactly that stat line.
        var scores = pars18
        // Front: 3 birdies on holes 1, 2, 3 → front score = 36 − 3 = 33
        scores[1] = 3
        scores[2] = 3
        scores[3] = 4   // birdie on par 5
        // Front adjustment for 38: need 5 more strokes. Add bogeys:
        scores[4] = 4   // bogey on par 3
        scores[5] = 5   // bogey on par 4
        scores[6] = 4   // bogey on par 3
        scores[7] = 5   // bogey on par 4
        scores[8] = 6   // bogey on par 5
        // That's 3 birdies + 5 bogeys + 1 par (hole 9) on the front → 33 - 3 + 5 = ... let me recompute
        // Par front = 36. Birdies save 3. Bogeys add 5. Front strokes = 36 - 3 + 5 = 38 ✓
        // Back strokes should be 38 with only pars.  Par back = 36. Need +2. Add bogeys.
        scores[10] = 6  // bogey on par 5
        scores[11] = 5  // bogey on par 4
        // So actual: front = 3 birdies + 5 bogeys + 1 par = 38
        //           back = 2 bogeys + 7 pars = 38
        //           total = 76
        //           3 Birdies, 7 Bogeys (not 1!)
        // Tweak: test the real output, not the user's example literally
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "38 \u{00B7} 38 76, 3 Birdies, 7 Bogeys")
    }

    // MARK: - Zero / sentinel values

    func testZeroScoresAreIgnored() {
        // Player has scored holes 1-9 at par, holes 10-18 marked 0 (unplayed)
        var scores = pars18
        for hole in 10...18 { scores[hole] = 0 }
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "36 \u{00B7} 0 36")
    }

    func testNegativeScoresAreIgnored() {
        // Negative scores shouldn't happen but defensively ignore them
        var scores = pars18
        scores[1] = -1
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        // Hole 1's score ignored. Rest is pure pars → 36 - 4 (par of hole 1) = 32 front
        XCTAssertEqual(line, "32 \u{00B7} 36 68")
    }

    // MARK: - Partial par map

    func testHolesWithoutParAreSkipped() {
        // Player scored 18 holes but we only have par for 9 of them
        let frontParOnly = Dictionary(uniqueKeysWithValues: pars18.filter { $0.key <= 9 })
        let scores = pars18   // all pars on full 18
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: frontParOnly)
        // Only front 9 scored (back holes have no par → skipped)
        XCTAssertEqual(line, "36 \u{00B7} 0 36")
    }

    // MARK: - Boundary cases

    func testSingleHolePlayed() {
        // Just one hole with a birdie — edge case but valid
        let scores = [1: 3]
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "3 \u{00B7} 0 3, 1 Birdie")
    }

    func testOnlyHoleTenPlayed_countsAsBackNine() {
        // Hole 10 is on the back nine
        let scores = [10: 5]   // par on par 5
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "0 \u{00B7} 5 5")
    }

    func testHoleNineCountsAsFront() {
        // Hole 9 is inclusive in front
        let scores = [9: 4]
        let line = RoundStatsLine.make(playerScores: scores, parsByHole: pars18)
        XCTAssertEqual(line, "4 \u{00B7} 0 4")
    }
}
