import XCTest
@testable import Carry

/// Tests for `SkinsGroupUpdate`'s custom encoder. The struct deliberately
/// omits unset fields from the payload (so partial updates don't null out
/// other columns) but has an explicit "clear" flag for fields that need to
/// support being set back to null. These tests lock that contract for the
/// new `teeTimesJson` / `clearTeeTimesJson` pair introduced with per-group
/// tee-time persistence.
final class SkinsGroupUpdateEncodingTests: XCTestCase {

    private func encode(_ update: SkinsGroupUpdate) throws -> [String: Any] {
        let data = try JSONEncoder().encode(update)
        let obj = try JSONSerialization.jsonObject(with: data)
        return obj as? [String: Any] ?? [:]
    }

    // MARK: - teeTimesJson

    func testEncode_teeTimesJson_whenSet_includesKey() throws {
        let update = SkinsGroupUpdate(teeTimesJson: #"["2026-04-18T09:00:00Z"]"#)
        let json = try encode(update)
        XCTAssertEqual(json["tee_times_json"] as? String,
                       #"["2026-04-18T09:00:00Z"]"#,
                       "teeTimesJson should serialize to snake_case tee_times_json")
    }

    func testEncode_teeTimesJson_whenUnset_omitsKey() throws {
        let update = SkinsGroupUpdate(name: "just a rename")
        let json = try encode(update)
        XCTAssertFalse(json.keys.contains("tee_times_json"),
                       "Unset teeTimesJson must be omitted — otherwise a name-only update would null out tee times")
    }

    func testEncode_teeTimesJson_whenClearFlagSet_sendsNull() throws {
        let update = SkinsGroupUpdate(teeTimesJson: nil, clearTeeTimesJson: true)
        let json = try encode(update)
        XCTAssertTrue(json.keys.contains("tee_times_json"),
                      "clearTeeTimesJson=true must include the key so Supabase writes NULL")
        XCTAssertTrue(json["tee_times_json"] is NSNull,
                      "clearTeeTimesJson=true must serialize as JSON null, not an empty string")
    }

    func testEncode_teeTimesJson_setTakesPrecedenceOverClearFlag() throws {
        // Defensive: if both are set, the value wins (clear flag only applies
        // when the optional is nil). This mirrors scheduledDate/clearScheduledDate.
        let update = SkinsGroupUpdate(
            teeTimesJson: #"[]"#,
            clearTeeTimesJson: true
        )
        let json = try encode(update)
        XCTAssertEqual(json["tee_times_json"] as? String, "[]",
                       "A provided value should beat the clear flag")
    }

    // MARK: - guestRosterJson (Quick Game between-round guest snapshot)

    func testEncode_guestRosterJson_whenSet_includesKey() throws {
        let payload = ##"[{"id":1,"name":"Guest","initials":"G","color":"#FF0000","handicap":12,"avatar":"😀","group":1,"profileId":null}]"##
        let update = SkinsGroupUpdate(guestRosterJson: payload)
        let json = try encode(update)
        XCTAssertEqual(json["guest_roster_json"] as? String, payload,
                       "guestRosterJson should serialize to snake_case guest_roster_json")
    }

    func testEncode_guestRosterJson_whenUnset_omitsKey() throws {
        let update = SkinsGroupUpdate(name: "just a rename")
        let json = try encode(update)
        XCTAssertFalse(json.keys.contains("guest_roster_json"),
                       "Unset guestRosterJson must be omitted — otherwise a name-only update would null out the guest roster")
    }

    func testEncode_guestRosterJson_whenClearFlagSet_sendsNull() throws {
        let update = SkinsGroupUpdate(guestRosterJson: nil, clearGuestRosterJson: true)
        let json = try encode(update)
        XCTAssertTrue(json.keys.contains("guest_roster_json"),
                      "clearGuestRosterJson=true must include the key so Supabase writes NULL")
        XCTAssertTrue(json["guest_roster_json"] is NSNull,
                      "clearGuestRosterJson=true must serialize as JSON null, not an empty string")
    }

    func testEncode_guestRosterJson_setTakesPrecedenceOverClearFlag() throws {
        let update = SkinsGroupUpdate(
            guestRosterJson: "[]",
            clearGuestRosterJson: true
        )
        let json = try encode(update)
        XCTAssertEqual(json["guest_roster_json"] as? String, "[]",
                       "A provided value should beat the clear flag")
    }

    // MARK: - Partial updates unaffected

    func testEncode_scorerIdsOnly_doesNotTouchTeeTimes() throws {
        // Regression: adding the new field must not change the partial-
        // update contract other call sites rely on.
        let update = SkinsGroupUpdate(scorerIds: [1, 2, 3])
        let json = try encode(update)
        XCTAssertNotNil(json["scorer_ids"])
        XCTAssertFalse(json.keys.contains("tee_times_json"))
        XCTAssertFalse(json.keys.contains("guest_roster_json"))
        XCTAssertFalse(json.keys.contains("scheduled_date"))
        XCTAssertFalse(json.keys.contains("name"))
    }
}
