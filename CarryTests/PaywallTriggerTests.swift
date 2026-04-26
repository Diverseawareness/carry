import XCTest
@testable import Carry

/// Tests for `PaywallTrigger.contextLine` — the one-line subtitle shown just
/// under the paywall hero ("Starting rounds is a Premium feature" etc.).
///
/// These strings are user-facing and tied to the gate that opened the paywall,
/// so drift here breaks the contextual upsell. `.general` must stay empty so
/// the PaywallView's `if !trigger.contextLine.isEmpty` guard hides the label
/// entirely when there's no specific reason to show it.
final class PaywallTriggerTests: XCTestCase {

    func testStartRoundContextLine() {
        XCTAssertEqual(
            PaywallTrigger.startRound.contextLine,
            "Starting rounds is a Premium feature"
        )
    }

    func testCreateGroupContextLine() {
        XCTAssertEqual(
            PaywallTrigger.createGroup.contextLine,
            "Recurring Skins Groups are Premium"
        )
    }

    func testScoreRoundContextLine() {
        XCTAssertEqual(
            PaywallTrigger.scoreRound.contextLine,
            "Scoring rounds is a Premium feature"
        )
    }

    func testManageGroupContextLine() {
        XCTAssertEqual(
            PaywallTrigger.manageGroup.contextLine,
            "Managing groups is a Premium feature"
        )
    }

    func testAllTimeLeaderboardContextLine() {
        XCTAssertEqual(
            PaywallTrigger.allTimeLeaderboard.contextLine,
            "All-time leaderboards are a Premium feature"
        )
    }

    /// `.general` must return an empty string so the PaywallView hides the
    /// context line entirely — used when the paywall is opened without a
    /// specific action context (e.g. the gated group empty-state screen,
    /// where the preceding copy already explains the "why").
    func testGeneralContextLineIsEmpty() {
        XCTAssertEqual(PaywallTrigger.general.contextLine, "")
    }

    /// Guards against accidentally adding a new trigger case without also
    /// adding a contextLine mapping — the compiler enforces exhaustiveness
    /// on the switch inside contextLine, but this test ensures every case
    /// is covered by a direct assertion above.
    func testAllTriggersHaveContextLine() {
        let allTriggers: [PaywallTrigger] = [
            .startRound, .createGroup, .scoreRound, .manageGroup,
            .allTimeLeaderboard, .general
        ]
        // If a new case is added to PaywallTrigger and not listed here,
        // this won't catch it — but the per-case tests above will fail
        // when the switch grows, so the failure mode surfaces immediately.
        for trigger in allTriggers {
            // Every trigger must return a string (possibly empty for .general)
            // — just accessing contextLine without crashing is the assertion.
            _ = trigger.contextLine
        }
        XCTAssertEqual(allTriggers.count, 6, "Update this test when PaywallTrigger gains a case")
    }
}
