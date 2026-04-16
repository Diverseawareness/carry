import Foundation

// MARK: - Profile

struct ProfileDTO: Codable, Identifiable, Equatable {
    let id: UUID
    var firstName: String
    var lastName: String
    var username: String?
    var displayName: String
    var initials: String
    var color: String
    var avatar: String
    var handicap: Double
    var ghinNumber: String?
    var homeClub: String?
    var homeClubId: Int?
    var avatarUrl: String?
    var email: String?
    var isClubMember: Bool?
    var isGuest: Bool?
    var createdBy: UUID?
    let createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case username
        case displayName = "display_name"
        case initials
        case color
        case avatar
        case handicap
        case ghinNumber = "ghin_number"
        case homeClub = "home_club"
        case homeClubId = "home_club_id"
        case avatarUrl = "avatar_url"
        case email
        case isClubMember = "is_club_member"
        case isGuest = "is_guest"
        case createdBy = "created_by"
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
    var holesJson: String?  // JSON array of per-hole data [{par,hcp},...] for 18 holes

    enum CodingKeys: String, CodingKey {
        case id
        case courseId = "course_id"
        case name, color
        case courseRating = "course_rating"
        case slopeRating = "slope_rating"
        case par
        case holesJson = "holes_json"
    }

    /// Decode holes from JSON string into [Hole] array
    func decodeHoles() -> [Hole]? {
        guard let json = holesJson, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([Hole].self, from: data)
    }
}

// MARK: - Round

struct RoundDTO: Codable, Identifiable {
    let id: UUID
    let courseId: UUID
    let createdBy: UUID
    var teeBoxId: UUID?
    var groupId: UUID?
    var scorerId: UUID?
    var buyIn: Int
    var gameType: String
    var net: Bool
    var carries: Bool
    var outright: Bool
    var handicapPercentage: Double  // e.g. 0.7 for 70%, 1.0 for 100%
    var status: String
    var scoringMode: String?
    /// True when the creator used End Game / End Game & Save Results. Combined with
    /// `status`, disambiguates natural completion from a forced end.
    /// Optional to tolerate rows written before the `force_completed` migration ran.
    var forceCompleted: Bool?
    let createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case courseId = "course_id"
        case createdBy = "created_by"
        case teeBoxId = "tee_box_id"
        case groupId = "group_id"
        case scorerId = "scorer_id"
        case buyIn = "buy_in"
        case gameType = "game_type"
        case net, carries, outright
        case handicapPercentage = "handicap_percentage"
        case status
        case scoringMode = "scoring_mode"
        case forceCompleted = "force_completed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Round Player

struct RoundPlayerDTO: Codable, Identifiable {
    let id: UUID
    let roundId: UUID
    let playerId: UUID
    var groupNum: Int
    var status: String  // "accepted", "invited", "declined"
    var invitedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case roundId = "round_id"
        case playerId = "player_id"
        case groupNum = "group_num"
        case status
        case invitedBy = "invited_by"
    }
}

/// Invite with joined round + course + inviter profile data
struct InviteDTO: Codable, Identifiable {
    let id: UUID              // round_players.id
    let roundId: UUID
    let playerId: UUID
    let status: String
    let invitedBy: UUID?
    let groupNum: Int
    let round: InviteRoundDTO

    enum CodingKeys: String, CodingKey {
        case id
        case roundId = "round_id"
        case playerId = "player_id"
        case status
        case invitedBy = "invited_by"
        case groupNum = "group_num"
        case round = "rounds"
    }
}

struct InviteRoundDTO: Codable {
    let id: UUID
    let courseId: UUID
    let createdBy: UUID
    let buyIn: Int
    let gameType: String
    let net: Bool
    let carries: Bool
    let outright: Bool
    let status: String
    let createdAt: Date?
    let course: InviteCourseDTO

    enum CodingKeys: String, CodingKey {
        case id
        case courseId = "course_id"
        case createdBy = "created_by"
        case buyIn = "buy_in"
        case gameType = "game_type"
        case net, carries, outright, status
        case createdAt = "created_at"
        case course = "courses"
    }
}

struct InviteCourseDTO: Codable {
    let id: UUID
    let name: String
    let clubName: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case clubName = "club_name"
    }
}

// MARK: - Score

