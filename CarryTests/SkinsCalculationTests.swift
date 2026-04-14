import XCTest
@testable import Carry

/// Tests for the core skins calculation logic.
/// These verify that RoundViewModel.calculateSkins produces correct results
/// for all common golf skins scenarios.
final class SkinsCalculationTests: XCTestCase {

    // MARK: - Helpers

    /// Build a minimal RoundConfig for testing with N players on default holes.
    private func makeConfig(playerCount: Int = 4, buyIn: Int = 50, carries: Bool = false, net: Bool = false) -> RoundConfig {
        let players = (0..<playerCount).map { i in
            Player(
                id: i + 1,
                name: "P\(i + 1)",
                initials: "P\(i + 1)",
                color: "#333333",
                handicap: Double(i) * 2.0,
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
            skinRules: SkinRules(net: net, carries: carries, outright: true, handicapPercentage: 1.0),
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
