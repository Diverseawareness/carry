import Foundation

enum ScoringMode: String {
    case single = "single"
    case everyone = "everyone"
}

enum UserRole {
    case creator
    case participant
    case viewer
}

struct SkinRules {
    let net: Bool
    let carries: Bool
    let outright: Bool
    let handicapPercentage: Double  // 0.0–1.0 (e.g. 0.7 = 70%, 1.0 = 100%)

    static let `default` = SkinRules(net: true, carries: false, outright: true, handicapPercentage: 1.0)
}

struct GroupConfig: Identifiable {
    let id: Int
    let startingSide: String  // "front" or "back"
    let playerIDs: [Int]
}

struct RoundConfig {
    let id: String
    let number: Int
    let course: String
    let date: String
    let buyIn: Int
    let gameType: String
    let skinRules: SkinRules
    var teeBox: TeeBox?  // selected tee box (nil = use simple handicap)
    let groups: [GroupConfig]
    let creatorId: Int?  // player ID of round creator (nil for legacy/demo)
    let groupName: String
    let players: [Player]  // all players in this round
    var holes: [Hole]? = nil  // per-hole par/handicap from API (nil = use Hole.allHoles defaults)

    // Supabase IDs — nil in devMode, populated when round is created in Supabase
    var supabaseRoundId: UUID? = nil
    var supabaseGroupId: UUID? = nil
    var scorerProfileId: UUID? = nil  // UUID of the designated scorer
    var scoringMode: ScoringMode = .single
    var isQuickGame: Bool = false  // Quick Game flag — lifts the sequential-hole scoring gate so multi-group parallel play can score any hole at any time
    var winningsDisplay: String = "gross"  // "gross" or "net" — controls scorecard cash bar display
    /// Tee time for the scorer's group. Rendered in the scorecard header
    /// subtitle before the course name so scorers in Group 2+ see their own
    /// time (not the round's earliest). nil when tee times aren't set.
    var scorerTeeTime: Date? = nil

    func role(for userId: Int) -> UserRole {
        creatorId == userId ? .creator : .participant
    }

    #if DEBUG
    static let `default` = RoundConfig(
        id: "r2",
        number: 2,
        course: "Torrey Pines South",
        date: "2026-02-23",
        buyIn: 50,
        gameType: "skins",
        skinRules: .default,
        teeBox: TeeBox.demo[1],  // Blue tees (71.5 / 134)
        groups: [
            GroupConfig(id: 1, startingSide: "front", playerIDs: [1, 2, 3, 4]),
            GroupConfig(id: 2, startingSide: "front", playerIDs: [5, 6, 7, 8]),
            GroupConfig(id: 3, startingSide: "back", playerIDs: [9, 10, 11, 12]),
        ],
        creatorId: 1,
        groupName: "The Friday Skins",
        players: Array(Player.allPlayers.prefix(12))  // Only players 1-12 (groups 1-3)
    )
    #endif
}
