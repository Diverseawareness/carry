import Foundation

/// Static seed data + opponent reaction logic for the first-launch Demo Round.
///
/// The demo plays out as a 3-hole sandbox (holes 16-18) with 15 holes pre-scored
/// to set up a big-bang finale on hole 18. See `~/.claude/skills/demo-round/SKILL.md`
/// for the full feature spec.
///
/// Key design points:
/// - 4 players: user (slot 1) + 3 fixed fictional opponents (Ryan, Mike, Zoe)
/// - Holes 1-15 pre-filled with hardcoded gross scores
/// - Holes 13, 14, 15 hand-tuned to all squash → 3 carried skins on the table
/// - Holes 16, 17 (user plays): forced tie (carry) via opponent reaction
/// - Hole 18 (user plays): user wins → claims 5 carried + hole 18's skin = 6 skins
///
/// Round IDs / Group IDs are fresh `UUID()` instances — `RoundConfig.isDemo`
/// is the discriminator, not the ID format. See RoundConfig.isDemo.
enum DemoSeed {

    // MARK: - Player IDs
    // High range to avoid collision with real Player.allPlayers (IDs 1-16) and
    // with currentUserId from auth.
    static let userId = 1001
    static let ryanId = 1002
    static let mikeId = 1003
    static let zoeId = 1004

    // MARK: - Opponents (fixed across all users)

    /// Ryan — the leader through hole 15. Low single-digit handicap.
    /// Avatar: demo_01 (user-provided face avatar; swap filename in
    /// `avatarImageName` below if you'd rather match a different photo).
    static let ryan = Player(
        id: ryanId,
        name: "Ryan",
        initials: "R",
        color: "#E0457B",
        handicap: 4.0,
        avatar: "⛳",
        group: 1,
        ghinNumber: nil,
        venmoUsername: nil,
        avatarImageName: "demo_01"
    )

    /// Mike — mid-pack single-digit. Solid but inconsistent.
    /// Avatar: demo_02.
    static let mike = Player(
        id: mikeId,
        name: "Mike",
        initials: "M",
        color: "#3B82F6",
        handicap: 7.0,
        avatar: "🏌️",
        group: 1,
        ghinNumber: nil,
        venmoUsername: nil,
        avatarImageName: "demo_02"
    )

    /// Zoe — single-digit, but a slow start today.
    /// Avatar: demo_03.
    static let zoe = Player(
        id: zoeId,
        name: "Zoe",
        initials: "Z",
        color: "#16A34A",
        handicap: 5.0,
        avatar: "🍻",
        group: 1,
        ghinNumber: nil,
        venmoUsername: nil,
        avatarImageName: "demo_03"
    )

    // MARK: - User slot constructor

    /// Build the user's player slot from the AuthService displayName (or fallback).
    /// User is hardcoded to handicap 14 for predictable opponent-reaction math.
    static func userPlayer(displayName: String?, profileId: UUID? = nil) -> Player {
        let resolvedName = (displayName?.isEmpty == false) ? displayName! : "Player"
        let initials = resolvedName.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        return Player(
            id: userId,
            name: resolvedName,
            initials: initials.isEmpty ? "P" : initials,
            color: "#D4A017",  // Carry gold — user pops vs muted opponent colors
            handicap: 14.0,
            avatar: "🏌️",
            group: 1,
            ghinNumber: nil,
            venmoUsername: nil,
            avatarImageName: nil,
            profileId: profileId
        )
    }

    /// Full 4-player roster ordered: user, Ryan, Mike, Zoe.
    static func roster(displayName: String?, userProfileId: UUID? = nil) -> [Player] {
        [userPlayer(displayName: displayName, profileId: userProfileId), ryan, mike, zoe]
    }

    // MARK: - Course + tee box

    /// Reuses the existing demo Blue tee structure (par 72, 71.5/134) but
    /// labeled as Pebble Beach in `RoundConfig.course`. Keeps the math
    /// realistic without needing to fetch live API data.
    static var teeBox: TeeBox {
        TeeBox.demo[1]  // Blue tees
    }

    static let courseName = "Pebble Beach Golf Links"
    static let buyIn = 120  // $120 × 4 players = $480 pot, $26.67/skin →
                            // 3 pre-carries = ~$80 on the table going into
                            // hole 16 (the Home card hook). User wins 6
                            // skins on hole-18 big bang = ~$160 gross.

