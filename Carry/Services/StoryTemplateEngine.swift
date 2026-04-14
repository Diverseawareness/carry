import Foundation

// MARK: - Seeded Random

struct SeededRandom {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed)) &+ 1
    }

    mutating func next() -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int(state >> 33)
    }

    mutating func pick<T>(_ array: [T]) -> T {
        array[abs(next()) % array.count]
    }
}

// MARK: - Template Engine

struct StoryTemplateEngine {

    func generateStory(patterns: [StoryPattern], seed: Int) -> RoundStory {
        var rng = SeededRandom(seed: seed)
        var sentences: [String] = []
        var usedTypes: Set<Int> = []

        let high = patterns.filter { $0.type.isHighPriority }
        let medium = patterns.filter { $0.type.isMediumPriority }
        let low = patterns.filter { $0.type.isLowPriority }

        // 1. Opener (always)
        if let opener = low.first(where: { $0.type == .potSize }) {
            let count = patterns.first(where: { $0.type == .playerCount })?.value ?? 0
            sentences.append(renderOpener(opener, playerCount: count, rng: &rng))
        }

        // 2. Headlines (1-2 high-priority)
        for pattern in high.prefix(2) {
            guard !usedTypes.contains(pattern.type.rawValue) else { continue }
            sentences.append(render(pattern, rng: &rng))
            usedTypes.insert(pattern.type.rawValue)
        }

        // 3. Color (fill to 5 sentences with medium-priority)
        let colorSlots = max(0, 5 - sentences.count - 1) // leave room for closer
        for pattern in medium.prefix(colorSlots) {
            guard !usedTypes.contains(pattern.type.rawValue) else { continue }
            sentences.append(render(pattern, rng: &rng))
            usedTypes.insert(pattern.type.rawValue)
        }

        // 4. Closer
        if let photo = high.first(where: { $0.type == .photoFinish }),
           !usedTypes.contains(PatternType.photoFinish.rawValue) {
            sentences.append(render(photo, rng: &rng))
        } else if let loser = low.first(where: { $0.type == .biggestLoser }) {
            sentences.append(render(loser, rng: &rng))
        } else if let closing = medium.first(where: { $0.type == .closingKill }),
                  !usedTypes.contains(PatternType.closingKill.rawValue) {
            sentences.append(render(closing, rng: &rng))
        } else {
            sentences.append(rng.pick(genericClosers))
        }

        // Cap at 6
        let capped = Array(sentences.prefix(6))
        return RoundStory(sentences: capped, patterns: patterns)
    }

    // MARK: - Rendering

    private func renderOpener(_ pattern: StoryPattern, playerCount: Int, rng: inout SeededRandom) -> String {
        let pot = pattern.value
        let skinVal = pot > 0 && playerCount > 0 ? "$\(pot / max(playerCount, 1))" : "$0"
        let templates = [
            "\(playerCount) players. $\(pot) pot. \(skinVal) per skin. Let's go.",
            "$\(pot) on the line today with \(playerCount) players hunting skins.",
            "\(playerCount) players put up $\(pot) and went after it.",
            "$\(pot) pot, \(playerCount) players, and 18 holes to sort it out.",
            "The group threw in $\(pot) and teed it up. Here's what happened.",
        ]
        return rng.pick(templates)
    }

