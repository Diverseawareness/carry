import XCTest
@testable import Carry

/// Locks the scorer-assignment rules (scorer-rules.md §"syncScorerIDs rules"),
/// extracted into the pure `GroupManagerView.resolvedScorerIDs(...)`. These are
/// load-bearing: scorer eligibility gates who can write scores, and the
/// creator-lock invariant (rule 6) had ZERO test coverage despite a documented
/// history of `currentUserId` vs `creatorId` regressions breaking it.
///
/// Rules under test:
///   1. expand to group count   2. trim to group count
///   3. wipe scorer who left the group   4. wipe permanent guests
///   5. SG-only: advance past pending   6. creator-lock (overrides 3–5)
///
/// See docs/architecture/scorer-rules.md.
final class ScorerRulesTests: XCTestCase {

    // Carry user: profileId set, not guest, not pending → canScore == true.
    private func carry(_ id: Int, profileId: UUID = UUID()) -> Player {
        Player(id: id, name: "C\(id)", initials: "C\(id)", color: "#000000",
               handicap: 0, avatar: "", group: 1, ghinNumber: nil,
               isGuest: false, profileId: profileId)
    }

    // Permanent guest: no profileId, isGuest, not pending → cannot score.
    private func guest(_ id: Int) -> Player {
        Player(id: id, name: "G\(id)", initials: "G\(id)", color: "#000000",
               handicap: 0, avatar: "", group: 1, ghinNumber: nil,
               isGuest: true, profileId: nil)
    }

    // Pending SMS invitee: no profileId yet, isPendingInvite.
    private func pendingInvite(_ id: Int) -> Player {
        Player(id: id, name: "P\(id)", initials: "P\(id)", color: "#000000",
               handicap: 0, avatar: "", group: 1, ghinNumber: nil,
               isPendingInvite: true, isGuest: false, profileId: nil)
    }

    private func resolve(_ groups: [[Player]], current: [Int],
                         isQuickGame: Bool, creatorId: Int) -> [Int] {
        GroupManagerView.resolvedScorerIDs(groups: groups, current: current,
                                           isQuickGame: isQuickGame, creatorId: creatorId)
    }

    // MARK: - Rule 1: expand

    func testExpand_newGroupDefaultsToFirstCarryUser() {
        let groups = [[carry(1)], [carry(2), guest(3)]]
        // current only has one entry → must expand to 2, group 2 defaults to its canScore player.
        let result = resolve(groups, current: [1], isQuickGame: true, creatorId: 999)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[1], 2, "new group should default to its first canScore player")
    }

    func testExpand_groupWithNoCarryUserDefaultsToZero() {
        let groups = [[carry(1)], [guest(2), guest(3)]]
        let result = resolve(groups, current: [1], isQuickGame: true, creatorId: 999)
        XCTAssertEqual(result[1], 0, "group with no scorer-eligible player defaults to 0 (banner prompts)")
    }

    // MARK: - Rule 2: trim

    func testTrim_extraEntriesRemovedWhenGroupsShrink() {
        let groups = [[carry(1)]]
        let result = resolve(groups, current: [1, 2, 3], isQuickGame: true, creatorId: 999)
        XCTAssertEqual(result, [1], "scorerIDs must trim to match group count")
    }

    // MARK: - Rule 3: wipe scorer who left the group

    func testWipe_scorerNoLongerInGroup() {
        let groups = [[carry(1)]]            // scorer 7 isn't here anymore
        let result = resolve(groups, current: [7], isQuickGame: true, creatorId: 999)
        XCTAssertEqual(result[0], 0, "scorer not in the group is wiped to 0")
    }

    func testZeroIsRespected_notAutoFilled() {
        let groups = [[carry(1), carry(2)]]  // explicitly empty (0) → must stay empty
        let result = resolve(groups, current: [0], isQuickGame: true, creatorId: 999)
        XCTAssertEqual(result[0], 0, "an intentional 0 must not be auto-filled")
    }

    // MARK: - Rule 4: wipe permanent guests

    func testWipe_permanentGuestScorer() {
        let groups = [[guest(5), carry(6)]]  // guest wrongly assigned as scorer
        let result = resolve(groups, current: [5], isQuickGame: true, creatorId: 999)
        XCTAssertEqual(result[0], 0, "a permanent guest can't score — wiped to 0")
    }

    // MARK: - Rule 5: SG advances past pending; QG preserves pending

    func testSkinsGroup_advancesPastPendingScorer() {
        let groups = [[pendingInvite(8), carry(9)]]
        let result = resolve(groups, current: [8], isQuickGame: false, creatorId: 999)
        XCTAssertEqual(result[0], 9, "Skins Group advances past a pending scorer to the next Carry user")
    }

    func testQuickGame_preservesPendingScorer() {
        let groups = [[pendingInvite(8), carry(9)]]
        let result = resolve(groups, current: [8], isQuickGame: true, creatorId: 999)
        XCTAssertEqual(result[0], 8, "Quick Game keeps a pending scorer — the assignment IS the playing-today signal")
    }

    // MARK: - Rule 6: creator-lock (the load-bearing invariant)

    func testCreatorLock_groupWithCreatorAlwaysScoredByCreator() {
        let creatorId = 42
        let groups = [[carry(1), carry(creatorId)]]
        // current assigns someone else; creator-lock must override.
        let result = resolve(groups, current: [1], isQuickGame: true, creatorId: creatorId)
        XCTAssertEqual(result[0], creatorId, "any group containing the creator must be scored by the creator")
    }

    func testCreatorLock_overridesEarlierWipe() {
        // The creator is also "not the assigned scorer + a wipe would fire" — but rule 6
        // runs LAST and must restore the creator regardless of what rules 3–5 did.
        let creatorId = 42
        let groups = [[carry(creatorId), guest(7)]]
        // Assign the guest (rule 4 would wipe to 0), but creator is in the group → ends as creatorId.
        let result = resolve(groups, current: [7], isQuickGame: true, creatorId: creatorId)
        XCTAssertEqual(result[0], creatorId, "creator-lock applies last, overriding the guest-wipe")
    }

    func testCreatorLock_onlyLocksGroupsContainingCreator() {
        let creatorId = 42
        let groups = [[carry(creatorId)], [carry(1), carry(2)]]
        let result = resolve(groups, current: [0, 2], isQuickGame: true, creatorId: creatorId)
        XCTAssertEqual(result[0], creatorId, "creator's group locked to creator")
        XCTAssertEqual(result[1], 2, "other group's scorer is untouched by creator-lock")
    }

    // MARK: - Idempotence

    func testIdempotent_resolvingTwiceIsStable() {
        let creatorId = 42
        let groups = [[carry(creatorId), guest(7)], [pendingInvite(8), carry(9)]]
        let once = resolve(groups, current: [], isQuickGame: false, creatorId: creatorId)
        let twice = resolve(groups, current: once, isQuickGame: false, creatorId: creatorId)
        XCTAssertEqual(once, twice, "re-resolving an already-resolved arrangement must be stable")
    }
}
