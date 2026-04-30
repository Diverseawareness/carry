#if DEBUG
import Foundation
import SwiftUI

// MARK: - Debug Scenarios

/// Each scenario defines a complete, consistent app state.
/// Every view reads from the same world state — navigate anywhere and it makes sense.
enum DebugScenario: String, CaseIterable, Identifiable {
    case home              // Browsing — active round, recent history, invites
    case homeAllCardStates // All 4 active card states on one screen
    case homeConcluded     // Round just concluded — all groups finished
    case homeEmpty         // Fresh user — no groups, no rounds
    case homeFree          // Free user — 1 group, 3 recent rounds capped, locked winnings
    case homePremium       // Premium user — unlimited groups, full history, all stats
    case homeSpectator     // Group member NOT in today's round — sees live card, can't open scorecard
    case groupCreator      // Creator setting up groups before starting
    case groupMember       // Member viewing group setup (read-only)
    case scorecardViewer   // Viewer — same UI, no score input
    case scorecardEmpty    // Fresh round started, no scores entered
    case scorecardMid      // Mid-round — hole 7, 6 holes scored
    case scorecardLate     // Late round — hole 17, one hole left
    case scorecardCarries  // Mid-round with carries enabled — shows gold arrows + Xx badges
    case confettiTest      // Auto-fires confetti + toast after 1.5s (simulates notification open)
    case pendingResults    // Pending results — some groups still out
    case roundComplete     // All 18 done, results screen
    case onboarding        // Auth → onboarding → home flow
    case onboarding3Step   // Onboarding with Apple name (3 steps: Profile → Notif → Disclaimer)
    case onboarding4Step   // Onboarding without name (4 steps: Name → Profile → Notif → Disclaimer)
    case welcome           // Sign-in / auth screen
    case inviteOverlay     // Full-screen invite overlay
    case paywall           // Paywall / subscription screen
    case createGroup       // Create new skins game sheet
    case disclaimer        // Scorekeeper disclaimer screen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home:            return "Home"
        case .homeAllCardStates: return "Home (All Card States)"
        case .homeConcluded:   return "Home (Concluded)"
        case .homeEmpty:       return "Home (Empty)"
        case .homeFree:        return "Home (Free User)"
        case .homePremium:     return "Home (Subscriber)"
        case .homeSpectator:   return "Home (Spectator)"
        case .groupCreator:    return "Group Setup (Creator)"
        case .groupMember:     return "Group Setup (Member)"
        case .scorecardViewer: return "Scorecard (Viewer)"
        case .scorecardEmpty:  return "Scorecard (Empty)"
        case .scorecardMid:    return "Scorecard (Mid-Round)"
        case .scorecardLate:   return "Scorecard (Hole 17)"
        case .scorecardCarries: return "Scorecard (Carries)"
        case .confettiTest:    return "Confetti + Toast Test"
        case .pendingResults:  return "Pending Results"
        case .roundComplete:   return "Round Complete (Final)"
        case .onboarding:      return "Onboarding Flow"
        case .onboarding3Step: return "Onboarding (3-Step)"
        case .onboarding4Step: return "Onboarding (4-Step)"
        case .welcome:         return "Welcome / Auth"
        case .inviteOverlay:   return "Invite Overlay"
        case .paywall:         return "Paywall"
        case .createGroup:     return "Create Skins Game"
        case .disclaimer:      return "Disclaimer"
        }
    }

    var icon: String {
        switch self {
        case .home:            return "house"
        case .homeAllCardStates: return "house.fill"
        case .homeConcluded:   return "house"
        case .homeEmpty:       return "house"
        case .homeFree:        return "lock"
        case .homePremium:     return "crown"
        case .homeSpectator:   return "eye"
        case .groupCreator:    return "person.2"
        case .groupMember:     return "person.2"
        case .scorecardViewer: return "eye"
        case .scorecardEmpty:  return "tablecells"
        case .scorecardMid:    return "tablecells"
        case .scorecardLate:   return "tablecells"
        case .scorecardCarries: return "arrow.right"
        case .confettiTest:    return "party.popper"
        case .pendingResults:  return "clock.badge.checkmark"
        case .roundComplete:   return "flag.checkered"
        case .onboarding:      return "person.badge.plus"
        case .onboarding3Step: return "3.circle"
        case .onboarding4Step: return "4.circle"
        case .welcome:         return "key"
        case .inviteOverlay:   return "envelope.open"
        case .paywall:         return "crown"
        case .createGroup:     return "plus.circle"
        case .disclaimer:      return "exclamationmark.triangle"
        }
    }

    var section: DebugSection {
        switch self {
        case .home, .homeAllCardStates, .homeConcluded, .homeEmpty, .homeSpectator:    return .navigation
        case .groupCreator, .groupMember, .createGroup:            return .navigation
        case .homeFree, .homePremium, .paywall:                    return .subscription
        case .scorecardViewer, .scorecardEmpty, .scorecardMid, .scorecardLate, .scorecardCarries, .confettiTest, .pendingResults, .roundComplete: return .scorecard
        case .onboarding, .onboarding3Step, .onboarding4Step, .welcome, .inviteOverlay, .disclaimer:    return .auth
        }
    }

    enum DebugSection: String, CaseIterable {
        case navigation   = "NAVIGATE TO"
        case subscription = "FREE vs PREMIUM"
        case scorecard    = "SCORECARD STATES"
        case auth         = "AUTH FLOW"

        var scenarios: [DebugScenario] {
            DebugScenario.allCases.filter { $0.section == self }
        }
    }
}

