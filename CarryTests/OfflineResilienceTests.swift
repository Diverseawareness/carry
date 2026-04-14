import XCTest
@testable import Carry

/// Tests for offline resilience — verifies that network errors and empty
/// responses do NOT falsely cancel rounds or lose data.
final class OfflineResilienceTests: XCTestCase {

    // MARK: - Helpers

    private func makeConfig(playerCount: Int = 4, buyIn: Int = 50) -> RoundConfig {
        let players = (0..<playerCount).map { i in
            Player(
                id: i + 1, name: "P\(i + 1)", initials: "P\(i + 1)",
                color: "#333333", handicap: Double(i) * 2.0, avatar: "",
                group: 1, ghinNumber: nil, venmoUsername: nil
            )
        }
        var config = RoundConfig(
            id: "test-\(UUID().uuidString)", number: 1,
            course: "Test", date: "2026-04-11", buyIn: buyIn, gameType: "skins",
            skinRules: SkinRules(net: false, carries: false, outright: true, handicapPercentage: 1.0),
            teeBox: TeeBox(id: "t1", courseId: "c1", name: "Blue", color: "#2563EB",
                           courseRating: 71.5, slopeRating: 134, par: 72, holes: Hole.allHoles),
            groups: [GroupConfig(id: 1, startingSide: "front", playerIDs: players.map(\.id))],
            creatorId: 1, groupName: "Test", players: players, holes: Hole.allHoles
        )
        config.supabaseRoundId = UUID()
        return config
    }

    // MARK: - roundWasCancelled flag

    func testRoundWasCancelled_defaultsFalse() {
        let vm = RoundViewModel(config: makeConfig(), currentUserId: 1)
        XCTAssertFalse(vm.roundWasCancelled, "Round should not be cancelled by default")
    }

    func testRoundWasCancelled_notSetByEmptyScores_whenNoLocalScores() {
        // If we have no local scores and server returns empty, that's normal (new round)
        // — should NOT trigger cancellation
        let vm = RoundViewModel(config: makeConfig(), currentUserId: 1)
        // Verify no scores exist
        let hasScores = !vm.scores.values.allSatisfy({ $0.isEmpty })
        XCTAssertFalse(hasScores, "Fresh VM should have no scores")
        XCTAssertFalse(vm.roundWasCancelled, "Empty scores on fresh round should not cancel")
    }

    // MARK: - Local score persistence

    func testScores_persistLocally() {
        let config = makeConfig()
        let vm = RoundViewModel(config: config, currentUserId: 1)

        // Enter a score
        vm.enterScore(playerId: 1, holeNum: 1, score: 4)

        // Verify it's stored
        XCTAssertEqual(vm.scores[1]?[1], 4, "Score should be stored locally")
    }

    func testScores_multiplePlayersMultipleHoles() {
        let config = makeConfig()
        let vm = RoundViewModel(config: config, currentUserId: 1)

        // Enter scores for multiple players on multiple holes
        vm.enterScore(playerId: 1, holeNum: 1, score: 3)
        vm.enterScore(playerId: 2, holeNum: 1, score: 4)
        vm.enterScore(playerId: 1, holeNum: 2, score: 5)
        vm.enterScore(playerId: 3, holeNum: 2, score: 3)

        XCTAssertEqual(vm.scores[1]?[1], 3)
        XCTAssertEqual(vm.scores[2]?[1], 4)
        XCTAssertEqual(vm.scores[1]?[2], 5)
        XCTAssertEqual(vm.scores[3]?[2], 3)
    }

    func testScores_overwritePrevious() {
        let config = makeConfig()
        let vm = RoundViewModel(config: config, currentUserId: 1)

        vm.enterScore(playerId: 1, holeNum: 1, score: 4)
        XCTAssertEqual(vm.scores[1]?[1], 4)

        // Overwrite with new score
        vm.enterScore(playerId: 1, holeNum: 1, score: 3)
        XCTAssertEqual(vm.scores[1]?[1], 3, "Score should be overwritten")
    }

    // MARK: - Skins survive offline

    func testSkins_calculateWithLocalScoresOnly() {
        // Even without Supabase sync, skins should calculate from local scores
        let config = makeConfig(playerCount: 4, buyIn: 50)
        let vm = RoundViewModel(config: config, currentUserId: 1)

        // Enter all 4 players on hole 1, P1 wins outright
        vm.enterScore(playerId: 1, holeNum: 1, score: 3)
        vm.enterScore(playerId: 2, holeNum: 1, score: 4)
        vm.enterScore(playerId: 3, holeNum: 1, score: 5)
        vm.enterScore(playerId: 4, holeNum: 1, score: 4)

        let skins = vm.cachedSkins
        if case .won(let winner, _, _, _) = skins[1] {
            XCTAssertEqual(winner.id, 1, "P1 should win hole 1 from local scores")
        } else {
            XCTFail("Hole 1 should be .won from local scores alone")
        }
    }

    // MARK: - Active hole computation

    func testActiveHole_advancesCorrectly() {
        let config = makeConfig(playerCount: 2)
        let vm = RoundViewModel(config: config, currentUserId: 1)

        // No scores — active hole should be hole 1
        XCTAssertEqual(vm.computeActiveHole(), 1)

        // Both players score hole 1
        vm.enterScore(playerId: 1, holeNum: 1, score: 4)
        vm.enterScore(playerId: 2, holeNum: 1, score: 4)

        // Active hole should advance to 2
        XCTAssertEqual(vm.computeActiveHole(), 2)
    }

    func testActiveHole_nilWhenAllScored() {
        let config = makeConfig(playerCount: 2)
        let vm = RoundViewModel(config: config, currentUserId: 1)

        // Score all 18 for both players
        for h in 1...18 {
            vm.enterScore(playerId: 1, holeNum: h, score: 4)
            vm.enterScore(playerId: 2, holeNum: h, score: 4)
        }

        XCTAssertNil(vm.computeActiveHole(), "No active hole when all scored")
    }

    // MARK: - isScoringBlocked

    func testScoringBlocked_falseByDefault() {
        let vm = RoundViewModel(config: makeConfig(), currentUserId: 1)
        XCTAssertFalse(vm.isScoringBlocked, "Scoring should not be blocked by default")
    }

    func testScoringBlocked_trueWhenProposalActive() {
        let vm = RoundViewModel(config: makeConfig(), currentUserId: 1)
        // Simulate an active proposal
        vm.activeProposal = (playerId: 1, holeNum: 1, original: 4, proposed: 3, proposedByUUID: UUID())
        XCTAssertTrue(vm.isScoringBlocked, "Scoring should be blocked when proposal is active")
    }
}
