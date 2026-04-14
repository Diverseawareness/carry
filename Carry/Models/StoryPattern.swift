import Foundation

// MARK: - Pattern Types

enum PatternType: Int, CaseIterable {
    // High priority (headlines)
    case bigCarryWin = 12
    case streak      = 11
    case comeback    = 10
    case shutout     = 9
    case sweep       = 8
    case photoFinish = 7

    // Medium priority (color)
    case birdieWin    = 6
    case uglyWin      = 5
    case carryStreak  = 4
    case backNineHero = 3
    case wireToWire   = 2
    case firstBlood   = 1
    case closingKill  = 0

    // Low priority (filler/opener)
    case biggestLoser = -1
    case potSize      = -2
    case playerCount  = -3

    var priority: Int {
        switch self {
        case .bigCarryWin, .streak, .comeback, .shutout, .sweep, .photoFinish:
            return 3
        case .birdieWin, .uglyWin, .carryStreak, .backNineHero, .wireToWire, .firstBlood, .closingKill:
            return 2
        case .biggestLoser, .potSize, .playerCount:
            return 1
        }
    }

    var isHighPriority: Bool { priority == 3 }
    var isMediumPriority: Bool { priority == 2 }
    var isLowPriority: Bool { priority == 1 }
}

// MARK: - Story Pattern

struct StoryPattern {
    let type: PatternType
    let player: Player?
    let secondPlayer: Player?
    let value: Int
    let holeNum: Int
    let holeRange: ClosedRange<Int>?
    let detail: String?
    let detail2: String?  // secondary context (e.g. score description)

    init(
        type: PatternType,
        player: Player? = nil,
        secondPlayer: Player? = nil,
        value: Int = 0,
        holeNum: Int = 0,
        holeRange: ClosedRange<Int>? = nil,
        detail: String? = nil,
        detail2: String? = nil
    ) {
        self.type = type
        self.player = player
        self.secondPlayer = secondPlayer
        self.value = value
        self.holeNum = holeNum
        self.holeRange = holeRange
        self.detail = detail
        self.detail2 = detail2
    }
}

// MARK: - Round Story

struct RoundStory {
    let sentences: [String]
    let patterns: [StoryPattern]

    var fullText: String {
        sentences.joined(separator: " ")
    }

    var shareText: String {
        "⛳️ " + fullText
    }
}
