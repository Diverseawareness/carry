import Foundation
import Supabase

final class GroupService {
    private let client = SupabaseManager.shared.client
    private let roundService = RoundService()

    // MARK: - Groups

    /// Create a new skins group with members.
    func createGroup(
        name: String,
        createdBy: UUID,
        memberIds: [UUID],
        buyIn: Double = 0,
        scheduledDate: Date? = nil,
        recurrence: GameRecurrence? = nil,
        courseName: String? = nil,
        courseClubName: String? = nil,
        teeBoxName: String? = nil,
        teeBoxColor: String? = nil,
        teeBoxCourseRating: Double? = nil,
        teeBoxSlopeRating: Int? = nil,
        teeBoxPar: Int? = nil,
        handicapPercentage: Double? = nil,
        allActive: Bool = false,
        isQuickGame: Bool = false,
        memberGroupNums: [UUID: Int] = [:],
        teeTimeInterval: Int? = nil,
        scorerIdsToInvite: Set<UUID> = [],
        lastTeeBoxHolesJson: String? = nil
    ) async throws -> SkinsGroupDTO {
        let recurrenceJSON: String? = {
            guard let recurrence else { return nil }
            guard let data = try? JSONEncoder().encode(recurrence),
                  let str = String(data: data, encoding: .utf8) else { return nil }
            return str
        }()

        #if DEBUG
        print("[GroupService] createGroup: createdBy=\(createdBy)")
        #endif
        let group: SkinsGroupDTO
        do {
            group = try await client.from("skins_groups")
                .insert(SkinsGroupInsert(
                    name: name,
                    createdBy: createdBy,
                    buyIn: buyIn,
                    lastCourseName: courseName,
                    lastCourseClubName: courseClubName,
                    scheduledDate: scheduledDate,
                    recurrence: recurrenceJSON,
                    lastTeeBoxName: teeBoxName,
                    lastTeeBoxColor: teeBoxColor,
                    lastTeeBoxCourseRating: teeBoxCourseRating,
                    lastTeeBoxSlopeRating: teeBoxSlopeRating,
                    lastTeeBoxPar: teeBoxPar,
                    handicapPercentage: handicapPercentage,
                    isQuickGame: isQuickGame,
                    teeTimeInterval: teeTimeInterval,
                    lastTeeBoxHolesJson: lastTeeBoxHolesJson
                ))
                .select()
                .single()
                .execute()
                .value
        } catch {
            #if DEBUG
            print("[GroupService] skins_groups INSERT failed: \(error)")
            #endif
            throw error
        }
        #if DEBUG
        print("[GroupService] skins_groups INSERT succeeded: \(group.id)")
        #endif

        // Insert creator as first member
        var memberInserts = [GroupMemberInsert(
            groupId: group.id,
            playerId: createdBy,
            role: "creator",
            status: "active",
            groupNum: memberGroupNums[createdBy] ?? 1
        )]

        // Insert other members — active (Quick Start) or invited (normal flow)
        // For Quick Games, scorers for groups 2+ are inserted as 'invited' so they
        // get a push notification and invite card (instead of relying on a separate UPDATE)
        for memberId in memberIds where memberId != createdBy {
            let status: String
            if scorerIdsToInvite.contains(memberId) {
                status = "invited"
            } else if allActive {
                status = "active"
            } else {
                status = "invited"
            }
            memberInserts.append(GroupMemberInsert(
                groupId: group.id,
                playerId: memberId,
                role: "member",
                status: status,
                groupNum: memberGroupNums[memberId] ?? 1
            ))
        }

        try await client.from("group_members")
            .insert(memberInserts)
            .execute()

        return group
    }

    /// Fetch all groups the user belongs to (as active member).
    func fetchMyGroups(userId: UUID) async throws -> [SkinsGroupDTO] {
        // First get the group IDs the user is a member of
        let memberships: [GroupMemberDTO] = try await client.from("group_members")
            .select()
            .eq("player_id", value: userId.uuidString)
            .eq("status", value: "active")
            .execute()
            .value

        guard !memberships.isEmpty else { return [] }

        let groupIds = memberships.map { $0.groupId.uuidString }
        let groups: [SkinsGroupDTO] = try await client.from("skins_groups")
            .select()
            .in("id", values: groupIds)
            .order("created_at", ascending: false)
            .execute()
            .value

        return groups
    }

