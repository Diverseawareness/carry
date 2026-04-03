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
    /// Falls back to `Hole.allHoles` defaults for any missing or incomplete data.
    static func fromAPI(_ apiHoles: [GolfCourseHole]) -> [Hole] {
        // Need exactly 18 holes worth of data to be useful
        guard !apiHoles.isEmpty else {
            #if DEBUG
            print("[Hole.fromAPI] No API holes provided, using defaults")
            #endif
            return allHoles
        }

        let defaults = allHoles
        var result: [Hole] = []

        for i in 0..<18 {
            let holeNum = i + 1
            let defaultHole = defaults[i]

            if i < apiHoles.count {
                let apiHole = apiHoles[i]
                let par = apiHole.par ?? defaultHole.par
                let hcp = apiHole.handicap ?? defaultHole.hcp
                result.append(Hole(id: holeNum, num: holeNum, par: par, hcp: hcp))
            } else {
                // API didn't provide this hole — use default
                result.append(defaultHole)
            }
        }

        #if DEBUG
        let apiCount = min(apiHoles.count, 18)
        let withPar = apiHoles.prefix(18).filter { $0.par != nil }.count
        let withHcp = apiHoles.prefix(18).filter { $0.handicap != nil }.count
        print("[Hole.fromAPI] Built \(result.count) holes from API: \(apiCount) provided, \(withPar) with par, \(withHcp) with handicap")
        #endif

        return result
    }
}
