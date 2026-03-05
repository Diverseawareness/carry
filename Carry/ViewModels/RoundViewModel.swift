import Foundation
import SwiftUI

class RoundViewModel: ObservableObject {
    let config: RoundConfig
    let currentUserId: Int
    let allPlayers: [Player]
    let holes: [Hole]

    @Published var scores: [Int: [Int: Int]]  // [playerID: [holeNum: score]]
    @Published var activeHole: Int?
    @Published var celebration: CelebrationEvent?

    // Computed: players in current user's group
    var groupPlayers: [Player] {
        guard let myGroup = config.groups.first(where: { $0.playerIDs.contains(currentUserId) }) else { return [] }
        return myGroup.playerIDs.compactMap { pid in allPlayers.first(where: { $0.id == pid }) }
    }

    // Play order based on starting side
    var playOrder: [Hole] {
        guard let myGroup = config.groups.first(where: { $0.playerIDs.contains(currentUserId) }) else { return Hole.allHoles }
        return myGroup.startingSide == "front" ? Hole.front9 + Hole.back9 : Hole.back9 + Hole.front9
    }

    // MARK: - Handicap & Strokes

    /// Simple stroke allocation using raw handicap index (fallback when no tee box).
    /// Rounds decimal handicap to nearest integer, distributes across 18 holes by difficulty.
    static func getStrokes(handicap: Double, holeHcp: Int) -> Int {
        let rHcp = Int(handicap.rounded())
        if rHcp <= 0 { return 0 }
        return rHcp / 18 + (holeHcp <= rHcp % 18 ? 1 : 0)
    }

    /// Full USGA Course Handicap calculation using tee box data.
    /// Course Handicap = Index x (Slope / 113) + (CR - Par)
    /// Playing Handicap = Course Handicap x percentage
    /// Then distributes playing handicap strokes across holes by difficulty.
    static func getStrokes(handicapIndex: Double, holeHcp: Int, teeBox: TeeBox, percentage: Double) -> Int {
        let playingHcp = teeBox.playingHandicap(forIndex: handicapIndex, percentage: percentage)
        return TeeBox.strokesOnHole(playingHandicap: playingHcp, holeHcp: holeHcp)
    }

    /// Get strokes for a player on a specific hole, using tee box if available.
    func strokes(for player: Player, hole: Hole) -> Int {
        if let teeBox = config.teeBox {
            return Self.getStrokes(
                handicapIndex: player.handicap,
                holeHcp: hole.hcp,
                teeBox: teeBox,
                percentage: config.skinRules.handicapPercentage
            )
        }
        // Fallback: simple allocation using raw index
        return Self.getStrokes(handicap: player.handicap, holeHcp: hole.hcp)
    }

    /// Get playing handicap for a player (total strokes across all 18 holes).
    func playingHandicap(for player: Player) -> Int {
        if let teeBox = config.teeBox {
            return teeBox.playingHandicap(
                forIndex: player.handicap,
                percentage: config.skinRules.handicapPercentage
            )
        }
        return Int(player.handicap.rounded())
    }

    func netScore(gross: Int, player: Player, hole: Hole) -> Int {
        gross - strokes(for: player, hole: hole)
    }

    // Cross-group skins calculation with optional carries
    func calculateSkins() -> [Int: SkinStatus] {
        let carriesEnabled = config.skinRules.carries
        var skins: [Int: SkinStatus] = [:]
        var pendingCarry = 0  // accumulated skins from prior squashed holes

        for hole in Hole.allHoles {
            let hNum = hole.num

            // Collect net scores from ALL players across all groups
            struct NetEntry {
                let player: Player
                let gross: Int
                let net: Int
            }

            let nets: [NetEntry] = allPlayers.compactMap { p in
                guard let gross = scores[p.id]?[hNum] else { return nil }
                let net = gross - strokes(for: p, hole: hole)
                return NetEntry(player: p, gross: gross, net: net)
            }

            let allFinished = allPlayers.allSatisfy { scores[$0.id]?[hNum] != nil }

            if nets.isEmpty {
                skins[hNum] = .pending
                // pendingCarry persists — will apply to the first resolved hole
            } else if !allFinished {
                let bestNet = nets.map(\.net).min()!
                let leaders = nets.filter { $0.net == bestNet }
                let bestGross = leaders.map(\.gross).min()!
                skins[hNum] = .provisional(leaders: leaders.map(\.player), bestNet: bestNet, bestGross: bestGross, scored: nets.count, total: Player.totalPlayers)
                // pendingCarry persists — not resolved yet
            } else {
                let bestNet = nets.map(\.net).min()!
                let winners = nets.filter { $0.net == bestNet }
                if winners.count == 1 {
                    // Outright win — collect this skin + any carried skins
                    let totalCarry = 1 + pendingCarry
                    skins[hNum] = .won(winner: winners[0].player, bestNet: bestNet, bestGross: winners[0].gross, carry: totalCarry)
                    pendingCarry = 0
                } else {
                    // Tied / squashed
                    if carriesEnabled {
                        skins[hNum] = .carried  // value moves to next hole
                        pendingCarry += 1
                    } else {
                        skins[hNum] = .squashed(tiedPlayers: winners.map(\.player), bestNet: bestNet, carry: 0)
                        // pendingCarry stays 0 in no-carries mode
                    }
                }
            }
        }

        // Unresolved carries after hole 18: simply unawarded (standard skins rules)
        return skins
    }

