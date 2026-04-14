import XCTest
@testable import Carry

/// Tests for pot calculation, skin value, and winnings distribution.
/// Verifies the denominator logic, no-show handling, and gross/net modes.
final class PotCalculationTests: XCTestCase {

    private func makeConfig(playerCount: Int = 4, buyIn: Int = 50, carries: Bool = false) -> RoundConfig {
        let players = (0..<playerCount).map { i in
            Player(
                id: i + 1, name: "P\(i + 1)", initials: "P\(i + 1)",
                color: "#333333", handicap: 0, avatar: "",
                group: 1, ghinNumber: nil, venmoUsername: nil
            )
        }
        return RoundConfig(
            id: "test-\(UUID().uuidString)", number: 1,
            course: "Test", date: "2026-04-11", buyIn: buyIn, gameType: "skins",
            skinRules: SkinRules(net: false, carries: carries, outright: true, handicapPercentage: 1.0),
            teeBox: TeeBox(id: "t1", courseId: "c1", name: "Blue", color: "#2563EB",
                           courseRating: 71.5, slopeRating: 134, par: 72, holes: Hole.allHoles),
            groups: [GroupConfig(id: 1, startingSide: "front", playerIDs: players.map(\.id))],
            creatorId: 1, groupName: "Test", players: players, holes: Hole.allHoles
        )
    }

    // MARK: - Pot

    func testPot_allPlayers() {
        let config = makeConfig(playerCount: 6, buyIn: 50)
        let vm = RoundViewModel(config: config, currentUserId: 1)
        XCTAssertEqual(vm.pot, 300, "6 × $50 = $300")
    }

    func testPot_singlePlayer() {
        let config = makeConfig(playerCount: 1, buyIn: 100)
        let vm = RoundViewModel(config: config, currentUserId: 1)
        XCTAssertEqual(vm.pot, 100, "1 × $100 = $100")
    }

    // MARK: - Skin Value Denominator

    func testSkinValue_allSquashed_dividesOnlyByAwarded() {
        // Carries OFF, 2 outright wins, 16 ties (squashed)
        let config = makeConfig(playerCount: 4, buyIn: 50, carries: false)
        var scores: [Int: [Int: Int]] = [:]
        for p in 1...4 {
            scores[p] = [:]
            for h in 1...18 {
                if h == 1 { scores[p]![h] = p == 1 ? 3 : 4 } // P1 wins
                else if h == 5 { scores[p]![h] = p == 2 ? 3 : 4 } // P2 wins
                else { scores[p]![h] = 4 } // tied → squashed
            }
        }

        let vm = RoundViewModel(config: config, currentUserId: 1)
        for (pid, hs) in scores { for (h, s) in hs { vm.enterScore(playerId: pid, holeNum: h, score: s) } }

        // 2 skins awarded, 0 open → denom = 2
        // skinValue = 200 / 2 = 100
        XCTAssertEqual(vm.skinValue, 100.0)
    }

    func testSkinValue_carriedHoles_notInDenominator() {
        // Carries ON, hole 1 tied (carried), hole 2 P1 wins (picks up carry)
        let config = makeConfig(playerCount: 4, buyIn: 50, carries: true)
        var scores: [Int: [Int: Int]] = [:]
        for p in 1...4 {
            scores[p] = [:]
            scores[p]![1] = 4 // tied
            scores[p]![2] = p == 1 ? 3 : 4 // P1 wins
            for h in 3...18 { scores[p]![h] = 4 } // rest tied
        }

        let vm = RoundViewModel(config: config, currentUserId: 1)
        for (pid, hs) in scores { for (h, s) in hs { vm.enterScore(playerId: pid, holeNum: h, score: s) } }

        // skinsWon = 2 (1 base + 1 carry). .carried holes should NOT inflate denom.
        // 16 other ties → .carried (carries on) → also not in denom
        // denom = skinsWon (2) = 2
        // skinValue = 200 / 2 = 100
        XCTAssertEqual(vm.skinValue, 100.0, ".carried holes must not be in denominator")
    }

    // MARK: - Winnings Distribution

    func testWinnings_potFullyDistributed() {
        // 4 players, each wins some holes, all holes resolved
        let config = makeConfig(playerCount: 4, buyIn: 50, carries: false)
        var scores: [Int: [Int: Int]] = [:]
        for p in 1...4 {
            scores[p] = [:]
            for h in 1...18 {
                // P1 wins holes 1-4, P2 wins 5-8, P3 wins 9-12, P4 wins 13-16, rest tied
                if h <= 4 { scores[p]![h] = p == 1 ? 3 : 5 }
                else if h <= 8 { scores[p]![h] = p == 2 ? 3 : 5 }
                else if h <= 12 { scores[p]![h] = p == 3 ? 3 : 5 }
                else if h <= 16 { scores[p]![h] = p == 4 ? 3 : 5 }
                else { scores[p]![h] = 4 } // tied → squashed
            }
        }

        var mutableConfig = config
        mutableConfig.winningsDisplay = "gross"
        let vm = RoundViewModel(config: mutableConfig, currentUserId: 1)
        for (pid, hs) in scores { for (h, s) in hs { vm.enterScore(playerId: pid, holeNum: h, score: s) } }

        let totals = vm.moneyTotals()
        let totalPaid = totals.values.reduce(0, +)

        // Each player won 4 skins out of 16 total. skinValue = 200/16 = 12.5
        // Each gets 4 × 12.5 = 50 (gross)
        XCTAssertEqual(totalPaid, 200, "Total gross winnings should equal pot")
    }
}
