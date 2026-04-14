import Foundation

struct StoryPatternDetector {

    let cachedSkins: [Int: SkinStatus]
    let allPlayers: [Player]
    let moneyTotals: [Int: Int]
    let skinsWonByPlayer: [Int: Int]
    let pot: Int
    let skinValue: Double
    let holes: [Hole]

    // MARK: - Public

    func detectPatterns() -> [StoryPattern] {
        var patterns: [StoryPattern] = []

        let wonHoles = holesWonByPlayer()
        let totalAwarded = totalSkinsAwarded()

        // Always include fillers
        patterns.append(StoryPattern(type: .potSize, value: pot))
        patterns.append(StoryPattern(type: .playerCount, value: allPlayers.count))

        // High priority
        patterns.append(contentsOf: detectBigCarryWins())
        if let streak = detectStreak(wonHoles: wonHoles) { patterns.append(streak) }
        if let comeback = detectComeback(wonHoles: wonHoles) { patterns.append(comeback) }
        if let shutout = detectShutout(totalAwarded: totalAwarded) { patterns.append(shutout) }
        if let sweep = detectSweep(totalAwarded: totalAwarded) { patterns.append(sweep) }
        if let photo = detectPhotoFinish() { patterns.append(photo) }

        // Medium priority
        patterns.append(contentsOf: detectBirdieWins())
        patterns.append(contentsOf: detectUglyWins())
        if let carry = detectCarryStreak() { patterns.append(carry) }
        if let hero = detectBackNineHero(wonHoles: wonHoles) { patterns.append(hero) }
        if let wire = detectWireToWire(wonHoles: wonHoles) { patterns.append(wire) }
        if let first = detectFirstBlood() { patterns.append(first) }
        if let closing = detectClosingKill() { patterns.append(closing) }

        // Low priority
        if let loser = detectBiggestLoser() { patterns.append(loser) }

        return patterns.sorted { $0.type.rawValue > $1.type.rawValue }
    }

    // MARK: - Helpers

    private func holesWonByPlayer() -> [Int: [Int]] {
        var result: [Int: [Int]] = [:]
        for (holeNum, status) in cachedSkins {
            if case .won(let winner, _, _, _) = status {
                result[winner.id, default: []].append(holeNum)
            }
        }
        for key in result.keys {
            result[key]?.sort()
        }
        return result
    }

    private func totalSkinsAwarded() -> Int {
        cachedSkins.values.reduce(0) { total, status in
            if case .won(_, _, _, let carry) = status { return total + carry }
            return total
        }
    }

    private var sortedHoleNums: [Int] {
        holes.map(\.num).sorted()
    }

    private func playerFor(id: Int) -> Player? {
        allPlayers.first { $0.id == id }
    }

    private var holePars: [Int: Int] {
        Dictionary(uniqueKeysWithValues: holes.map { ($0.num, $0.par) })
    }

    /// Returns "eagle", "birdie", "par", "bogey", "double bogey", etc.
    private func scoreLabel(gross: Int, par: Int) -> String {
        let diff = gross - par
        switch diff {
        case ...(-3): return "albatross"
        case -2:      return "eagle"
        case -1:      return "birdie"
        case 0:       return "par"
        case 1:       return "bogey"
        case 2:       return "double bogey"
        default:      return "triple bogey"
        }
    }

    /// Returns "eagled", "birdied", "parred", "bogeyed", etc.
    private func scoreVerb(gross: Int, par: Int) -> String {
        let diff = gross - par
        switch diff {
        case ...(-2): return "eagled"
        case -1:      return "birdied"
        case 0:       return "parred"
        case 1:       return "bogeyed"
        default:      return "double-bogeyed"
        }
    }

    // MARK: - High Priority Detection

    /// Player won a hole with 3+ carried skins
    private func detectBigCarryWins() -> [StoryPattern] {
        let pars = holePars
        var patterns: [StoryPattern] = []
        for (holeNum, status) in cachedSkins {
            if case .won(let winner, _, let bestGross, let carry) = status, carry >= 3 {
                let dollarValue = Int(Double(carry) * skinValue)
                let par = pars[holeNum] ?? 4
                let verb = scoreVerb(gross: bestGross, par: par)
                patterns.append(StoryPattern(
                    type: .bigCarryWin,
                    player: winner,
                    value: carry,
                    holeNum: holeNum,
                    detail: "$\(dollarValue)",
                    detail2: verb
                ))
            }
        }
        return patterns.sorted { $0.value > $1.value }
    }

