//
//  CarryRoundAttributes.swift
//  Carry
//
//  Shared between the main app (starts/updates the activity)
//  and the widget extension (renders it).
//

import ActivityKit
import Foundation

struct CarryRoundAttributes: ActivityAttributes {

    // Static — set once when the activity starts
    let roundId: String
    let courseName: String
    let groupName: String?        // nil for Quick Game
    let totalHoles: Int           // 9 or 18
    let groupId: String?          // nil for Quick Game; used by lock-screen deep link

    // Dynamic — updated as the round progresses
    public struct ContentState: Codable, Hashable {
        var currentHole: Int              // 0 = not started
        var state: RoundState             // notStarted / live / pending / done
        var players: [PillPlayer]         // sorted by winnings desc
        var completedGroups: Int          // for pending footer
        var totalGroups: Int              // for pending footer
        var skinsWon: Int                 // total skins awarded so far (for "Game Done · X Skins")
        var waitingOnGroup: String?       // nil unless my group is done + others playing
    }

    public enum RoundState: String, Codable, Hashable {
        case notStarted
        case live
        case pending
        case done
    }

    public struct PillPlayer: Codable, Hashable, Identifiable {
        let id: Int
        let shortName: String
        let initials: String
        let colorHex: String              // e.g. "#D4A017"
        let winnings: Int
        let isCurrentUser: Bool
    }
}
