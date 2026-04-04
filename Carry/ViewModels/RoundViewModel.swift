import Foundation
import SwiftUI
import Supabase
import Combine

class RoundViewModel: ObservableObject {
    let config: RoundConfig
    let currentUserId: Int
    let allPlayers: [Player]
    let holes: [Hole]
    private let roundKey: String
    private let roundService = RoundService()
    // Map Int player IDs → Supabase UUIDs (populated from Player.profileId)
    let playerUUIDs: [Int: UUID]
    // Reverse map: UUID → Int player ID (for realtime score ingestion)
    private let uuidToPlayerId: [UUID: Int]
    // Realtime subscription channel (nil in devMode)
    private var scoreChannel: RealtimeChannelV2?
    // Polling timer for cross-group score sync (15s interval)
    private var pollingCancellable: AnyCancellable?

    @Published var scores: [Int: [Int: Int]]  // [playerID: [holeNum: score]]
    @Published var activeHole: Int?
    @Published var celebration: CelebrationEvent?
    @Published var isRoundComplete = false
    @Published var forceCompleted = false
    @Published var myGroupFinished = false
    @Published var pendingSkinCelebrations: [SkinCelebration] = []
    @Published private(set) var cachedSkins: [Int: SkinStatus] = [:]
    @Published var gameEvents: [GameEvent] = []
    @Published var activeProposal: (playerId: Int, holeNum: Int, original: Int, proposed: Int, proposedByUUID: UUID)? = nil

    /// When a proposal is active, no one can enter new scores until it's resolved.
    var isScoringBlocked: Bool { activeProposal != nil }

    private var celebratedSkinHoles: Set<Int> = []
    private var emittedEventHoles: Set<Int> = []  // dedup for game events
    private var emittedCarryHoles: Set<Int> = []  // dedup for carry events

    // Computed: players in current user's group (falls back to first group if currentUserId not found)
    private var myGroup: GroupConfig? {
        config.groups.first(where: { $0.playerIDs.contains(currentUserId) }) ?? config.groups.first
    }

    var groupPlayers: [Player] {
        guard let group = myGroup else { return [] }
        return group.playerIDs.compactMap { pid in allPlayers.first(where: { $0.id == pid }) }
    }

    /// Players who have scored at least one hole — excludes no-shows (e.g. solo group member who never joined).
    var activePlayers: [Player] {
        allPlayers.filter { p in scores[p.id]?.values.isEmpty == false }
    }

    // Dynamic front/back nine derived from instance holes (respects API par data)
    var front9: [Hole] { Array(holes.prefix(9)) }
    var back9: [Hole] { Array(holes.suffix(9)) }
    var frontPar: Int { front9.reduce(0) { $0 + $1.par } }
    var backPar: Int { back9.reduce(0) { $0 + $1.par } }
    var totalPar: Int { holes.reduce(0) { $0 + $1.par } }

    // Play order based on starting side
    var playOrder: [Hole] {
        guard let group = myGroup else { return holes }
        return group.startingSide == "front" ? front9 + back9 : back9 + front9
    }

    // MARK: - Handicap & Strokes

    /// Simple stroke allocation using raw handicap index (fallback when no tee box).
    /// Rounds decimal handicap to nearest integer, distributes across 18 holes by difficulty.
    static func getStrokes(handicap: Double, holeHcp: Int) -> Int {
        let rHcp = Int(handicap.rounded())
        if rHcp <= 0 { return 0 }
        return rHcp / 18 + (holeHcp <= rHcp % 18 ? 1 : 0)
    }

    /// Full USGA Course Handicap calculation using tee box data.
    /// Course Handicap = Index x (Slope / 113) + (CR - Par)
    /// Playing Handicap = Course Handicap x percentage
    /// Then distributes playing handicap strokes across holes by difficulty.
    static func getStrokes(handicapIndex: Double, holeHcp: Int, teeBox: TeeBox, percentage: Double) -> Int {
        let playingHcp = teeBox.playingHandicap(forIndex: handicapIndex, percentage: percentage)
        return TeeBox.strokesOnHole(playingHandicap: playingHcp, holeHcp: holeHcp)
    }

    /// Get strokes for a player on a specific hole, using tee box if available.
    func strokes(for player: Player, hole: Hole) -> Int {
        if let teeBox = config.teeBox {
            return Self.getStrokes(
                handicapIndex: player.handicap,
                holeHcp: hole.hcp,
                teeBox: teeBox,
                percentage: config.skinRules.handicapPercentage
            )
        }
        // Fallback: simple allocation using raw index
        return Self.getStrokes(handicap: player.handicap, holeHcp: hole.hcp)
    }

    /// Get playing handicap for a player (total strokes across all 18 holes).
    func playingHandicap(for player: Player) -> Int {
        if let teeBox = config.teeBox {
            return teeBox.playingHandicap(
                forIndex: player.handicap,
                percentage: config.skinRules.handicapPercentage
            )
        }
        return Int(player.handicap.rounded())
    }

    func netScore(gross: Int, player: Player, hole: Hole) -> Int {
        max(1, gross - strokes(for: player, hole: hole))
    }

