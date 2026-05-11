import XCTest
@testable import Carry

/// Tests for the core skins calculation logic.
/// These verify that RoundViewModel.calculateSkins produces correct results
/// for all common golf skins scenarios.
final class SkinsCalculationTests: XCTestCase {

    // MARK: - Helpers

    /// Build a minimal RoundConfig for testing with N players on default holes.
    /// `handicapPercentage` defaults to 1.0 (full allowance) — pass < 1.0
    /// to exercise the reduced-allowance code path used in 80% / 70% skins.
    private func makeConfig(
        playerCount: Int = 4,
        buyIn: Int = 50,
        carries: Bool = false,
        net: Bool = false,
        handicapPercentage: Double = 1.0,
        playerIndices: [Double]? = nil
    ) -> RoundConfig {
        let players = (0..<playerCount).map { i -> Player in
            let hcp: Double = {
                if let indices = playerIndices, i < indices.count { return indices[i] }
                return Double(i) * 2.0
            }()
            return Player(
                id: i + 1,
                name: "P\(i + 1)",
                initials: "P\(i + 1)",
                color: "#333333",
                handicap: hcp,
                avatar: "",
                group: 1,
                ghinNumber: nil,
                venmoUsername: nil
            )
        }
        return RoundConfig(
            id: "test-\(UUID().uuidString)",
            number: 1,
            course: "Test Course",
            date: "2026-04-11",
            buyIn: buyIn,
            gameType: "skins",
            skinRules: SkinRules(net: net, carries: carries, outright: true, handicapPercentage: handicapPercentage),
            teeBox: TeeBox(id: "t1", courseId: "c1", name: "Blue", color: "#2563EB",
                           courseRating: 71.5, slopeRating: 134, par: 72, holes: Hole.allHoles),
            groups: [GroupConfig(id: 1, startingSide: "front", playerIDs: players.map(\.id))],
            creatorId: 1,
            groupName: "Test",
            players: players,
            holes: Hole.allHoles
        )
    }

    /// Create a RoundViewModel, enter scores, and return it for assertions.
    private func makeVM(config: RoundConfig, scores: [Int: [Int: Int]]) -> RoundViewModel {
        let vm = RoundViewModel(config: config, currentUserId: 1)
        for (playerId, holeScores) in scores {
            for (hole, score) in holeScores {
                vm.enterScore(playerId: playerId, holeNum: hole, score: score)
            }
        }
        return vm
    }

    // MARK: - Basic Skins

    func testOutrightWinner_getsSkin() {
        let config = makeConfig()
        // Hole 1: P1 shoots 3, everyone else shoots 4
        var scores: [Int: [Int: Int]] = [:]
        for h in 1...18 {
            scores[1] = (scores[1] ?? [:]).merging([h: h == 1 ? 3 : 4]) { _, new in new }
            scores[2] = (scores[2] ?? [:]).merging([h: 4]) { _, new in new }
            scores[3] = (scores[3] ?? [:]).merging([h: 4]) { _, new in new }
            scores[4] = (scores[4] ?? [:]).merging([h: 4]) { _, new in new }
        }

        let vm = makeVM(config: config, scores: scores)
        let skins = vm.cachedSkins

        // Hole 1 should be won by P1
        if case .won(let winner, _, _, let carry) = skins[1] {
            XCTAssertEqual(winner.id, 1, "P1 should win hole 1")
            XCTAssertEqual(carry, 1, "No carries — single skin")
        } else {
            XCTFail("Hole 1 should be .won")
        }
    }

    func testTiedHole_carriesOff_squashed() {
        let config = makeConfig(carries: false)
        // All holes: everyone shoots 4 (all tied)
        var scores: [Int: [Int: Int]] = [:]
        for p in 1...4 {
            for h in 1...18 {
                scores[p, default: [:]][h] = 4
            }
        }

        let vm = makeVM(config: config, scores: scores)
        let skins = vm.cachedSkins

        // All holes should be squashed
        for h in 1...18 {
            if case .squashed = skins[h] {
                // Correct
            } else {
                XCTFail("Hole \(h) should be .squashed when carries are off and all tied")
            }
        }
    }

