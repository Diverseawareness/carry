import SwiftUI

class RoundViewModel: ObservableObject {
    @Published var scores: [Int: [Int: Int?]]  // [playerID: [holeNum: score]]
    @Published var activeHole: Int? = 5
    @Published var celebration: CelebrationEvent? = nil

    let players: [Player]
    let holes: [Hole]
    let skinValue: Int = 5

    init(players: [Player] = Player.samples, holes: [Hole] = Hole.front9) {
        self.players = players
        self.holes = holes

        // Pre-fill first 4 holes for demo
        var initial: [Int: [Int: Int?]] = [:]
        let demoScores: [Int: [Int: Int?]] = [
            1: [1: 4, 2: 5, 3: 4, 4: 4],
            2: [1: 5, 2: 3, 3: 5, 4: 5],
            3: [1: 4, 2: 4, 3: 6, 4: 4],
            4: [1: 6, 2: 3, 3: 5, 4: 3],
        ]
        for player in players {
            var playerScores: [Int: Int?] = [:]
            for hole in holes {
                playerScores[hole.num] = demoScores[player.id]?[hole.num] ?? nil
            }
            initial[player.id] = playerScores
        }
        self.scores = initial
    }

    // MARK: - Stroke Calculation

    func strokes(for player: Player, hole: Hole) -> Int {
        Int(player.handicap / 18) + (hole.hcp <= player.handicap % 18 ? 1 : 0)
    }

    func netScore(gross: Int, player: Player, hole: Hole) -> Int {
        gross - strokes(for: player, hole: hole)
    }

    // MARK: - Skins Calculation

    func calculateSkins() -> [Int: SkinResult] {
        var results: [Int: SkinResult] = [:]
        var currentValue = skinValue
        var carryCount = 0

        for hole in holes {
            let nets: [(player: Player, net: Int)] = players.compactMap { p in
                guard let score = scores[p.id]?[hole.num], let s = score else { return nil }
                return (p, netScore(gross: s, player: p, hole: hole))
            }

            if nets.count < players.count {
                let minNet = nets.map(\.net).min()
                let leaders = nets.filter { $0.net == minNet }.map(\.player)
                results[hole.num] = SkinResult(
                    status: .pending(leaders: leaders),
                    value: currentValue,
                    carryCount: carryCount
                )
                continue
            }

            let minNet = nets.map(\.net).min()!
            let winners = nets.filter { $0.net == minNet }

            if winners.count == 1 {
                results[hole.num] = SkinResult(
                    status: .won(winner: winners[0].player),
                    value: currentValue,
                    carryCount: carryCount
                )
                currentValue = skinValue
                carryCount = 0
            } else {
                results[hole.num] = SkinResult(
                    status: .carry,
                    value: currentValue,
                    carryCount: carryCount
                )
                currentValue += skinValue
                carryCount += 1
            }
        }

        return results
    }

    // MARK: - Money Totals

    func moneyTotals() -> [Int: Int] {
        let skins = calculateSkins()
        var totals: [Int: Int] = [:]
        for p in players { totals[p.id] = 0 }

        for (_, skin) in skins {
            if case .won(let winner) = skin.status {
                for p in players {
                    if p.id == winner.id {
                        totals[p.id]! += skin.value * (players.count - 1)
                    } else {
                        totals[p.id]! -= skin.value
                    }
                }
            }
        }
        return totals
    }

    // MARK: - Score Entry

    func enterScore(_ score: Int, forHole hole: Int) {
        scores[1]?[hole] = score

        // Random scores for other players (demo)
        let par = holes.first { $0.num == hole }?.par ?? 4
        let offsets = [-1, 0, 0, 0, 1, 1, 2]
        for pid in 2...4 {
            scores[pid]?[hole] = par + offsets.randomElement()!
        }

        // Advance active hole
        activeHole = holes.first { h in scores[1]?[h.num] == nil }?.num

        objectWillChange.send()
    }
}

// MARK: - Celebration

struct CelebrationEvent: Identifiable {
    let id = UUID()
    let type: CelebrationType
    let player: Player
    let value: Int
}

enum CelebrationType {
    case birdie, eagle, hio, skinWon, carry
}
