import Foundation
import Supabase

final class RoundService {
    private let client = SupabaseManager.shared.client

    // MARK: - Courses

    func createCourse(name: String, clubName: String?, holes: [Hole], userId: UUID) async throws -> CourseDTO {
        let course: CourseDTO = try await client.from("courses")
            .insert(CourseInsert(name: name, clubName: clubName, createdBy: userId))
            .select()
            .single()
            .execute()
            .value

        // Insert all holes
        let holeInserts = holes.map { hole in
            HoleInsert(courseId: course.id, num: hole.num, par: hole.par, hcp: hole.hcp)
        }
        try await client.from("holes")
            .insert(holeInserts)
            .execute()

        return course
    }

    func createTeeBox(courseId: UUID, teeBox: TeeBox) async throws -> TeeBoxDTO {
        // Encode per-hole data as JSON string for storage
        var holesJson: String? = nil
        if let holes = teeBox.holes {
            if let data = try? JSONEncoder().encode(holes) {
                holesJson = String(data: data, encoding: .utf8)
            }
        }
        return try await client.from("tee_boxes")
            .insert(TeeBoxInsert(
                courseId: courseId,
                name: teeBox.name,
                color: teeBox.color,
                courseRating: teeBox.courseRating,
                slopeRating: teeBox.slopeRating,
                par: teeBox.par,
                holesJson: holesJson
            ))
            .select()
            .single()
            .execute()
            .value
    }

    func fetchCourseHoles(courseId: UUID) async throws -> [HoleDTO] {
        try await client.from("holes")
            .select()
            .eq("course_id", value: courseId.uuidString)
            .order("num")
            .execute()
            .value
    }

    // MARK: - Rounds

    func createRound(courseId: UUID, createdBy: UUID, teeBoxId: UUID? = nil, buyIn: Int, net: Bool, carries: Bool, outright: Bool, handicapPercentage: Double = 1.0, groupId: UUID? = nil, scorerId: UUID? = nil, scoringMode: String = "single", players: [(userId: UUID, group: Int)]) async throws -> RoundDTO {
        let insertPayload = RoundInsert(
            courseId: courseId,
            createdBy: createdBy,
            teeBoxId: teeBoxId,
            buyIn: buyIn,
            gameType: "skins",
            net: net,
            carries: carries,
            outright: outright,
            handicapPercentage: handicapPercentage,
            groupId: groupId,
            scorerId: scorerId,
            scoringMode: scoringMode
        )

        // Insert round, then fetch it back (bare insert avoids trigger conflicts)
        try await client.from("rounds")
            .insert(insertPayload)
            .execute()

        let round: RoundDTO = try await client.from("rounds")
            .select()
            .eq("course_id", value: courseId.uuidString)
            .eq("created_by", value: createdBy.uuidString)
            .order("created_at", ascending: false)
            .limit(1)
            .single()
            .execute()
            .value

        // Add players to round. If this fails, the rounds row would be orphaned with
        // no players — roll it back so we don't leave junk in the DB.
        let playerInserts = players.map { p in
            RoundPlayerInsert(roundId: round.id, playerId: p.userId, groupNum: p.group)
        }
        do {
            try await client.from("round_players")
                .insert(playerInserts)
                .execute()
        } catch {
            #if DEBUG
            print("[RoundService] round_players insert failed — rolling back rounds row \(round.id): \(error)")
            #endif
            // Best-effort cleanup; ignore secondary failure
            _ = try? await client.from("rounds")
                .delete()
                .eq("id", value: round.id.uuidString)
                .execute()
            throw error
        }

        return round
    }

    /// Check whether a specific round still exists in the DB. Returns nil if deleted.
    func fetchRoundById(roundId: UUID) async throws -> RoundDTO? {
        let rounds: [RoundDTO] = try await client.from("rounds")
            .select()
            .eq("id", value: roundId.uuidString)
            .limit(1)
            .execute()
            .value
        return rounds.first
    }

