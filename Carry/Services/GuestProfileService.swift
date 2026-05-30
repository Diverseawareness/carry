import Foundation
import Supabase

class GuestProfileService {
    private let client = SupabaseManager.shared.client

    /// Batch-create guest profiles via Supabase RPC. Returns array of profile UUIDs.
    ///
    /// Stable-UUID architecture (1.1.2): callers pass `ids` (client-minted UUIDs)
    /// so the server uses THOSE ids rather than minting fresh ones via
    /// gen_random_uuid(). This is the load-bearing change that keeps a guest's
    /// identity stable across delete_quick_game_guests + recreate cycles — every
    /// re-creation reuses the same UUID, so iOS Player.profileId never diverges
    /// from server state. Without `ids`, the RPC falls back to gen_random_uuid()
    /// for back-compat (any legacy callers keep working).
    ///
    /// Migration: `supabase/migrations/20260530000000_guest_profiles_client_supplied_uuid.sql`
    /// — adds `p_ids uuid[]` with `ON CONFLICT (id) DO NOTHING` to absorb the
    /// case where the SAME id arrives twice (race during restart cycles).
    func createGuestProfiles(ids: [UUID]? = nil, names: [String], initials: [String], handicaps: [Double], colors: [String], creatorId: UUID? = nil) async throws -> [UUID] {
        var params: [String: AnyJSON] = [
            "p_names": .array(names.map { .string($0) }),
            "p_initials": .array(initials.map { .string($0) }),
            "p_handicaps": .array(handicaps.map { .double($0) }),
            "p_colors": .array(colors.map { .string($0) })
        ]
        if let creatorId = creatorId {
            params["p_creator_id"] = .string(creatorId.uuidString)
        }
        if let ids = ids {
            // Pass as string array; the server casts to uuid[]. Same encoding
            // pattern as the other UUID params on this RPC. Length validated
            // by the server loop (array_length(p_ids,1) >= i).
            params["p_ids"] = .array(ids.map { .string($0.uuidString) })
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

    /// Update a guest profile's name / handicap. RLS forbids the creator from
    /// directly UPDATEing a guest's profile row (`auth.uid() = id` check),
    /// so we route through a SECURITY DEFINER RPC that re-checks
    /// `created_by = auth.uid()`. See migration
    /// 20260510000001_update_guest_profile_handicap.sql.
    ///
    /// Pass nil for fields not being updated. Without this call, guest
    /// edits in PlayerGroupsSheet only mutated local @State + the
    /// guest_roster_json snapshot — never `profiles.display_name` /
    /// `profiles.handicap`. The next refresh stomped the local edit with
    /// stale server state. Skins payouts are handicap-weighted, so silent
    /// reversion of handicap = wrong winnings.
    ///
    /// Initials are auto-derived server-side from displayName when
    /// displayName is non-nil (matches Player.initials convention).
    func updateGuestProfile(profileId: UUID, displayName: String? = nil, handicap: Double? = nil) async throws {
        var params: [String: AnyJSON] = [
            "p_profile_id": .string(profileId.uuidString)
        ]
        if let displayName { params["p_display_name"] = .string(displayName) }
        if let handicap { params["p_handicap"] = .double(handicap) }
        _ = try await client.rpc("update_guest_profile", params: params).execute()
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