    private func render(_ pattern: StoryPattern, rng: inout SeededRandom) -> String {
        let name = firstName(pattern.player)
        let name2 = firstName(pattern.secondPlayer)

        switch pattern.type {

        // MARK: High Priority

        case .bigCarryWin:
            let verb = pattern.detail2 ?? "won"
            let templates = [
                "\(name) \(verb) Hole \(pattern.holeNum) to collect \(pattern.value) carried skins — \(pattern.detail ?? "$0") on a single hole.",
                "Hole \(pattern.holeNum) was the jackpot. \(name) \(verb) it and swept \(pattern.value) carries for \(pattern.detail ?? "$0").",
                "\(pattern.value) skins had been piling up. \(name) finally broke through on Hole \(pattern.holeNum) with a \(pattern.detail2 ?? "win") and took \(pattern.detail ?? "$0").",
                "The pressure built for \(pattern.value) holes. \(name) \(verb) \(pattern.holeNum) and cashed in \(pattern.detail ?? "$0").",
                "Everyone was watching Hole \(pattern.holeNum). \(name) \(verb) it and collected \(pattern.value) skins worth \(pattern.detail ?? "$0").",
            ]
            return rng.pick(templates)

        case .streak:
            let range = pattern.holeRange
            let start = range?.lowerBound ?? 0
            let end = range?.upperBound ?? 0
            let templates = [
                "\(name) went on a tear — \(pattern.value) skins between Holes \(start) and \(end).",
                "Holes \(start) through \(end) belonged to \(name). \(pattern.value) skins, no arguments.",
                "\(name) caught fire and rattled off \(pattern.value) skins in a \(end - start + 1)-hole stretch.",
                "Nobody could stop \(name) from \(start) to \(end) — \(pattern.value) skins in that run.",
                "From Hole \(start) to \(end), \(name) was untouchable. \(pattern.value) skins.",
            ]
            return rng.pick(templates)

        case .comeback:
            let templates = [
                "\(name) was down \(pattern.detail ?? "") at the turn but stormed back to finish with $\(pattern.value).",
                "Write off \(name) at your own risk — down early, walked away with $\(pattern.value).",
                "\(name) flipped the script on the back nine. Down at the turn, finished up $\(pattern.value).",
                "Back nine \(name) was a different player. Erased a \(pattern.detail ?? "") hole and won $\(pattern.value).",
                "It looked rough at the turn for \(name). Didn't matter — finished with $\(pattern.value) in pocket.",
            ]
            return rng.pick(templates)

        case .shutout:
            let templates = [
                "\(name) took every skin. Nobody else got on the board.",
                "Complete shutout — \(name) owned the entire round, all \(pattern.value) skins.",
                "\(name) won all \(pattern.value) skins. The rest were just making donations.",
                "Total domination by \(name). \(pattern.value) skins, zero for everyone else.",
            ]
            return rng.pick(templates)

        case .sweep:
            let total = pattern.detail ?? "0"
            let templates = [
                "\(name) won \(pattern.value) of \(total) skins. Hard to do much about that.",
                "Over half the skins went to \(name) — \(pattern.value) out of \(total).",
                "\(name) took \(pattern.value) of \(total) available skins. Dominant.",
                "\(pattern.value) out of \(total) skins had \(name)'s name on them.",
            ]
            return rng.pick(templates)

        case .photoFinish:
            if pattern.value == 0 {
                let templates = [
                    "Dead even at the top. \(name) and \(name2) finished tied.",
                    "\(name) and \(name2) couldn't be separated — exact same number.",
                    "You can't get closer than that. \(name) and \(name2) tied.",
                ]
                return rng.pick(templates)
            } else {
                let templates = [
                    "It came down to $\(pattern.value) between \(name) and \(name2).",
                    "\(name) edged out \(name2) by just $\(pattern.value). One skin was the difference.",
                    "Tight at the top — only $\(pattern.value) separated \(name) from \(name2).",
                    "\(name) and \(name2) battled all day. \(name) won by $\(pattern.value).",
                ]
                return rng.pick(templates)
            }

        // MARK: Medium Priority

        case .birdieWin:
            let score = pattern.detail ?? "birdie"
            if let carry = pattern.detail2 {
                let templates = [
                    "\(name) made \(score) on Hole \(pattern.holeNum) to grab a \(carry) worth \(pattern.value > 0 ? "$\(pattern.value)" : "a skin").",
                    "A \(score) on \(pattern.holeNum) from \(name) — and it came with a \(carry).",
                ]
                return rng.pick(templates)
            } else {
                let templates = [
                    "\(name) \(score == "eagle" ? "eagled" : "birdied") Hole \(pattern.holeNum) to take the skin.",
                    "Clean \(score) from \(name) on Hole \(pattern.holeNum) — that's how you win a skin.",
                    "\(name) made \(score) on \(pattern.holeNum). Nobody could match it.",
                ]
                return rng.pick(templates)
            }

        case .uglyWin:
            let score = pattern.detail ?? "bogey"
            let templates = [
                "\(name) won Hole \(pattern.holeNum) with a \(score). Sometimes ugly is good enough.",
                "Hole \(pattern.holeNum) wasn't pretty — \(name) won it with a \(score).",
                "A \(score) won the skin on Hole \(pattern.holeNum). \(name) will take it.",
                "Not every skin is earned with a birdie. \(name) ground one out with a \(score) on \(pattern.holeNum).",
                "\(name) won Hole \(pattern.holeNum) with a \(score). Hey, a skin is a skin.",
            ]
            return rng.pick(templates)

        case .carryStreak:
            let range = pattern.holeRange
            let start = range?.lowerBound ?? 0
            let end = range?.upperBound ?? 0
            let templates = [
                "Nobody could separate themselves for \(pattern.value) straight holes. The pot kept building.",
                "Holes \(start) through \(end) were a dead heat — \(pattern.value) carries in a row.",
                "\(pattern.value) consecutive ties from Hole \(start) to \(end). Tension was thick.",
                "The skins stacked up through \(pattern.value) ties. Everyone was watching the next one.",
            ]
            return rng.pick(templates)

        case .backNineHero:
            let front = pattern.detail ?? "0"
            let templates = [
                "\(name) was quiet on the front (\(front) skin\(front == "1" ? "" : "s")) then exploded with \(pattern.value) on the back.",
                "The back nine belonged to \(name) — \(pattern.value) skins after a slow start.",
                "\(name) woke up on the back nine. \(pattern.value) skins after just \(front) on the front.",
                "Slow start for \(name), then \(pattern.value) skins on the back. Timing is everything.",
            ]
            return rng.pick(templates)

        case .wireToWire:
            let templates = [
                "\(name) led from start to finish. Won the first skin and never looked back — $\(pattern.value).",
                "Wire to wire for \(name). Took the first skin, took the last check. $\(pattern.value).",
                "\(name) set the tone early and rode it all day. $\(pattern.value) at the finish.",
            ]
            return rng.pick(templates)

        case .firstBlood:
            let verb = pattern.detail ?? "won"
            let templates = [
                "\(name) drew first blood — \(verb) Hole \(pattern.holeNum) to open the scoring.",
                "\(name) \(verb) Hole \(pattern.holeNum) for the first skin of the day.",
                "First skin went to \(name) on Hole \(pattern.holeNum) with a \(pattern.detail ?? "win").",
                "It took until Hole \(pattern.holeNum) for someone to break through. \(name) \(verb) it.",
            ]
            return rng.pick(templates)

        case .closingKill:
            let verb = pattern.detail ?? "won"
            if pattern.value > 1 {
                let templates = [
                    "\(name) \(verb) Hole \(pattern.holeNum) to close it out — a \(pattern.value)x carry to end the day.",
                    "Last skin of the round: \(name) on Hole \(pattern.holeNum), worth \(pattern.value) skins.",
                    "\(name) \(verb) \(pattern.holeNum) for the final skin — and it was a \(pattern.value)x carry.",
                ]
                return rng.pick(templates)
            } else {
                let templates = [
                    "\(name) \(verb) Hole \(pattern.holeNum) for the last skin of the day.",
                    "Final skin: \(name) on \(pattern.holeNum).",
                    "\(name) closed it out with a \(pattern.detail ?? "win") on \(pattern.holeNum).",
                ]
                return rng.pick(templates)
            }

        // MARK: Low Priority

        case .biggestLoser:
            let templates = [
                "\(name) donated $\(pattern.value) to the group today. Generous.",
                "Tough day for \(name) — down $\(pattern.value). The course will be there next week.",
                "\(name) left $\(pattern.value) on the table. Fuel for the comeback.",
            ]
            return rng.pick(templates)

        case .potSize, .playerCount:
            return "" // handled by renderOpener
        }
    }

    // MARK: - Helpers

    private func firstName(_ player: Player?) -> String {
        guard let player = player else { return "Someone" }
        return String(player.name.split(separator: " ").first ?? Substring(player.name))
    }

    private let genericClosers = [
        "Another round in the books.",
        "That's a wrap. Same time next week?",
        "Settle up and see you on the first tee.",
        "18 holes down. Time to settle up.",
    ]
}