    // Money model — flat buy-in
    var pot: Int { config.buyIn * Player.totalPlayers }

    func moneyTotals() -> [Int: Int] {
        let skins = calculateSkins()

        var skinsWon: [Int: Int] = [:]
        allPlayers.forEach { skinsWon[$0.id] = 0 }

        for (_, status) in skins {
            if case .won(let winner, _, _, let carry) = status {
                skinsWon[winner.id, default: 0] += carry
            }
        }

        let totalSkinsAwarded = skins.values.reduce(0) { total, status in
            if case .won(_, _, _, let carry) = status { return total + carry }
            return total
        }

        let openCount = skins.values.reduce(0) { total, status in
            switch status {
            case .pending, .provisional, .carried: return total + 1
            case .won, .squashed: return total
            }
        }

        let estimatedTotalSkins = openCount == 0 ? totalSkinsAwarded : (totalSkinsAwarded + openCount)
        let skinValue = estimatedTotalSkins > 0 ? Double(pot) / Double(estimatedTotalSkins) : 0

        var totals: [Int: Int] = [:]
        allPlayers.forEach { p in
            if totalSkinsAwarded > 0 {
                totals[p.id] = Int((Double(skinsWon[p.id] ?? 0) * skinValue - Double(config.buyIn)).rounded())
            } else {
                totals[p.id] = 0
            }
        }

        return totals
    }

    var skinValue: Double {
        let skins = calculateSkins()
        let totalWon = skins.values.reduce(0) { total, status in
            if case .won(_, _, _, let carry) = status { return total + carry }
            return total
        }
        let stillOpen = skins.values.reduce(0) { total, status in
            switch status {
            case .pending, .provisional, .carried: return total + 1
            default: return total
            }
        }
        let est = stillOpen == 0 ? totalWon : (totalWon + stillOpen)
        return est > 0 ? Double(pot) / Double(est) : 0
    }

    var skinsStillOpen: Int {
        let skins = calculateSkins()
        return skins.values.reduce(0) { total, status in
            switch status {
            case .pending, .provisional, .carried: return total + 1
            default: return total
            }
        }
    }

    // Active hole — first hole where ANY group player hasn't scored
    func computeActiveHole() -> Int? {
        for hole in playOrder {
            if groupPlayers.contains(where: { scores[$0.id]?[hole.num] == nil }) {
                return hole.num
            }
        }
        return nil
    }

    // Can only score holes at or before the active hole in play order
    func canScore(holeNum: Int) -> Bool {
        guard let active = activeHole else { return true }
        guard let activeIdx = playOrder.firstIndex(where: { $0.num == active }),
              let holeIdx = playOrder.firstIndex(where: { $0.num == holeNum }) else { return true }
        return holeIdx <= activeIdx
    }

    // Enter score for any player
    func enterScore(playerId: Int, holeNum: Int, score: Int) {
        scores[playerId, default: [:]][holeNum] = score
        activeHole = computeActiveHole()

        // Check for celebration
        if let hole = Hole.allHoles.first(where: { $0.num == holeNum }),
           let player = allPlayers.first(where: { $0.id == playerId }) {
            let label = ScoreLabel.from(score: score, par: hole.par)
            if label.isMoment {
                celebration = CelebrationEvent(
                    id: UUID(),
                    player: player,
                    hole: holeNum,
                    type: label == .hio ? .hio : label == .eagle ? .eagle : .birdie
                )
            }
        }
    }

    // Section totals
    func frontTotal(for playerId: Int) -> Int {
        Hole.front9.reduce(0) { $0 + (scores[playerId]?[$1.num] ?? 0) }
    }

    func backTotal(for playerId: Int) -> Int {
        Hole.back9.reduce(0) { $0 + (scores[playerId]?[$1.num] ?? 0) }
    }

    func total(for playerId: Int) -> Int {
        frontTotal(for: playerId) + backTotal(for: playerId)
    }

    func hasFrontScores(for playerId: Int) -> Bool {
        Hole.front9.contains { scores[playerId]?[$0.num] != nil }
    }

    func hasBackScores(for playerId: Int) -> Bool {
        Hole.back9.contains { scores[playerId]?[$0.num] != nil }
    }

    // MARK: - Init

    init(config: RoundConfig = .default, currentUserId: Int = 1) {
        self.config = config
        self.currentUserId = currentUserId
        self.allPlayers = Player.allPlayers
        self.holes = Hole.allHoles

        // Start with empty scores for all players
        var s: [Int: [Int: Int]] = [:]
        Player.allPlayers.forEach { s[$0.id] = [:] }

        self.scores = s
        self.activeHole = nil
        // Compute now that all stored properties are initialized
        self.activeHole = computeActiveHole()
    }

    // MARK: - Types

    struct CelebrationEvent: Identifiable {
        let id: UUID
        let player: Player
        let hole: Int
        let type: CelebrationType
    }

    enum CelebrationType {
        case birdie, eagle, hio, skinWon
    }
}
