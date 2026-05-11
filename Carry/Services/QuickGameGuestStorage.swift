import Foundation

/// Persistence for Quick Game between-round guest rosters. Two-layer:
/// UserDefaults (fast local read) + server-side `skins_groups.guest_roster_json`
/// (durable across app delete + reinstall + multi-device).
///
/// Background
/// ----------
/// Quick Game guest *profiles* live in `round_players` server-side only
/// when a round is active (locked 2026-05-01 ephemeral guest rule).
/// `loadSingleGroup` is deliberately Carry-only, so guests only re-surface
/// via `buildHomeRound` when there's an active or concluded round.
///
/// **Without an active round, guests had no server home** — they vanished on
/// app rebuild, force-quit, OS reap for memory pressure, app store updates,
/// or phone restart. The local UserDefaults snapshot mitigated process death
/// but not app delete + reinstall, and didn't sync across devices.
///
/// Strategy (post 2026-05-10 migration)
/// ------------------------------------
/// `save()` writes through to BOTH UserDefaults AND server's
/// `guest_roster_json` column. The server write debounces (0.8s) and retries
/// with exponential backoff (1s, 2s, 4s) before giving up. `load()` returns
/// the local UserDefaults copy. `hydrateFromServer()` is called by
/// `loadSingleGroup` to overwrite UserDefaults with server-truth — but
/// only when no local save fired in the last 8 seconds (race guard).
///
/// Race guard (5th instance of the `lastSavedAt` pattern — see
/// docs/architecture/refresh-race-guards.md)
/// -----------------------------------------------------------------
/// Without a guard, this scenario reverts a just-added guest:
///   1. User adds Bdbd → UserDefaults updated, async server write queued
///   2. Before server write replicates, user navigates out and back
///   3. `loadSingleGroup` runs → reads server (still stale, no Bdbd)
///   4. Hydrate overwrites UserDefaults → Bdbd disappears
///
/// Fix: every save() stamps `quickGameGuests_<uuid>_savedAt`. `hydrateFromServer`
/// skips the overwrite when the stamp is <8s old.
///
/// This does NOT violate any locked invariant:
///   - `group_members` stays Carry-only (guests live in a separate JSONB column)
///   - Guest profile rows still get wiped on round end (ephemeral guest rule)
///   - Carry users never appear in this column (filtered out at save time)
///
/// Cleanup
/// -------
/// - On Quick Game → Skins Group conversion: clear both layers (Skins
///   Groups can't have guests, by the same architectural invariant).
/// - On Quick Game deletion: clear both layers. (TODO: wire this from the
///   delete path; currently the snapshot leaks until UserDefaults is wiped.)
enum QuickGameGuestStorage {

    /// Lightweight Codable representation of a Quick Game guest. Captures
    /// only the fields needed to rehydrate the guest's display + tee-sheet
    /// position. Excludes computed properties (`shortName`, `swiftColor`,
    /// `hasPhoto`) and pending/invite flags (always false for guests).
    struct GuestSnapshot: Codable {
        let id: Int
        let name: String
        let initials: String
        let color: String
        let handicap: Double
        let avatar: String
        let group: Int
        let profileId: UUID?

        init(_ p: Player) {
            self.id = p.id
            self.name = p.name
            self.initials = p.initials
            self.color = p.color
            self.handicap = p.handicap
            self.avatar = p.avatar
            self.group = p.group
            self.profileId = p.profileId
        }

        var asPlayer: Player {
            Player(
                id: id,
                name: name,
                initials: initials,
                color: color,
                handicap: handicap,
                avatar: avatar,
                group: group,
                ghinNumber: nil,
                venmoUsername: nil,
                avatarImageName: nil,
                avatarUrl: nil,
                phoneNumber: nil,
                isPendingInvite: false,
                isPendingAccept: false,
                isGuest: true,
                profileId: profileId
            )
        }
    }

    /// Window during which `hydrateFromServer` skips the overwrite, treating
    /// UserDefaults as the source of truth. Mirrors the 8s constant used in
    /// the four GroupManagerView race guards.
    static let hydrateGuardWindow: TimeInterval = 8

    /// Server write debounce. Mirrors the 0.8s used by tee-time sync.
    private static let saveDebounce: UInt64 = 800_000_000

    /// Retry delays for the server write. 1s, 2s, 4s. After all three
    /// fail, we re-stamp `lastSavedAt` to extend the hydrate guard so
    /// the local roster is preserved until the next successful sync.
    private static let retryDelays: [UInt64] = [
        1_000_000_000,
        2_000_000_000,
        4_000_000_000,
    ]

    /// In-flight debounce/retry tasks per group. MainActor-isolated to
    /// avoid concurrent dict mutation.
    @MainActor
    private static var pendingTasks: [UUID: Task<Void, Never>] = [:]

    private static func key(_ groupId: UUID) -> String {
        "quickGameGuests_\(groupId.uuidString)"
    }

    private static func savedAtKey(_ groupId: UUID) -> String {
        "quickGameGuests_\(groupId.uuidString)_savedAt"
    }