    func fetchActiveRound(userId: UUID) async throws -> RoundDTO? {
        let rounds: [RoundDTO] = try await client.from("rounds")
            .select()
            .eq("status", value: "active")
            .eq("created_by", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rounds.first
    }

    /// Fetch all rounds for a group, newest first.
    func fetchRoundsForGroup(groupId: UUID) async throws -> [RoundDTO] {
        try await client.from("rounds")
            .select()
            .eq("group_id", value: groupId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Fan-in variant for the Games-feed poll: one query returns rounds
    /// for every group the user belongs to. The caller groups the result
    /// by `groupId` locally. Replaces N per-group fetches with a single
    /// `.in()` query, materially cutting Supabase traffic when the user
    /// has several groups.
    func fetchRoundsForGroups(groupIds: [UUID]) async throws -> [RoundDTO] {
        guard !groupIds.isEmpty else { return [] }
        return try await client.from("rounds")
            .select()
            .in("group_id", values: groupIds.map(\.uuidString))
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Update the designated scorer for a round.
    func updateScorer(roundId: UUID, scorerId: UUID) async throws {
        try await client.from("rounds")
            .update(["scorer_id": scorerId.uuidString])
            .eq("id", value: roundId.uuidString)
            .execute()
    }

    /// Update round status (e.g. "active" → "concluded" → "completed").
    /// Terminal-status transitions (completed) trigger a guest-profile wipe
    /// per the ephemeral-guest rule (see migration 20260501000001). For the
    /// 'concluded' transition we DON'T wipe yet — that's a transient state
    /// before the user decides Save vs Discard, and pre-final guest deletion
    /// would defeat any "go back" affordance. Wipe is invoked at:
    ///   - status='completed' here
    ///   - deleteRound (cancel)
    ///   - endGameDestructively (status='cancelled' + force_completed)
    ///   - forceEndRoundWithResults (status='concluded' + force_completed,
    ///     where the user has explicitly chosen to End & Save)
    ///   - convert_quick_game_to_group RPC (server-side, see migration 20260501000002)
    func updateRoundStatus(roundId: UUID, status: String) async throws {
        if status == "completed" {
            _ = try? await GuestProfileService().deleteQuickGameGuests(roundId: roundId)
        }
        try await client.from("rounds")
            .update(["status": status])
            .eq("id", value: roundId.uuidString)
            .execute()
    }

    /// Delete all scores for a round (used by Restart Round).
    func deleteScores(roundId: UUID) async throws {
        try await client.from("scores")
            .delete()
            .eq("round_id", value: roundId.uuidString)
            .execute()
    }

    /// Delete a round and all associated data (scores + round_players cascade via FK).
    /// Delete a round. `wipeGuests` controls whether guest profiles are also
    /// deleted (the ephemeral-guest rule, migration 20260501000001). Default
    /// `true` for backwards-compatible TERMINATION paths (e.g. Home tab history
    /// purge). Restart Round MUST pass `false` — restart is a continuation, not
    /// a termination, and wiping profiles on restart was the root cause of the
    /// 1.1.0/1.1.1 duplicate-guest bug (commit a74173e, 2026-05-02, added the
    /// unconditional wipe; this restores the pre-2026-05-02 working behavior on
    /// the restart path while keeping wipe semantics for true termination).
    func deleteRound(roundId: UUID, wipeGuests: Bool = true) async throws {
        if wipeGuests {
            // Wipe guests BEFORE deleting the round. The wipe RPC's auth check
            // requires the round to still exist (it reads round.created_by).
            // Once the round is deleted, round_players cascade-clean anyway,
            // so denormalization-into-round_players is moot here — but the
            // profile delete still happens, satisfying the ephemeral rule.
            _ = try? await GuestProfileService().deleteQuickGameGuests(roundId: roundId)
        }
        try await client.from("rounds")
            .delete()
            .eq("id", value: roundId.uuidString)
            .execute()
    }

    // MARK: - End Game (creator-only)

    /// End Game (destructive): marks the round cancelled + force_completed, deletes scores.
    /// The UPDATE fires the push trigger which fans `gameDeleted` out to every participant.
    /// Preserves the round row for history; status = 'cancelled' is the canonical signal.
    func endGameDestructively(roundId: UUID) async throws {
        // Wipe guests BEFORE deleteScores. The wipe denormalizes guest names
        // onto scores rows; deleteScores then removes those rows. round_players
        // still has the denormalized fields, which is what Round History reads.
        _ = try? await GuestProfileService().deleteQuickGameGuests(roundId: roundId)
        // Score delete first — if this fails, the round is still active (safer rollback).
        try await deleteScores(roundId: roundId)
        try await client.from("rounds")
            .update([
                "status": "cancelled",
                "force_completed": "true",
            ])
            .eq("id", value: roundId.uuidString)
            .execute()
    }

    /// End Game & Save Results: concludes the round with whatever scores exist, flips
    /// force_completed so every participant's client knows this was a forced end and
    /// should auto-show final results. Push trigger fans `gameForceEnded` out.
    func forceEndRoundWithResults(roundId: UUID) async throws {
        // Explicit user choice to End & Save — wipe guests now (the round
        // is terminal from this point; status flips to 'concluded' but
        // force_completed=true means it'll never go back to active).
        _ = try? await GuestProfileService().deleteQuickGameGuests(roundId: roundId)
        try await client.from("rounds")
            .update([
                "status": "concluded",
                "force_completed": "true",
            ])
            .eq("id", value: roundId.uuidString)
            .execute()
    }

    func fetchRoundPlayers(roundId: UUID) async throws -> [RoundPlayerDTO] {
        try await client.from("round_players")
            .select()
            .eq("round_id", value: roundId.uuidString)
            .execute()
            .value
    }

    /// Sync group_num on round_players for every active or concluded round in
    /// the given skins group. Called after the creator rearranges tee times so
    /// scorecards of in-flight rounds reflect the new group assignments.
    /// Completed rounds are historical and intentionally skipped.
    func syncRoundPlayersGroupNums(
        groupId: UUID,
        assignments: [(playerId: UUID, groupNum: Int)]
    ) async throws {
        let rounds: [RoundDTO] = try await client.from("rounds")
            .select()
            .eq("group_id", value: groupId.uuidString)
            .in("status", values: ["active", "concluded"])
            .execute()
            .value
        guard !rounds.isEmpty else { return }
        for round in rounds {
            for assignment in assignments {
                let updates: [String: Int] = ["group_num": assignment.groupNum]
                _ = try? await client.from("round_players")
                    .update(updates)
                    .eq("round_id", value: round.id.uuidString)
                    .eq("player_id", value: assignment.playerId.uuidString)
                    .execute()
            }
        }
    }

    func fetchPlayerProfiles(playerIds: [UUID]) async throws -> [ProfileDTO] {
        let ids = playerIds.map { $0.uuidString }
        return try await client.from("profiles")
            .select()
            .in("id", values: ids)
            .execute()
            .value
    }

    // MARK: - Scores

    func fetchScores(roundId: UUID) async throws -> [ScoreDTO] {
        try await client.from("scores")
            .select()
            .eq("round_id", value: roundId.uuidString)
            .execute()
            .value
    }

    func upsertScore(roundId: UUID, playerId: UUID, holeNum: Int, score: Int) async throws {
        try await client.from("scores")
            .upsert(
                ScoreInsert(roundId: roundId, playerId: playerId, holeNum: holeNum, score: score),
                onConflict: "round_id,player_id,hole_num"
            )
            .execute()
    }

    // MARK: - Score Proposals (Everyone Scores mode)

    /// Propose a score change (sets proposed_score and proposed_by on existing score row).
    func proposeScoreChange(roundId: UUID, playerId: UUID, holeNum: Int, proposedScore: Int, proposedBy: UUID) async throws {
        let payload = ScoreProposalUpdate(proposedScore: proposedScore, proposedBy: proposedBy)
        try await client.from("scores")
            .update(payload)
            .eq("round_id", value: roundId.uuidString)
            .eq("player_id", value: playerId.uuidString)
            .eq("hole_num", value: holeNum)
            .execute()
    }

    /// Resolve a score proposal — accept (apply proposed score) or reject (discard proposal).
    func resolveProposal(roundId: UUID, playerId: UUID, holeNum: Int, accept: Bool) async throws {
        if accept {
            // Fetch the proposed score first
            let scores: [ScoreDTO] = try await client.from("scores")
                .select()
                .eq("round_id", value: roundId.uuidString)
                .eq("player_id", value: playerId.uuidString)
                .eq("hole_num", value: holeNum)
                .execute()
                .value
            guard let scoreRow = scores.first, let proposed = scoreRow.proposedScore else {
                #if DEBUG
                print("[RoundService] resolveProposal: no proposed score found")
                #endif
                return
            }
            // Accept: set score to proposed, clear proposal fields
            let updates: [String: AnyJSON] = [
                "score": .integer(proposed),
                "proposed_score": .null,
                "proposed_by": .null
            ]
            try await client.from("scores")
                .update(updates)
                .eq("round_id", value: roundId.uuidString)
                .eq("player_id", value: playerId.uuidString)
                .eq("hole_num", value: holeNum)
                .execute()
            #if DEBUG
            print("[RoundService] resolveProposal: accepted, score set to \(proposed)")
            #endif
        } else {
            // Reject: just clear the proposal fields
            let updates: [String: AnyJSON] = [
                "proposed_score": .null,
                "proposed_by": .null
            ]
            try await client.from("scores")
                .update(updates)
                .eq("round_id", value: roundId.uuidString)
                .eq("player_id", value: playerId.uuidString)
                .eq("hole_num", value: holeNum)
                .execute()
            #if DEBUG
            print("[RoundService] resolveProposal: rejected, proposal cleared")
            #endif
        }
    }

    // MARK: - Realtime

    func subscribeToScores(roundId: UUID, onChange: @escaping (ScoreDTO) -> Void) -> RealtimeChannelV2 {
        let channel = client.realtimeV2.channel("scores-\(roundId.uuidString)")

        // Register both postgres_changes hooks BEFORE calling subscribe, then
        // await subscribe exactly once, then fan out into separate tasks to
        // consume each stream. Previously the UPDATE task's for-await started
        // without waiting for subscribe, so early UPDATE events fired before
        // the channel was live could be missed — users had to cancel + restart
        // a Quick Game round before cross-group scores began flowing.
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "scores",
            filter: .eq("round_id", value: roundId.uuidString)
        )
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "scores",
            filter: .eq("round_id", value: roundId.uuidString)
        )

        Task {
            try? await channel.subscribeWithError()
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await change in inserts {
                        if let score = try? change.decodeRecord(as: ScoreDTO.self, decoder: JSONDecoder()) {
                            await MainActor.run { onChange(score) }
                        }
                    }
                }
                group.addTask {
                    for await change in updates {
                        do {
                            let decoder = JSONDecoder()
                            decoder.dateDecodingStrategy = .custom { decoder in
                                let container = try decoder.singleValueContainer()
                                let str = try container.decode(String.self)
                                let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ", "yyyy-MM-dd'T'HH:mm:ssZZZZZ", "yyyy-MM-dd'T'HH:mm:ss"]
                                for fmt in formats {
                                    let f = DateFormatter()
                                    f.locale = Locale(identifier: "en_US_POSIX")
                                    f.dateFormat = fmt
                                    if let d = f.date(from: str) { return d }
                                }
                                return Date()
                            }
                            let score = try change.decodeRecord(as: ScoreDTO.self, decoder: decoder)
                            #if DEBUG
                            print("[RoundService] realtime UPDATE decoded: hole=\(score.holeNum) proposed=\(String(describing: score.proposedScore))")
                            #endif
                            await MainActor.run { onChange(score) }
                        } catch {
                            #if DEBUG
                            print("[RoundService] realtime UPDATE decode FAILED: \(error)")
                            #endif
                        }
                    }
                }
            }
        }

        return channel
    }

    func unsubscribe(channel: RealtimeChannelV2) {
        Task {
            await channel.unsubscribe()
        }
    }
}