    func testTiedHole_carriesOn_carriesForward() {
        let config = makeConfig(carries: true)
        // Hole 1: tied (all 4s). Hole 2: P1 wins with 3.
        var scores: [Int: [Int: Int]] = [:]
        for p in 1...4 {
            scores[p] = [1: 4, 2: p == 1 ? 3 : 4]
            for h in 3...18 { scores[p]![h] = 4 } // rest tied
        }

        let vm = makeVM(config: config, scores: scores)
        let skins = vm.cachedSkins

        // Hole 1 should be .carried
        if case .carried = skins[1] {
            // Correct
        } else {
            XCTFail("Hole 1 should be .carried")
        }

        // Hole 2: P1 wins with carry from hole 1 = 2 total skins
        if case .won(let winner, _, _, let carry) = skins[2] {
            XCTAssertEqual(winner.id, 1)
            XCTAssertEqual(carry, 2, "Should pick up carry from hole 1")
        } else {
            XCTFail("Hole 2 should be .won")
        }
    }

    // MARK: - Pot & Money

    func testPot_usesAllPlayers() {
        let config = makeConfig(playerCount: 4, buyIn: 50)
        let vm = RoundViewModel(config: config, currentUserId: 1)
        XCTAssertEqual(vm.pot, 200, "Pot should be 4 × $50 = $200")
    }

    func testSkinValue_excludesCarriedFromDenominator() {
        let config = makeConfig(playerCount: 4, buyIn: 50, carries: true)
        // Hole 1: tied → carried. Hole 2: P1 wins (picks up carry). Rest: tied.
        var scores: [Int: [Int: Int]] = [:]
        for p in 1...4 {
            scores[p] = [1: 4, 2: p == 1 ? 3 : 4]
            for h in 3...18 { scores[p]![h] = 4 }
        }

        let vm = makeVM(config: config, scores: scores)

        // Only 2 skins awarded (1 base + 1 carry, on hole 2). 16 holes squashed (tied, no winner).
        // .carried hole 1 should NOT be in denominator.
        // Denominator = skinsWon (2) + stillOpen (0) = 2
        // skinValue = 200 / 2 = 100
        XCTAssertEqual(vm.skinValue, 100.0, "Skin value should be pot/skinsWon when no open holes")
    }

    func testMoneyTotals_respectsGrossMode() {
        var config = makeConfig(playerCount: 4, buyIn: 50)
        config.winningsDisplay = "gross"
        // P1 wins hole 1, rest tied
        var scores: [Int: [Int: Int]] = [:]
        for p in 1...4 {
            scores[p] = [:]
            for h in 1...18 {
                scores[p]![h] = (h == 1 && p == 1) ? 3 : 4
            }
        }

        let vm = makeVM(config: config, scores: scores)
        let totals = vm.moneyTotals()

        // P1 gross winnings: should be positive (skins × skinValue, no buyIn subtracted)
        let p1Winnings = totals[1] ?? 0
        XCTAssertGreaterThan(p1Winnings, 0, "Gross mode: winner should have positive winnings")

        // Non-winners: $0 in gross mode (0 skins × value = 0)
        let p2Winnings = totals[2] ?? 0
        XCTAssertEqual(p2Winnings, 0, "Gross mode: non-winner should have $0")
    }

    func testMoneyTotals_respectsNetMode() {
        var config = makeConfig(playerCount: 4, buyIn: 50)
        config.winningsDisplay = "net"
        // All tied — nobody wins
        var scores: [Int: [Int: Int]] = [:]
        for p in 1...4 {
            scores[p] = [:]
            for h in 1...18 { scores[p]![h] = 4 }
        }

        let vm = makeVM(config: config, scores: scores)
        let totals = vm.moneyTotals()

        // Net mode with 0 skins: everyone should be $0 (not -buyIn, since totalSkinsAwarded == 0)
        for p in 1...4 {
            XCTAssertEqual(totals[p] ?? 0, 0, "Net mode with no skins: should be $0")
        }
    }

    // MARK: - Pending / Provisional

    func testIncompleteHole_staysPending() {
        let config = makeConfig(playerCount: 4)
        // Only P1 and P2 scored hole 1
        let scores: [Int: [Int: Int]] = [
            1: [1: 3],
            2: [1: 4]
        ]

        let vm = makeVM(config: config, scores: scores)
        let skins = vm.cachedSkins

        if case .provisional(let leaders, _, _, let scored, let total) = skins[1] {
            XCTAssertEqual(leaders.first?.id, 1, "P1 should lead")
            XCTAssertEqual(scored, 2)
            XCTAssertEqual(total, 4)
        } else {
            XCTFail("Hole 1 should be .provisional when not all players scored")
        }
    }