    /// Save the current guest roster (deduped, guests only) for this group.
    /// No-op for non-Quick-Games. Writes UserDefaults synchronously, stamps
    /// `lastSavedAt` so the hydrate guard kicks in, then schedules a debounced
    /// server write with retry. Cancels any pending debounce for this group.
    ///
    /// Corruption guard (2026-05-10): never persists guests whose `name` is
    /// the literal "Guest" or whitespace-only. Such names only ever come from
    /// `buildHomeRound`'s wiped-guest fallback (GroupService.swift:1599) and
    /// were the load-bearing trigger of the "Guest+0.0 everywhere" bug — once
    /// in the snapshot, they propagate into round-start guest profile recreation
    /// and become permanent. Drop them at save time so the cycle never closes.
    @MainActor
    static func save(groupId: UUID, isQuickGame: Bool, allRosterPlayers: [Player]) {
        guard isQuickGame else { return }
        // Filter to true guests only (`isGuest` flag). Earlier this also
        // included `profileId == nil` to catch fresh-from-QuickStart slots
        // that hadn't been server-created yet, but that branch could
        // accidentally persist a Carry user whose profile hadn't loaded
        // (offline join, transient fetch failure, etc.) into the
        // guest_roster_json column. QuickStart slots always set
        // `isGuest = slot.existingProfileId == nil && !slot.isPendingInvite`
        // (QuickStartSheet.swift:1393), so the `isGuest` flag alone catches
        // them — without false positives on Carry users.
        let guestsOnly = allRosterPlayers.filter { $0.isGuest }
        var seen = Set<Int>()
        let deduped = guestsOnly.filter { seen.insert($0.id).inserted }
        let cleaned = deduped.filter {
            let trimmed = $0.name.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && trimmed != "Guest"
        }
        let snapshots = cleaned.map(GuestSnapshot.init)
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(data, forKey: key(groupId))
        // Stamp BEFORE the async server write fires. Otherwise a refresh
        // landing during the debounce or replication window stomps the
        // user's just-saved roster. See refresh-race-guards.md §5.
        UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: savedAtKey(groupId))

        let json = String(data: data, encoding: .utf8)
        scheduleServerSync(groupId: groupId, json: json)
    }

    /// Load the guest roster for this group from local UserDefaults.
    /// Returns the guests as `Player` objects. Empty array if no snapshot
    /// exists or decode fails.
    ///
    /// Corruption guard: drops any entry whose name is the literal "Guest"
    /// or whitespace-only — these are corrupted entries from the legacy
    /// "Guest"+0.0 bug (see save() doc above). Better to render the guest
    /// as missing than to leak a corrupted name into reconciliation.
    static func load(groupId: UUID) -> [Player] {
        guard let data = UserDefaults.standard.data(forKey: key(groupId)),
              let snapshots = try? JSONDecoder().decode([GuestSnapshot].self, from: data)
        else { return [] }
        return snapshots.compactMap { snap in
            let trimmed = snap.name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed != "Guest" else { return nil }
            return snap.asPlayer
        }
    }

    /// Reconcile UserDefaults with the server's `guest_roster_json` payload.
    /// Called from `loadSingleGroup` when a Quick Game is fetched.
    ///
    /// Skips the overwrite when a local save fired in the last 8 seconds —
    /// the server may not have replicated yet. Without this guard, navigating
    /// out and back during the debounce or retry window would stomp the
    /// user's just-saved roster.
    static func hydrateFromServer(groupId: UUID, json: String?) {
        let lastSavedAt = UserDefaults.standard.double(forKey: savedAtKey(groupId))
        if lastSavedAt > 0 {
            let age = Date().timeIntervalSinceReferenceDate - lastSavedAt
            if age < hydrateGuardWindow {
                return
            }
        }
        guard let json, let data = json.data(using: .utf8) else {
            UserDefaults.standard.removeObject(forKey: key(groupId))
            return
        }
        UserDefaults.standard.set(data, forKey: key(groupId))
    }

    /// Clear the snapshot for a group on BOTH layers. Call when the group is
    /// deleted, or converted from Quick Game to Skins Group.
    @MainActor
    static func clear(groupId: UUID) {
        UserDefaults.standard.removeObject(forKey: key(groupId))
        UserDefaults.standard.removeObject(forKey: savedAtKey(groupId))
        pendingTasks[groupId]?.cancel()
        pendingTasks[groupId] = nil
        Task { @MainActor in
            await syncToServerWithRetry(groupId: groupId, json: nil)
        }
    }

    // MARK: - Internals

    /// Cancel any pending debounce for this group, then schedule a new one.
    /// After the debounce fires, the server write attempts up to 3 times
    /// with exponential backoff.
    @MainActor
    private static func scheduleServerSync(groupId: UUID, json: String?) {
        pendingTasks[groupId]?.cancel()
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: saveDebounce)
            guard !Task.isCancelled else { return }
            await syncToServerWithRetry(groupId: groupId, json: json)
            pendingTasks[groupId] = nil
        }
        pendingTasks[groupId] = task
    }

    /// Server write with exponential backoff. On final failure, re-stamp
    /// `lastSavedAt` so the hydrate guard keeps treating UserDefaults as
    /// truth — the alternative is the next refresh clobbering the local
    /// roster with stale server state.
    private static func syncToServerWithRetry(groupId: UUID, json: String?) async {
        let service = GroupService()
        for (attempt, delay) in zip(0..<retryDelays.count, retryDelays) {
            do {
                try await service.saveGuestRoster(groupId: groupId, json: json)
                return
            } catch {
                let isLast = attempt == retryDelays.count - 1
                if isLast {
                    // Extend the guard so a refresh post-failure doesn't
                    // overwrite UserDefaults with the server's stale state.
                    // Logged outside DEBUG so production telemetry catches
                    // durable network outages.
                    UserDefaults.standard.set(
                        Date().timeIntervalSinceReferenceDate,
                        forKey: savedAtKey(groupId)
                    )
                    print("[QuickGameGuestStorage] server save failed after \(retryDelays.count) attempts: \(error)")
                    return
                }
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }
}