    /// Player won 3+ skins within a 5-hole sliding window
    private func detectStreak(wonHoles: [Int: [Int]]) -> StoryPattern? {
        let sorted = sortedHoleNums
        guard sorted.count >= 5 else { return nil }

        var bestPlayer: Player?
        var bestCount = 0
        var bestRange: ClosedRange<Int>?

        for (playerId, holes) in wonHoles {
            let holeSet = Set(holes)
            for windowStart in 0...(sorted.count - 5) {
                let window = sorted[windowStart..<(windowStart + 5)]
                let count = window.filter { holeSet.contains($0) }.count
                if count >= 3 && count > bestCount {
                    bestCount = count
                    bestPlayer = playerFor(id: playerId)
                    bestRange = window.first!...window.last!
                }
            }
        }

        guard let player = bestPlayer, let range = bestRange else { return nil }
        return StoryPattern(
            type: .streak,
            player: player,
            value: bestCount,
            holeRange: range
        )
    }

    /// Player was losing at the turn but finished as top earner
    private func detectComeback(wonHoles: [Int: [Int]]) -> StoryPattern? {
        guard allPlayers.count >= 2 else { return nil }

        let frontHoles = Set(sortedHoleNums.filter { $0 <= 9 })
        let finalTotals = moneyTotals

        guard let winnerId = finalTotals.max(by: { $0.value < $1.value })?.key,
              let winner = playerFor(id: winnerId) else { return nil }

        let winnerFrontSkins = (wonHoles[winnerId] ?? []).filter { frontHoles.contains($0) }
        let winnerFrontValue = winnerFrontSkins.reduce(0) { total, holeNum in
            if case .won(_, _, _, let carry) = cachedSkins[holeNum] {
                return total + Int(Double(carry) * skinValue)
            }
            return total
        }

        let buyIn = pot / max(allPlayers.count, 1)
        let frontNet = winnerFrontValue - buyIn
        if frontNet >= 0 { return nil }

        let finalAmount = finalTotals[winnerId] ?? 0
        guard finalAmount > 0 else { return nil }

        return StoryPattern(
            type: .comeback,
            player: winner,
            value: finalAmount,
            detail: "$\(abs(frontNet))"
        )
    }

    /// Only one player won any skins at all
    private func detectShutout(totalAwarded: Int) -> StoryPattern? {
        guard totalAwarded > 0 else { return nil }
        let playersWithSkins = skinsWonByPlayer.filter { $0.value > 0 }
        guard playersWithSkins.count == 1,
              let entry = playersWithSkins.first,
              let player = playerFor(id: entry.key) else { return nil }
        return StoryPattern(type: .shutout, player: player, value: entry.value)
    }

    /// One player won 50%+ of all skins
    private func detectSweep(totalAwarded: Int) -> StoryPattern? {
        guard totalAwarded >= 4 else { return nil }
        for (playerId, count) in skinsWonByPlayer {
            if Double(count) / Double(totalAwarded) >= 0.5,
               let player = playerFor(id: playerId) {
                return StoryPattern(
                    type: .sweep,
                    player: player,
                    value: count,
                    detail: "\(totalAwarded)"
                )
            }
        }
        return nil
    }

    /// Top two players separated by ≤1 skin value
    private func detectPhotoFinish() -> StoryPattern? {
        let sorted = moneyTotals.sorted { $0.value > $1.value }
        guard sorted.count >= 2 else { return nil }

        let diff = sorted[0].value - sorted[1].value
        guard diff >= 0, Double(diff) <= skinValue, diff < pot else { return nil }

        guard let p1 = playerFor(id: sorted[0].key),
              let p2 = playerFor(id: sorted[1].key) else { return nil }

        return StoryPattern(
            type: .photoFinish,
            player: p1,
            secondPlayer: p2,
            value: diff
        )
    }

    // MARK: - Medium Priority Detection

    /// A skin won with a birdie or better — exciting golf moment
    private func detectBirdieWins() -> [StoryPattern] {
        let pars = holePars
        var patterns: [StoryPattern] = []
        for (holeNum, status) in cachedSkins {
            if case .won(let winner, _, let bestGross, let carry) = status {
                let par = pars[holeNum] ?? 4
                if bestGross < par {
                    let label = scoreLabel(gross: bestGross, par: par)
                    let dollarValue = Int(Double(carry) * skinValue)
                    patterns.append(StoryPattern(
                        type: .birdieWin,
                        player: winner,
                        value: dollarValue,
                        holeNum: holeNum,
                        detail: label,
                        detail2: carry > 1 ? "\(carry)x carry" : nil
                    ))
                }
            }
        }
        // Return most valuable first, limit to best 2
        return Array(patterns.sorted { $0.value > $1.value }.prefix(2))
    }