    // MARK: - Handicap allowance percentage

    /// At 100% allowance, a high-index player gets full strokes and can
    /// turn a worse gross into a better net than a low-index player. At
    /// 70% allowance, the same matchup may flip — fewer pops, fewer net
    /// adjustments, harder to cover the gross gap.
    ///
    /// This is the regression test for the 1.0.7 hotfix where the
    /// allowance was silently reverting to 100% on every Game Options save.
    /// Verifies the SkinRules.handicapPercentage value actually flows into
    /// the per-hole stroke allocation.
    func testHandicapPercentage_70PercentReducesPops() {
        // Net mode, 2 players: P1 idx 0 (zero pops), P2 idx 18 (gets pops on every hole).
        // Hole 5 in `Hole.allHoles` has hcp=1 (hardest); hole 18 has hcp=18 (easiest).
        //
        // P2 with idx 18.0 on the test tee box (slope 134, rating 71.5, par 72):
        //   raw = 18 × 134/113 + (71.5 - 72) = 21.345 - 0.5 = 20.845
        //   100% → round(20.845) = 21 pops → 1 stroke on every hole + extra on hcp 1-3
        //   70%  → round(20.845 × 0.7) = 15 pops → 1 stroke on hcp 1-15, 0 strokes on hcp 16-18
        let configFull = makeConfig(playerCount: 2, net: true, handicapPercentage: 1.0,
                                    playerIndices: [0.0, 18.0])
        let configReduced = makeConfig(playerCount: 2, net: true, handicapPercentage: 0.7,
                                       playerIndices: [0.0, 18.0])

        // Both shoot par on every hole (4 on par-4, 5 on par-5, 3 on par-3).
        // P2's net depends entirely on stroke allocation.
        var scores: [Int: [Int: Int]] = [:]
        for p in 1...2 {
            scores[p] = [:]
            for hole in Hole.allHoles { scores[p]![hole.num] = hole.par }
        }

        let vmFull = makeVM(config: configFull, scores: scores)
        let vmReduced = makeVM(config: configReduced, scores: scores)

        // Hole 5 (hcp 1, par 4) — both allowances give P2 a stroke, so P2 wins
        // outright. (At 100% P2 actually gets 2 strokes — bonus on hardest 3 holes
        // — but P1's net 4 is still beaten by P2's net 2.)
        if case .won(let w, _, _, _) = vmFull.cachedSkins[5] {
            XCTAssertEqual(w.id, 2, "Hole 5 at 100%: P2 wins via stroke(s)")
        } else {
            XCTFail("Hole 5 at 100% should be .won")
        }
        if case .won(let w, _, _, _) = vmReduced.cachedSkins[5] {
            XCTAssertEqual(w.id, 2, "Hole 5 at 70%: P2 still has 15 pops covering hcp 1")
        } else {
            XCTFail("Hole 5 at 70% should be .won")
        }

        // Hole 18 (hcp 18, par 5) — at 100% P2 has 21 pops → covers hcp 18 (1 stroke),
        // net 4 < P1's 5 → P2 wins. At 70% P2 has 15 pops → does NOT cover hcp 18,
        // net 5 = P1's 5 → tied → squashed (carries off).
        if case .won(let w, _, _, _) = vmFull.cachedSkins[18] {
            XCTAssertEqual(w.id, 2, "Hole 18 at 100%: P2 has stroke, wins")
        } else {
            XCTFail("Hole 18 at 100% should be .won")
        }
        if case .squashed = vmReduced.cachedSkins[18] {
            // Correct — P2 lost the stroke on the easiest hole at 70%.
        } else {
            XCTFail("Hole 18 at 70% should be .squashed (P2 lost stroke at hcp 18)")
        }
    }

