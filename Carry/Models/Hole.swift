import Foundation

struct Hole: Identifiable, Hashable, Codable {
    let id: Int
    let num: Int
    let par: Int
    let hcp: Int  // handicap index for stroke allocation

    static let front9: [Hole] = [
        Hole(id: 1, num: 1, par: 4, hcp: 7),
        Hole(id: 2, num: 2, par: 4, hcp: 13),
        Hole(id: 3, num: 3, par: 5, hcp: 3),
        Hole(id: 4, num: 4, par: 3, hcp: 9),
        Hole(id: 5, num: 5, par: 4, hcp: 1),
        Hole(id: 6, num: 6, par: 3, hcp: 15),
        Hole(id: 7, num: 7, par: 4, hcp: 5),
        Hole(id: 8, num: 8, par: 3, hcp: 11),
        Hole(id: 9, num: 9, par: 4, hcp: 17),
    ]

    static let back9: [Hole] = [
        Hole(id: 10, num: 10, par: 5, hcp: 8),
        Hole(id: 11, num: 11, par: 4, hcp: 14),
        Hole(id: 12, num: 12, par: 4, hcp: 4),
        Hole(id: 13, num: 13, par: 4, hcp: 10),
        Hole(id: 14, num: 14, par: 4, hcp: 2),
        Hole(id: 15, num: 15, par: 3, hcp: 16),
        Hole(id: 16, num: 16, par: 4, hcp: 6),
        Hole(id: 17, num: 17, par: 3, hcp: 12),
        Hole(id: 18, num: 18, par: 5, hcp: 18),
    ]

    static let allHoles: [Hole] = front9 + back9

    static let frontPar: Int = front9.reduce(0) { $0 + $1.par }
    static let backPar: Int = back9.reduce(0) { $0 + $1.par }
    static let totalPar: Int = frontPar + backPar

    // MARK: - Build holes from Golf Course API data

    /// Convert API hole data to 18 `Hole` objects.
    /// STRICT: every par must be present and > 0. Refuses (returns []) if any par is missing,
    /// any par is 0, or fewer than 18 holes were provided. Output is always 18 holes numbered 1-18.
    /// (The API doesn't always return holes in order — par values are taken positionally from
    /// the first 18 entries, since the API has no `num` field per hole.)
    static func fromAPI(_ apiHoles: [GolfCourseHole]) -> [Hole] {
        guard apiHoles.count >= 18 else {
            #if DEBUG
            print("[Hole.fromAPI] ❌ Only \(apiHoles.count) holes from API — refusing to build (need 18)")
            #endif
            return []
        }
        // Validate first 18: every par non-nil AND > 0
        let first18 = Array(apiHoles.prefix(18))
        let allValid = first18.allSatisfy { hole in
            guard let par = hole.par, par > 0 else { return false }
            return true
        }
        guard allValid else {
            #if DEBUG
            let missing = first18.enumerated().compactMap { (i, h) -> Int? in
                (h.par == nil || h.par == 0) ? (i + 1) : nil
            }
            print("[Hole.fromAPI] ❌ Holes with missing/zero par: \(missing) — refusing to build")
            #endif
            return []
        }
        var result: [Hole] = []
        for i in 0..<18 {
            let holeNum = i + 1
            let apiHole = first18[i]
            let par = apiHole.par!
            let hcp = apiHole.handicap ?? holeNum
            result.append(Hole(id: holeNum, num: holeNum, par: par, hcp: hcp))
        }
        #if DEBUG
        print("[Hole.fromAPI] ✅ Built 18 holes from API")
        #endif
        return result
    }
}
