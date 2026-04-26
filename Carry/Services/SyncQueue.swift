import Foundation
import Network
import UIKit

/// Queues failed Supabase writes and retries when connectivity returns.
/// Designed for on-course use where cell signal is unreliable.
@MainActor
final class SyncQueue: ObservableObject {
    static let shared = SyncQueue()

    @Published var pendingCount: Int = 0
    @Published var isOnline: Bool = true

    private let storageKey = "carry.syncQueue"
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "carry.network.monitor")
    private var retryTask: Task<Void, Never>?
    private var periodicRetryTask: Task<Void, Never>?
    private let roundService = RoundService()

    /// How often to re-attempt the queue while the app is in the foreground.
    /// Short enough that a scorer won't finish a hole with stale data queued,
    /// long enough not to hammer Supabase during a flaky-signal scroll.
    private let periodicRetryInterval: Duration = .seconds(30)

    private init() {
        loadQueue()
        startMonitoring()
        startPeriodicRetry()
        // Flush queued scores when app returns to foreground
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.pendingCount > 0, self.isOnline else { return }
                self.flushQueue()
            }
        }
    }

    /// Foreground retry loop. Without this the queue only flushed on
    /// foreground/network transitions — a score that failed while the user
    /// kept the app open and online would sit unsynced until they
    /// backgrounded the app, meaning the round could finalize with missing
    /// scores. The loop attempts a flush every 30s whenever there's pending
    /// work, so the indicator can't persist past that window.
    private func startPeriodicRetry() {
        periodicRetryTask?.cancel()
        periodicRetryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.periodicRetryInterval ?? .seconds(30))
                if Task.isCancelled { return }
                await MainActor.run {
                    guard let self, self.pendingCount > 0, self.isOnline else { return }
                    self.flushQueue()
                }
            }
        }
    }

    // MARK: - Connectivity

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = path.status == .satisfied
                // Came back online — flush the queue
                if wasOffline && self.isOnline && self.pendingCount > 0 {
                    self.flushQueue()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Queue Operations

    /// Enqueue a score upsert for retry. Called when the direct Supabase call fails.
    func enqueueScore(roundId: UUID, playerId: UUID, holeNum: Int, score: Int) {
        var queue = loadEntries()
        // Deduplicate — replace existing entry for same round/player/hole
        queue.removeAll { $0.roundId == roundId && $0.playerId == playerId && $0.holeNum == holeNum }
        queue.append(SyncEntry(
            roundId: roundId,
            playerId: playerId,
            holeNum: holeNum,
            score: score,
            createdAt: Date()
        ))
        saveEntries(queue)
        pendingCount = queue.count
    }

    /// Attempt to flush all queued entries to Supabase.
    func flushQueue() {
        retryTask?.cancel()
        retryTask = Task {
            let queue = loadEntries()
            guard !queue.isEmpty else { return }

            var remaining: [SyncEntry] = []
            for entry in queue {
                // Skip entries older than 7 days
                if entry.createdAt.timeIntervalSinceNow < -7 * 24 * 60 * 60 { continue }

                do {
                    try await roundService.upsertScore(
                        roundId: entry.roundId,
                        playerId: entry.playerId,
                        holeNum: entry.holeNum,
                        score: entry.score
                    )
                } catch {
                    // Still failing — keep in queue
                    remaining.append(entry)
                }

                // Check cancellation between entries
                if Task.isCancelled { return }
            }

            await MainActor.run {
                self.saveEntries(remaining)
                self.pendingCount = remaining.count
                if remaining.isEmpty {
                    ToastManager.shared.success("Scores synced")
                }
            }
        }
    }

    // MARK: - Persistence

    private struct SyncEntry: Codable {
        let roundId: UUID
        let playerId: UUID
        let holeNum: Int
        let score: Int
        let createdAt: Date
    }

    private func loadEntries() -> [SyncEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([SyncEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private func saveEntries(_ entries: [SyncEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadQueue() {
        pendingCount = loadEntries().count
    }
}