    /// Returns the user's current status in a group, or nil if no row exists.
    /// Used to distinguish "you were kicked" from "you were demoted to invited"
    /// (e.g. Quick Game → Group conversion flips active members to invited).
    func membershipStatus(groupId: UUID, userId: UUID) async -> String? {
        let rows: [GroupMemberDTO]? = try? await client.from("group_members")
            .select()
            .eq("group_id", value: groupId.uuidString)
            .eq("player_id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        return rows?.first?.status
    }

    /// Fetch all active and invited members of a group.
    func fetchGroupMembers(groupId: UUID) async throws -> [GroupMemberDTO] {
        let rows: [GroupMemberDTO] = try await client.from("group_members")
            .select()
            .eq("group_id", value: groupId.uuidString)
            .in("status", values: ["active", "invited"])
            .execute()
            .value
        return Self.dedupeMembers(rows)
    }

    /// Fan-in variant for the Games-feed poll: returns all active+invited
    /// memberships across N groups in a single query. Caller groups the
    /// result by `groupId` locally. Replaces N per-group fetches.
    func fetchGroupMembersForGroups(groupIds: [UUID]) async throws -> [GroupMemberDTO] {
        guard !groupIds.isEmpty else { return [] }
        let rows: [GroupMemberDTO] = try await client.from("group_members")
            .select()
            .in("group_id", values: groupIds.map(\.uuidString))
            .in("status", values: ["active", "invited"])
            .execute()
            .value
        return Self.dedupeMembers(rows)
    }

    /// Deduplicate `group_members` rows where the same (group_id, player_id)
    /// pair has both an `active` and an `invited` row. Observed 2026-04-23
    /// after a Quick Game scorer assignment wrote an `active` row on top of
    /// an existing `invited` row instead of updating it — the client then
    /// saw the player flicker on every refresh. `active` wins; phone-only
    /// invites (rows with `invited_phone` set) are keyed separately so they
    /// don't collide with the profile-based rows for the same inviter UUID.
    private static func dedupeMembers(_ rows: [GroupMemberDTO]) -> [GroupMemberDTO] {
        var best: [String: GroupMemberDTO] = [:]
        for row in rows {
            let key = "\(row.groupId.uuidString)|\(row.playerId.uuidString)|\(row.invitedPhone ?? "")"
            if let existing = best[key] {
                if existing.status == "active" { continue }
                if row.status == "active" { best[key] = row; continue }
            } else {
                best[key] = row
            }
        }
        return Array(best.values)
    }

    /// Fan-in variant for `round_players` — one query returns all round
    /// players for every round id. Used by the Games-feed poll to
    /// pre-populate the quick-game backfill cache without firing a per-group
    /// query. Caller groups the result by `roundId` locally.
    func fetchRoundPlayersForRounds(roundIds: [UUID]) async throws -> [RoundPlayerDTO] {
        guard !roundIds.isEmpty else { return [] }
        return try await client.from("round_players")
            .select()
            .in("round_id", values: roundIds.map(\.uuidString))
            .execute()
            .value
    }

    /// Fetch profiles for a list of player UUIDs.
    func fetchMemberProfiles(playerIds: [UUID]) async throws -> [ProfileDTO] {
        guard !playerIds.isEmpty else { return [] }
        let ids = playerIds.map { $0.uuidString }
        return try await client.from("profiles")
            .select()
            .in("id", values: ids)
            .execute()
            .value
    }

    /// Update group properties (partial update — only non-nil fields).
    func updateGroup(groupId: UUID, update: SkinsGroupUpdate) async throws {
        try await client.from("skins_groups")
            .update(update)
            .eq("id", value: groupId.uuidString)
            .execute()
    }

    /// Single source of truth for reading per-hole data from a group.
    /// Returns nil if the group has no persisted holes JSON.
    func fetchPersistedHoles(groupId: UUID) async -> [Hole]? {
        struct HolesOnly: Codable {
            let lastTeeBoxHolesJson: String?
            enum CodingKeys: String, CodingKey { case lastTeeBoxHolesJson = "last_tee_box_holes_json" }
        }
        guard let rows: [HolesOnly] = try? await client.from("skins_groups")
            .select("last_tee_box_holes_json")
            .eq("id", value: groupId.uuidString)
            .limit(1)
            .execute()
            .value,
            let json = rows.first?.lastTeeBoxHolesJson,
            let data = json.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([Hole].self, from: data),
            !decoded.isEmpty else { return nil }
        return decoded
    }

    /// Single source of truth for persisting a course selection to a group.
    /// Writes both denormalized fields AND the per-hole JSON in one call.
    /// Use this everywhere a course is saved — never write course fields directly.
    func persistCourseSelection(groupId: UUID, course: SelectedCourse) async throws {
        var holesJson: String? = nil
        if let holes = course.teeBox?.holes,
           !holes.isEmpty,
           let data = try? JSONEncoder().encode(holes) {
            holesJson = String(data: data, encoding: .utf8)
        }
        try await updateGroup(
            groupId: groupId,
            update: SkinsGroupUpdate(
                lastCourseName: course.courseName,
                lastCourseClubName: course.clubName,
                lastTeeBoxName: course.teeBox?.name,
                lastTeeBoxColor: course.teeBox?.color,
                lastTeeBoxCourseRating: course.teeBox?.courseRating,
                lastTeeBoxSlopeRating: course.teeBox?.slopeRating,
                lastTeeBoxPar: course.teeBox?.par,
                lastTeeBoxHolesJson: holesJson
            )
        )
    }

    /// Convert a Quick Game to a recurring group. Sets name and marks guests as pending.
    func convertQuickGameToGroup(groupId: UUID, groupName: String) async throws {
        try await client.rpc("convert_quick_game_to_group", params: [
            "p_group_id": AnyJSON.string(groupId.uuidString),
            "p_group_name": AnyJSON.string(groupName)
        ]).execute()
    }

    /// Fetch guest members in a group (invited guests who haven't claimed their profile).
    func fetchGuestMembers(groupId: UUID) async throws -> [ProfileDTO] {
        let members: [GroupMemberDTO] = try await client.from("group_members")
            .select()
            .eq("group_id", value: groupId.uuidString)
            .eq("status", value: "invited")
            .execute()
            .value

        let playerIds = members.map(\.playerId)
        guard !playerIds.isEmpty else { return [] }

        let profiles: [ProfileDTO] = try await client.from("profiles")
            .select()
            .in("id", values: playerIds.map(\.uuidString))
            .eq("is_guest", value: true)
            .execute()
            .value

        return profiles
    }

    /// Invite a member to a group (status = "invited"). Skips if already a member.
    func inviteMember(groupId: UUID, playerId: UUID) async throws {
        // Check for existing membership (any status).
        let existing: [GroupMemberDTO] = try await client.from("group_members")
            .select()
            .eq("group_id", value: groupId.uuidString)
            .eq("player_id", value: playerId.uuidString)
            .execute()
            .value

        if let row = existing.first {
            // Ghost `status='removed'` row from an earlier soft-delete
            // (before `removeMember` was switched to hard-DELETE) still
            // blocks fresh re-invites. Resurrect it to 'invited' so the
            // user can be added again without requiring manual DB
            // cleanup. Active and invited rows are left alone — no-op.
            if row.status == "removed" {
                try await client.from("group_members")
                    .update(["status": "invited"] as [String: String])
                    .eq("id", value: row.id.uuidString)
                    .execute()
            }
            return
        }

        try await client.from("group_members")
            .insert(GroupMemberInsert(
                groupId: groupId,
                playerId: playerId,
                role: "member",
                status: "invited"
            ))
            .execute()
    }

    /// Mark an existing active member as 'invited' so they get a push notification and invite card.
    /// Used when a Quick Game scorer (Carry user) needs to be formally invited.
    func inviteExistingMember(groupId: UUID, playerId: UUID) async throws {
        try await client.from("group_members")
            .update(["status": "invited"] as [String: String])
            .eq("group_id", value: groupId.uuidString)
            .eq("player_id", value: playerId.uuidString)
            .execute()
    }

    /// Invite by phone number — stores the phone for matching when the recipient signs up.
    /// Uses the inviter's UUID as placeholder player_id (FK requires non-null).
    /// The invited_phone column is the real identifier until the user claims the invite.
    func inviteMemberByPhone(groupId: UUID, phone: String, invitedBy: UUID, groupNum: Int = 1) async throws {
        // Check if this phone is already invited to this group
        let existing: [GroupMemberDTO] = try await client.from("group_members")
            .select()
            .eq("group_id", value: groupId.uuidString)
            .eq("invited_phone", value: phone)
            .execute()
            .value
        guard existing.isEmpty else { return } // Already invited

        try await client.from("group_members")
            .insert(GroupMemberInsert(
                groupId: groupId,
                playerId: invitedBy,
                role: "member",
                status: "invited",
                invitedPhone: phone,
                groupNum: groupNum
            ))
            .execute()
    }

    /// Check if a phone number has pending group invites (called on sign-up/sign-in).
    func checkPhoneInvites(phone: String) async throws -> [GroupMemberDTO] {
        try await client.from("group_members")
            .select()
            .eq("invited_phone", value: phone)
            .eq("status", value: "invited")
            .execute()
            .value
    }

    /// Claim a phone-based invite — update player_id to the real user.
    func claimPhoneInvite(membershipId: UUID, realPlayerId: UUID) async throws {
        try await client.from("group_members")
            .update(["player_id": realPlayerId.uuidString, "invited_phone": ""])
            .eq("id", value: membershipId.uuidString)
            .execute()
    }

    /// Add a member to a group as active (e.g. creator adding themselves).
    func addMember(groupId: UUID, playerId: UUID, role: String = "member") async throws {
        try await client.from("group_members")
            .insert(GroupMemberInsert(
                groupId: groupId,
                playerId: playerId,
                role: role,
                status: "active"
            ))
            .execute()
    }

    /// Fetch pending group invites for a user.
    func fetchGroupInvites(userId: UUID) async throws -> [GroupMemberDTO] {
        try await client.from("group_members")
            .select()
            .eq("player_id", value: userId.uuidString)
            .eq("status", value: "invited")
            .execute()
            .value
    }

    /// Explicit-consent join for the in-app QR scanner and tap-to-join
    /// invite links: create a membership if missing, otherwise promote an
    /// existing invited/declined row to active, and return the group's
    /// display name so the caller can confirm to the scanner with a toast.
    /// Scanning a QR is itself the accept — skipping the invited → active
    /// two-step that the Universal Link push flow uses.
    @discardableResult
    func joinGroupViaInvite(groupId: UUID, playerId: UUID) async throws -> String {
        // Insert the invited membership FIRST — a brand-new scanner has no
        // `skins_groups` read access until they're at least an invited
        // member (per RLS). If we SELECTed the group before inserting,
        // the row would come back empty and this method would throw a
        // spurious "Group not found" before the join could succeed.
        // `inviteMember` is idempotent: no-op on an existing membership,
        // inserts status='invited' otherwise.
        do {
            try await inviteMember(groupId: groupId, playerId: playerId)
        } catch {
            #if DEBUG
            print("[joinGroupViaInvite] inviteMember failed (continuing to SELECT): \(error)")
            #endif
        }

        // Now readable via the "Invited users can see invited groups"
        // policy (or the active-membership policy if the user was already
        // in the group).
        let groups: [SkinsGroupDTO]
        do {
            groups = try await client.from("skins_groups")
                .select()
                .eq("id", value: groupId.uuidString)
                .execute()
                .value
        } catch {
            #if DEBUG
            print("[joinGroupViaInvite] skins_groups SELECT failed: \(error)")
            #endif
            throw error
        }
        guard let group = groups.first else {
            #if DEBUG
            print("[joinGroupViaInvite] skins_groups SELECT returned empty for groupId=\(groupId) — RLS likely denied read (user isn't a member yet)")
            #endif
            throw NSError(domain: "GroupService", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "Group not found"])
        }

        // Promote to active (auto-placing into the first non-full tee-time
        // group) via the shared accept helper.
        let rows: [GroupMemberDTO]
        do {
            rows = try await client.from("group_members")
                .select()
                .eq("group_id", value: groupId.uuidString)
                .eq("player_id", value: playerId.uuidString)
                .execute()
                .value
        } catch {
            #if DEBUG
            print("[joinGroupViaInvite] group_members SELECT (self) failed: \(error)")
            #endif
            throw error
        }
        if let row = rows.first, row.status != "active" {
            do {
                try await acceptGroupInvite(membershipId: row.id)
            } catch {
                #if DEBUG
                print("[joinGroupViaInvite] acceptGroupInvite failed (membershipId=\(row.id), currentStatus=\(row.status)): \(error)")
                #endif
                throw error
            }
        }

        return group.name
    }

