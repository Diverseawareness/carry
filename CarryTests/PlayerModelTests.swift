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

    // MARK: - Cross-language verification with SQL player_stable_id
    //
    // These assertions MUST match the values asserted in
    // supabase/tests/db/player_stable_id_test.sql. The SMS-invite-as-scorer
    // reconciliation triggers (migration 20260513000003) depend on iOS and
    // Postgres producing identical ints for the same UUID — if this test
    // fails OR the SQL test produces different values, the entire fix
    // silently breaks. Update both files together; never one alone.
    //
    // Expected values were computed by hand from the bit-shift formula
    // in Player.stableId(from:). See migration 20260513000002 docs for
    // the derivation.

    func testStableId_allZeroUUID_returnsZero() {
        let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        XCTAssertEqual(Player.stableId(from: uuid), 0,
                       "All-zero UUID must produce 0; SQL test asserts the same")
    }

    func testStableId_knownUUID_matchesSQLExpectation() {
        // First 8 bytes: 01 02 03 04 05 06 07 08
        // a<<24 | b<<16 | c<<8 | d | e<<20 | f<<12 | g<<4 | h
        // = 0x0152637C = 22307708 decimal
        let uuid = UUID(uuidString: "01020304-0506-0708-0000-000000000000")!
        XCTAssertEqual(Player.stableId(from: uuid), 22307708,
                       "Must match SQL player_stable_id for the same UUID — see player_stable_id_test.sql test_id 2")
    }

    func testStableId_allFFFirst8Bytes_returnsMaxUInt32() {
        // First 8 bytes all 0xff → OR of all shifts → 0xFFFFFFFF = 4294967295
        let uuid = UUID(uuidString: "ffffffff-ffff-ffff-0000-000000000000")!
        XCTAssertEqual(Player.stableId(from: uuid), 4294967295,
                       "Must match SQL player_stable_id for the same UUID — see player_stable_id_test.sql test_id 3")
    }

    func testStableId_bytesBeyondIndex7_ignored() {
        // Two UUIDs that differ ONLY in bytes 8+ should produce the same int
        let a = UUID(uuidString: "01020304-0506-0708-aaaa-aaaaaaaaaaaa")!
        let b = UUID(uuidString: "01020304-0506-0708-bbbb-bbbbbbbbbbbb")!
        XCTAssertEqual(Player.stableId(from: a), Player.stableId(from: b),
                       "Bytes beyond index 7 must be ignored by stableId — invariant SQL relies on")
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
