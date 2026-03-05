import Foundation

// MARK: - Profile

struct ProfileDTO: Codable, Identifiable {
    let id: UUID
    var displayName: String
    var initials: String
    var color: String
    var avatar: String
    var handicap: Double
    var ghinNumber: String?
    var email: String?
    let createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case initials
        case color
        case avatar
        case handicap
        case ghinNumber = "ghin_number"
        case email
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Course

struct CourseDTO: Codable, Identifiable {
    let id: UUID
    var name: String
    var clubName: String?
    let createdBy: UUID?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case clubName = "club_name"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

// MARK: - Hole

struct HoleDTO: Codable, Identifiable {
    let id: UUID
    let courseId: UUID
    let num: Int
    let par: Int
    let hcp: Int

    enum CodingKeys: String, CodingKey {
        case id
        case courseId = "course_id"
        case num, par, hcp
    }
}

// MARK: - Tee Box

struct TeeBoxDTO: Codable, Identifiable {
    let id: UUID
    let courseId: UUID
    var name: String
    var color: String
    var courseRating: Double
    var slopeRating: Int
    var par: Int

    enum CodingKeys: String, CodingKey {
        case id
        case courseId = "course_id"
        case name, color
        case courseRating = "course_rating"
        case slopeRating = "slope_rating"
        case par
    }
}

// MARK: - Round

struct RoundDTO: Codable, Identifiable {
    let id: UUID
    let courseId: UUID
    let createdBy: UUID
    var teeBoxId: UUID?
    var buyIn: Int
    var gameType: String
    var net: Bool
    var carries: Bool
    var outright: Bool
    var handicapPercentage: Double  // e.g. 0.7 for 70%, 1.0 for 100%
    var status: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case courseId = "course_id"
        case createdBy = "created_by"
        case teeBoxId = "tee_box_id"
        case buyIn = "buy_in"
        case gameType = "game_type"
        case net, carries, outright
        case handicapPercentage = "handicap_percentage"
        case status
        case createdAt = "created_at"
    }
}

// MARK: - Round Player

struct RoundPlayerDTO: Codable, Identifiable {
    let id: UUID
    let roundId: UUID
    let playerId: UUID
    var groupNum: Int

    enum CodingKeys: String, CodingKey {
        case id
        case roundId = "round_id"
        case playerId = "player_id"
        case groupNum = "group_num"
    }
}

// MARK: - Score

struct ScoreDTO: Codable, Identifiable {
    let id: UUID
    let roundId: UUID
    let playerId: UUID
    let holeNum: Int
    var score: Int
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case roundId = "round_id"
        case playerId = "player_id"
        case holeNum = "hole_num"
        case score
        case createdAt = "created_at"
    }
}

// MARK: - Insert DTOs (without server-generated fields)

struct ScoreInsert: Codable {
    let roundId: UUID
    let playerId: UUID
    let holeNum: Int
    let score: Int

    enum CodingKeys: String, CodingKey {
        case roundId = "round_id"
        case playerId = "player_id"
        case holeNum = "hole_num"
        case score
    }
}

struct RoundInsert: Codable {
    let courseId: UUID
    let createdBy: UUID
    let teeBoxId: UUID?
    let buyIn: Int
    let gameType: String
    let net: Bool
    let carries: Bool
    let outright: Bool
    let handicapPercentage: Double

    enum CodingKeys: String, CodingKey {
        case courseId = "course_id"
        case createdBy = "created_by"
        case teeBoxId = "tee_box_id"
        case buyIn = "buy_in"
        case gameType = "game_type"
        case net, carries, outright
        case handicapPercentage = "handicap_percentage"
    }
}

struct RoundPlayerInsert: Codable {
    let roundId: UUID
    let playerId: UUID
    let groupNum: Int

    enum CodingKeys: String, CodingKey {
        case roundId = "round_id"
        case playerId = "player_id"
        case groupNum = "group_num"
    }
}

struct CourseInsert: Codable {
    let name: String
    let clubName: String?
    let createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case name
        case clubName = "club_name"
        case createdBy = "created_by"
    }
}

struct HoleInsert: Codable {
    let courseId: UUID
    let num: Int
    let par: Int
    let hcp: Int

    enum CodingKeys: String, CodingKey {
        case courseId = "course_id"
        case num, par, hcp
    }
}

struct TeeBoxInsert: Codable {
    let courseId: UUID
    let name: String
    let color: String
    let courseRating: Double
    let slopeRating: Int
    let par: Int

    enum CodingKeys: String, CodingKey {
        case courseId = "course_id"
        case name, color
        case courseRating = "course_rating"
        case slopeRating = "slope_rating"
        case par
    }
}

struct ProfileUpdate: Codable {
    var displayName: String?
    var initials: String?
    var color: String?
    var avatar: String?
    var handicap: Double?
    var ghinNumber: String?
    var email: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case initials, color, avatar, handicap
        case ghinNumber = "ghin_number"
        case email
    }
}
