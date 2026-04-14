import Foundation
import Supabase

final class PlayerSearchService {
    static let shared = PlayerSearchService()
    private let client = SupabaseManager.shared.client

    private init() {}

    /// Search Carry users by username or display name via Supabase.
    func searchPlayers(query: String) async throws -> [ProfileDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.count >= 2 else { return [] }

        // Search by username prefix (exclude guest profiles)
        let byUsername: [ProfileDTO] = try await client.from("profiles")
            .select()
            .ilike("username", pattern: "\(trimmed)%")
            .neq("is_guest", value: true)
            .limit(10)
            .execute()
            .value

        // Search by display name prefix or last name prefix (exclude guest profiles)
        let byName: [ProfileDTO] = try await client.from("profiles")
            .select()
            .or("display_name.ilike.\(trimmed)%,last_name.ilike.\(trimmed)%")
            .neq("is_guest", value: true)
            .limit(10)
            .execute()
            .value

        // Merge and deduplicate
        var seen = Set<UUID>()
        var results: [ProfileDTO] = []
        for profile in byUsername + byName {
            if seen.insert(profile.id).inserted {
                results.append(profile)
            }
        }
        return results
    }

    // MARK: - Demo / Offline

    #if DEBUG
    // Demo last names and clubs keyed by player name
    private static let demoExtras: [String: (last: String, club: String)] = [
        "Daniel":      ("Sigvardsson", "Torrey Pines"),
        "Garret":      ("Baker",       "Riverwalk Golf Club"),
        "Adi":         ("Raman",       "Torrey Pines"),
        "Bartholomew": ("Smith",       "Balboa Park"),
        "Keith":       ("Brooks",      "Maderas Golf Club"),
        "Tyson":       ("Bell",        "The Grand Golf Club"),
        "Ryan":        ("Scott",       "Coronado Golf Course"),
        "AJ":          ("Johnson",     "Torrey Pines"),
        "Ronnie":      ("Barrera",     "Steele Canyon"),
        "Cameron":     ("Mitchell",    "Carlton Oaks"),
        "Jai":         ("Desai",       "Encinitas Ranch"),
        "Frank":       ("Morales",     "Salt Creek Golf Club"),
        "Marcus":      ("Lee",         "Rancho Bernardo Inn"),
        "Jay":         ("Vasquez",     "Aviara Golf Club"),
        "Stefano":     ("Ricci",       "The Farms Golf Club"),
        "Abraham":     ("Park",        "Mt. Woodson Golf Club"),
    ]

    static let demoProfiles: [ProfileDTO] = Player.allPlayers.map { player in
        let extras = demoExtras[player.name]
        return ProfileDTO(
            id: UUID(),
            firstName: player.name,
            lastName: extras?.last ?? "",
            username: player.name.lowercased(),
            displayName: "\(player.name) \(extras?.last ?? "")",
            initials: player.initials,
            color: player.color,
            avatar: player.avatar,
            handicap: player.handicap,
            ghinNumber: player.ghinNumber,
            homeClub: extras?.club,
            homeClubId: nil,
            email: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }
    #endif

    /// Offline search against demo data when Supabase is unavailable.
    func searchPlayersOffline(query: String) -> [ProfileDTO] {
        #if DEBUG
        let q = query.lowercased()
        guard q.count >= 2 else { return [] }
        return Self.demoProfiles.filter {
            ($0.username ?? "").hasPrefix(q) ||
            $0.displayName.lowercased().contains(q) ||
            $0.firstName.lowercased().hasPrefix(q) ||
            $0.lastName.lowercased().hasPrefix(q)
        }
        #else
        return []
        #endif
    }
}
