import Foundation

/// Persists round scores to UserDefaults.
/// Scores are keyed by round config ID so each round's scores are independent.
class ScoreStorage {
    static let shared = ScoreStorage()
    private let prefix = "carry.scores."

    /// Save scores for a round. Converts [Int: [Int: Int]] to string-keyed JSON.
    func save(scores: [Int: [Int: Int]], forKey roundKey: String) {
        var encoded: [String: [String: Int]] = [:]
        for (playerId, holes) in scores {
            var holeMap: [String: Int] = [:]
            for (hole, score) in holes {
                holeMap[String(hole)] = score
            }
            encoded[String(playerId)] = holeMap
        }
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: prefix + roundKey)
        }
    }

    /// Load scores for a round. Returns nil if no saved data exists.
    func load(forKey roundKey: String) -> [Int: [Int: Int]]? {
        guard let data = UserDefaults.standard.data(forKey: prefix + roundKey),
              let encoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data)
        else { return nil }

        var result: [Int: [Int: Int]] = [:]
        for (playerStr, holes) in encoded {
            guard let playerId = Int(playerStr) else { continue }
            var holeMap: [Int: Int] = [:]
            for (holeStr, score) in holes {
                guard let hole = Int(holeStr) else { continue }
                holeMap[hole] = score
            }
            result[playerId] = holeMap
        }
        return result
    }

    /// Remove saved scores for a completed round.
    func clear(forKey roundKey: String) {
        UserDefaults.standard.removeObject(forKey: prefix + roundKey)
    }
}