struct ScoreDTO: Codable, Identifiable {
    let id: UUID
    let roundId: UUID
    let playerId: UUID
    let holeNum: Int
    var score: Int
    var proposedScore: Int?
    var proposedBy: UUID?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case roundId = "round_id"
        case playerId = "player_id"
        case holeNum = "hole_num"
        case score
        case proposedScore = "proposed_score"
        case proposedBy = "proposed_by"
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

/// Used to propose a score change (sets proposed_score and proposed_by).
struct ScoreProposalUpdate: Codable {
    let proposedScore: Int
    let proposedBy: UUID

    enum CodingKeys: String, CodingKey {
        case proposedScore = "proposed_score"
        case proposedBy = "proposed_by"
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
    var groupId: UUID? = nil
    var scorerId: UUID? = nil
    var scoringMode: String = "single"

    enum CodingKeys: String, CodingKey {
        case courseId = "course_id"
        case createdBy = "created_by"
        case teeBoxId = "tee_box_id"
        case buyIn = "buy_in"
        case gameType = "game_type"
        case net, carries, outright
        case handicapPercentage = "handicap_percentage"
        case groupId = "group_id"
        case scorerId = "scorer_id"
        case scoringMode = "scoring_mode"
    }
}

struct RoundPlayerInsert: Codable {
    let roundId: UUID
    let playerId: UUID
    let groupNum: Int
    var status: String = "accepted"   // "accepted" for creator/confirmed, "invited" for pending
    var invitedBy: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case roundId = "round_id"
        case playerId = "player_id"
        case groupNum = "group_num"
        case status
        case invitedBy = "invited_by"
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
    let holesJson: String?  // JSON array of per-hole data [{par,hcp},...] for 18 holes

    enum CodingKeys: String, CodingKey {
        case courseId = "course_id"
        case name, color
        case courseRating = "course_rating"
        case slopeRating = "slope_rating"
        case par
        case holesJson = "holes_json"
    }
}

// MARK: - Skins Group

struct SkinsGroupDTO: Codable, Identifiable {
    let id: UUID
    var name: String
    let createdBy: UUID?
    var buyIn: Double
    var lastCourseName: String?
    var lastCourseClubName: String?
    var scheduledDate: Date?
    var recurrence: String?   // JSON-encoded GameRecurrence
    var lastTeeBoxName: String?
    var lastTeeBoxColor: String?
    var lastTeeBoxCourseRating: Double?
    var lastTeeBoxSlopeRating: Int?
    var lastTeeBoxPar: Int?
    var handicapPercentage: Double?
    var scoringMode: String?
    var isQuickGame: Bool?
    var scorerIds: [Int]?  // per-group scorer player IDs
    var teeTimeInterval: Int?  // minutes between consecutive tee times (0 or nil = off)
    var lastTeeBoxHolesJson: String?  // per-hole par/hcp data, saved at course selection
    var winningsDisplay: String?  // 'gross' (default) or 'net' — how winnings are shown
    let createdAt: Date?
    var updatedAt: Date?

