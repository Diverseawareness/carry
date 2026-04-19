import XCTest
@testable import Carry

/// Tests for the per-group tee-times JSON round-trip on SkinsGroupDTO.
///
/// Context: `tee_times_json` on `skins_groups` stores an array of nullable
/// ISO8601 timestamps so independent (non-consecutive) tee times survive
/// across devices. Members rebuild their per-group tee times from this array
/// on refresh. These tests lock the decode contract — particularly the nil
/// passthrough and the two ISO8601 variants the formatter accepts.
final class TeeTimesPersistenceTests: XCTestCase {

    // MARK: - Helpers

    /// Minimal SkinsGroupDTO factory — only fills the one field under test.
    private func makeDTO(teeTimesJson: String?) -> SkinsGroupDTO {
        SkinsGroupDTO(
            id: UUID(),
            name: "Test Group",
            createdBy: nil,
            buyIn: 0,
            lastCourseName: nil,
            lastCourseClubName: nil,
            scheduledDate: nil,
            recurrence: nil,
            lastTeeBoxName: nil,
            lastTeeBoxColor: nil,
            lastTeeBoxCourseRating: nil,
            lastTeeBoxSlopeRating: nil,
            lastTeeBoxPar: nil,
            handicapPercentage: nil,
            scoringMode: nil,
            isQuickGame: nil,
            scorerIds: nil,
            teeTimeInterval: nil,
            teeTimesJson: teeTimesJson,
            lastTeeBoxHolesJson: nil,
            winningsDisplay: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }

    /// Matches the encoding done by `GroupService.saveTeeTimes`.
    private func encode(_ dates: [Date?]) throws -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let strings: [String?] = dates.map { $0.map { iso.string(from: $0) } }
        let data = try JSONEncoder().encode(strings)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - Decode

    func testDecodeTeeTimes_nilColumn_returnsNil() {
        let dto = makeDTO(teeTimesJson: nil)
        XCTAssertNil(dto.decodeTeeTimes(), "No persisted JSON → nil, callers fall back to interval math")
    }

    func testDecodeTeeTimes_invalidJSON_returnsNil() {
        let dto = makeDTO(teeTimesJson: "not-json-at-all")
        XCTAssertNil(dto.decodeTeeTimes(), "Corrupt JSON should not crash — returns nil and falls back")
    }

    func testDecodeTeeTimes_emptyArray_returnsEmpty() {
        let dto = makeDTO(teeTimesJson: "[]")
        let result = dto.decodeTeeTimes()
        XCTAssertEqual(result?.count, 0, "Empty array decodes to empty, not nil")
    }

    func testDecodeTeeTimes_roundTripWithAllTimes() throws {
        // Three consecutive groups, 8 min apart. Encode via the same helper
        // saveTeeTimes uses, decode via the DTO — must round-trip exactly.
        let base = Date(timeIntervalSince1970: 1_755_000_000) // arbitrary fixed instant
        let dates: [Date?] = [
            base,
            base.addingTimeInterval(8 * 60),
            base.addingTimeInterval(16 * 60)
        ]
        let json = try encode(dates)
        let dto = makeDTO(teeTimesJson: json)
        let decoded = dto.decodeTeeTimes()
        XCTAssertEqual(decoded?.count, 3)
        XCTAssertEqual(decoded?[0], dates[0])
        XCTAssertEqual(decoded?[1], dates[1])
        XCTAssertEqual(decoded?[2], dates[2])
    }

    func testDecodeTeeTimes_preservesNilEntries() throws {
        // A group can have a nil slot (no tee time picked yet). Nil must
        // survive both encode and decode — dropping it would misalign the
        // per-group array with groupCount.
        let date = Date(timeIntervalSince1970: 1_755_000_000)
        let dates: [Date?] = [date, nil, date.addingTimeInterval(30 * 60)]
        let json = try encode(dates)
        let decoded = makeDTO(teeTimesJson: json).decodeTeeTimes()
        XCTAssertEqual(decoded?.count, 3, "Nil entries must not be dropped")
        XCTAssertEqual(decoded?[0], dates[0])
        XCTAssertNil(decoded?[1], "Middle nil slot must decode back to nil")
        XCTAssertEqual(decoded?[2], dates[2])
    }

    func testDecodeTeeTimes_allNilEntries() throws {
        let dates: [Date?] = [nil, nil]
        let json = try encode(dates)
        let decoded = makeDTO(teeTimesJson: json).decodeTeeTimes()
        XCTAssertEqual(decoded?.count, 2)
        XCTAssertNil(decoded?[0])
        XCTAssertNil(decoded?[1])
    }

    func testDecodeTeeTimes_acceptsISO8601WithoutFractionalSeconds() {
        // Legacy/alternate encoder output — plain ISO8601 without
        // fractional seconds must still decode so older rows don't break.
        let json = #"["2026-04-18T09:00:00Z","2026-04-18T09:30:00Z"]"#
        let decoded = makeDTO(teeTimesJson: json).decodeTeeTimes()
        XCTAssertEqual(decoded?.count, 2)
        XCTAssertNotNil(decoded?[0])
        XCTAssertNotNil(decoded?[1])
        // Second entry should be exactly 30 minutes after the first.
        if let a = decoded?[0] ?? nil, let b = decoded?[1] ?? nil {
            XCTAssertEqual(b.timeIntervalSince(a), 30 * 60, accuracy: 0.001)
        } else {
            XCTFail("Both dates should decode from plain ISO8601")
        }
    }

    // MARK: - Independent tee times (the whole reason this column exists)

    func testDecodeTeeTimes_independentSchedulePreservesGaps() throws {
        // Group 1 at 9:00, Group 2 at 9:30 (30-min gap, not 8-min interval).
        // The old scheduledDate + teeTimeInterval scheme would lose this —
        // the whole point of tee_times_json is to preserve it exactly.
        let base = Date(timeIntervalSince1970: 1_755_000_000)
        let g1 = base
        let g2 = base.addingTimeInterval(30 * 60)
        let json = try encode([g1, g2])
        let decoded = makeDTO(teeTimesJson: json).decodeTeeTimes()
        guard let decoded, decoded.count == 2,
              let d1 = decoded[0], let d2 = decoded[1] else {
            XCTFail("Expected two non-nil entries"); return
        }
        XCTAssertEqual(d2.timeIntervalSince(d1), 30 * 60, accuracy: 0.001,
                       "30-min independent gap must survive the round trip")
    }
}
