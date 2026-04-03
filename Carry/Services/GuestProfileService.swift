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

    /// Claim a guest profile — merges scores, round history, and group membership into the real user.
    func claimGuestProfile(guestId: UUID, realUserId: UUID, groupId: UUID) async throws {
        try await client.rpc("claim_guest_profile", params: [
            "p_guest_id": AnyJSON.string(guestId.uuidString),
            "p_real_id": AnyJSON.string(realUserId.uuidString),
            "p_group_id": AnyJSON.string(groupId.uuidString)
        ]).execute()
    }

    /// Fetch guest profiles created by this user (for re-use in future Quick Start games).
    func fetchMyGuests(createdBy: UUID) async throws -> [ProfileDTO] {
        let guests: [ProfileDTO] = try await client.from("profiles")
            .select()
            .eq("is_guest", value: true)
            .eq("created_by", value: createdBy.uuidString)
            .execute()
            .value
        return guests
    }
}
