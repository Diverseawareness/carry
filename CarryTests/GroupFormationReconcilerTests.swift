import XCTest
@testable import Carry

/// Locks the group-formation single-source-of-truth invariant (locked 2026-05-10,
/// sufficiency-reviewed 2026-05-31): `groups[][]` is canonical, and every player's
/// `Player.group` MUST equal its array index + 1. The `.onChange(of: groups)`
/// reconciler in GroupManagerView enforces this after every mutation by calling
/// `GroupManagerView.normalizedGroupNums(_:)`.
///
/// This is the load-bearing rule that stopped the drift-bug class (edit-reverts,
/// drag-snap-back, stale Player.group). It had ZERO test coverage before this file.
/// If a future change breaks the invariant, the pre-push hook now catches it.
///
/// See docs/architecture/group-formation-canonical.md.
final class GroupFormationReconcilerTests: XCTestCase {

    private func player(_ id: Int, group: Int) -> Player {
        Player(id: id, name: "P\(id)", initials: "P\(id)",
               color: "#000000", handicap: 0, avatar: "", group: group,
               ghinNumber: nil, venmoUsername: nil)
    }

    /// The core invariant: after normalization, every player's `.group` equals
    /// its array index + 1, for any arrangement.
    private func assertInvariant(_ groups: [[Player]],
                                 file: StaticString = #filePath, line: UInt = #line) {
        for (gi, group) in groups.enumerated() {
            for p in group {
                XCTAssertEqual(p.group, gi + 1,
                    "player \(p.id) in group index \(gi) has .group=\(p.group), expected \(gi + 1)",
                    file: file, line: line)
            }
        }
    }

    // MARK: - No-op (already consistent)

    func testAlreadyConsistent_noChange() {
        let groups = [[player(1, group: 1), player(2, group: 1)],
                      [player(3, group: 2)]]
        let (result, changed) = GroupManagerView.normalizedGroupNums(groups)
        XCTAssertFalse(changed, "consistent arrangement should report no change")
        assertInvariant(result)
    }

    // MARK: - Drag-and-drop (player moved to a group whose index ≠ their .group)

    func testDrop_movedPlayerKeepsStaleGroup_getsCorrected() {
        // Player 3 dragged from group 2 into group 1, but the drop handler left
        // their .group == 2 (the bug the reconciler fixes).
        var moved = player(3, group: 2)        // stale: still says group 2
        let groups = [[player(1, group: 1), moved],   // ...but now sits in index 0
                      [player(2, group: 2)]]
        let (result, changed) = GroupManagerView.normalizedGroupNums(groups)
        XCTAssertTrue(changed, "stale .group must be detected as needing rewrite")
        XCTAssertEqual(result[0][1].group, 1, "moved player must adopt index 0 → group 1")
        assertInvariant(result)
        _ = moved // silence unused-write warning
    }

    // MARK: - Regroup collapse (empty group removed, indices shift)

    func testCollapse_indicesShiftDown_allCorrected() {
        // Group 1 emptied out; what was group 3 is now at index 1. Every player's
        // .group is now stale relative to its new index.
        let groups = [[player(10, group: 3), player(11, group: 3)],  // was group 3, now index 0
                      [player(20, group: 5)]]                        // was group 5, now index 1
        let (result, changed) = GroupManagerView.normalizedGroupNums(groups)
        XCTAssertTrue(changed)
        assertInvariant(result)
    }

    // MARK: - Swap (two players exchange groups, .group not updated)

    func testSwap_bothPlayersCorrected() {
        // P1 and P2 swapped groups but kept their old .group values.
        let groups = [[player(1, group: 2)],   // P1 now in index 0, stale group 2
                      [player(2, group: 1)]]    // P2 now in index 1, stale group 1
        let (result, changed) = GroupManagerView.normalizedGroupNums(groups)
        XCTAssertTrue(changed)
        XCTAssertEqual(result[0][0].group, 1)
        XCTAssertEqual(result[1][0].group, 2)
        assertInvariant(result)
    }

    // MARK: - Refresh rebuild (many groups rebuilt from server, mixed staleness)

    func testManyGroups_mixedStaleness_allNormalized() {
        let groups = [
            [player(1, group: 1), player(2, group: 99)],  // one correct, one stale
            [player(3, group: 1)],                         // stale (should be 2)
            [player(4, group: 3), player(5, group: 3)],    // both correct
            [player(6, group: 2)],                         // stale (should be 4)
        ]
        let (result, changed) = GroupManagerView.normalizedGroupNums(groups)
        XCTAssertTrue(changed)
        assertInvariant(result)
    }

    // MARK: - Idempotence (running it twice changes nothing the second time)

    func testIdempotent_secondPassReportsNoChange() {
        let messy = [[player(1, group: 7)], [player(2, group: 1)]]
        let (once, firstChanged) = GroupManagerView.normalizedGroupNums(messy)
        XCTAssertTrue(firstChanged)
        let (_, secondChanged) = GroupManagerView.normalizedGroupNums(once)
        XCTAssertFalse(secondChanged, "normalizing an already-normalized arrangement must be a no-op")
    }

    // MARK: - Edge cases

    func testEmptyArrangement_noChange() {
        let (result, changed) = GroupManagerView.normalizedGroupNums([])
        XCTAssertFalse(changed)
        XCTAssertTrue(result.isEmpty)
    }

    func testEmptyGroupsPreserved_noCrash() {
        // An empty inner group has no players to correct; indices of populated
        // groups still resolve. (The handler trims empties elsewhere; the
        // reconciler itself must not crash on them.)
        let groups: [[Player]] = [[], [player(1, group: 5)], []]
        let (result, changed) = GroupManagerView.normalizedGroupNums(groups)
        XCTAssertTrue(changed)
        XCTAssertEqual(result[1][0].group, 2, "player in index 1 → group 2")
    }
}
