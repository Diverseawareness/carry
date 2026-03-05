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

    func fetchCourseHoles(courseId: UUID) async throws -> [HoleDTO] {
        try await client.from("holes")
            .select()
            .eq("course_id", value: courseId.uuidString)
            .order("num")
            .execute()
            .value
    }

    // MARK: - Rounds

    func createRound(courseId: UUID, createdBy: UUID, teeBoxId: UUID? = nil, buyIn: Int, net: Bool, carries: Bool, outright: Bool, handicapPercentage: Double = 1.0, players: [(userId: UUID, group: Int)]) async throws -> RoundDTO {
        let round: RoundDTO = try await client.from("rounds")
            .insert(RoundInsert(
                courseId: courseId,
                createdBy: createdBy,
                teeBoxId: teeBoxId,
                buyIn: buyIn,
                gameType: "skins",
                net: net,
                carries: carries,
                outright: outright,
                handicapPercentage: handicapPercentage
            ))
            .select()
            .single()
            .execute()
            .value

        // Add players to round
        let playerInserts = players.map { p in
            RoundPlayerInsert(roundId: round.id, playerId: p.userId, groupNum: p.group)
        }
        try await client.from("round_players")
            .insert(playerInserts)
            .execute()

        return round
    }

    func fetchActiveRound(userId: UUID) async throws -> RoundDTO? {
        let rounds: [RoundDTO] = try await client.from("rounds")
            .select()
            .eq("status", value: "active")
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rounds.first
    }

    func fetchRoundPlayers(roundId: UUID) async throws -> [RoundPlayerDTO] {
        try await client.from("round_players")
            .select()
            .eq("round_id", value: roundId.uuidString)
            .execute()
            .value
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

    // MARK: - Realtime

    func subscribeToScores(roundId: UUID, onChange: @escaping (ScoreDTO) -> Void) -> RealtimeChannelV2 {
        let channel = client.realtimeV2.channel("scores-\(roundId.uuidString)")

        let changes = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "scores",
            filter: "round_id=eq.\(roundId.uuidString)"
        )

        Task {
            await channel.subscribe()
            for await change in changes {
                if let score = try? change.decodeRecord(as: ScoreDTO.self, decoder: JSONDecoder()) {
                    await MainActor.run { onChange(score) }
                }
            }
        }

        // Also listen for updates (score corrections)
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "scores",
            filter: "round_id=eq.\(roundId.uuidString)"
        )

        Task {
            for await change in updates {
                if let score = try? change.decodeRecord(as: ScoreDTO.self, decoder: JSONDecoder()) {
                    await MainActor.run { onChange(score) }
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