    // MARK: - Pre-filled scores (holes 1-15)
    //
    // Hand-tuned to produce roughly:
    //   - Ryan ~6 skins won (steady par golf)
    //   - User  ~4 skins won (mid-pack with handful of bright spots)
    //   - Mike  ~3 skins won (occasional good hole, mostly bogeys)
    //   - Zoe    0 skins won (shutout — playing poorly even with strokes)
    //   - Holes 13, 14, 15 ALL squashed → 3 carried skins sitting on the table
    //     when the user starts playing hole 16
    //
    // Format below: [holeNum: [playerId: grossScore]] — readable hole-by-hole.
    // `prefilledScoresByPlayer` (computed below) transposes to the shape
    // `RoundViewModel.scores` expects ([playerId: [holeNum: score]]).
    //
    // Note: actual skin distribution depends on the per-hole hcp ranking from
    // Hole.allHoles. If the resulting distribution drifts noticeably from the
    // intent above, tune individual gross scores here. The carries on 13-15
    // are the load-bearing property; the exact 6/4/3/0 split is aspirational.
    private static let preFilledScoresByHole: [Int: [Int: Int]] = [
        //  hole : [user, ryan, mike, zoe] (gross)
        1:  [userId: 5, ryanId: 4, mikeId: 6, zoeId: 7],   // Ryan wins
        2:  [userId: 4, ryanId: 4, mikeId: 5, zoeId: 6],   // User+Ryan tie low? carries or wins
        3:  [userId: 4, ryanId: 5, mikeId: 5, zoeId: 7],   // User wins
        4:  [userId: 6, ryanId: 4, mikeId: 6, zoeId: 8],   // Ryan wins
        5:  [userId: 5, ryanId: 5, mikeId: 4, zoeId: 7],   // Mike wins
        6:  [userId: 4, ryanId: 4, mikeId: 5, zoeId: 6],   // tie — carries
        7:  [userId: 5, ryanId: 4, mikeId: 6, zoeId: 7],   // Ryan wins
        8:  [userId: 4, ryanId: 5, mikeId: 6, zoeId: 7],   // User wins
        9:  [userId: 5, ryanId: 4, mikeId: 7, zoeId: 8],   // Ryan wins
        10: [userId: 4, ryanId: 5, mikeId: 5, zoeId: 7],   // User wins
        11: [userId: 5, ryanId: 4, mikeId: 5, zoeId: 8],   // Ryan wins
        12: [userId: 6, ryanId: 5, mikeId: 4, zoeId: 7],   // Mike wins
        // Holes 13-15: HAND-TUNED FOR SQUASH (all carry)
        // Same gross for all 4 → after handicap strokes, multiple players
        // at the same lowest net → squashed.
        13: [userId: 5, ryanId: 5, mikeId: 5, zoeId: 5],
        14: [userId: 4, ryanId: 4, mikeId: 4, zoeId: 4],
        15: [userId: 5, ryanId: 5, mikeId: 5, zoeId: 5],
    ]

    /// Transposed shape for assignment to `RoundViewModel.scores`
    /// (`[playerId: [holeNum: score]]`). Built once at access time from
    /// `preFilledScoresByHole` above.
    static var preFilledScores: [Int: [Int: Int]] {
        var result: [Int: [Int: Int]] = [:]
        for (hole, perPlayer) in preFilledScoresByHole {
            for (playerId, score) in perPlayer {
                result[playerId, default: [:]][hole] = score
            }
        }
        return result
    }

    // MARK: - Opponent reaction logic (holes 16-18)

    /// Outcome the demo wants on a given user-played hole.
    enum ScriptedOutcome {
        /// Force a tie at the user's net score (hole carries forward).
        case forceTie
        /// User wins outright by 1 net stroke.
        case userWins
    }

    /// Hardcoded script for the 3 user-played holes.
    static let script: [Int: ScriptedOutcome] = [
        16: .forceTie,
        17: .forceTie,
        18: .userWins,
    ]

    /// Compute opponent gross scores reactive to the user's tapped score.
    ///
    /// Strategy:
    /// - For `.forceTie`: at least one opponent must end at the user's net.
    ///   We try the closest gross that produces an exact net match, iterating
    ///   user's gross ± 5. If no exact match found (rare with similar handicaps),
    ///   pick the closest by net distance.
    /// - For `.userWins`: every opponent's net must be strictly worse than the
    ///   user's net. Try `userGross + 1` first; if it ties the net, bump by 2.
    ///
    /// Returns a `[playerId: gross]` dict for the 3 opponents.
    static func opponentReactions(
        for hole: Hole,
        userGross: Int,
        userHandicap: Double,
        opponentHandicaps: [Int: Double],
        teeBox: TeeBox,
        outcome: ScriptedOutcome,
        handicapPercentage: Double = 1.0
    ) -> [Int: Int] {
        let userPlayingHcp = teeBox.playingHandicap(forIndex: userHandicap, percentage: handicapPercentage)
        let userStrokes = TeeBox.strokesOnHole(playingHandicap: userPlayingHcp, holeHcp: hole.hcp)
        let userNet = max(1, userGross - userStrokes)

        var result: [Int: Int] = [:]
        for (oppId, oppHcp) in opponentHandicaps {
            let oppPlayingHcp = teeBox.playingHandicap(forIndex: oppHcp, percentage: handicapPercentage)
            let oppStrokes = TeeBox.strokesOnHole(playingHandicap: oppPlayingHcp, holeHcp: hole.hcp)

            switch outcome {
            case .forceTie:
                // Want opp net == userNet → opp gross = userNet + oppStrokes
                let targetGross = max(1, userNet + oppStrokes)
                result[oppId] = targetGross

            case .userWins:
                // Want opp net > userNet → opp gross = userNet + oppStrokes + 1
                let targetGross = max(1, userNet + oppStrokes + 1)
                result[oppId] = targetGross
            }
        }
        return result
    }
}
