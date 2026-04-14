import XCTest
@testable import Carry

/// Tests for the holes/pars data pipeline — validates that the strict
/// validation rules prevent wrong or missing hole data from ever reaching
/// the scorecard.
final class HolesPipelineTests: XCTestCase {

    // MARK: - Hole.fromAPI

    func testFromAPI_with18ValidHoles_succeeds() {
        let apiHoles = (1...18).map { GolfCourseHole(par: 4, yardage: 400, handicap: $0) }
        let result = Hole.fromAPI(apiHoles)
        XCTAssertEqual(result.count, 18)
        XCTAssertEqual(result[0].par, 4)
        XCTAssertEqual(result[0].num, 1)
        XCTAssertEqual(result[17].num, 18)
    }

    func testFromAPI_withFewerThan18_returnsEmpty() {
        let apiHoles = (1...9).map { GolfCourseHole(par: 4, yardage: 400, handicap: $0) }
        let result = Hole.fromAPI(apiHoles)
        XCTAssertTrue(result.isEmpty, "Should refuse to build with fewer than 18 holes")
    }

    func testFromAPI_withNilPar_returnsEmpty() {
        var apiHoles = (1...18).map { GolfCourseHole(par: 4, yardage: 400, handicap: $0) }
        apiHoles[5] = GolfCourseHole(par: nil, yardage: 400, handicap: 6)
        let result = Hole.fromAPI(apiHoles)
        XCTAssertTrue(result.isEmpty, "Should refuse to build when any hole has nil par")
    }

    func testFromAPI_withZeroPar_returnsEmpty() {
        var apiHoles = (1...18).map { GolfCourseHole(par: 4, yardage: 400, handicap: $0) }
        apiHoles[10] = GolfCourseHole(par: 0, yardage: 400, handicap: 11)
        let result = Hole.fromAPI(apiHoles)
        XCTAssertTrue(result.isEmpty, "Should refuse to build when any hole has par=0")
    }

    func testFromAPI_withMoreThan18_usesFirst18() {
        let apiHoles = (1...27).map { i in GolfCourseHole(par: 4, yardage: 400, handicap: (i - 1) % 18 + 1) }
        let result = Hole.fromAPI(apiHoles)
        XCTAssertEqual(result.count, 18, "Should use first 18 holes only")
    }

    func testFromAPI_missingHandicap_fallsBackToPosition() {
        let apiHoles = (1...18).map { _ in GolfCourseHole(par: 4, yardage: 400, handicap: nil) }
        let result = Hole.fromAPI(apiHoles)
        XCTAssertEqual(result.count, 18, "Should build even with nil handicaps")
        XCTAssertEqual(result[0].hcp, 1, "Missing handicap should use position (hole num)")
        XCTAssertEqual(result[17].hcp, 18)
    }

    // MARK: - Hole.allHoles (reference data)

    func testAllHoles_has18() {
        XCTAssertEqual(Hole.allHoles.count, 18)
    }

    func testAllHoles_numberedSequentially() {
        for (i, hole) in Hole.allHoles.enumerated() {
            XCTAssertEqual(hole.num, i + 1, "Hole \(i + 1) should have num = \(i + 1)")
        }
    }

    func testAllHoles_allParsPositive() {
        for hole in Hole.allHoles {
            XCTAssertGreaterThan(hole.par, 0, "Hole \(hole.num) should have positive par")
        }
    }

    // MARK: - TeeBox demo data (debug)

    func testDemoTeeBoxes_haveHoles() {
        for (i, teeBox) in TeeBox.demo.enumerated() {
            XCTAssertNotNil(teeBox.holes, "Demo tee box \(i) (\(teeBox.name)) should have holes")
            XCTAssertEqual(teeBox.holes?.count, 18, "Demo tee box \(i) should have 18 holes")
        }
    }
}
