import Foundation
import SwiftUI

/// Orchestrator for the first-launch Demo Round.
///
/// Pure functions over `RoundViewModel` — no own observable state. Constructs
/// the demo's seeded RoundConfig + RoundViewModel, orchestrates the user's
/// score-tap → opponent-reaction-fill cascade, and exposes the dismissal flag.
///
/// See `~/.claude/skills/demo-round/SKILL.md` for the full spec.
enum DemoRoundController {

    // MARK: - Dismissal flag

    private static let dismissedKey = "demoRoundDismissed"

    /// One-bit "user has seen + dismissed the demo" flag. Set true on any
    /// dismiss path (✕ on card, completed + accepted convert, completed + declined).
    /// Once true, never re-renders. No reset path in production code.
    static var isDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: dismissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: dismissedKey) }
    }

    // MARK: - ViewModel construction

    /// Build a fresh `RoundViewModel` for the demo round.
    /// - User pulled from `authService.currentUser.displayName` (fallback "Player")
    /// - Holes 1-15 pre-scored from `DemoSeed.preFilledScores`
    /// - `cachedSkins` populated via `calculateSkins()` so the leaderboard
    ///   renders correctly the moment the user enters the scorecard
    /// - `isDemo: true` — RoundConfig flag that gates `ScoreStorage` writes
    /// - `supabaseRoundId: nil` + `supabaseGroupId: nil` — gates network calls
    ///   (subscriptions, polling, upserts, Live Activity all auto-skip)
    @MainActor
    static func makeViewModel(authService: AuthService) -> RoundViewModel {
        let displayName = authService.currentUser?.displayName ?? authService.currentUser?.firstName
        let userProfileId = authService.currentUser?.id
        let players = DemoSeed.roster(displayName: displayName, userProfileId: userProfileId)

        var config = RoundConfig(
            id: "demo-\(UUID().uuidString)",
            number: 1,
            course: DemoSeed.courseName,
            date: ISO8601DateFormatter().string(from: Date()),
            buyIn: DemoSeed.buyIn,
            gameType: "skins",
            skinRules: SkinRules(net: true, carries: true, outright: true, handicapPercentage: 1.0),
            teeBox: DemoSeed.teeBox,
            groups: [GroupConfig(
                id: 1,
                startingSide: "front",
                playerIDs: [DemoSeed.userId, DemoSeed.sarahId, DemoSeed.mikeId, DemoSeed.tomId]
            )],
            creatorId: DemoSeed.userId,
            groupName: "Demo Round",
            players: players,
            holes: DemoSeed.teeBox.holes
        )
        config.scoringMode = .single
        config.isQuickGame = true
        config.isDemo = true
        config.scorerPlayerId = DemoSeed.userId  // user is scorer of own group
        config.scorerPlayerIds = [DemoSeed.userId]

        let vm = RoundViewModel(config: config, currentUserId: DemoSeed.userId)
        vm.scores = DemoSeed.preFilledScores
        _ = vm.calculateSkins()
        // Init left activeHole = nil because scores were empty. Now that
        // holes 1-15 are seeded, recompute so the scorecard opens directly
        // on hole 16 (the first unscored hole) instead of falling back to
        // hole 1.
        vm.activeHole = vm.computeActiveHole()
        return vm
    }

    // MARK: - User score orchestration

    /// Stagger between opponent reaction-fill animations (seconds).
    /// 300ms feels intentional but not slow.
    private static let opponentStagger: Double = 0.3

    /// Record the user's tapped score on a demo hole, then cascade opponent
    /// reaction-fills per the script in `DemoSeed.script`.
    ///
    /// Holes 16, 17 → forced tie (carry forward).
    /// Hole 18 → user wins outright (claims all carried skins).
    ///
    /// Opponents not in the script (i.e. user re-scoring a pre-filled hole)
    /// are left alone — only the user's score updates.
    static func recordUserScore(hole: Int, score: Int, viewModel: RoundViewModel) {
        // Defensive: caller (ScorecardView tap-gate) should only route demo
        // rounds here, but enforce.
        guard viewModel.config.isDemo else {
            viewModel.enterScore(playerId: DemoSeed.userId, holeNum: hole, score: score)
            return
        }

        // 1. User's own score
        viewModel.enterScore(playerId: DemoSeed.userId, holeNum: hole, score: score)

        // 2. Look up the scripted outcome for this hole. Holes outside the
        // script (1-15) are no-ops on the opponent side.
        guard let outcome = DemoSeed.script[hole] else { return }

        // 3. Compute opponent reaction gross scores
        guard let holeData = viewModel.config.holes?.first(where: { $0.num == hole })
            ?? viewModel.holes.first(where: { $0.num == hole }) else { return }

        let userHandicap = viewModel.config.players
            .first(where: { $0.id == DemoSeed.userId })?
            .handicap ?? 14.0

        let opponentHandicaps: [Int: Double] = [
            DemoSeed.sarahId: DemoSeed.sarah.handicap,
            DemoSeed.mikeId: DemoSeed.mike.handicap,
            DemoSeed.tomId: DemoSeed.tom.handicap,
        ]

        let reactions = DemoSeed.opponentReactions(
            for: holeData,
            userGross: score,
            userHandicap: userHandicap,
            opponentHandicaps: opponentHandicaps,
            teeBox: viewModel.config.teeBox ?? DemoSeed.teeBox,
            outcome: outcome,
            handicapPercentage: viewModel.config.skinRules.handicapPercentage
        )

        // 4. Cascade opponent scores with stagger animation
        let opponents: [(id: Int, score: Int)] = [
            (DemoSeed.sarahId, reactions[DemoSeed.sarahId] ?? score),
            (DemoSeed.mikeId, reactions[DemoSeed.mikeId] ?? score),
            (DemoSeed.tomId, reactions[DemoSeed.tomId] ?? score),
        ]
        for (index, opp) in opponents.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + opponentStagger * Double(index + 1)) {
                viewModel.enterScore(playerId: opp.id, holeNum: hole, score: opp.score)
            }
        }
    }
}
