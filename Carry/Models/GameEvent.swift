import Foundation

/// In-app notification event for the live skins feed.
/// Queued in RoundViewModel, consumed by ToastOverlay on the scorecard.
struct GameEvent: Identifiable {
    let id = UUID()
    let type: EventType
    let message: String
    let player: Player?
    let holeNum: Int?
    let value: Int?  // dollar value (for carry events)
    let timestamp: Date = Date()

    enum EventType {
        case skinWon        // "Daniel won Hole 5"
        case carryBuilding  // "3x carry on Hole 12 — $99"
        case groupFinished  // "Group 1 finished — 2/4 groups"
    }

    // MARK: - Factory Methods

    static func skinWon(player: Player, holeNum: Int, isLastGroup: Bool = true) -> GameEvent {
        let verb = isLastGroup ? "won" : "is leading"
        return GameEvent(
            type: .skinWon,
            message: "\(player.shortName) \(verb) Hole \(holeNum)",
            player: player,
            holeNum: holeNum,
            value: nil
        )
    }

    static func carryBuilding(holeNum: Int, carryCount: Int, skinValue: Int) -> GameEvent {
        GameEvent(
            type: .carryBuilding,
            message: "\(carryCount)x carry on Hole \(holeNum) — $\(skinValue)",
            player: nil,
            holeNum: holeNum,
            value: skinValue
        )
    }

    static func groupFinished(groupNum: Int, completedGroups: Int, totalGroups: Int) -> GameEvent {
        GameEvent(
            type: .groupFinished,
            message: "Group \(groupNum) finished — \(completedGroups)/\(totalGroups)",
            player: nil,
            holeNum: nil,
            value: nil
        )
    }
}
