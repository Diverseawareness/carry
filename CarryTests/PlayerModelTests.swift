import XCTest
@testable import Carry

/// Tests for Player model, handicap formatting, and related utilities.
final class PlayerModelTests: XCTestCase {

    // MARK: - Handicap Input Filtering

    func testFilterHandicapInput_normalValue() {
        let result = filterHandicapInput("12.4")
        XCTAssertEqual(result, "12.4")
    }

    func testFilterHandicapInput_plusHandicap() {
        let result = filterHandicapInput("+5.2")
        XCTAssertEqual(result, "+5.2")
    }

    func testFilterHandicapInput_maxLength() {
        let result = filterHandicapInput("54.01")
        XCTAssertTrue(result.count <= 4, "Normal HC should be max 4 chars")
    }

    func testFilterHandicapInput_plusMaxLength() {
        let result = filterHandicapInput("+10.01")
        XCTAssertTrue(result.count <= 5, "Plus HC should be max 5 chars")
    }

    // MARK: - Short Name

    func testShortName_firstAndLastInitial() {
        let player = Player(id: 1, name: "Daniel Sigvardsson", initials: "DS",
                           color: "#333", handicap: 5.6, avatar: "", group: 1,
                           ghinNumber: nil, venmoUsername: nil)
        XCTAssertEqual(player.shortName, "Daniel S.")
    }

    func testShortName_singleName() {
        let player = Player(id: 1, name: "Ziggy", initials: "ZI",
                           color: "#333", handicap: 5.6, avatar: "", group: 1,
                           ghinNumber: nil, venmoUsername: nil)
        XCTAssertEqual(player.shortName, "Ziggy")
    }

    // MARK: - Stable ID

    func testStableId_deterministic() {
        let uuid = UUID()
        let id1 = Player.stableId(from: uuid)
        let id2 = Player.stableId(from: uuid)
        XCTAssertEqual(id1, id2, "Same UUID should produce same stable ID")
    }

    func testStableId_differentUUIDs_differentIds() {
        let id1 = Player.stableId(from: UUID())
        let id2 = Player.stableId(from: UUID())
        XCTAssertNotEqual(id1, id2, "Different UUIDs should produce different stable IDs")
    }

    // MARK: - Player from ProfileDTO

    func testPlayerFromProfile_includesHomeClub() {
        let profile = ProfileDTO(
            id: UUID(), firstName: "Daniel", lastName: "Sigvardsson",
            username: "daniel", displayName: "Daniel", initials: "DS",
            color: "#D4A017", avatar: "🏌️", handicap: 5.6,
            homeClub: "Ruby Hill Gc", createdAt: nil, updatedAt: nil
        )
        let player = Player(from: profile)
        XCTAssertEqual(player.homeClub, "Ruby Hill Gc")
    }
}