    /// Recalculate skins and update the published cache.
    @discardableResult
    func calculateSkins() -> [Int: SkinStatus] {
        let carriesEnabled = config.skinRules.carries
        let useNet = config.skinRules.net
        var skins: [Int: SkinStatus] = [:]
        var pendingCarry = 0  // accumulated skins from prior squashed holes

        for hole in holes {
            let hNum = hole.num

            // Collect scores from ALL players across all groups
            struct NetEntry {
                let player: Player
                let gross: Int
                let net: Int  // effective score (net if enabled, gross otherwise)
            }

            // Use activePlayers so no-shows (zero scores) are excluded from skins
            let participating = activePlayers
            let nets: [NetEntry] = participating.compactMap { p in
                guard let gross = scores[p.id]?[hNum] else { return nil }
                let effective = useNet ? max(1, gross - strokes(for: p, hole: hole)) : gross
                return NetEntry(player: p, gross: gross, net: effective)
            }

            // When force-completed, treat hole as finished if 2+ players scored (ignore missing players)
            let allFinished = forceCompleted
                ? nets.count >= 2
                : participating.allSatisfy { scores[$0.id]?[hNum] != nil }

            if nets.isEmpty {
                skins[hNum] = .pending
                // pendingCarry persists — will apply to the first resolved hole
            } else if nets.count < 2 && !forceCompleted {
                // Only 1 player scored — show as provisional, can't award skin yet
                guard let bestNet = nets.map(\.net).min() else { continue }
                let leaders = nets.filter { $0.net == bestNet }
                let bestGross = leaders.map(\.gross).min() ?? 0
                skins[hNum] = .provisional(leaders: leaders.map(\.player), bestNet: bestNet, bestGross: bestGross, scored: nets.count, total: participating.count)
            } else if nets.count < 2 {
                // Force-completed but only 1 scorer on this hole — unawarded
                skins[hNum] = .pending
            } else if !allFinished {
                // Not all players scored this hole — provisional
                guard let bestNet = nets.map(\.net).min() else { continue }
                let leaders = nets.filter { $0.net == bestNet }
                let bestGross = leaders.map(\.gross).min() ?? 0
                skins[hNum] = .provisional(leaders: leaders.map(\.player), bestNet: bestNet, bestGross: bestGross, scored: nets.count, total: participating.count)
            } else {
                guard let bestNet = nets.map(\.net).min() else { continue }
                let winners = nets.filter { $0.net == bestNet }
                if winners.count == 1 {
                    // Outright win — collect this skin + any carried skins
                    let totalCarry = 1 + pendingCarry
                    skins[hNum] = .won(winner: winners[0].player, bestNet: bestNet, bestGross: winners[0].gross, carry: totalCarry)
                    pendingCarry = 0
                } else {
                    // Tied / squashed
                    if carriesEnabled {
                        skins[hNum] = .carried  // value moves to next hole
                        pendingCarry += 1
                    } else {
                        skins[hNum] = .squashed(tiedPlayers: winners.map(\.player), bestNet: bestNet, carry: 0)
                        // pendingCarry stays 0 in no-carries mode
                    }
                }
            }
        }

        // Unresolved carries after hole 18: simply unawarded (standard skins rules)
        cachedSkins = skins
        return skins
    }

    // Money model — pot counts only players who actually played (have at least one score)
    var pot: Int { config.buyIn * max(activePlayers.count, 1) }

    func moneyTotals() -> [Int: Int] {
        let skins = cachedSkins
        let participating = activePlayers

        var skinsWon: [Int: Int] = [:]
        participating.forEach { skinsWon[$0.id] = 0 }

        for (_, status) in skins {
            if case .won(let winner, _, _, let carry) = status {
                skinsWon[winner.id, default: 0] += carry
            }
        }

        let totalSkinsAwarded = skins.values.reduce(0) { total, status in
            if case .won(_, _, _, let carry) = status { return total + carry }
            return total
        }

        let openCount = skins.values.reduce(0) { total, status in
            switch status {
            case .pending, .provisional, .carried: return total + 1
            case .won, .squashed: return total
            }
        }

        let estimatedTotalSkins = openCount == 0 ? totalSkinsAwarded : (totalSkinsAwarded + openCount)
        let skinValue = estimatedTotalSkins > 0 ? Double(pot) / Double(estimatedTotalSkins) : 0

        var totals: [Int: Int] = [:]
        participating.forEach { p in
            if totalSkinsAwarded > 0 {
                totals[p.id] = Int((Double(skinsWon[p.id] ?? 0) * skinValue - Double(config.buyIn)).rounded())
            } else {
                totals[p.id] = 0
            }
        }

        return totals
    }

    /// Skins won per player (carries included in count).
    func skinsWonByPlayer() -> [Int: Int] {
        let skins = cachedSkins
        var result: [Int: Int] = [:]
        activePlayers.forEach { result[$0.id] = 0 }
        for (_, status) in skins {
            if case .won(let winner, _, _, let carry) = status {
                result[winner.id, default: 0] += carry
            }
        }
        return result
    }

    var skinValue: Double {
        let skins = cachedSkins
        let totalWon = skins.values.reduce(0) { total, status in
            if case .won(_, _, _, let carry) = status { return total + carry }
            return total
        }
        let stillOpen = skins.values.reduce(0) { total, status in
            switch status {
            case .pending, .provisional, .carried: return total + 1
            default: return total
            }
        }
        let est = stillOpen == 0 ? totalWon : (totalWon + stillOpen)
        guard est > 0 else { return 0 }
        return Double(pot) / Double(est)
    }

    var skinsStillOpen: Int {
        let skins = cachedSkins
        return skins.values.reduce(0) { total, status in
            switch status {
            case .pending, .provisional, .carried: return total + 1
            default: return total
            }
        }
    }

    // Active hole — first hole where ANY group player hasn't scored (drives scorecard navigation)
    func computeActiveHole() -> Int? {
        for hole in playOrder {
            if groupPlayers.contains(where: { scores[$0.id]?[hole.num] == nil }) {
                return hole.num
            }
        }
        return nil
    }

    /// True when all participating players (those with at least one score) have scored all 18 holes.
    /// No-shows (zero scores) are excluded so they don't block round completion.
    var allGroupsFinished: Bool {
        let participating = activePlayers
        guard !participating.isEmpty else { return false }
        return participating.allSatisfy { player in
            holes.allSatisfy { hole in scores[player.id]?[hole.num] != nil }
        }
    }