    /// Accept a group invite — sets status to "active".
    /// If the row was inserted without a `group_num` (e.g. self-invite via
    /// QR scan or invite link, where the invitee never picked a tee-time
    /// slot), auto-place them top-to-bottom: fill Group 1 to 4 players,
    /// then Group 2, etc., up to the 5-group cap. The creator can still
    /// drag them to a different group after they accept.
    func acceptGroupInvite(membershipId: UUID) async throws {
        // Fetch the membership row first to know which group + whether
        // group_num is already set (e.g. by manual placement at invite time).
        let rows: [GroupMemberDTO] = try await client.from("group_members")
            .select()
            .eq("id", value: membershipId.uuidString)
            .execute()
            .value
        guard let row = rows.first else { return }

        if row.groupNum == nil {
            // Count current active/invited members per group_num so the new
            // joiner lands in the first non-full group.
            let allMembers: [GroupMemberDTO] = (try? await client.from("group_members")
                .select()
                .eq("group_id", value: row.groupId.uuidString)
                .in("status", values: ["active", "invited"])
                .execute()
                .value) ?? []
            var counts: [Int: Int] = [:]
            for m in allMembers {
                if let g = m.groupNum { counts[g, default: 0] += 1 }
            }
            let maxGroupSize = 4
            let maxGroups = 5
            var assignedGroup = 1
            for g in 1...maxGroups where (counts[g] ?? 0) < maxGroupSize {
                assignedGroup = g
                break
            }
            try await client.from("group_members")
                .update(["group_num": assignedGroup])
                .eq("id", value: membershipId.uuidString)
                .execute()
        }

        try await client.from("group_members")
            .update(["status": "active"])
            .eq("id", value: membershipId.uuidString)
            .execute()
    }

    /// Decline a group invite — sets status to "declined" (triggers push to creator).
    func declineGroupInvite(membershipId: UUID) async throws {
        try await client.from("group_members")
            .update(["status": "declined"])
            .eq("id", value: membershipId.uuidString)
            .execute()
    }

    /// Load pending group invites as displayable models for the invite overlay.
    func loadPendingGroupInvites(userId: UUID) async throws -> [(membership: GroupMemberDTO, group: SkinsGroupDTO, inviterName: String?, members: [Player])] {
        let invites = try await fetchGroupInvites(userId: userId)
        guard !invites.isEmpty else { return [] }

        var results: [(membership: GroupMemberDTO, group: SkinsGroupDTO, inviterName: String?, members: [Player])] = []

        for invite in invites {
            // Fetch the group
            let groups: [SkinsGroupDTO] = try await client.from("skins_groups")
                .select()
                .eq("id", value: invite.groupId.uuidString)
                .execute()
                .value
            guard let group = groups.first else { continue }

            // Fetch active members (to show who's in the group)
            let activeMembers = try await fetchGroupMembers(groupId: group.id)
            let profileIds = activeMembers.map(\.playerId)
            let profiles = try await fetchMemberProfiles(playerIds: profileIds)
            let players = profiles.map { Player(from: $0) }

            // Get creator name
            let creatorProfile = group.createdBy.flatMap { cb in profiles.first { $0.id == cb } }
            let inviterName = creatorProfile?.displayName

            results.append((membership: invite, group: group, inviterName: inviterName, members: players))
        }

        return results
    }

    /// Remove a member from a group (sets status to 'removed').
    /// Hard-DELETE the membership row. Previously this soft-deleted via
    /// `status='removed'`, but the ghost row blocked `inviteMember` (which
    /// no-ops on any existing row), so leaving a group and then being
    /// re-invited silently did nothing. Deleting the row clears the path
    /// for a clean re-invite, whether the removal came from self-leave or
    /// from the long-press permanent-remove action in Manage Members.
    ///
    /// Also cascades to `round_players` for every active/concluded round of
    /// this group — otherwise `loadSingleGroup`'s round_players → members
    /// backfill resurrects the removed player on the next refresh.
    func removeMember(groupId: UUID, playerId: UUID) async throws {
        try await client.from("group_members")
            .delete()
            .eq("group_id", value: groupId.uuidString)
            .eq("player_id", value: playerId.uuidString)
            .execute()

        let rounds: [RoundDTO] = (try? await client.from("rounds")
            .select()
            .eq("group_id", value: groupId.uuidString)
            .execute()
            .value) ?? []
        for round in rounds {
            try? await client.from("round_players")
                .delete()
                .eq("round_id", value: round.id.uuidString)
                .eq("player_id", value: playerId.uuidString)
                .execute()
        }
    }

    /// Save player sort order for a group. Takes an array of (playerId, sortOrder) tuples.
    func savePlayerOrder(groupId: UUID, order: [(playerId: UUID, sortOrder: Int)]) async throws {
        for item in order {
            try await client.from("group_members")
                .update(["sort_order": item.sortOrder])
                .eq("group_id", value: groupId.uuidString)
                .eq("player_id", value: item.playerId.uuidString)
                .execute()
        }
    }

    /// Save group_num assignments for all members (Quick Games).
    func saveGroupNums(groupId: UUID, assignments: [(playerId: UUID, groupNum: Int)]) async throws {
        for item in assignments {
            try await client.from("group_members")
                .update(["group_num": item.groupNum])
                .eq("group_id", value: groupId.uuidString)
                .eq("player_id", value: item.playerId.uuidString)
                .execute()
        }
    }