// MARK: - World State

/// Complete state for a debug scenario. Every view can derive what it needs from this.
struct DebugWorldState {
    let currentUserId: Int
    let creatorId: Int
    let players: [Player]
    let roundConfig: RoundConfig
    let demoMode: RoundViewModel.DemoMode
    let course: SelectedCourse
    let groups: [SavedGroup]
    let startScreen: DebugStartScreen
    let isCreator: Bool
    var isPremium: Bool? = nil  // nil = don't change current state
    var isViewer: Bool = false
}

enum DebugStartScreen {
    case home
    case homeEmpty
    case groupSetup
    case scorecard
    case onboarding
    case onboarding3Step
    case onboarding4Step
    case welcome
    case inviteOverlay
    case paywall
    case createGroup
}

// MARK: - Scenario → World State

extension DebugScenario {
    /// RoundConfig with carries enabled for the carries debug scenario
    private static let carriesConfig = RoundConfig(
        id: "debug-carries",
        number: 1,
        course: "Torrey Pines South",
        date: "2026-03-17",
        buyIn: 50,
        gameType: "skins",
        skinRules: SkinRules(net: true, carries: true, outright: true, handicapPercentage: 1.0),
        teeBox: TeeBox.demo[1],
        groups: [
            GroupConfig(id: 1, startingSide: "front", playerIDs: [1, 2, 3, 4]),
            GroupConfig(id: 2, startingSide: "front", playerIDs: [5, 6, 7, 8]),
            GroupConfig(id: 3, startingSide: "back", playerIDs: [9, 10, 11, 12]),
        ],
        creatorId: 1,
        groupName: "The Friday Skins",
        players: Array(Player.allPlayers.prefix(12))
    )

    private static let demoCourse = SelectedCourse(
        courseId: 1,
        courseName: "Torrey Pines South",
        clubName: "Torrey Pines",
        location: "La Jolla, CA",
        teeBox: TeeBox.demo[1],
        apiTee: nil
    )

    var worldState: DebugWorldState {
        switch self {

        case .home:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .none,
                course: Self.demoCourse,
                groups: SavedGroup.demo,
                startScreen: .home,
                isCreator: true
            )

        case .homeAllCardStates:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .none,
                course: Self.demoCourse,
                groups: SavedGroup.demoAllCardStates,
                startScreen: .home,
                isCreator: true
            )