    /// Decode holes from the stored JSON string.
    func decodeHoles() -> [Hole]? {
        guard let json = lastTeeBoxHolesJson, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([Hole].self, from: data)
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdBy = "created_by"
        case buyIn = "buy_in"
        case lastCourseName = "last_course_name"
        case lastCourseClubName = "last_course_club_name"
        case scheduledDate = "scheduled_date"
        case recurrence
        case lastTeeBoxName = "last_tee_box_name"
        case lastTeeBoxColor = "last_tee_box_color"
        case lastTeeBoxCourseRating = "last_tee_box_course_rating"
        case lastTeeBoxSlopeRating = "last_tee_box_slope_rating"
        case lastTeeBoxPar = "last_tee_box_par"
        case handicapPercentage = "handicap_percentage"
        case scoringMode = "scoring_mode"
        case isQuickGame = "is_quick_game"
        case scorerIds = "scorer_ids"
        case teeTimeInterval = "tee_time_interval"
        case lastTeeBoxHolesJson = "last_tee_box_holes_json"
        case winningsDisplay = "winnings_display"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SkinsGroupInsert: Codable {
    let name: String
    let createdBy: UUID
    var buyIn: Double = 0
    var lastCourseName: String?
    var lastCourseClubName: String?
    var scheduledDate: Date?
    var recurrence: String?
    var lastTeeBoxName: String?
    var lastTeeBoxColor: String?
    var lastTeeBoxCourseRating: Double?
    var lastTeeBoxSlopeRating: Int?
    var lastTeeBoxPar: Int?
    var handicapPercentage: Double?
    var scoringMode: String = "single"
    var isQuickGame: Bool = false
    var teeTimeInterval: Int? = nil
    var lastTeeBoxHolesJson: String? = nil
    var winningsDisplay: String = "gross"

    enum CodingKeys: String, CodingKey {
        case name
        case createdBy = "created_by"
        case buyIn = "buy_in"
        case lastCourseName = "last_course_name"
        case lastCourseClubName = "last_course_club_name"
        case scheduledDate = "scheduled_date"
        case recurrence
        case lastTeeBoxName = "last_tee_box_name"
        case lastTeeBoxColor = "last_tee_box_color"
        case lastTeeBoxCourseRating = "last_tee_box_course_rating"
        case lastTeeBoxSlopeRating = "last_tee_box_slope_rating"
        case lastTeeBoxPar = "last_tee_box_par"
        case handicapPercentage = "handicap_percentage"
        case scoringMode = "scoring_mode"
        case isQuickGame = "is_quick_game"
        case teeTimeInterval = "tee_time_interval"
        case lastTeeBoxHolesJson = "last_tee_box_holes_json"
        case winningsDisplay = "winnings_display"
    }
}

struct SkinsGroupUpdate: Codable {
    var name: String?
    var buyIn: Double?
    var lastCourseName: String?
    var lastCourseClubName: String?
    var scheduledDate: Date?
    var clearScheduledDate: Bool = false  // when true, sends null for scheduled_date column
    var recurrence: String?
    var clearRecurrence: Bool = false  // when true, sends null for recurrence column
    var lastTeeBoxName: String?
    var lastTeeBoxColor: String?
    var lastTeeBoxCourseRating: Double?
    var lastTeeBoxSlopeRating: Int?
    var lastTeeBoxPar: Int?
    var handicapPercentage: Double?
    var isQuickGame: Bool?
    var scorerIds: [Int]?
    var teeTimeInterval: Int?
    var lastTeeBoxHolesJson: String?
    var winningsDisplay: String?

    enum CodingKeys: String, CodingKey {
        case name
        case buyIn = "buy_in"
        case lastCourseName = "last_course_name"
        case lastCourseClubName = "last_course_club_name"
        case scheduledDate = "scheduled_date"
        case recurrence
        case lastTeeBoxName = "last_tee_box_name"
        case lastTeeBoxColor = "last_tee_box_color"
        case lastTeeBoxCourseRating = "last_tee_box_course_rating"
        case lastTeeBoxSlopeRating = "last_tee_box_slope_rating"
        case lastTeeBoxPar = "last_tee_box_par"
        case handicapPercentage = "handicap_percentage"
        case isQuickGame = "is_quick_game"
        case scorerIds = "scorer_ids"
        case teeTimeInterval = "tee_time_interval"
        case lastTeeBoxHolesJson = "last_tee_box_holes_json"
        case winningsDisplay = "winnings_display"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let name { try container.encode(name, forKey: .name) }
        if let buyIn { try container.encode(buyIn, forKey: .buyIn) }
        if let lastCourseName { try container.encode(lastCourseName, forKey: .lastCourseName) }
        if let lastCourseClubName { try container.encode(lastCourseClubName, forKey: .lastCourseClubName) }
        if let scheduledDate {
            try container.encode(scheduledDate, forKey: .scheduledDate)
        } else if clearScheduledDate {
            try container.encodeNil(forKey: .scheduledDate)
        }
        if let recurrence {
            try container.encode(recurrence, forKey: .recurrence)
        } else if clearRecurrence {
            try container.encodeNil(forKey: .recurrence)
        }
        if let lastTeeBoxName { try container.encode(lastTeeBoxName, forKey: .lastTeeBoxName) }
        if let lastTeeBoxColor { try container.encode(lastTeeBoxColor, forKey: .lastTeeBoxColor) }
        if let lastTeeBoxCourseRating { try container.encode(lastTeeBoxCourseRating, forKey: .lastTeeBoxCourseRating) }
        if let lastTeeBoxSlopeRating { try container.encode(lastTeeBoxSlopeRating, forKey: .lastTeeBoxSlopeRating) }
        if let lastTeeBoxPar { try container.encode(lastTeeBoxPar, forKey: .lastTeeBoxPar) }
        if let handicapPercentage { try container.encode(handicapPercentage, forKey: .handicapPercentage) }
        if let isQuickGame { try container.encode(isQuickGame, forKey: .isQuickGame) }
        if let scorerIds { try container.encode(scorerIds, forKey: .scorerIds) }
        if let teeTimeInterval { try container.encode(teeTimeInterval, forKey: .teeTimeInterval) }
        if let lastTeeBoxHolesJson { try container.encode(lastTeeBoxHolesJson, forKey: .lastTeeBoxHolesJson) }
        if let winningsDisplay { try container.encode(winningsDisplay, forKey: .winningsDisplay) }
    }
}

// MARK: - Group Member

struct GroupMemberDTO: Codable, Identifiable {
    let id: UUID
    let groupId: UUID
    let playerId: UUID
    var role: String       // "creator" | "member"
    var status: String     // "active" | "invited" | "removed"
    let joinedAt: Date?
    var sortOrder: Int?
    var invitedPhone: String?
    var groupNum: Int?     // which foursome group (1, 2, 3...) — for multi-group Quick Games

    enum CodingKeys: String, CodingKey {
        case id
        case groupId = "group_id"
        case playerId = "player_id"
        case role, status
        case joinedAt = "joined_at"
        case sortOrder = "sort_order"
        case invitedPhone = "invited_phone"
        case groupNum = "group_num"
    }
}

struct GroupMemberInsert: Codable {
    let groupId: UUID
    let playerId: UUID
    var role: String = "member"
    var status: String = "active"
    var invitedPhone: String? = nil
    var sortOrder: Int? = nil
    var groupNum: Int? = nil

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case playerId = "player_id"
        case role, status
        case invitedPhone = "invited_phone"
        case sortOrder = "sort_order"
        case groupNum = "group_num"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupId, forKey: .groupId)
        try container.encode(playerId, forKey: .playerId)
        try container.encode(role, forKey: .role)
        try container.encode(status, forKey: .status)
        if let invitedPhone { try container.encode(invitedPhone, forKey: .invitedPhone) }
        if let sortOrder { try container.encode(sortOrder, forKey: .sortOrder) }
        if let groupNum { try container.encode(groupNum, forKey: .groupNum) }
    }
}

// MARK: - Profile Update

struct ProfileUpdate: Codable {
    var firstName: String?
    var lastName: String?
    var username: String?
    var displayName: String?
    var initials: String?
    var color: String?
    var avatar: String?
    var handicap: Double?
    var ghinNumber: String?
    var homeClub: String?
    var homeClubId: Int?
    var avatarUrl: String?
    var email: String?
    var isClubMember: Bool?

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case username
        case displayName = "display_name"
        case initials, color, avatar, handicap
        case ghinNumber = "ghin_number"
        case homeClub = "home_club"
        case homeClubId = "home_club_id"
        case avatarUrl = "avatar_url"
        case email
        case isClubMember = "is_club_member"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let firstName { try container.encode(firstName, forKey: .firstName) }
        if let lastName { try container.encode(lastName, forKey: .lastName) }
        if let username { try container.encode(username, forKey: .username) }
        if let displayName { try container.encode(displayName, forKey: .displayName) }
        if let initials { try container.encode(initials, forKey: .initials) }
        if let color { try container.encode(color, forKey: .color) }
        if let avatar { try container.encode(avatar, forKey: .avatar) }
        if let handicap { try container.encode(handicap, forKey: .handicap) }
        if let ghinNumber { try container.encode(ghinNumber, forKey: .ghinNumber) }
        if let homeClub { try container.encode(homeClub, forKey: .homeClub) }
        if let homeClubId { try container.encode(homeClubId, forKey: .homeClubId) }
        if let avatarUrl { try container.encode(avatarUrl, forKey: .avatarUrl) }
        if let email { try container.encode(email, forKey: .email) }
        if let isClubMember { try container.encode(isClubMember, forKey: .isClubMember) }
    }
}
