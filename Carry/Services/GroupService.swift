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

    /// Fetch all active and invited members of a group.
    func fetchGroupMembers(groupId: UUID) async throws -> [GroupMemberDTO] {
        try await client.from("group_members")
            .select()
            .eq("group_id", value: groupId.uuidString)
            .in("status", values: ["active", "invited"])
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
        // Check for existing membership (any status)
        let existing: [GroupMemberDTO] = try await client.from("group_members")
            .select()
            .eq("group_id", value: groupId.uuidString)
            .eq("player_id", value: playerId.uuidString)
            .execute()
            .value
        guard existing.isEmpty else { return }

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

    /// Accept a group invite — sets status to "active".
    func acceptGroupInvite(membershipId: UUID) async throws {
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
    func removeMember(groupId: UUID, playerId: UUID) async throws {
        try await client.from("group_members")
            .update(["status": "removed"])
            .eq("group_id", value: groupId.uuidString)
            .eq("player_id", value: playerId.uuidString)
            .execute()
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

    /// Delete a group entirely — uses RPC to delete in FK-safe order.
    func deleteGroup(groupId: UUID) async throws {
        try await client.rpc("delete_group", params: ["gid": groupId.uuidString]).execute()
    }

    // MARK: - High-Level: Load SavedGroups

    /// Load all groups for a user, fully hydrated as SavedGroup objects.
    /// This is the main entry point for authenticated group loading.
    func loadGroups(userId: UUID) async throws -> [SavedGroup] {
        let groups = try await fetchMyGroups(userId: userId)
        guard !groups.isEmpty else { return [] }

        // Load all groups in parallel for faster startup
        return await withTaskGroup(of: SavedGroup?.self) { taskGroup in
            for group in groups {
                let service = self
                taskGroup.addTask {
                    try? await service.loadSingleGroup(groupId: group.id, userId: userId)
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
                        currentUserId: currentPlayerIntId,
                        teeBox: lastCourse?.teeBox,
                        supabaseGroupId: group.id,
                        winningsDisplay: group.winningsDisplay,
                        isQuickGame: group.isQuickGame ?? false
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

            let teeTimes = reconstructTeeTimes(
                scheduledDate: group.scheduledDate,
                teeTimeInterval: group.teeTimeInterval,
                groupCount: Set(players.map(\.group)).count
            )

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
    func loadSingleGroup(groupId: UUID, userId: UUID) async throws -> SavedGroup? {
        let groups: [SkinsGroupDTO] = try await client.from("skins_groups")
            .select()
            .eq("id", value: groupId.uuidString)
            .execute()
            .value
        guard let group = groups.first else { return nil }

        let members = try await fetchGroupMembers(groupId: group.id)

        // Separate phone-invited members from regular members
        let phoneInvites = members.filter { $0.invitedPhone != nil && !($0.invitedPhone ?? "").isEmpty && $0.status == "invited" }
        let regularMembers = members.filter { $0.invitedPhone == nil || ($0.invitedPhone ?? "").isEmpty }

        let profileIds = regularMembers.map(\.playerId)
        let profiles = try await fetchMemberProfiles(playerIds: profileIds)
        let invitedIds = Set(regularMembers.filter { $0.status == "invited" }.map(\.playerId))
        let groupNumMap = Dictionary(uniqueKeysWithValues: regularMembers.map { ($0.playerId, $0.groupNum ?? 1) })
        var players = profiles.map { profile -> Player in
            var player = Player(from: profile)
            if invitedIds.contains(profile.id) {
                player.isPendingAccept = true
            }
            player.group = groupNumMap[profile.id] ?? 1
            return player
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
        let activePlayers = players.filter { !$0.isPendingAccept }

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
                    currentUserId: currentPlayerIntId,
                    teeBox: lastCourse?.teeBox,
                    supabaseGroupId: group.id,
                    winningsDisplay: group.winningsDisplay,
                    isQuickGame: group.isQuickGame ?? false
                )
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

        let teeTimes = reconstructTeeTimes(
            scheduledDate: group.scheduledDate,
            teeTimeInterval: group.teeTimeInterval,
            groupCount: Set(players.map(\.group)).count
        )

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
            winningsDisplay: group.winningsDisplay ?? "gross"
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
    private func buildHomeRound(
        from roundDTO: RoundDTO,
        groupName: String,
        courseName: String,
        players: [Player],
        creatorId: Int,
        buyIn: Int,
        scheduledDate: Date? = nil,
        currentUserId: Int? = nil,
        teeBox: TeeBox? = nil,
        supabaseGroupId: UUID? = nil,
        winningsDisplay: String? = nil,
        isQuickGame: Bool = false
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
        if let rpDTOs: [RoundPlayerDTO] = try? await client.from("round_players")
            .select()
            .eq("round_id", value: roundDTO.id.uuidString)
            .execute()
            .value, !rpDTOs.isEmpty {
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
            scheduledDate: scheduledDate,
            playerWinnings: playerWinnings,
            playerWonHoles: playerWonHoles
        )
        round.teeBox = resolvedTeeBox
        round.supabaseGroupId = supabaseGroupId
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