    /// A skin won with a bogey or worse — the "ugly win"
    private func detectUglyWins() -> [StoryPattern] {
        let pars = holePars
        var patterns: [StoryPattern] = []
        for (holeNum, status) in cachedSkins {
            if case .won(let winner, _, let bestGross, _) = status {
                let par = pars[holeNum] ?? 4
                if bestGross > par {
                    let label = scoreLabel(gross: bestGross, par: par)
                    patterns.append(StoryPattern(
                        type: .uglyWin,
                        player: winner,
                        holeNum: holeNum,
                        detail: label
                    ))
                }
            }
        }
        // Return at most 1 (funniest one)
        return Array(patterns.prefix(1))
    }

    /// 3+ consecutive carried/squashed holes
    private func detectCarryStreak() -> StoryPattern? {
        let sorted = sortedHoleNums
        var runStart = 0
        var runLength = 0
        var bestStart = 0
        var bestLength = 0

        for (i, holeNum) in sorted.enumerated() {
            let status = cachedSkins[holeNum]
            let isUndecided: Bool
            switch status {
            case .carried: isUndecided = true
            case .squashed: isUndecided = true
            default: isUndecided = false
            }

            if isUndecided {
                if runLength == 0 { runStart = i }
                runLength += 1
            } else {
                if runLength > bestLength {
                    bestLength = runLength
                    bestStart = runStart
                }
                runLength = 0
            }
        }
        if runLength > bestLength {
            bestLength = runLength
            bestStart = runStart
        }

        guard bestLength >= 3 else { return nil }
        let range = sorted[bestStart]...sorted[bestStart + bestLength - 1]
        return StoryPattern(
            type: .carryStreak,
            value: bestLength,
            holeRange: range
        )
    }

    /// Player won 0-1 skins on front 9, 3+ on back 9
    private func detectBackNineHero(wonHoles: [Int: [Int]]) -> StoryPattern? {
        for (playerId, holes) in wonHoles {
            let front = holes.filter { $0 <= 9 }.count
            let back = holes.filter { $0 > 9 }.count
            if front <= 1 && back >= 3, let player = playerFor(id: playerId) {
                return StoryPattern(
                    type: .backNineHero,
                    player: player,
                    value: back,
                    detail: "\(front)"
                )
            }
        }
        return nil
    }

    /// Player won the first skin AND finished as top earner — led wire-to-wire
    private func detectWireToWire(wonHoles: [Int: [Int]]) -> StoryPattern? {
        // Find who won the first skin
        guard let firstWonHole = sortedHoleNums.first(where: {
            if case .won = cachedSkins[$0] { return true }
            return false
        }) else { return nil }

        guard case .won(let firstWinner, _, _, _) = cachedSkins[firstWonHole] else { return nil }

        // Check if that player also has the most money
        guard let topEarner = moneyTotals.max(by: { $0.value < $1.value }),
              topEarner.key == firstWinner.id,
              topEarner.value > 0 else { return nil }

        // Must have won at least 3 skins (not just one lucky early skin)
        let totalSkins = skinsWonByPlayer[firstWinner.id] ?? 0
        guard totalSkins >= 3 else { return nil }

        return StoryPattern(
            type: .wireToWire,
            player: firstWinner,
            value: topEarner.value
        )
    }

    /// Who won the first skin and on which hole
    private func detectFirstBlood() -> StoryPattern? {
        let pars = holePars
        let sorted = sortedHoleNums
        for holeNum in sorted {
            if case .won(let winner, _, let bestGross, _) = cachedSkins[holeNum] {
                let par = pars[holeNum] ?? 4
                let verb = scoreVerb(gross: bestGross, par: par)
                return StoryPattern(
                    type: .firstBlood,
                    player: winner,
                    holeNum: holeNum,
                    detail: verb
                )
            }
        }
        return nil
    }

    /// Who won the last skin of the day
    private func detectClosingKill() -> StoryPattern? {
        let pars = holePars
        let sorted = sortedHoleNums.reversed()
        for holeNum in sorted {
            if case .won(let winner, _, let bestGross, let carry) = cachedSkins[holeNum] {
                let par = pars[holeNum] ?? 4
                let verb = scoreVerb(gross: bestGross, par: par)
                return StoryPattern(
                    type: .closingKill,
                    player: winner,
                    value: carry,
                    holeNum: holeNum,
                    detail: verb
                )
            }
        }
        return nil
    }

    /// Player who lost the most money
    private func detectBiggestLoser() -> StoryPattern? {
        guard let loserEntry = moneyTotals.min(by: { $0.value < $1.value }),
              loserEntry.value < 0,
              let player = playerFor(id: loserEntry.key) else { return nil }
        return StoryPattern(
            type: .biggestLoser,
            player: player,
            value: abs(loserEntry.value)
        )
    }
}
