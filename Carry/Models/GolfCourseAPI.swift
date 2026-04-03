import Foundation

// MARK: - Failable decode helper

/// Wraps any Decodable so a single bad element doesn't crash the whole array.
private struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        self.value = try? T(from: decoder)
    }
}

// MARK: - String helper

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Golf Course API Response Models
// Maps to https://api.golfcourseapi.com OpenAPI spec

/// Top-level search response: { "courses": [...] }
struct GolfCourseSearchResponse: Codable {
    let courses: [GolfCourseResult]

    private enum CodingKeys: String, CodingKey { case courses }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Per-element failable decode: one bad course won't kill the whole response
        let failables = (try? container.decode([FailableDecodable<GolfCourseResult>].self, forKey: .courses)) ?? []
        self.courses = failables.compactMap(\.value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(courses, forKey: .courses)
    }
}

/// A course returned by search or detail endpoints
struct GolfCourseResult: Codable, Identifiable {
    let id: Int
    let clubName: String?
    let courseName: String?
    let location: GolfCourseLocation?
    let tees: GolfCourseTees?

    enum CodingKeys: String, CodingKey {
        case id
        case clubName  = "club_name"
        case courseName = "course_name"
        case location
        case tees
    }

    /// Fully defensive custom decode — no single missing/null field throws.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id is required by the spec but guard against null / missing gracefully
        self.id          = (try? c.decode(Int.self, forKey: .id)) ?? 0
        self.clubName    = try? c.decodeIfPresent(String.self, forKey: .clubName)
        self.courseName  = try? c.decodeIfPresent(String.self, forKey: .courseName)
        self.location    = try? c.decodeIfPresent(GolfCourseLocation.self, forKey: .location)
        self.tees        = try? c.decodeIfPresent(GolfCourseTees.self, forKey: .tees)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(clubName,   forKey: .clubName)
        try c.encodeIfPresent(courseName, forKey: .courseName)
        try c.encodeIfPresent(location,   forKey: .location)
        try c.encodeIfPresent(tees,       forKey: .tees)
    }

    /// Display name: prefer courseName, fall back to clubName, then id
    var displayName: String {
        let cn   = courseName?.nilIfEmpty
        let club = clubName?.nilIfEmpty
        if let cn = cn, let club = club {
            return cn == club ? club : cn
        }
        return cn ?? club ?? "Course #\(id)"
    }

    /// Short location string: "City, ST"
    var locationLabel: String {
        guard let loc = location else { return "" }
        return [loc.city, loc.state].compactMap { $0?.nilIfEmpty }.joined(separator: ", ")
    }

    /// Placeholder used when all decode attempts fail
    static let empty = GolfCourseResult(id: 0, clubName: nil, courseName: nil, location: nil, tees: nil)

    init(id: Int, clubName: String?, courseName: String?, location: GolfCourseLocation?, tees: GolfCourseTees?) {
        self.id = id
        self.clubName = clubName
        self.courseName = courseName
        self.location = location
        self.tees = tees
    }
}

struct GolfCourseLocation: Codable {
    let address:   String?
    let city:      String?
    let state:     String?
    let country:   String?
    let latitude:  Double?
    let longitude: Double?
}

struct GolfCourseTees: Codable {
    let male:   [GolfCourseTeeBox]?
    let female: [GolfCourseTeeBox]?

    /// All tees combined, male first
    var all: [GolfCourseTeeBox] {
        (male ?? []) + (female ?? [])
    }
}

struct GolfCourseTeeBox: Codable, Identifiable {
    let teeName:          String?   // nullable in practice even though spec says string
    let courseRating:     Double?
    let slopeRating:      Int?
    let bogeyRating:      Double?
    let totalYards:       Int?
    let totalMeters:      Int?
    let numberOfHoles:    Int?
    let parTotal:         Int?
    let frontCourseRating: Double?
    let frontSlopeRating:  Int?
    let frontBogeyRating:  Double?
    let backCourseRating:  Double?
    let backSlopeRating:   Int?
    let backBogeyRating:   Double?
    let holes:            [GolfCourseHole]?

    /// Stable ID from tee name (fallback to rating string so ForEach is stable)
    var id: String { teeName ?? "\(courseRating ?? 0)-\(slopeRating ?? 0)" }

    enum CodingKeys: String, CodingKey {
        case teeName          = "tee_name"
        case courseRating     = "course_rating"
        case slopeRating      = "slope_rating"
        case bogeyRating      = "bogey_rating"
        case totalYards       = "total_yards"
        case totalMeters      = "total_meters"
        case numberOfHoles    = "number_of_holes"
        case parTotal         = "par_total"
        case frontCourseRating = "front_course_rating"
        case frontSlopeRating  = "front_slope_rating"
        case frontBogeyRating  = "front_bogey_rating"
        case backCourseRating  = "back_course_rating"
        case backSlopeRating   = "back_slope_rating"
        case backBogeyRating   = "back_bogey_rating"
        case holes
    }

    /// Hex color guess from tee name for UI display
    var colorHex: String {
        let n = (teeName ?? "").lowercased()
        if n.contains("black")  { return "#1A1A1A" }
        if n.contains("blue")   { return "#2563EB" }
        if n.contains("white")  { return "#E0E0E0" }
        if n.contains("gold")   { return "#D4A017" }
        if n.contains("red")    { return "#E05555" }
        if n.contains("green")  { return "#22C55E" }
        if n.contains("silver") { return "#A0A0A0" }
        if n.contains("copper") { return "#B87333" }
        if n.contains("combo")  { return "#8B5CF6" }
        return "#6E6E73"
    }

    /// Formatted yardage string
    var yardsLabel: String {
        guard let y = totalYards else { return "—" }
        return "\(y) yds"
    }

    /// Formatted rating string
    var ratingLabel: String {
        guard let cr = courseRating, let sr = slopeRating else { return "—" }
        return String(format: "%.1f / %d", cr, sr)
    }
}

struct GolfCourseHole: Codable {
    let par:      Int?
    let yardage:  Int?
    let handicap: Int?
}

// MARK: - Recently Played Course (local cache)

struct RecentCourse: Codable, Identifiable {
    let courseId:      Int
    let courseName:    String
    let clubName:      String
    let city:          String
    let state:         String
    let lastTeeName:   String
    let lastPlayedDate: Date

    var id: Int { courseId }

    var locationLabel: String {
        [city, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var displayName: String {
        if courseName == clubName || courseName.isEmpty {
            return clubName
        }
        // Combine club + course when they differ (e.g. "Torrey Pines - South")
        let shortClub = clubName
            .replacingOccurrences(of: " Municipal Golf Course", with: "")
            .replacingOccurrences(of: " Golf Course", with: "")
            .replacingOccurrences(of: " Golf Club", with: "")
            .replacingOccurrences(of: " Country Club", with: "")
            .replacingOccurrences(of: " CC", with: "")
        return "\(shortClub) - \(courseName)"
    }

    /// Demo recent courses (real API IDs)
    static let demo: [RecentCourse] = [
        RecentCourse(
            courseId: 20516,
            courseName: "South",
            clubName: "Torrey Pines Municipal Golf Course",
            city: "La Jolla",
            state: "CA",
            lastTeeName: "Blue",
            lastPlayedDate: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        ),
        RecentCourse(
            courseId: 20748,
            courseName: "18 Hole Course",
            clubName: "Balboa Park Golf Club",
            city: "San Diego",
            state: "CA",
            lastTeeName: "White",
            lastPlayedDate: Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        ),
    ]
}