    /// Persist per-group tee times as JSON so independent (non-consecutive)
    /// schedules survive across devices. Nil entries encode groups that
    /// haven't had a time set yet. Pass an empty array to clear.
    func saveTeeTimes(groupId: UUID, teeTimes: [Date?]) async throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let encoded: [String?] = teeTimes.map { date in
            date.map { iso.string(from: $0) }
        }
        let update: SkinsGroupUpdate
        if teeTimes.isEmpty {
            update = SkinsGroupUpdate(teeTimesJson: nil, clearTeeTimesJson: true)
        } else {
            let data = try JSONEncoder().encode(encoded)
            let json = String(data: data, encoding: .utf8) ?? "[]"
            update = SkinsGroupUpdate(teeTimesJson: json)
        }
        try await updateGroup(groupId: groupId, update: update)
    }

    /// Delete a group entirely — uses RPC to delete in FK-safe order.
    func deleteGroup(groupId: UUID) async throws {
        try await client.rpc("delete_group", params: ["gid": groupId.uuidString]).execute()
    }

    // MARK: - High-Level: Load SavedGroups

    /// Load all groups for a user, fully hydrated as SavedGroup objects.
    /// This is the main entry point for authenticated group loading and the
    /// backbone of the 15s Games-feed poll.
    ///
    /// Performance model: the previous implementation fanned out
    /// `loadSingleGroup` in parallel per group, and each `loadSingleGroup`
    /// fired 5-9 Supabase queries (group row, members, profiles, rounds,
    /// round_players backfill, extra profiles, tee box, scores, ...). For a
    /// user in 10 groups that was 50-90 HTTP round-trips every 15 seconds —
    /// heavy on battery, data, and Supabase quota, and a risk at launch if
    /// the app sees a traffic spike.
    ///
    /// This version batches the top-level fetches into **5 Supabase
    /// round-trips total, regardless of group count**:
    ///   1. `fetchMyGroups` — memberships + group rows
    ///   2. `fetchGroupMembersForGroups` — all active/invited memberships
    ///   3. `fetchRoundsForGroups` — all rounds across every group
    ///   4. `fetchRoundPlayersForRounds` — all round_players in one call
    ///   5. `fetchMemberProfiles` — every profile needed by members OR
    ///      round_players, deduped
    ///
    /// The prefetched dicts are then handed to `loadSingleGroup` so it
    /// skips its own top-level fetches. Inner per-round score + tee_box
    /// fetches inside `buildHomeRound` remain (future optimization if
    /// needed) but are a small constant per round, not multiplied by group
    /// count.
    func loadGroups(userId: UUID) async throws -> [SavedGroup] {
        let groupDTOs = try await fetchMyGroups(userId: userId)
        guard !groupDTOs.isEmpty else { return [] }
        let groupIds = groupDTOs.map(\.id)

        // Fan-in: members + rounds in parallel. Two queries, any group count.
        // Track success per-batch so a batch failure falls back cleanly —
        // we pass `nil` prefetched to `loadSingleGroup` instead of an
        // empty array, which would otherwise be indistinguishable from
        // "no data" and block the per-group recovery fetch.
        async let membersTask: [GroupMemberDTO] = fetchGroupMembersForGroups(groupIds: groupIds)
        async let roundsTask: [RoundDTO] = roundService.fetchRoundsForGroups(groupIds: groupIds)

        var membersByGroup: [UUID: [GroupMemberDTO]]? = nil
        var roundsByGroup: [UUID: [RoundDTO]]? = nil
        var allMembers: [GroupMemberDTO] = []
        var allRounds: [RoundDTO] = []

        do {
            allMembers = try await membersTask
            membersByGroup = Dictionary(grouping: allMembers, by: \.groupId)
        } catch {
            #if DEBUG
            print("[loadGroups] batched members fetch failed — each group will fall back to its own fetch: \(error)")
            #endif
        }
        do {
            allRounds = try await roundsTask
            // `RoundDTO.groupId` is `UUID?` (nil for pre-conversion Quick
            // Games). Drop nils when bucketing — the Games-feed poll only
            // cares about rounds attached to an actual group.
            var byGroup: [UUID: [RoundDTO]] = [:]
            for round in allRounds {
                guard let gid = round.groupId else { continue }
                byGroup[gid, default: []].append(round)
            }
            roundsByGroup = byGroup
        } catch {
            #if DEBUG
            print("[loadGroups] batched rounds fetch failed — each group will fall back to its own fetch: \(error)")
            #endif
        }

        // Round players for every round in one call (used by the Quick Game
        // backfill inside `loadSingleGroup` AND by `buildHomeRound` via the
        // `preloadedRoundPlayers` parameter — prefetching here satisfies both).
        let roundIds = allRounds.map(\.id)
        let allRoundPlayers = roundIds.isEmpty ? [] : ((try? await fetchRoundPlayersForRounds(roundIds: roundIds)) ?? [])
        let roundPlayersByRoundId: [UUID: [RoundPlayerDTO]]? = roundIds.isEmpty
            ? nil
            : Dictionary(grouping: allRoundPlayers, by: \.roundId)

        // Consolidated profile fetch: union member + round_player player_ids.
        // One query replaces (a) per-group `fetchMemberProfiles` and (b) the
        // per-group "extra profiles for round_players missing from members"
        // fetch inside `loadSingleGroup`.
        let memberPlayerIds = allMembers
            .filter { $0.invitedPhone == nil || ($0.invitedPhone ?? "").isEmpty }
            .map(\.playerId)
        let roundPlayerIds = allRoundPlayers.map(\.playerId)
        let dedupedProfileIds = Array(Set(memberPlayerIds + roundPlayerIds))
        let allProfiles = dedupedProfileIds.isEmpty
            ? []
            : ((try? await fetchMemberProfiles(playerIds: dedupedProfileIds)) ?? [])
        let profilesByUUID: [UUID: ProfileDTO]? = dedupedProfileIds.isEmpty
            ? nil
            : Dictionary(uniqueKeysWithValues: allProfiles.map { ($0.id, $0) })

        return await withTaskGroup(of: SavedGroup?.self) { taskGroup in
            for groupDTO in groupDTOs {
                // Nil prefetched param → `loadSingleGroup` falls back to
                // its original per-group fetch. Pass only when the batch
                // succeeded so a transient batch failure doesn't starve
                // all groups of data.
                let prefMembers = membersByGroup?[groupDTO.id]
                let prefRounds = roundsByGroup?[groupDTO.id]?
                    .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                taskGroup.addTask {
                    try? await self.loadSingleGroup(
                        groupId: groupDTO.id,
                        userId: userId,
                        prefetchedGroup: groupDTO,
                        prefetchedMembers: prefMembers,
                        prefetchedProfiles: profilesByUUID,
                        prefetchedRounds: prefRounds,
                        prefetchedRoundPlayers: roundPlayersByRoundId
                    )
                }
            }
            var results: [SavedGroup] = []
            for await result in taskGroup {
                if let group = result { results.append(group) }
            }
            return results.sorted { ($0.scheduledDate ?? .distantPast) > ($1.scheduledDate ?? .distantPast) }
        }
    }

    /// Original sequential loadGroups (kept for reference, replaced by parallel version above)
    private func _loadGroupsSequential(userId: UUID) async throws -> [SavedGroup] {
        let groups = try await fetchMyGroups(userId: userId)
        guard !groups.isEmpty else { return [] }

        var savedGroups: [SavedGroup] = []

        for group in groups {
            let members = try await fetchGroupMembers(groupId: group.id)
            let profileIds = members.map(\.playerId)
            let profiles = try await fetchMemberProfiles(playerIds: profileIds)
            // Build sort order map from group_members
            let sortOrderMap = Dictionary(uniqueKeysWithValues: members.compactMap { m -> (UUID, Int)? in
                guard let order = m.sortOrder else { return nil }
                return (m.playerId, order)
            })
            // Build player list, marking invited members as pending + setting group nums
            let invitedIds = Set(members.filter { $0.status == "invited" }.map(\.playerId))
            let groupNumMap = Dictionary(uniqueKeysWithValues: members.map { ($0.playerId, $0.groupNum ?? 1) })
            var players = profiles.map { profile -> Player in
                var player = Player(from: profile)
                if invitedIds.contains(profile.id) {
                    player.isPendingAccept = true
                }
                player.group = groupNumMap[profile.id] ?? 1
                return player
            }
            // Sort by sort_order if available
            if !sortOrderMap.isEmpty {
                players.sort { a, b in
                    let orderA = sortOrderMap[a.profileId ?? UUID()] ?? Int.max
                    let orderB = sortOrderMap[b.profileId ?? UUID()] ?? Int.max
                    return orderA < orderB
                }
            }

            let creatorPlayer = group.createdBy.flatMap { cb in players.first { $0.profileId == cb } }
            let creatorId = creatorPlayer?.id ?? (group.createdBy.map { Player.stableId(from: $0) } ?? 0)

            // Reconstruct SelectedCourse if we have a saved course name
            var lastCourse: SelectedCourse? = nil
            if let courseName = group.lastCourseName {
                // Reconstruct tee box from group-level data — holes come from skins_groups directly
                var groupTeeBox: TeeBox? = nil
                if let teeBoxName = group.lastTeeBoxName, let teeBoxColor = group.lastTeeBoxColor {
                    // Primary source: holes stored on the group itself (saved at course selection)
                    var holes = group.decodeHoles()

                    // Fallback: fetch from most recent round's tee_box (for groups created before this change)
                    if holes == nil || holes?.isEmpty == true {
                        if let rounds = try? await roundService.fetchRoundsForGroup(groupId: group.id),
                           let latestRound = rounds.first, let teeBoxId = latestRound.teeBoxId,
                           let dto: TeeBoxDTO = try? await client.from("tee_boxes")
                            .select().eq("id", value: teeBoxId.uuidString).single().execute().value {
                            holes = dto.decodeHoles()
                        }
                    }

                    #if DEBUG
                    print("[GroupService] Tee box holes for \(group.id): \(holes?.count ?? 0) (source: \(group.lastTeeBoxHolesJson != nil ? "group" : "round"))")
                    #endif

                    groupTeeBox = TeeBox(
                        id: UUID().uuidString,
                        courseId: "0",
                        name: teeBoxName,
                        color: teeBoxColor,
                        courseRating: group.lastTeeBoxCourseRating ?? 0,
                        slopeRating: group.lastTeeBoxSlopeRating ?? 0,
                        par: group.lastTeeBoxPar ?? 72,
                        holes: holes
                    )
                }
                lastCourse = SelectedCourse(
                    courseId: 0,
                    courseName: courseName,
                    clubName: group.lastCourseClubName ?? courseName,
                    location: "",
                    teeBox: groupTeeBox,
                    apiTee: nil
                )
            }

            // Decode recurrence from JSON string
            var recurrence: GameRecurrence? = nil
            if let recurrenceStr = group.recurrence,
               let data = recurrenceStr.data(using: .utf8) {
                recurrence = try? JSONDecoder().decode(GameRecurrence.self, from: data)
            }

            // Hydrate rounds for this group
            var activeRound: HomeRound? = nil
            var concludedRound: HomeRound? = nil
            var roundHistory: [HomeRound] = []

            // Only active (non-pending) players count for rounds, skins, and pot
            let activePlayers = players.filter { !$0.isPendingAccept }

            // Compute per-group tee times once so every round in this group
            // can resolve the current user's slot from the same array.
            let groupTeeTimes = reconstructTeeTimes(
                group: group,
                groupCount: Set(players.map(\.group)).count
            )

            if let rounds = try? await roundService.fetchRoundsForGroup(groupId: group.id) {
                for roundDTO in rounds {
                    let currentPlayerIntId = Player.stableId(from: userId)
                    let homeRound = await buildHomeRound(
                        from: roundDTO,
                        groupName: group.name,
                        courseName: group.lastCourseName ?? "Unknown Course",
                        players: activePlayers,
                        creatorId: creatorId,
                        buyIn: roundDTO.buyIn,
                        scheduledDate: group.scheduledDate,
                        teeTimes: groupTeeTimes,
                        currentUserId: currentPlayerIntId,
                        teeBox: lastCourse?.teeBox,
                        supabaseGroupId: group.id,
                        winningsDisplay: group.winningsDisplay,
                        isQuickGame: group.isQuickGame ?? false,
                        groupScorerIds: group.scorerIds
                    )

                    switch roundDTO.status {
                    case "active":
                        if activeRound == nil { activeRound = homeRound }
                    case "concluded":
                        // Concluded rounds stay pinned to the active section until the user
                        // explicitly taps "Save Round Results" (which marks them completed).
                        // No time-based auto-archive — would cause confusing disappearance.
                        if concludedRound == nil { concludedRound = homeRound }
                    case "completed":
                        roundHistory.append(homeRound)
                    default:
                        break
                    }
                }
            }

            // Extract tee box from most recent round and attach to lastCourse
            if let existingCourse = lastCourse {
                let roundTeeBox = activeRound?.teeBox ?? concludedRound?.teeBox ?? roundHistory.first?.teeBox
                if let teeBox = roundTeeBox {
                    lastCourse = SelectedCourse(
                        courseId: existingCourse.courseId,
                        courseName: existingCourse.courseName,
                        clubName: existingCourse.clubName,
                        location: existingCourse.location,
                        teeBox: teeBox,
                        apiTee: existingCourse.apiTee
                    )
                }
            }

            let teeTimes = groupTeeTimes

            let savedGroup = SavedGroup(
                id: group.id,
                name: group.name,
                members: players,
                lastPlayed: nil,
                creatorId: creatorId,
                lastCourse: lastCourse,
                activeRound: activeRound,
                concludedRound: concludedRound,
                roundHistory: roundHistory,
                potSize: group.buyIn * Double(activePlayers.count),
                buyInPerPlayer: group.buyIn,
                scheduledDate: group.scheduledDate,
                recurrence: recurrence,
                isQuickGame: group.isQuickGame ?? false,
                scorerIds: group.scorerIds,
                teeTimes: teeTimes,
                teeTimeInterval: group.teeTimeInterval,
                winningsDisplay: group.winningsDisplay ?? "gross"
            )
            savedGroups.append(savedGroup)
        }

        return savedGroups
    }

    /// Load a single group by ID, fully hydrated as a SavedGroup.
    /// Used for pull-to-refresh and polling in the group detail view.
    ///
    /// The optional `prefetched*` parameters let the Games-feed `loadGroups`
    /// batch-fetch top-level DTOs once across every group the user is in,
    /// then hand them off here instead of firing a separate Supabase call
    /// per group. When nil (the default), each parameter falls back to its
    /// original per-group fetch — preserving behavior for existing callers
    /// like `GroupManagerView.refreshGroupData` that load one group at a
    /// time on pull-to-refresh.
    func loadSingleGroup(
        groupId: UUID,
        userId: UUID,
        prefetchedGroup: SkinsGroupDTO? = nil,
        prefetchedMembers: [GroupMemberDTO]? = nil,
        prefetchedProfiles: [UUID: ProfileDTO]? = nil,
        prefetchedRounds: [RoundDTO]? = nil,
        prefetchedRoundPlayers: [UUID: [RoundPlayerDTO]]? = nil
    ) async throws -> SavedGroup? {
        let group: SkinsGroupDTO
        if let prefetched = prefetchedGroup {
            group = prefetched
        } else {
            let groups: [SkinsGroupDTO] = try await client.from("skins_groups")
                .select()
                .eq("id", value: groupId.uuidString)
                .execute()
                .value
            guard let g = groups.first else { return nil }
            group = g
        }

        // `??` on the RHS is an autoclosure that Swift forbids `try`/`await`
        // inside — resolve with an explicit branch.
        let members: [GroupMemberDTO]
        if let prefetched = prefetchedMembers {
            members = prefetched
        } else {
            members = try await fetchGroupMembers(groupId: group.id)
        }

        // Separate phone-invited members from regular members
        let phoneInvites = members.filter { $0.invitedPhone != nil && !($0.invitedPhone ?? "").isEmpty && $0.status == "invited" }
        let regularMembers = members.filter { $0.invitedPhone == nil || ($0.invitedPhone ?? "").isEmpty }

        let profileIds = regularMembers.map(\.playerId)
        let profiles: [ProfileDTO]
        if let byId = prefetchedProfiles {
            // Use the batched dict — preserves original order via profileIds.
            // If a profile is missing from the batch (partial failure,
            // race, or edge case), fall back to a targeted query for
            // just the missing ids instead of silently dropping members.
            let hits = profileIds.compactMap { byId[$0] }
            let missing = profileIds.filter { byId[$0] == nil }
            if missing.isEmpty {
                profiles = hits
            } else {
                let missingProfiles = (try? await fetchMemberProfiles(playerIds: missing)) ?? []
                profiles = hits + missingProfiles
            }
        } else {
            profiles = try await fetchMemberProfiles(playerIds: profileIds)
        }
        let invitedIds = Set(regularMembers.filter { $0.status == "invited" }.map(\.playerId))
        let groupNumMap = Dictionary(uniqueKeysWithValues: regularMembers.map { ($0.playerId, $0.groupNum ?? 1) })
        let sortOrderMap: [UUID: Int] = Dictionary(uniqueKeysWithValues: regularMembers.compactMap { m in
            guard let order = m.sortOrder else { return nil }
            return (m.playerId, order)
        })
        var players = profiles.map { profile -> Player in
            var player = Player(from: profile)
            if invitedIds.contains(profile.id) {
                player.isPendingAccept = true
            }
            player.group = groupNumMap[profile.id] ?? 1
            return player
        }
        // Sort by persisted sort_order so the tee-table position the creator
        // arranged actually sticks across refreshes. Without this, Supabase
        // returns rows in arbitrary order and refresh randomly reshuffles
        // players within a group. UUID tiebreaker keeps order deterministic
        // when sort_order is missing or duplicated (a brand-new member that
        // hasn't been written to yet).
        players.sort { a, b in
            let orderA = sortOrderMap[a.profileId ?? UUID()] ?? Int.max
            let orderB = sortOrderMap[b.profileId ?? UUID()] ?? Int.max
            if orderA != orderB { return orderA < orderB }
            return (a.profileId?.uuidString ?? "") < (b.profileId?.uuidString ?? "")
        }

        // Add phone-invited members as pending invite players
        for invite in phoneInvites {
            let phone = invite.invitedPhone ?? ""
            let player = Player(
                id: Player.stableId(from: invite.id),
                name: phone,
                initials: "✉️",
                color: "#CB895D",
                handicap: 0,
                avatar: "✉️",
                group: invite.groupNum ?? 1,
                ghinNumber: nil,
                venmoUsername: nil,
                phoneNumber: phone,
                isPendingInvite: true,
                profileId: nil
            )
            players.append(player)
        }

        let creatorPlayer = group.createdBy.flatMap { cb in players.first { $0.profileId == cb } }
        let creatorId = creatorPlayer?.id ?? (group.createdBy.map { Player.stableId(from: $0) } ?? 0)

        var lastCourse: SelectedCourse? = nil
        if let courseName = group.lastCourseName {
            var groupTeeBox: TeeBox? = nil
            if let teeBoxName = group.lastTeeBoxName, let teeBoxColor = group.lastTeeBoxColor {
                // Hole resolution chain: group JSON → fetchPersistedHoles fallback
                var holes = group.decodeHoles()
                if holes == nil || holes?.isEmpty == true {
                    holes = await fetchPersistedHoles(groupId: group.id)
                }
                groupTeeBox = TeeBox(
                    id: UUID().uuidString,
                    courseId: "0",
                    name: teeBoxName,
                    color: teeBoxColor,
                    courseRating: group.lastTeeBoxCourseRating ?? 0,
                    slopeRating: group.lastTeeBoxSlopeRating ?? 0,
                    par: group.lastTeeBoxPar ?? 72,
                    holes: holes
                )
            }
            lastCourse = SelectedCourse(
                courseId: 0,
                courseName: courseName,
                clubName: group.lastCourseClubName ?? courseName,
                location: "",
                teeBox: groupTeeBox,
                apiTee: nil
            )
        }

        var recurrence: GameRecurrence? = nil
        if let recurrenceStr = group.recurrence,
           let data = recurrenceStr.data(using: .utf8) {
            recurrence = try? JSONDecoder().decode(GameRecurrence.self, from: data)
        }

        var activeRound: HomeRound? = nil
        var concludedRound: HomeRound? = nil
        var roundHistory: [HomeRound] = []

        let rounds: [RoundDTO]
        if let prefetched = prefetchedRounds {
            rounds = prefetched
        } else {
            rounds = (try? await roundService.fetchRoundsForGroup(groupId: group.id)) ?? []
        }

        // Quick Games occasionally end up with players in `round_players` that
        // were never written to `group_members` (atomicity gap during creation).
        // Without this backfill, scorers referencing those missing players get
        // wiped by syncScorerIDs because `groupPlayerIDs.contains(scorerIDs[i])`
        // fails. Seed the cache from prefetched round_players when available
        // (Games-feed batch path) so we don't re-query `round_players` for the
        // same round, then fall back to a per-group query for single-group
        // callers like GroupManagerView.
        var roundPlayersCache: [UUID: [RoundPlayerDTO]] = prefetchedRoundPlayers ?? [:]
        let backfillRoundDTO = rounds.first { $0.status == "active" || $0.status == "concluded" || $0.status == "completed" }
        if let backfillRoundDTO,
           roundPlayersCache[backfillRoundDTO.id] == nil,
           let rpDTOs: [RoundPlayerDTO] = try? await client.from("round_players")
            .select()
            .eq("round_id", value: backfillRoundDTO.id.uuidString)
            .execute()
            .value, !rpDTOs.isEmpty {
            roundPlayersCache[backfillRoundDTO.id] = rpDTOs
        }
        if let backfillRoundDTO, let rpDTOs = roundPlayersCache[backfillRoundDTO.id], !rpDTOs.isEmpty {
            let existingIds = Set(players.compactMap(\.profileId))
            let missingIds = rpDTOs.map(\.playerId).filter { !existingIds.contains($0) }
            if !missingIds.isEmpty {
                // Prefer the batched profile dict if provided — the
                // Games-feed path already union'd member + round_player
                // ids into a single consolidated profile fetch, so no
                // extra network here.
                let extraProfiles: [ProfileDTO]
                if let byId = prefetchedProfiles {
                    extraProfiles = missingIds.compactMap { byId[$0] }
                } else {
                    extraProfiles = (try? await client.from("profiles")
                        .select()
                        .in("id", values: missingIds.map(\.uuidString))
                        .execute()
                        .value) ?? []
                }
                for profile in extraProfiles {
                    var player = Player(from: profile)
                    if let rp = rpDTOs.first(where: { $0.playerId == profile.id }) {
                        player.group = rp.groupNum
                    }
                    players.append(player)
                }
                #if DEBUG
                print("[loadSingleGroup] Backfilled \(extraProfiles.count) players from round_players (missing from group_members) for group \(group.name)")
                #endif
            }
        }

        let activePlayers = players.filter { !$0.isPendingAccept }

        // Compute per-group tee times once so every round in this group can
        // resolve the current user's slot from the same array.
        let groupTeeTimes = reconstructTeeTimes(
            group: group,
            groupCount: Set(players.map(\.group)).count
        )

        // Build all rounds in parallel — each `buildHomeRound` fires several
        // independent Supabase queries (tee_box, holes, scores, round_players).
        // Sequentially this multiplied the per-group latency by N rounds; in
        // a parallel TaskGroup the whole group finishes in ~one round's worth
        // of network round-trip. Materially improves cold-start time on the
        // Games tab, which was the dominant load bottleneck.
        let currentPlayerIntId = Player.stableId(from: userId)
        let groupScorerIds = group.scorerIds
        let builtRounds: [(RoundDTO, HomeRound)] = await withTaskGroup(of: (RoundDTO, HomeRound).self) { taskGroup in
            for roundDTO in rounds {
                taskGroup.addTask {
                    let homeRound = await self.buildHomeRound(
                        from: roundDTO,
                        groupName: group.name,
                        courseName: group.lastCourseName ?? "Unknown Course",
                        players: activePlayers,
                        creatorId: creatorId,
                        buyIn: roundDTO.buyIn,
                        scheduledDate: group.scheduledDate,
                        teeTimes: groupTeeTimes,
                        currentUserId: currentPlayerIntId,
                        teeBox: lastCourse?.teeBox,
                        supabaseGroupId: group.id,
                        winningsDisplay: group.winningsDisplay,
                        isQuickGame: group.isQuickGame ?? false,
                        preloadedRoundPlayers: roundPlayersCache[roundDTO.id],
                        groupScorerIds: groupScorerIds
                    )
                    return (roundDTO, homeRound)
                }
            }
            var collected: [(RoundDTO, HomeRound)] = []
            for await result in taskGroup { collected.append(result) }
            return collected
        }
        // Restore the original `rounds` order so active/concluded picks
        // (first-of-status) match the pre-parallelization behavior.
        let builtById = Dictionary(uniqueKeysWithValues: builtRounds.map { ($0.0.id, $0.1) })
        for roundDTO in rounds {
            guard let homeRound = builtById[roundDTO.id] else { continue }
            switch roundDTO.status {
            case "active":
                if activeRound == nil { activeRound = homeRound }
            case "concluded":
                // Concluded rounds stay pinned until user saves results — no auto-archive.
                if concludedRound == nil { concludedRound = homeRound }
            case "completed":
                roundHistory.append(homeRound)
            default:
                break
            }
        }

        if let existingCourse = lastCourse {
            let roundTeeBox = activeRound?.teeBox ?? concludedRound?.teeBox ?? roundHistory.first?.teeBox
            if let teeBox = roundTeeBox {
                lastCourse = SelectedCourse(
                    courseId: existingCourse.courseId,
                    courseName: existingCourse.courseName,
                    clubName: existingCourse.clubName,
                    location: existingCourse.location,
                    teeBox: teeBox,
                    apiTee: existingCourse.apiTee
                )
            }
        }

        let teeTimes = groupTeeTimes

        return SavedGroup(
            id: group.id,
            name: group.name,
            members: players,
            lastPlayed: nil,
            creatorId: creatorId,
            lastCourse: lastCourse,
            activeRound: activeRound,
            concludedRound: concludedRound,
            roundHistory: roundHistory,
            potSize: group.buyIn * Double(activePlayers.count),
            buyInPerPlayer: group.buyIn,
            scheduledDate: group.scheduledDate,
            recurrence: recurrence,
            handicapPercentage: group.handicapPercentage ?? 1.0,
            isQuickGame: group.isQuickGame ?? false,
            scorerIds: group.scorerIds,
            teeTimes: teeTimes,
            teeTimeInterval: group.teeTimeInterval,
            winningsDisplay: group.winningsDisplay ?? "gross",
            todayDeselectedIds: group.todayDeselectedIds ?? []
        )
    }

    /// Save/sync a SavedGroup to Supabase (create if new, update if existing).
    func syncGroup(_ group: SavedGroup, userId: UUID) async throws {
        // Encode recurrence
        let recurrenceJSON: String? = {
            guard let rec = group.recurrence else { return nil }
            guard let data = try? JSONEncoder().encode(rec),
                  let str = String(data: data, encoding: .utf8) else { return nil }
            return str
        }()

        // Encode holes JSON so par/hcp data syncs across devices
        var holesJson: String? = nil
        if let holes = group.lastCourse?.teeBox?.holes,
           !holes.isEmpty,
           let data = try? JSONEncoder().encode(holes) {
            holesJson = String(data: data, encoding: .utf8)
        }

        let update = SkinsGroupUpdate(
            name: group.name,
            buyIn: group.buyInPerPlayer,
            lastCourseName: group.lastCourse?.courseName,
            lastCourseClubName: group.lastCourse?.clubName,
            scheduledDate: group.scheduledDate,
            recurrence: recurrenceJSON,
            lastTeeBoxName: group.lastCourse?.teeBox?.name,
            lastTeeBoxColor: group.lastCourse?.teeBox?.color,
            lastTeeBoxCourseRating: group.lastCourse?.teeBox?.courseRating,
            lastTeeBoxSlopeRating: group.lastCourse?.teeBox?.slopeRating,
            lastTeeBoxPar: group.lastCourse?.teeBox?.par,
            lastTeeBoxHolesJson: holesJson
        )

        try await updateGroup(groupId: group.id, update: update)
    }

    // MARK: - Tee Time Reconstruction

    /// Reconstruct per-group tee times from a base scheduled date and interval.
    /// Resolve the per-group tee times for a skins group. Prefers the
    /// persisted `tee_times_json` array (preserves independent/non-consecutive
    /// tee times exactly as the creator set them). Falls back to deriving
    /// consecutive tee times from `scheduledDate + teeTimeInterval` so
    /// pre-migration groups keep working.
    private func reconstructTeeTimes(group: SkinsGroupDTO, groupCount: Int) -> [Date?]? {
        if let persisted = group.decodeTeeTimes(), !persisted.isEmpty {
            // Pad/truncate to match current groupCount so parallel arrays
            // stay in lockstep if a group was added/removed since last save.
            let target = max(groupCount, 1)
            if persisted.count == target { return persisted }
            if persisted.count > target { return Array(persisted.prefix(target)) }
            return persisted + Array(repeating: nil, count: target - persisted.count)
        }
        return reconstructTeeTimes(
            scheduledDate: group.scheduledDate,
            teeTimeInterval: group.teeTimeInterval,
            groupCount: groupCount
        )
    }

    private func reconstructTeeTimes(scheduledDate: Date?, teeTimeInterval: Int?, groupCount: Int) -> [Date?]? {
        guard let baseTime = scheduledDate else { return nil }
        let interval = teeTimeInterval ?? 0
        return (0..<max(groupCount, 1)).map { i in
            baseTime.addingTimeInterval(Double(i) * Double(interval) * 60)
        }
    }

    // MARK: - Auto-Advance Scheduled Date

    /// If the group has a recurrence, compute the next scheduled date and update.
    func advanceScheduledDateIfRecurring(groupId: UUID) async {
        do {
            let groups: [SkinsGroupDTO] = try await client.from("skins_groups")
                .select()
                .eq("id", value: groupId.uuidString)
                .execute()
                .value
            guard let group = groups.first,
                  let recurrenceStr = group.recurrence,
                  let data = recurrenceStr.data(using: .utf8),
                  let recurrence = try? JSONDecoder().decode(GameRecurrence.self, from: data)
            else { return }

            let nextDate = recurrence.nextDate(after: Date())
            try await updateGroup(groupId: groupId, update: SkinsGroupUpdate(scheduledDate: nextDate))
        } catch {
            #if DEBUG
            print("[GroupService] advanceScheduledDate error: \(error)")
            #endif
        }
    }

    // MARK: - Round → HomeRound Builder

    /// Build a HomeRound from a RoundDTO by fetching its scores and computing skins summary.
    /// Resolves the scorer of the current user's tee-time group. Fixes the
    /// Quick Game bug where a non-creator scorer (e.g. Group 2 scorer when
    /// the creator is teeing off in Group 2 themselves) got locked out of
    /// scoring after a refresh. `HomeRound.scorerPlayerId` used to stay
    /// nil on refresh because `buildHomeRound` never populated it, and
    /// HomeView's `isViewer` check then fell back to `creatorId` — which
    /// doesn't match the actual Group 1 scorer on non-creator devices.
    /// Returns nil if the user isn't in the round or if no scorer IDs
    /// are available (nothing breaks — HomeView falls back to creatorId,
    /// which is correct behavior for single-group rounds).
    private func resolveCurrentGroupScorer(
        currentUserId: Int?,
        roundPlayers: [Player],
        groupScorerIds: [Int]?
    ) -> Int? {
        guard let uid = currentUserId,
              let me = roundPlayers.first(where: { $0.id == uid }),
              let scorers = groupScorerIds,
              me.group >= 1, me.group <= scorers.count else { return nil }
        let scorerId = scorers[me.group - 1]
        return scorerId == 0 ? nil : scorerId
    }

    private func buildHomeRound(
        from roundDTO: RoundDTO,
        groupName: String,
        courseName: String,
        players: [Player],
        creatorId: Int,
        buyIn: Int,
        scheduledDate: Date? = nil,
        teeTimes: [Date?]? = nil,
        currentUserId: Int? = nil,
        teeBox: TeeBox? = nil,
        supabaseGroupId: UUID? = nil,
        winningsDisplay: String? = nil,
        isQuickGame: Bool = false,
        preloadedRoundPlayers: [RoundPlayerDTO]? = nil,
        groupScorerIds: [Int]? = nil  // per-group scorer IDs from skins_groups.scorer_ids
    ) async -> HomeRound {
        // Fetch tee box from round if not provided
        var resolvedTeeBox = teeBox
        if resolvedTeeBox == nil, let teeBoxId = roundDTO.teeBoxId {
            if let dto: TeeBoxDTO = try? await client.from("tee_boxes")
                .select()
                .eq("id", value: teeBoxId.uuidString)
                .single()
                .execute()
                .value {
                resolvedTeeBox = TeeBox(id: dto.id.uuidString, courseId: dto.courseId.uuidString, name: dto.name, color: dto.color, courseRating: dto.courseRating, slopeRating: dto.slopeRating, par: dto.par, holes: dto.decodeHoles())
            }
        }

        // Holes safety net: if the resolved tee box is missing per-hole data,
        // pull from the group's persisted JSON (single source of truth helper).
        if (resolvedTeeBox?.holes ?? []).isEmpty, let groupId = supabaseGroupId,
           let decodedHoles = await fetchPersistedHoles(groupId: groupId) {
            if let tb = resolvedTeeBox {
                resolvedTeeBox = TeeBox(id: tb.id, courseId: tb.courseId, name: tb.name, color: tb.color, courseRating: tb.courseRating, slopeRating: tb.slopeRating, par: tb.par, holes: decodedHoles)
            } else {
                resolvedTeeBox = TeeBox(id: "", courseId: "", name: "", color: "", courseRating: 0, slopeRating: 0, par: decodedHoles.reduce(0) { $0 + $1.par }, holes: decodedHoles)
            }
        }

        // Build the actual player list from round_players (all who were in the round),
        // merging with group_members for any extras. This ensures scorers who are still
        // "pending" in group_members are included.
        var roundPlayers = players
        let fetchedRpDTOs: [RoundPlayerDTO]?
        if let preloaded = preloadedRoundPlayers {
            fetchedRpDTOs = preloaded
        } else {
            fetchedRpDTOs = try? await client.from("round_players")
                .select()
                .eq("round_id", value: roundDTO.id.uuidString)
                .execute()
                .value
        }
        if let rpDTOs = fetchedRpDTOs, !rpDTOs.isEmpty {
            let existingIds = Set(players.compactMap(\.profileId))
            let missingIds = rpDTOs.map(\.playerId).filter { !existingIds.contains($0) }
            if !missingIds.isEmpty {
                let profiles: [ProfileDTO] = (try? await client.from("profiles")
                    .select()
                    .in("id", values: missingIds.map(\.uuidString))
                    .execute()
                    .value) ?? []
                for profile in profiles {
                    var player = Player(from: profile)
                    // Set group number from round_players
                    if let rp = rpDTOs.first(where: { $0.playerId == profile.id }) {
                        player.group = rp.groupNum
                    }
                    roundPlayers.append(player)
                }
                #if DEBUG
                print("[buildHomeRound] Added \(profiles.count) players from round_players (were missing from group_members)")
                #endif
            }
        }

        // Fetch scores for this round
        let scoreDTOs = (try? await roundService.fetchScores(roundId: roundDTO.id)) ?? []

        // Build UUID → Int player ID mapping
        var uuidToInt: [UUID: Int] = [:]
        for player in roundPlayers {
            if let profileId = player.profileId {
                uuidToInt[profileId] = player.id
            }
        }

        // Convert ScoreDTOs to [Int: [Int: Int]] (playerID → holeNum → score)
        var scores: [Int: [Int: Int]] = [:]
        for dto in scoreDTOs {
            guard let intId = uuidToInt[dto.playerId] else { continue }
            scores[intId, default: [:]][dto.holeNum] = dto.score
        }

        // Compute current hole (max hole scored by any player)
        let currentHole = scores.values.flatMap { $0.keys }.max() ?? 0

        // Compute skins — must mirror RoundViewModel.calculateSkins exactly so the
        // home active card pill and the scorecard CashGamesBar agree.
        //
        // participatingPlayers excludes no-shows (players who scored zero holes across the
        // entire round). For an ACTIVE round we keep the full roundPlayers as the threshold
        // so the pot doesn't shrink while waiting for late scorers. For a CONCLUDED or
        // COMPLETED round we exclude no-shows entirely — they never put money in and
        // shouldn't block hole resolution or inflate the player count.
        let activeRoundPlayers = roundPlayers.filter { scores[$0.id]?.isEmpty == false }
        let roundIsDone = (roundDTO.status == "concluded" || roundDTO.status == "completed")
        let participatingPlayers: [Player] = roundIsDone ? activeRoundPlayers : roundPlayers
        let useNet = roundDTO.net
        let carriesEnabled = roundDTO.carries
        let handicapPct = roundDTO.handicapPercentage
        // STRICT: if we still don't have real per-hole data, skip skin computation.
        // The home active card will show $0 rather than wrong numbers based on default pars.
        guard let holes = resolvedTeeBox?.holes, !holes.isEmpty else {
            #if DEBUG
            print("[buildHomeRound] ⚠️ No holes available — returning round with empty winnings")
            #endif
            var emptyRound = HomeRound(
                id: roundDTO.id,
                groupName: groupName,
                courseName: courseName,
                players: roundPlayers,
                status: roundDTO.status == "active" ? .active : (roundDTO.status == "concluded" ? .concluded : .completed),
                currentHole: currentHole,
                totalHoles: 18,
                buyIn: buyIn,
                skinsWon: 0,
                totalSkins: 18,
                yourSkins: 0,
                invitedBy: nil,
                creatorId: creatorId,
                startedAt: nil,
                completedAt: nil,
                playerWinnings: [:],
                playerWonHoles: [:]
            )
            emptyRound.teeBox = resolvedTeeBox
            emptyRound.supabaseGroupId = supabaseGroupId
            emptyRound.scoringMode = ScoringMode(rawValue: roundDTO.scoringMode ?? "single") ?? .single
            emptyRound.skinRules = SkinRules(net: roundDTO.net, carries: roundDTO.carries, outright: roundDTO.outright, handicapPercentage: roundDTO.handicapPercentage)
            emptyRound.winningsDisplay = winningsDisplay ?? "gross"
            emptyRound.isQuickGame = isQuickGame
            emptyRound.scorerPlayerId = resolveCurrentGroupScorer(
                currentUserId: currentUserId,
                roundPlayers: roundPlayers,
                groupScorerIds: groupScorerIds
            )
            return emptyRound
        }

        var skinsWon = 0       // total skins awarded so far (carries baked in)
        var openSkins = 0      // pending/provisional holes (not all players scored)
        var pendingCarry = 0   // carries waiting to be picked up by the next outright winner
        var playerSkins: [Int: Int] = [:]
        var playerWonHoles: [Int: [Int]] = [:]
        var pendingLeaders: [HomeRound.PendingHoleLeader] = []  // provisional holes (some scored, not all)
        participatingPlayers.forEach { playerSkins[$0.id] = 0 }

        for holeNum in 1...18 {
            let hole = holes[holeNum - 1]

            // Effective scores for THIS hole, across all participating players
            let holeEntries: [(Int, Int)] = participatingPlayers.compactMap { p in
                guard let gross = scores[p.id]?[holeNum] else { return nil }
                if useNet, let teeBox = resolvedTeeBox {
                    let strokes = RoundViewModel.getStrokes(
                        handicapIndex: p.handicap,
                        holeHcp: hole.hcp,
                        teeBox: teeBox,
                        percentage: handicapPct
                    )
                    return (p.id, max(1, gross - strokes))
                } else if useNet {
                    let strokes = RoundViewModel.getStrokes(handicap: p.handicap, holeHcp: hole.hcp)
                    return (p.id, max(1, gross - strokes))
                }
                return (p.id, gross)
            }

            // A hole is finished when every PARTICIPATING player (not no-shows) scored it.
            // For active rounds, participating = full roster so nothing gets awarded until
            // every configured player has scored. For concluded/completed rounds, no-shows
            // are already excluded from participating, so the threshold matches reality.
            if holeEntries.count < participatingPlayers.count {
                openSkins += 1
                // Always capture an entry for in-flight holes so the "Pending Results"
                // sheet shows the full per-hole snapshot. If anyone has scored, capture
                // the current leader; otherwise emit a placeholder (leader: nil → "-" row).
                if !holeEntries.isEmpty,
                   let bestScore = holeEntries.map(\.1).min() {
                    let leaderIds = holeEntries.filter { $0.1 == bestScore }.map(\.0)
                    let leader = roundPlayers.first(where: { leaderIds.contains($0.id) })
                    pendingLeaders.append(HomeRound.PendingHoleLeader(
                        id: holeNum,
                        holeNum: holeNum,
                        leader: leader,
                        score: bestScore,
                        scored: holeEntries.count,
                        total: participatingPlayers.count
                    ))
                } else {
                    pendingLeaders.append(HomeRound.PendingHoleLeader(
                        id: holeNum,
                        holeNum: holeNum,
                        leader: nil,
                        score: 0,
                        scored: 0,
                        total: participatingPlayers.count
                    ))
                }
                continue
            }

            // All scored — resolve
            guard let bestScore = holeEntries.map(\.1).min() else { continue }
            let winners = holeEntries.filter { $0.1 == bestScore }
            if winners.count == 1 {
                let totalCarry = 1 + pendingCarry
                skinsWon += totalCarry
                let winnerId = winners[0].0
                playerSkins[winnerId, default: 0] += totalCarry
                playerWonHoles[winnerId, default: []].append(holeNum)
                pendingCarry = 0
            } else {
                // Tied — carry forward if enabled, otherwise squashed (money lost to the pot)
                if carriesEnabled {
                    pendingCarry += 1
                }
            }
        }

        // Pot = buyIn × participatingPlayers.count. For active rounds participating =
        // full roster (pot stable while waiting for late scorers). For done rounds
        // participating = only actual scorers (no-shows excluded — they never paid in).
        let potPlayerCount = participatingPlayers.count
        let pot = buyIn * max(potPlayerCount, 1)
        // Denominator for per-skin value:
        //   - Awarded skins (carries already baked in via skinsWon += totalCarry)
        //   - Plus holes still in play (not all players scored yet) — these hold
        //     a share of the pot while we wait for resolution
        //   - Unresolved pending carries at round end are squashed (money lost) and
        //     intentionally NOT counted in the denom, so remaining awarded skins take
        //     the full pot between them.
        let stillOpen = openSkins
        let estimatedTotalSkins = stillOpen == 0 ? skinsWon : (skinsWon + stillOpen)
        let skinValue = estimatedTotalSkins > 0 ? Double(pot) / Double(estimatedTotalSkins) : 0
        let displayMode = winningsDisplay ?? "gross"
        var playerWinnings: [Int: Int] = [:]
        for player in activeRoundPlayers {
            let skins = playerSkins[player.id] ?? 0
            let gross = Int((Double(skins) * skinValue).rounded())
            playerWinnings[player.id] = displayMode == "net" ? (gross - buyIn) : gross
        }

        let status: HomeRoundStatus = {
            switch roundDTO.status {
            case "active": return .active
            case "concluded": return .concluded
            default: return .completed
            }
        }()

        // Compute completed groups: how many groups have ALL players scored all 18.
        // Iterate ALL roundPlayers (not activeRoundPlayers) so a group with a player
        // who hasn't started yet correctly counts as "not done". Otherwise if Group 1
        // finished and Group 2 hasn't scored anything, the activeRoundPlayers filter
        // would drop Group 2 entirely → hasPendingResults breaks.
        let groupNums = Set(roundPlayers.map(\.group))
        let totalGroups = max(groupNums.count, 1)
        var completedGroups = 0
        for gNum in groupNums {
            let groupPlayers = roundPlayers.filter { $0.group == gNum }
            guard !groupPlayers.isEmpty else { continue }
            let allDone = groupPlayers.allSatisfy { p in
                (1...18).allSatisfy { hole in scores[p.id]?[hole] != nil }
            }
            if allDone { completedGroups += 1 }
        }

        // For concluded/completed rounds, the leaderboard and pills should only show
        // players who actually played. No-shows stay out of the display.
        // Active rounds keep the full roster so late scorers still appear in the pills.
        var round = HomeRound(
            id: roundDTO.id,
            groupName: groupName,
            courseName: courseName,
            players: participatingPlayers,
            status: status,
            currentHole: currentHole,
            totalHoles: 18,
            buyIn: buyIn,
            skinsWon: skinsWon,
            totalSkins: 18,
            yourSkins: currentUserId.flatMap { playerSkins[$0] } ?? 0,
            invitedBy: nil,
            creatorId: creatorId,
            totalGroups: totalGroups,
            completedGroups: completedGroups,
            startedAt: roundDTO.createdAt,
            completedAt: status == .completed ? roundDTO.createdAt : nil,
            scheduledDate: {
                // Prefer the current user's own group tee time (e.g. a Quick
                // Game scorer in group 2 should see their 9:30 slot, not the
                // group's first tee time). Falls back to scheduledDate when
                // no per-group array is persisted or the user isn't in this
                // round's player list.
                if let teeTimes, let uid = currentUserId,
                   let me = roundPlayers.first(where: { $0.id == uid }),
                   me.group >= 1, me.group <= teeTimes.count,
                   let mine = teeTimes[me.group - 1] {
                    return mine
                }
                return scheduledDate
            }(),
            playerWinnings: playerWinnings,
            playerWonHoles: playerWonHoles
        )
        round.teeBox = resolvedTeeBox
        round.supabaseGroupId = supabaseGroupId
        round.scorerPlayerId = resolveCurrentGroupScorer(
            currentUserId: currentUserId,
            roundPlayers: roundPlayers,
            groupScorerIds: groupScorerIds
        )
        round.scoringMode = ScoringMode(rawValue: roundDTO.scoringMode ?? "single") ?? .single
        round.skinRules = SkinRules(
            net: roundDTO.net,
            carries: roundDTO.carries,
            outright: roundDTO.outright,
            handicapPercentage: roundDTO.handicapPercentage
        )
        // Match internal pot math: pot is buyIn × participatingPlayers.count
        round.activePlayerCount = participatingPlayers.count
        round.winningsDisplay = displayMode
        round.pendingHoleLeaders = pendingLeaders
        round.isQuickGame = isQuickGame
        return round
    }
}
