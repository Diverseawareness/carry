import Foundation

/// Lightweight Codable summary of a SavedGroup for UserDefaults persistence.
/// Avoids making Player, SelectedCourse, HomeRound conform to Codable.
struct SavedGroupSummary: Codable, Identifiable {
    let id: UUID
    let name: String
    let memberIds: [Int]
    let creatorId: Int
    var potSize: Double
    var buyInPerPlayer: Double
    var lastCourseName: String?
    var lastCourseClubName: String?
    var scheduledDate: Date?
    var recurrence: GameRecurrence?
}

/// Persists skins groups to UserDefaults as lightweight summaries.
class GroupStorage {
    static let shared = GroupStorage()
    private let key = "carry.savedGroups"

    func save(_ groups: [SavedGroup]) {
        let summaries = groups.map { g in
            SavedGroupSummary(
                id: g.id,
                name: g.name,
                memberIds: g.members.map(\.id),
                creatorId: g.creatorId,
                potSize: g.potSize,
                buyInPerPlayer: g.buyInPerPlayer,
                lastCourseName: g.lastCourse?.courseName,
                lastCourseClubName: g.lastCourse?.clubName,
                scheduledDate: g.scheduledDate,
                recurrence: g.recurrence
            )
        }
        if let data = try? JSONEncoder().encode(summaries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() -> [SavedGroupSummary] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let summaries = try? JSONDecoder().decode([SavedGroupSummary].self, from: data)
        else { return [] }
        return summaries
    }

    func hydrate(_ summaries: [SavedGroupSummary]) -> [SavedGroup] {
        summaries.map { s in
            let members = s.memberIds.compactMap { id in
                Player.allPlayers.first(where: { $0.id == id })
            }
            // Reconstruct a minimal SelectedCourse if we have a name
            var lastCourse: SelectedCourse? = nil
            if let courseName = s.lastCourseName {
                lastCourse = SelectedCourse(
                    courseId: 0,
                    courseName: courseName,
                    clubName: s.lastCourseClubName ?? courseName,
                    location: "",
                    teeBox: nil,
                    apiTee: nil
                )
            }
            return SavedGroup(
                id: s.id,
                name: s.name,
                members: members,
                lastPlayed: nil,
                creatorId: s.creatorId,
                lastCourse: lastCourse,
                potSize: s.potSize,
                buyInPerPlayer: s.buyInPerPlayer,
                scheduledDate: s.scheduledDate,
                recurrence: s.recurrence
            )
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
