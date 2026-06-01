import XCTest
@testable import Carry

/// Guards the shared `moneyText(_:)` formatter (Player.swift) that replaced ~8
/// copy-pasted duplicates across the results/leaderboard/scorecard views.
/// Canonical signed format: positive → "$X", negative → "-$X", zero → "$0".
final class MoneyTextTests: XCTestCase {

    func testPositive() {
        XCTAssertEqual(moneyText(25), "$25")
        XCTAssertEqual(moneyText(1), "$1")
        XCTAssertEqual(moneyText(316), "$316")
    }

    func testNegative() {
        XCTAssertEqual(moneyText(-25), "-$25")
        XCTAssertEqual(moneyText(-1), "-$1")
    }

    func testZero() {
        XCTAssertEqual(moneyText(0), "$0")
    }
}
