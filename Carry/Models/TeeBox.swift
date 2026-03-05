import Foundation

/// Represents a set of tees at a golf course (e.g., Blue, White, Gold).
/// Each tee box has its own Course Rating and Slope Rating, which determine
/// how many strokes a player receives using the USGA Course Handicap formula:
///
///   Course Handicap = Handicap Index x (Slope Rating / 113) + (Course Rating - Par)
///
struct TeeBox: Identifiable, Hashable {
    let id: String  // UUID string or local ID
    let courseId: String
    let name: String  // e.g. "Blue", "White", "Gold", "Red"
    let color: String  // hex color for UI display
    let courseRating: Double  // e.g. 72.1
    let slopeRating: Int  // e.g. 131 (range: 55-155)
    let par: Int  // total par from these tees (may differ by tee)

    /// Compute the Course Handicap for a player from these tees.
    /// Formula: Handicap Index x (Slope Rating / 113) + (Course Rating - Par)
    func courseHandicap(forIndex handicapIndex: Double) -> Int {
        let raw = handicapIndex * (Double(slopeRating) / 113.0) + (courseRating - Double(par))
        return Int(raw.rounded())
    }

    /// Compute the Playing Handicap (Course Handicap adjusted by percentage).
    /// Common percentages: 100% (full), 80%, 70%
    func playingHandicap(forIndex handicapIndex: Double, percentage: Double = 1.0) -> Int {
        let courseHcp = courseHandicap(forIndex: handicapIndex)
        return Int((Double(courseHcp) * percentage).rounded())
    }

    /// USGA stroke allocation for a specific hole.
    /// Distributes `playingHandicap` strokes across 18 holes by hole difficulty (hcp ranking).
    static func strokesOnHole(playingHandicap: Int, holeHcp: Int) -> Int {
        if playingHandicap <= 0 { return 0 }
        // Full rounds of strokes (everyone gets this many on every hole)
        let fullRounds = playingHandicap / 18
        // Remaining strokes go to the hardest holes (lowest hcp numbers)
        let remainder = playingHandicap % 18
        let bonus = holeHcp <= remainder ? 1 : 0
        return fullRounds + bonus
    }

    // Demo tee boxes for Blackhawk CC
    static let demo: [TeeBox] = [
        TeeBox(id: "t1", courseId: "c1", name: "Black", color: "#1A1A1A",
               courseRating: 73.8, slopeRating: 142, par: 72),
        TeeBox(id: "t2", courseId: "c1", name: "Blue", color: "#2563EB",
               courseRating: 71.5, slopeRating: 134, par: 72),
        TeeBox(id: "t3", courseId: "c1", name: "White", color: "#F5F5F5",
               courseRating: 69.2, slopeRating: 126, par: 72),
        TeeBox(id: "t4", courseId: "c1", name: "Gold", color: "#D4A017",
               courseRating: 66.8, slopeRating: 117, par: 72),
        TeeBox(id: "t5", courseId: "c1", name: "Red", color: "#E05555",
               courseRating: 64.1, slopeRating: 110, par: 72),
    ]
}