    // Allow scoring: (a) any hole already scored by a group player, or
    // (b) holes at or before the active hole in play order.
    func canScore(holeNum: Int) -> Bool {
        guard let active = activeHole else { return true }   // round complete → all editable

        // Any hole that already has a score from a group player can be edited
        let hasScore = groupPlayers.contains { scores[$0.id]?[holeNum] != nil }
        if hasScore { return true }

        // Otherwise, only allow holes up to and including the active hole
        guard let activeIdx = playOrder.firstIndex(where: { $0.num == active }),
              let holeIdx = playOrder.firstIndex(where: { $0.num == holeNum }) else { return true }
        return holeIdx <= activeIdx
    }

    // Clear a previously entered score
    func clearScore(playerId: Int, holeNum: Int) {
        scores[playerId]?[holeNum] = nil
        activeHole = computeActiveHole()
    }

    // Clear all scores (used by Restart Round)
    func clearAllScores() {
        scores = [:]
        ScoreStorage.shared.save(scores: scores, forKey: roundKey)
        activeHole = computeActiveHole()
        calculateSkins()
        isRoundComplete = false
    }

    // Enter score for any player
    func enterScore(playerId: Int, holeNum: Int, score: Int) {
        // Everyone Scores mode: if cell already has a DIFFERENT score, propose instead of overwriting
        if config.scoringMode == .everyone,
           let existing = scores[playerId]?[holeNum],
           existing != score,
           let roundId = config.supabaseRoundId,
           let playerUUID = playerUUIDs[playerId] {
            // Find the current user's UUID to record who proposed the change
            let proposerUUID = playerUUIDs[currentUserId] ?? UUID()
            activeProposal = (playerId: playerId, holeNum: holeNum, original: existing, proposed: score, proposedByUUID: proposerUUID)
            Task {
                try? await roundService.proposeScoreChange(
                    roundId: roundId,
                    playerId: playerUUID,
                    holeNum: holeNum,
                    proposedScore: score,
                    proposedBy: proposerUUID
                )
            }
            return
        }

        scores[playerId, default: [:]][holeNum] = score
        ScoreStorage.shared.save(scores: scores, forKey: roundKey)

        // Sync score to Supabase — queue for retry if offline/failed
        if let roundId = config.supabaseRoundId, let playerUUID = playerUUIDs[playerId] {
            Task {
                do {
                    try await roundService.upsertScore(
                        roundId: roundId,
                        playerId: playerUUID,
                        holeNum: holeNum,
                        score: score
                    )
                } catch {
                    // Network failed — queue for retry when connectivity returns
                    await SyncQueue.shared.enqueueScore(
                        roundId: roundId,
                        playerId: playerUUID,
                        holeNum: holeNum,
                        score: score
                    )
                }
            }
        }

        checkForNewSkinWins()
        let hasSkinCelebration = !pendingSkinCelebrations.isEmpty

        let newActive = computeActiveHole()
        // If all group players finished this hole, delay before advancing the indicator
        // Extra delay when a skin was just won so the confetti plays first
        if newActive != activeHole && newActive != nil {
            let delay: Double = hasSkinCelebration ? 1.5 : 0.6
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self?.activeHole = self?.computeActiveHole()
                }
            }
        } else {
            activeHole = newActive
        }

        // Check if local group finished all 18 — show pending results
        if computeActiveHole() == nil && !myGroupFinished {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.myGroupFinished = true
            }
        }

        // Check for round complete — only when ALL groups across ALL players have scored every hole
        if allGroupsFinished && !isRoundComplete {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.isRoundComplete = true
                if let roundId = self?.config.supabaseRoundId {
                    Task { try? await self?.roundService.updateRoundStatus(roundId: roundId, status: "concluded") }
                }
            }
        }

        // Check for celebration
        if let hole = holes.first(where: { $0.num == holeNum }),
           let player = allPlayers.first(where: { $0.id == playerId }) {
            let label = ScoreLabel.from(score: score, par: hole.par)
            if label.isMoment {
                celebration = CelebrationEvent(
                    id: UUID(),
                    player: player,
                    hole: holeNum,
                    type: label == .hio ? .hio : label == .eagle ? .eagle : .birdie
                )
            }
        }
    }

    // MARK: - Proposal Resolution

    /// Resolve the active score proposal (accept or reject).
    /// Does NOT clear activeProposal locally — the realtime subscription handles that
    /// when the proposed_score column becomes NULL.
    func resolveActiveProposal(accept: Bool) {
        guard let proposal = activeProposal,
              let roundId = config.supabaseRoundId,
              let playerUUID = playerUUIDs[proposal.playerId] else {
            #if DEBUG
            print("[RoundVM] resolveActiveProposal: missing proposal/roundId/playerUUID")
            #endif
            return
        }
        #if DEBUG
        print("[RoundVM] resolveActiveProposal: accept=\(accept) hole=\(proposal.holeNum) player=\(playerUUID)")
        #endif
        Task {
            do {
                try await roundService.resolveProposal(
                    roundId: roundId,
                    playerId: playerUUID,
                    holeNum: proposal.holeNum,
                    accept: accept
                )
                await MainActor.run {
                    if accept {
                        scores[proposal.playerId, default: [:]][proposal.holeNum] = proposal.proposed
                        ScoreStorage.shared.save(scores: scores, forKey: roundKey)
                        calculateSkins()
                    }
                    activeProposal = nil
                }
            } catch {
                #if DEBUG
                print("[RoundVM] resolveActiveProposal failed: \(error)")
                #endif
                await MainActor.run { activeProposal = nil }
            }
        }
    }

    // MARK: - Supabase Realtime

    /// Subscribe to realtime score changes from other players/scorers.
    private func subscribeToRealtimeScores() {
        guard let roundId = config.supabaseRoundId else {
            #if DEBUG
            print("[RoundVM] subscribeToRealtimeScores: NO roundId, skipping")
            #endif
            return
        }
        #if DEBUG
        print("[RoundVM] subscribeToRealtimeScores: subscribing to roundId=\(roundId)")
        #endif
        scoreChannel = roundService.subscribeToScores(roundId: roundId) { [weak self] scoreDTO in
            self?.handleRemoteScore(scoreDTO)
        }
    }

    /// Start a 15-second polling timer for cross-group score sync.
    /// Detects new skin wins from other groups and fires celebrations + notifications.
    private func startScorePolling() {
        guard config.supabaseRoundId != nil else { return }
        pollingCancellable = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Don't poll if the round is already complete
                guard !self.isRoundComplete else {
                    self.pollingCancellable?.cancel()
                    return
                }
                Task { await self.pollAndDetectNewSkins() }
            }
    }

    /// Poll Supabase for scores and detect newly won skins since last check.
    private func pollAndDetectNewSkins() async {
        guard let roundId = config.supabaseRoundId else { return }

        // Snapshot current won skins before refresh
        let previousWonHoles: Set<Int> = await MainActor.run {
            Set(cachedSkins.compactMap { holeNum, status in
                if case .won = status { return holeNum }
                return nil
            })
        }

        do {
            let scoreDTOs = try await roundService.fetchScores(roundId: roundId)
            guard !scoreDTOs.isEmpty else { return }

            await MainActor.run {
                var updated = false
                for dto in scoreDTOs {
                    guard let intId = uuidToPlayerId[dto.playerId] else { continue }
                    let existing = scores[intId]?[dto.holeNum]
                    if existing == nil || existing != dto.score {
                        scores[intId, default: [:]][dto.holeNum] = dto.score
                        updated = true
                    }
                }

                guard updated else { return }
                ScoreStorage.shared.save(scores: scores, forKey: roundKey)
                activeHole = computeActiveHole()

                // Recalculate skins and detect new wins
                let newSkins = calculateSkins()
                for (holeNum, status) in newSkins {
                    if case .won(let winner, _, _, let carry) = status,
                       !previousWonHoles.contains(holeNum) {
                        // New skin won from cross-group data

                        // Fire celebration if winner is in our group
                        if !celebratedSkinHoles.contains(holeNum) {
                            celebratedSkinHoles.insert(holeNum)
                            let isInMyGroup = groupPlayers.contains(where: { $0.id == winner.id })
                            if isInMyGroup {
                                pendingSkinCelebrations.append(
                                    SkinCelebration(holeNum: holeNum, winner: winner, carry: carry)
                                )
                            }
                        }

                        // Emit game event
                        if !emittedEventHoles.contains(holeNum) {
                            emittedEventHoles.insert(holeNum)
                            let lastGroup = config.groups.count <= 1 ||
                                myGroup?.id == config.groups.last?.id
                            gameEvents.append(.skinWon(player: winner, holeNum: holeNum, isLastGroup: lastGroup))
                        }

                        // Send local notification for cross-group skin
                        NotificationService.shared.notifySkinWon(
                            playerName: winner.name,
                            holeNum: holeNum
                        )
                    }
                }

                // Also check for carry building events
                if config.skinRules.carries {
                    checkForCarryEvents(skins: newSkins)
                }

                // Check if local group finished
                if self.computeActiveHole() == nil && !self.myGroupFinished {
                    self.myGroupFinished = true
                }

                // Check for round complete — all groups finished
                if self.allGroupsFinished && !isRoundComplete {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                        self?.isRoundComplete = true
                        if let roundId = self?.config.supabaseRoundId {
                            Task { try? await self?.roundService.updateRoundStatus(roundId: roundId, status: "concluded") }
                        }
                    }
                }
            }
        } catch {
            #if DEBUG
            print("[RoundViewModel] Polling failed: \(error)")
            #endif
        }
    }

    /// Handle an incoming remote score update.
    private func handleRemoteScore(_ dto: ScoreDTO) {
        guard let intId = uuidToPlayerId[dto.playerId] else {
            #if DEBUG
            print("[RoundVM] handleRemoteScore: unknown player \(dto.playerId)")
            #endif
            return
        }

        #if DEBUG
        print("[RoundVM] handleRemoteScore: hole=\(dto.holeNum) player=\(dto.playerId) score=\(dto.score) proposed=\(String(describing: dto.proposedScore)) proposedBy=\(String(describing: dto.proposedBy))")
        #endif

        // Detect proposal state changes (Everyone Scores mode) — only within same group
        let isInMyGroup = groupPlayers.contains(where: { $0.id == intId })
        if isInMyGroup, let proposedScore = dto.proposedScore, let proposedBy = dto.proposedBy {
            // A new proposal arrived — show the dispute modal
            let original = scores[intId]?[dto.holeNum] ?? dto.score
            #if DEBUG
            print("[RoundVM] Proposal detected: original=\(original) proposed=\(proposedScore)")
            #endif
            activeProposal = (playerId: intId, holeNum: dto.holeNum, original: original, proposed: proposedScore, proposedByUUID: proposedBy)
            return
        } else if dto.proposedScore == nil, activeProposal != nil {
            // Proposal was resolved (proposed_score cleared) — dismiss modal, apply score, skip race detection
            #if DEBUG
            print("[RoundVM] Proposal resolved, clearing modal for hole=\(dto.holeNum)")
            #endif
            activeProposal = nil
            scores[intId, default: [:]][dto.holeNum] = dto.score
            ScoreStorage.shared.save(scores: scores, forKey: roundKey)
            calculateSkins()
            return
        }

        let existing = scores[intId]?[dto.holeNum]

        // Race condition detection (Everyone Scores): we just wrote a score for this cell
        // but real-time returned a DIFFERENT value — someone else wrote at the same time
        // Only detect conflicts for players in the same group (cross-group conflicts are expected)
        if config.scoringMode == .everyone,
           isInMyGroup,
           let existing = existing,
           existing != dto.score,
           dto.proposedScore == nil,
           activeProposal == nil {
            // Race condition — write proposal to Supabase so ALL devices see the conflict
            let proposedBy = playerUUIDs[currentUserId] ?? dto.playerId
            #if DEBUG
            print("[RoundVM] Race condition detected: hole=\(dto.holeNum) local=\(existing) remote=\(dto.score), writing proposal")
            #endif
            activeProposal = (playerId: intId, holeNum: dto.holeNum, original: dto.score, proposed: existing, proposedByUUID: proposedBy)
            if let roundId = config.supabaseRoundId {
                Task {
                    try? await roundService.proposeScoreChange(
                        roundId: roundId,
                        playerId: dto.playerId,
                        holeNum: dto.holeNum,
                        proposedScore: existing,
                        proposedBy: proposedBy
                    )
                }
            }
            return
        }

        // Only apply if it's a new or changed score (avoid re-triggering our own writes)
        guard existing == nil || existing != dto.score else { return }
        scores[intId, default: [:]][dto.holeNum] = dto.score
        ScoreStorage.shared.save(scores: scores, forKey: roundKey)
        activeHole = computeActiveHole()
        calculateSkins()
    }

    deinit {
        pollingCancellable?.cancel()
        if let channel = scoreChannel {
            roundService.unsubscribe(channel: channel)
        }
    }

    // MARK: - Supabase Score Loading

    private func loadScoresFromSupabase() async {
        guard let roundId = config.supabaseRoundId else { return }
        do {
            let scoreDTOs = try await roundService.fetchScores(roundId: roundId)

            // If Supabase has no scores, clear local scores (new round after end)
            if scoreDTOs.isEmpty {
                await MainActor.run {
                    let hadScores = scores.values.contains { !$0.isEmpty }
                    if hadScores {
                        scores = [:]
                        ScoreStorage.shared.save(scores: scores, forKey: roundKey)
                        activeHole = computeActiveHole()
                        calculateSkins()
                    }
                }
                return
            }

            // Merge Supabase scores into local scores
            await MainActor.run {
                var updated = false
                for dto in scoreDTOs {
                    guard let intId = uuidToPlayerId[dto.playerId] else { continue }
                    let existing = scores[intId]?[dto.holeNum]
                    if existing == nil || existing != dto.score {
                        scores[intId, default: [:]][dto.holeNum] = dto.score
                        updated = true
                    }
                }
                if updated {
                    ScoreStorage.shared.save(scores: scores, forKey: roundKey)
                    activeHole = computeActiveHole()
                    calculateSkins()

                    // Check if local group finished after loading scores
                    if computeActiveHole() == nil && !myGroupFinished {
                        myGroupFinished = true
                    }
                    if allGroupsFinished && !isRoundComplete {
                        isRoundComplete = true
                    }
                }
            }
        } catch {
            #if DEBUG
            print("[RoundViewModel] Failed to load scores from Supabase: \(error)")
            #endif
            await MainActor.run {
                ToastManager.shared.error("Couldn't load scores")
            }
        }
    }

    // Section totals (using dynamic holes from API data)
    func frontTotal(for playerId: Int) -> Int {
        front9.reduce(0) { $0 + (scores[playerId]?[$1.num] ?? 0) }
    }

    func backTotal(for playerId: Int) -> Int {
        back9.reduce(0) { $0 + (scores[playerId]?[$1.num] ?? 0) }
    }

    func total(for playerId: Int) -> Int {
        frontTotal(for: playerId) + backTotal(for: playerId)
    }

    func hasFrontScores(for playerId: Int) -> Bool {
        front9.contains { scores[playerId]?[$0.num] != nil }
    }

    func hasBackScores(for playerId: Int) -> Bool {
        back9.contains { scores[playerId]?[$0.num] != nil }
    }

    #if DEBUG
    // MARK: - Demo mid-game scores
    //
    // Holes 1-6 pre-populated for all 12 players (Blue tees, 100% handicap).
    // Results: H1 Dan wins, H2 squashed (Garret+Tyson), H3 Tyson wins,
    //          H4 squashed (6-way), H5 Adi wins, H6 squashed (Garret+Adi+Tyson).
    // → 3 skins won after 6 holes, hole 7 is the active hole.
    static let demoMidGameScores: [Int: [Int: Int]] = [
        //     H1  H2  H3  H4  H5  H6
        1:  [1:3, 2:4, 3:5, 4:4, 5:5, 6:4],  // Daniel     (phcp 7)
        2:  [1:4, 2:3, 3:5, 4:3, 5:5, 6:3],  // Garret     (phcp 2)
        3:  [1:4, 2:4, 3:5, 4:3, 5:3, 6:3],  // Adi        (phcp 0)
        4:  [1:4, 2:5, 3:7, 4:4, 5:6, 6:5],  // Bartholomew(phcp 16)
        5:  [1:4, 2:4, 3:5, 4:4, 5:5, 6:4],  // Keith      (phcp 7)
        6:  [1:4, 2:3, 3:3, 4:4, 5:4, 6:3],  // Tyson      (phcp 0/+)
        7:  [1:4, 2:4, 3:6, 4:4, 5:5, 6:4],  // Ryan       (phcp 10)
        8:  [1:4, 2:4, 3:5, 4:4, 5:5, 6:4],  // AJ         (phcp 2)
        9:  [1:4, 2:4, 3:5, 4:4, 5:5, 6:4],  // Ronnie     (phcp 6)
        10: [1:4, 2:4, 3:6, 4:4, 5:5, 6:4],  // Cameron    (phcp 7)
        11: [1:4, 2:5, 3:6, 4:4, 5:6, 6:4],  // Jai        (phcp 13)
        12: [1:4, 2:5, 3:7, 4:4, 5:6, 6:5],  // Frank      (phcp 15)
    ]

    // MARK: - Demo full-game scores (all 18 holes, all 12 players)
    //
    // Extends the mid-game data through hole 18.
    // Creates varied skins distribution for a realistic leaderboard.
    static let demoFullGameScores: [Int: [Int: Int]] = {
        var s = demoMidGameScores
        // Holes 7-18 scores for all 12 players
        let extra: [Int: [Int: Int]] = [
            1:  [7:4, 8:3, 9:5, 10:4, 11:4, 12:3, 13:5, 14:4, 15:4, 16:3, 17:4, 18:5], // Daniel
            2:  [7:4, 8:4, 9:4, 10:3, 11:5, 12:4, 13:4, 14:3, 15:5, 16:4, 17:4, 18:4], // Garret
            3:  [7:3, 8:4, 9:4, 10:4, 11:4, 12:4, 13:3, 14:4, 15:4, 16:4, 17:3, 18:4], // Adi
            4:  [7:5, 8:5, 9:6, 10:5, 11:5, 12:5, 13:6, 14:5, 15:5, 16:5, 17:5, 18:6], // Bartholomew
            5:  [7:4, 8:4, 9:5, 10:4, 11:4, 12:4, 13:5, 14:4, 15:4, 16:4, 17:5, 18:4], // Keith
            6:  [7:3, 8:4, 9:4, 10:4, 11:3, 12:4, 13:4, 14:4, 15:3, 16:4, 17:4, 18:4], // Tyson
            7:  [7:5, 8:4, 9:5, 10:4, 11:5, 12:4, 13:5, 14:5, 15:4, 16:4, 17:5, 18:5], // Ryan
            8:  [7:4, 8:3, 9:4, 10:4, 11:4, 12:4, 13:4, 14:4, 15:4, 16:3, 17:4, 18:4], // AJ
            9:  [7:4, 8:4, 9:4, 10:4, 11:4, 12:4, 13:5, 14:4, 15:4, 16:4, 17:4, 18:5], // Ronnie
            10: [7:4, 8:5, 9:5, 10:4, 11:5, 12:4, 13:5, 14:4, 15:5, 16:4, 17:5, 18:5], // Cameron
            11: [7:5, 8:5, 9:6, 10:5, 11:5, 12:5, 13:6, 14:5, 15:5, 16:5, 17:6, 18:6], // Jai
            12: [7:5, 8:6, 9:6, 10:5, 11:6, 12:5, 13:6, 14:5, 15:6, 16:5, 17:6, 18:6], // Frank
        ]
        for (pid, holes) in extra {
            for (h, score) in holes {
                s[pid, default: [:]][h] = score
            }
        }
        return s
    }()

    // MARK: - Demo hole-17 scores (holes 1-17 scored, hole 18 is active)
    //
    // Full game data minus hole 18 — lets you fill in the last hole and trigger round complete.
    static let demoHole17Scores: [Int: [Int: Int]] = {
        var s = demoFullGameScores
        for pid in s.keys {
            s[pid]?.removeValue(forKey: 18)
        }
        return s
    }()

    // MARK: - Demo confetti test (player 1 missing holes 16 + 17)
    //
    // Enter hole 16 score → skin resolves + confetti fires.
    // Hole 17 stays unscored so the round doesn't complete.
    static let demoHole18TestScores: [Int: [Int: Int]] = {
        var s = demoFullGameScores
        s[1]?.removeValue(forKey: 16)
        s[1]?.removeValue(forKey: 17)
        s[1]?.removeValue(forKey: 18)
        return s
    }()

    // MARK: - Demo pill celebration test
    //
    // Custom scores designed to test pill confetti + reorder animation.
    // Player 1 missing holes 14, 16, 17.
    // Skin distribution: Tyson 4, Adi 3, Daniel 2, AJ 2.
    // Entering hole 14 → Adi wins → ties Tyson at top.
    // Entering hole 16 → Adi wins again → TAKES SOLE LEAD.
    // Entering hole 17 → squash → round completes.
    //
    // Winners get birdie (par-1), all others get bogey (par+1).
    // Squash holes: everyone gets par.
    // This guarantees unique skin winners regardless of handicap strokes.
    static let demoPillCelebrationScores: [Int: [Int: Int]] = {
        let pars: [Int: Int] = [
            1:4, 2:4, 3:5, 4:3, 5:4, 6:3,
            7:4, 8:3, 9:4, 10:5, 11:4, 12:4,
            13:4, 14:4, 15:3, 16:4, 17:3, 18:5
        ]
        // Hole → winner player ID (nil = squash/tie)
        let winners: [Int: Int?] = [
            1: 6,      // Tyson
            2: 3,      // Adi
            3: 6,      // Tyson
            4: 6,      // Tyson
            5: 1,      // Daniel
            6: nil,    // squash
            7: 3,      // Adi
            8: nil,    // squash
            9: 6,      // Tyson
            10: 8,     // AJ
            11: 3,     // Adi
            12: 1,     // Daniel
            13: 8,     // AJ
            14: 3,     // Adi (player 1 pending) → ties Tyson
            15: nil,   // squash
            16: 3,     // Adi (player 1 pending) → TAKES THE LEAD
            17: nil,   // squash (player 1 pending)
            18: nil,   // squash
        ]
        let pendingHoles: Set<Int> = [14, 16, 17]

        var scores: [Int: [Int: Int]] = [:]
        for pid in 1...12 {
            var ps: [Int: Int] = [:]
            for hole in 1...18 {
                if pid == 1 && pendingHoles.contains(hole) { continue }
                let par = pars[hole]!
                if let wid = winners[hole], wid == pid {
                    ps[hole] = par - 1  // birdie
                } else if winners[hole] != nil {
                    ps[hole] = par + 1  // bogey (non-winner)
                } else {
                    ps[hole] = par      // squash — everyone pars
                }
            }
            scores[pid] = ps
        }
        return scores
    }()

    // MARK: - Demo pending results (group 1 done, others missing last 3 holes)
    //
    // Group 1 (players 1-4) has all 18 holes scored → round completes.
    // Groups 2 & 3 are missing holes 16-18 → "Pending Results" with pending skins.
    static let demoProvisionalScores: [Int: [Int: Int]] = {
        var s = demoFullGameScores
        // Remove holes 16-18 for players in groups 2 & 3
        for pid in [5, 6, 7, 8, 9, 10, 11, 12] {
            s[pid]?.removeValue(forKey: 16)
            s[pid]?.removeValue(forKey: 17)
            s[pid]?.removeValue(forKey: 18)
        }
        return s
    }()

    // MARK: - Demo carries scores (10 holes, carries-enabled)
    //
    // H1-2: all tie (net) → carried, carried
    // H3: Daniel wins outright → 3x carry
    // H4: Adi wins outright → 1x normal
    // H5-6: all tie → carried, carried
    // H7: Garret wins outright → 3x carry
    // H8-10: partial scores (provisional/pending)
    static let demoCarriesScores: [Int: [Int: Int]] = [
        1:  [1:4, 2:4, 3:2, 4:4, 5:5, 6:4, 7:4, 8:3, 9:4, 10:5],  // Daniel
        2:  [1:4, 2:4, 3:3, 4:4, 5:5, 6:4, 7:3, 8:3, 9:4, 10:5],  // Garret
        3:  [1:4, 2:4, 3:3, 4:3, 5:5, 6:4, 7:4, 8:4, 9:4, 10:5],  // Adi
        4:  [1:5, 2:5, 3:4, 4:5, 5:6, 6:5, 7:5, 8:4, 9:5],        // Bartholomew (missing H10)
        5:  [1:4, 2:4, 3:3, 4:4, 5:5, 6:4, 7:4, 8:4, 9:4, 10:5],  // Keith
        6:  [1:4, 2:4, 3:3, 4:4, 5:5, 6:4, 7:4, 8:4, 9:4, 10:5],  // Tyson
        7:  [1:4, 2:5, 3:4, 4:4, 5:6, 6:5, 7:5, 8:4, 9:5],        // Ryan (missing H10)
        8:  [1:4, 2:4, 3:3, 4:4, 5:5, 6:4, 7:4, 8:3, 9:4, 10:5],  // AJ
        9:  [1:4, 2:4, 3:3, 4:4, 5:5, 6:4, 7:4, 8:4, 9:4],        // Ronnie (missing H10)
        10: [1:4, 2:5, 3:4, 4:4, 5:5, 6:5, 7:5, 8:5, 9:5],        // Cameron (missing H10)
        11: [1:5, 2:5, 3:4, 4:5, 5:6, 6:5, 7:5, 8:5],             // Jai (missing H9-10)
        12: [1:5, 2:6, 3:5, 4:5, 5:7, 6:5, 7:6, 8:5],             // Frank (missing H9-10)
    ]
    #endif

    // MARK: - Init

    enum DemoMode {
        case none, midGame, hole17, hole18Test, pillCelebration, fullGame, provisionalResults, carries, confettiTest
    }

    init(config: RoundConfig, currentUserId: Int = 1, demoScores: Bool = false, demoMode: DemoMode = .none) {
        self.config = config
        self.currentUserId = currentUserId
        self.allPlayers = config.players
        // Use real per-hole data from API if available, otherwise fall back to defaults
        self.holes = config.holes ?? config.teeBox?.holes ?? Hole.allHoles
        #if DEBUG
        if config.holes != nil || config.teeBox?.holes != nil {
            let source = config.holes != nil ? "config.holes" : "teeBox.holes"
            let totalPar = self.holes.reduce(0) { $0 + $1.par }
            print("[RoundViewModel] Using API hole data from \(source): totalPar=\(totalPar)")
        } else {
            print("[RoundViewModel] No API hole data, using Hole.allHoles defaults")
        }
        #endif
        self.roundKey = config.id
        // Build Int→UUID lookup for Supabase score sync
        var uuids: [Int: UUID] = [:]
        for player in config.players {
            if let profileId = player.profileId {
                uuids[player.id] = profileId
            }
        }
        self.playerUUIDs = uuids
        // Build reverse lookup
        var reverse: [UUID: Int] = [:]
        for (intId, uuid) in uuids { reverse[uuid] = intId }
        self.uuidToPlayerId = reverse

        let mode: DemoMode = demoScores ? .midGame : demoMode
        var s: [Int: [Int: Int]] = [:]
        switch mode {
        case .none:
            // Try to load saved scores first
            if let saved = ScoreStorage.shared.load(forKey: config.id) {
                s = saved
                // Ensure all players have an entry
                config.players.forEach { if s[$0.id] == nil { s[$0.id] = [:] } }
            } else {
                config.players.forEach { s[$0.id] = [:] }
            }
        #if DEBUG
        case .midGame:
            config.players.forEach { s[$0.id] = RoundViewModel.demoMidGameScores[$0.id] ?? [:] }
        case .hole17:
            config.players.forEach { s[$0.id] = RoundViewModel.demoHole17Scores[$0.id] ?? [:] }
        case .hole18Test:
            config.players.forEach { s[$0.id] = RoundViewModel.demoHole18TestScores[$0.id] ?? [:] }
        case .pillCelebration:
            config.players.forEach { s[$0.id] = RoundViewModel.demoPillCelebrationScores[$0.id] ?? [:] }
        case .fullGame:
            config.players.forEach { s[$0.id] = RoundViewModel.demoFullGameScores[$0.id] ?? [:] }
        case .provisionalResults:
            config.players.forEach { s[$0.id] = RoundViewModel.demoProvisionalScores[$0.id] ?? [:] }
        case .carries:
            config.players.forEach { s[$0.id] = RoundViewModel.demoCarriesScores[$0.id] ?? [:] }
        case .confettiTest:
            config.players.forEach { s[$0.id] = RoundViewModel.demoHole18TestScores[$0.id] ?? [:] }
        #else
        default:
            config.players.forEach { s[$0.id] = [:] }
        #endif
        }

        self.scores = s
        self.activeHole = nil
        self.activeHole = computeActiveHole()

        // Pre-populate celebrated skins + emitted events so demo/loaded data doesn't trigger confetti or toasts
        let initialSkins = calculateSkins()
        for (holeNum, status) in initialSkins {
            if case .won = status {
                celebratedSkinHoles.insert(holeNum)
                emittedEventHoles.insert(holeNum)
            }
            if case .carried = status {
                emittedCarryHoles.insert(holeNum)
            }
        }

        // Load scores from Supabase if available (supplements local cache)
        if mode == .none, config.supabaseRoundId != nil {
            Task { await loadScoresFromSupabase() }
            subscribeToRealtimeScores()
            startScorePolling()
        }

        #if DEBUG
        print("[RoundViewModel.init] CREATED — holes=\(self.holes.count) H3par=\(self.holes.first(where: { $0.num == 3 })?.par ?? -1) H8par=\(self.holes.first(where: { $0.num == 8 })?.par ?? -1)")
        #endif

        // Debug: auto-fire confetti test — simulate notification opening scorecard
        #if DEBUG
        if mode == .confettiTest {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                // Enter score on hole 16 for player 1 — triggers skin win + confetti + toast
                self?.enterScore(playerId: 1, holeNum: 16, score: 3)
            }
        }
        #endif

        // Debug: test toasts on scorecard demos
        #if DEBUG
        if mode == .midGame || mode == .carries {
            let players = self.allPlayers
            if players.count > 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.gameEvents.append(.skinWon(player: players[1], holeNum: 7))
                }
            }
            if players.count > 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
                    self?.gameEvents.append(.skinWon(player: players[2], holeNum: 8))
                }
            }
            if mode == .carries {
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                    self?.gameEvents.append(.carryBuilding(holeNum: 12, carryCount: 3, skinValue: 100))
                }
            }
        }
        #endif

        // If local group already done (e.g. rejoining after finishing), trigger results sheet
        let hasScores = !s.values.allSatisfy({ $0.isEmpty })
        if hasScores {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                if self.computeActiveHole() == nil {
                    self.myGroupFinished = true
                }
                if self.allGroupsFinished {
                    self.isRoundComplete = true
                }
            }
        }
    }

    // MARK: - Skin Celebrations

    struct SkinCelebration: Identifiable {
        let id = UUID()
        let holeNum: Int
        let winner: Player
        let carry: Int
    }

    private func checkForNewSkinWins() {
        let skins = calculateSkins()
        for (holeNum, status) in skins {
            if case .won(let winner, _, _, let carry) = status,
               !celebratedSkinHoles.contains(holeNum) {
                celebratedSkinHoles.insert(holeNum)
                pendingSkinCelebrations.append(
                    SkinCelebration(holeNum: holeNum, winner: winner, carry: carry)
                )
                // Emit game event for toast
                if !emittedEventHoles.contains(holeNum) {
                    emittedEventHoles.insert(holeNum)
                    let lastGroup = config.groups.count <= 1 ||
                        myGroup?.id == config.groups.last?.id
                    gameEvents.append(.skinWon(player: winner, holeNum: holeNum, isLastGroup: lastGroup))
                }
            }
        }
        // Check for carry building events
        if config.skinRules.carries {
            checkForCarryEvents(skins: skins)
        }
    }

    /// Detect consecutive carried holes and emit carry building events
    private func checkForCarryEvents(skins: [Int: SkinStatus]) {
        var consecutiveCarries = 0
        for hole in holes {
            if case .carried = skins[hole.num] {
                consecutiveCarries += 1
                if consecutiveCarries >= 2 && !emittedCarryHoles.contains(hole.num) {
                    emittedCarryHoles.insert(hole.num)
                    let carryValue = Int(Double(consecutiveCarries + 1) * skinValue)
                    gameEvents.append(.carryBuilding(
                        holeNum: hole.num,
                        carryCount: consecutiveCarries + 1,
                        skinValue: carryValue
                    ))
                }
            } else {
                consecutiveCarries = 0
            }
        }
    }

    func consumeSkinCelebration(_ celebration: SkinCelebration) {
        pendingSkinCelebrations.removeAll { $0.id == celebration.id }
    }

    func consumeGameEvent(_ event: GameEvent) {
        gameEvents.removeAll { $0.id == event.id }
    }

    // MARK: - Types

    struct CelebrationEvent: Identifiable {
        let id: UUID
        let player: Player
        let hole: Int
        let type: CelebrationType
    }

    enum CelebrationType {
        case birdie, eagle, hio, skinWon
    }

    // MARK: - Share Scorecard

    /// Generate a shareable text summary of the current round.
    func generateScorecard() -> String {
        var lines: [String] = []
        lines.append("⛳ \(config.groupName) — \(config.course)")
        lines.append("")

        let skinResults = skinsWonByPlayer()

        for player in groupPlayers {
            let playerScores = scores[player.id] ?? [:]
            let holesPlayed = playerScores.count
            let totalStrokes = playerScores.values.reduce(0, +)
            let skinsWon = skinResults[player.id] ?? 0

            var line = "\(player.name): \(totalStrokes) (\(holesPlayed)H)"
            if skinsWon > 0 {
                line += " · \(skinsWon) skin\(skinsWon == 1 ? "" : "s")"
            }
            lines.append(line)
        }

        if config.buyIn > 0 {
            lines.append("")
            lines.append("💰 $\(config.buyIn)/player")
        }

        lines.append("")
        lines.append("Tracked with Carry")
        return lines.joined(separator: "\n")
    }
}