        case .homeConcluded:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .none,
                course: Self.demoCourse,
                groups: SavedGroup.demoConcluded,
                startScreen: .home,
                isCreator: true
            )

        case .homeEmpty:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .none,
                course: Self.demoCourse,
                groups: [],
                startScreen: .homeEmpty,
                isCreator: true
            )

        case .homeFree:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .none,
                course: Self.demoCourse,
                groups: SavedGroup.demoConcluded,
                startScreen: .home,
                isCreator: true,
                isPremium: false
            )

        case .homePremium:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .none,
                course: Self.demoCourse,
                groups: SavedGroup.demo,
                startScreen: .home,
                isCreator: true,
                isPremium: true
            )

        case .homeSpectator:
            // User 1 (Daniel) is a GROUP member but NOT in today's active round's
            // player list. The home card should still render + poll, but tapping
            // it should NOT open the scorecard. Final results are viewable.
            let spectatorActiveRound = HomeRound(
                id: UUID(),
                groupName: "The Friday Skins",
                courseName: "Torrey Pines South",
                // NOTE: player id 1 (Daniel / current user) intentionally excluded
                players: Array(Player.allPlayers.dropFirst()).prefix(12).map { $0 },
                status: .active,
                currentHole: 7,
                totalHoles: 18,
                buyIn: 50,
                skinsWon: 3,
                totalSkins: 18,
                yourSkins: 0,
                invitedBy: nil,
                creatorId: 2,
                startedAt: Calendar.current.date(byAdding: .hour, value: -1, to: Date()),
                completedAt: nil,
                scheduledDate: Calendar.current.date(byAdding: .hour, value: -1, to: Date()),
                playerWinnings: [2: 45, 3: 22, 5: 15],
                playerWonHoles: [2: [1, 4], 3: [3], 5: [6]]
            )
            let spectatorGroup = SavedGroup(
                id: UUID(),
                name: "The Friday Skins",
                members: Player.allPlayers,   // Daniel IS in the group members
                lastPlayed: "Today",
                creatorId: 2,                 // Someone else is creator
                lastCourse: SelectedCourse(
                    courseId: 1,
                    courseName: "Torrey Pines South",
                    clubName: "Torrey Pines",
                    location: "La Jolla, CA",
                    teeBox: TeeBox.demo[1],
                    apiTee: nil
                ),
                activeRound: spectatorActiveRound,
                roundHistory: []
            )
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 2,                 // Not the creator
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .none,
                course: Self.demoCourse,
                groups: [spectatorGroup],
                startScreen: .home,
                isCreator: false              // Daniel isn't the round creator either
            )

        case .groupCreator:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .none,
                course: Self.demoCourse,
                groups: SavedGroup.demo,
                startScreen: .groupSetup,
                isCreator: true
            )

        case .groupMember:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 2,  // someone else is creator
                players: Player.allPlayers,
                roundConfig: RoundConfig(
                    id: "r2", number: 2, course: "Torrey Pines South", date: "2026-03-16",
                    buyIn: 50, gameType: "skins", skinRules: .default, teeBox: TeeBox.demo[1],
                    groups: RoundConfig.default.groups,
                    creatorId: 2, groupName: "The Friday Skins", players: Player.allPlayers
                ),
                demoMode: .none,
                course: Self.demoCourse,
                groups: SavedGroup.demo,
                startScreen: .groupSetup,
                isCreator: false
            )

        case .scorecardViewer:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 2,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .midGame,
                course: Self.demoCourse,
                groups: SavedGroup.demo,
                startScreen: .scorecard,
                isCreator: false,
                isViewer: true
            )

        case .scorecardEmpty:
            // Use a unique config ID so stale saved scores from other demos don't load
            let emptyConfig = RoundConfig(
                id: "debug-empty",
                number: 1,
                course: "Torrey Pines South",
                date: "2026-03-16",
                buyIn: 50,
                gameType: "skins",
                skinRules: .default,
                teeBox: TeeBox.demo[1],
                groups: RoundConfig.default.groups,
                creatorId: 1,
                groupName: "The Friday Skins",
                players: Player.allPlayers
            )
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: emptyConfig,
                demoMode: .none,
                course: Self.demoCourse,
                groups: SavedGroup.demo,
                startScreen: .scorecard,
                isCreator: true
            )

        case .scorecardMid:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .midGame,
                course: Self.demoCourse,
                groups: SavedGroup.demo,
                startScreen: .scorecard,
                isCreator: true
            )

        case .scorecardLate:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .hole17,
                course: Self.demoCourse,
                groups: SavedGroup.demo,
                startScreen: .scorecard,
                isCreator: true
            )

        case .scorecardCarries:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: Self.carriesConfig,
                demoMode: .carries,
                course: Self.demoCourse,
                groups: SavedGroup.demo,
                startScreen: .scorecard,
                isCreator: true
            )

        case .confettiTest:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .confettiTest,
                course: Self.demoCourse,
                groups: SavedGroup.demo,
                startScreen: .scorecard,
                isCreator: true
            )

        case .pendingResults:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .provisionalResults,
                course: Self.demoCourse,
                groups: SavedGroup.demo,
                startScreen: .scorecard,
                isCreator: true
            )

        case .roundComplete:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .fullGame,
                course: Self.demoCourse,
                groups: SavedGroup.demo,
                startScreen: .scorecard,
                isCreator: true
            )

        case .onboarding:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .none,
                course: Self.demoCourse,
                groups: [],
                startScreen: .onboarding,
                isCreator: true
            )

        case .onboarding3Step:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .none,
                course: Self.demoCourse,
                groups: [],
                startScreen: .onboarding3Step,
                isCreator: true
            )

        case .onboarding4Step:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .none,
                course: Self.demoCourse,
                groups: [],
                startScreen: .onboarding4Step,
                isCreator: true
            )

        case .welcome:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .none,
                course: Self.demoCourse,
                groups: [],
                startScreen: .welcome,
                isCreator: true
            )

        case .inviteOverlay:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .none,
                course: Self.demoCourse,
                groups: [],
                startScreen: .inviteOverlay,
                isCreator: true
            )

        case .paywall:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .none,
                course: Self.demoCourse,
                groups: [],
                startScreen: .paywall,
                isCreator: true
            )

        case .createGroup:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .none,
                course: Self.demoCourse,
                groups: [],
                startScreen: .createGroup,
                isCreator: true
            )

        case .disclaimer:
            return DebugWorldState(
                currentUserId: 1,
                creatorId: 1,
                players: Player.allPlayers,
                roundConfig: .default,
                demoMode: .none,
                course: Self.demoCourse,
                groups: [],
                startScreen: .homeEmpty,
                isCreator: true
            )
        }
    }
}
#endif
