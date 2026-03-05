import Foundation

enum UserRole {
    case creator
    case participant
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
    let teeBox: TeeBox?  // selected tee box (nil = use simple handicap)
    let groups: [GroupConfig]
    let creatorId: Int?  // player ID of round creator (nil for legacy/demo)

    func role(for userId: Int) -> UserRole {
        creatorId == userId ? .creator : .participant
    }

    static let `default` = RoundConfig(
        id: "r2",
        number: 2,
        course: "Blackhawk CC",
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
        creatorId: 1
    )
}