    /// Plus-handicap players give strokes BACK on the easiest holes.
    /// Verifies the negative-pops branch of `TeeBox.strokesOnHole` flows through
    /// the skins calc — a plus player effectively plays the easiest holes at
    /// par+1 net (their gross is unchanged, but net is gross − (−1)).
    func testPlusHandicap_givesStrokesBackOnEasiestHoles() {
        // 2 players. Tee box has rating 71.5 < par 72, so a literal idx 0
        // produces raw -0.5 which rounds AWAY from zero to -1 (plus-1 player).
        // Use idx 0.5 to land at pH = 0 cleanly:
        //   raw = 0.5 × 134/113 + (71.5 - 72) = 0.593 - 0.5 = 0.093 → round 0
        //
        // P2 idx -3:
        //   raw = -3 × 134/113 + (71.5 - 72) = -3.558 - 0.5 = -4.058 → round -4
        // -4 pH means 4 give-backs on the easiest holes (hcp 15-18).
        // In Hole.allHoles those map to: hole 18 (hcp 18), hole 9 (hcp 17),
        // hole 15 (hcp 16), hole 6 (hcp 15).
        let config = makeConfig(playerCount: 2, net: true, handicapPercentage: 1.0,
                                playerIndices: [0.5, -3.0])

        // Both shoot par on every hole.
        var scores: [Int: [Int: Int]] = [:]
        for p in 1...2 {
            scores[p] = [:]
            for hole in Hole.allHoles { scores[p]![hole.num] = hole.par }
        }

        let vm = makeVM(config: config, scores: scores)

        // Hole 18 (hcp 18, par 5): P1 net 5, P2 net 5 − (−1) = 6 → P1 wins outright.
        // Without the plus-HC give-back this would tie + squash.
        if case .won(let w, _, _, _) = vm.cachedSkins[18] {
            XCTAssertEqual(w.id, 1, "Hole 18 (easiest): P2's plus-HC give-back hands the skin to P1")
        } else {
            XCTFail("Hole 18 should be .won by P1 — plus-HC penalty broke the tie")
        }

        // Hole 5 (hcp 1, par 4): give-back only reaches hcp 15-18, so neither
        // player gets a stroke or give-back here. Both net = 4 → tied → squashed.
        if case .squashed = vm.cachedSkins[5] {
            // Correct — plus-HC give-back doesn't reach the hardest holes
        } else {
            XCTFail("Hole 5 should be .squashed — plus-HC give-back doesn't apply on hardest holes")
        }
    }

    /// 0% allowance is gross-equivalent: every player effectively plays at 0 pops.
    /// Net winners under 0% should match what gross-low would produce.
    func testHandicapPercentage_zero_isGrossEquivalent() {
        let config = makeConfig(playerCount: 4, net: true, handicapPercentage: 0.0,
                                playerIndices: [0.0, 8.0, 16.0, 24.0])

        // Hole 1: P1 (low index) shoots 3, others 4. P1 should win even though
        // others would receive strokes at any allowance > 0%.
        var scores: [Int: [Int: Int]] = [:]
        for p in 1...4 { scores[p] = [:]; for h in 1...18 { scores[p]![h] = 4 } }
        scores[1]![1] = 3

        let vm = makeVM(config: config, scores: scores)
        if case .won(let w, _, _, _) = vm.cachedSkins[1] {
            XCTAssertEqual(w.id, 1, "0% allowance: lowest gross wins outright (no stroke conversions)")
        } else {
            XCTFail("Hole 1 should be .won at 0% allowance with a gross outright")
        }
    }

    // MARK: - allGroupsFinished

    func testAllGroupsFinished_requiresAllPlayers() {
        let config = makeConfig(playerCount: 4)
        // Only P1 scored all 18
        var scores: [Int: [Int: Int]] = [:]
        scores[1] = [:]
        for h in 1...18 { scores[1]![h] = 4 }

        let vm = makeVM(config: config, scores: scores)
        XCTAssertFalse(vm.allGroupsFinished, "Should not be finished when only 1 of 4 scored all 18")
    }

    func testAllGroupsFinished_trueWhenAllScored() {
        let config = makeConfig(playerCount: 4)
        var scores: [Int: [Int: Int]] = [:]
        for p in 1...4 {
            scores[p] = [:]
            for h in 1...18 { scores[p]![h] = 4 }
        }

        let vm = makeVM(config: config, scores: scores)
        XCTAssertTrue(vm.allGroupsFinished, "Should be finished when all 4 scored all 18")
    }
}
