import Foundation
import Supabase

class GuestProfileService {
    private let client = SupabaseManager.shared.client

    /// Batch-create guest profiles via Supabase RPC. Returns array of new profile UUIDs.
    func createGuestProfiles(names: [String], initials: [String], handicaps: [Double], colors: [String], creatorId: UUID? = nil) async throws -> [UUID] {
        var params: [String: AnyJSON] = [
            "p_names": .array(names.map { .string($0) }),
            "p_initials": .array(initials.map { .string($0) }),
            "p_handicaps": .array(handicaps.map { .double($0) }),
            "p_colors": .array(colors.map { .string($0) })
        ]
        if let creatorId = creatorId {
            params["p_creator_id"] = .string(creatorId.uuidString)
        }

        // Try direct UUID decode first; fall back to String decode if needed
        do {
            let uuids: [UUID] = try await client.rpc("create_guest_profiles", params: params).execute().value
            return uuids
        } catch {
            #if DEBUG
            print("[GuestProfileService] UUID decode failed, trying String fallback: \(error)")
            #endif
            let strings: [String] = try await client.rpc("create_guest_profiles", params: params).execute().value
            return strings.compactMap { UUID(uuidString: $0) }
        }
    }

    /// Wipe all guest profiles tied to this Quick Game round. Called on every
    /// Quick Game termination path (skip / save / end / force-end / convert).
    /// Server-side denormalizes display_name + handicap onto round_players and
    /// scores BEFORE deleting the profile, so Round History keeps rendering
    /// the original guest names. See migration 20260501000001 for full spec.
    @discardableResult
    func deleteQuickGameGuests(roundId: UUID) async throws -> Int {
        let count: Int = try await client.rpc(
            "delete_quick_game_guests",
            params: ["p_round_id": AnyJSON.string(roundId.uuidString)]
        ).execute().value
        return count
    }
}
