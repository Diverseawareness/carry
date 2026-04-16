//
//  LiveActivityService.swift
//  Carry
//
//  Thin wrapper around ActivityKit for the round Live Activity.
//  One activity at a time — starting a new round ends any previous one.
//
//  Safe to call from any context: all ActivityKit work is hopped to @MainActor internally.
//
//  Cleanup strategy (3 layers):
//    1. staleDate — every start/update sets a 10-minute stale window. If the app
//       is killed and can't refresh, iOS dims + auto-removes the banner.
//    2. cleanupOrphanedActivities() — called on app launch, ends any activities
//       that survived a force-quit or crash.
//    3. applicationWillTerminate — ends activities when the app is killed from
//       the foreground (best-effort; iOS doesn't always call this).
//

import Foundation
import ActivityKit
import OSLog

final class LiveActivityService {
    static let shared = LiveActivityService()

    private let log = Logger(subsystem: "com.diverseawareness.carry", category: "LiveActivity")

    /// How long before an un-refreshed activity goes stale. Every update resets
    /// this clock, so it only fires if the app is killed and stops updating.
    private let staleDuration: TimeInterval = 10 * 60  // 10 minutes

    // Touched only from MainActor internals — safe as unsafe
    nonisolated(unsafe) private var currentActivity: Activity<CarryRoundAttributes>?

    private init() {}

    // MARK: - Start

    func start(
        roundId: String,
        courseName: String,
        groupName: String?,
        totalHoles: Int,
        groupId: String?,
        initialState: CarryRoundAttributes.ContentState
    ) {
        Task { @MainActor in
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                self.log.info("Live Activities disabled by user; skipping start")
                return
            }

            let nextStale = Date().addingTimeInterval(self.staleDuration)

            // Already tracking this round? Just update state + reset stale clock.
            if let existing = self.currentActivity, existing.attributes.roundId == roundId {
                await existing.update(ActivityContent(state: initialState, staleDate: nextStale))
                return
            }

            // End any previous activity first.
            await self.endAllInternal()

            let attributes = CarryRoundAttributes(
                roundId: roundId,
                courseName: courseName,
                groupName: groupName,
                totalHoles: totalHoles,
                groupId: groupId
            )

            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: initialState, staleDate: nextStale),
                    pushType: nil
                )
                self.currentActivity = activity
                self.log.info("Started Live Activity for round \(roundId, privacy: .public)")
            } catch {
                self.log.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Update

    func update(_ state: CarryRoundAttributes.ContentState) {
        Task { @MainActor in
            guard let activity = self.currentActivity else { return }
            let nextStale = Date().addingTimeInterval(self.staleDuration)
            await activity.update(ActivityContent(state: state, staleDate: nextStale))
        }
    }

    // MARK: - End

    func end(finalState: CarryRoundAttributes.ContentState? = nil) {
        Task { @MainActor in
            guard let activity = self.currentActivity else { return }
            let content = finalState.map { ActivityContent(state: $0, staleDate: nil) }
            await activity.end(content, dismissalPolicy: .immediate)
            self.currentActivity = nil
            self.log.info("Ended Live Activity")
        }
    }

    func endAll() {
        Task { @MainActor in
            await self.endAllInternal()
        }
    }

    // MARK: - Orphan Cleanup (call on app launch)

    /// End any Live Activities left over from a previous session (force-quit, crash,
    /// or OOM kill). Safe to call every launch — no-ops if nothing is active.
    func cleanupOrphanedActivities() {
        Task { @MainActor in
            let orphans = Activity<CarryRoundAttributes>.activities
            guard !orphans.isEmpty else { return }
            self.log.info("Cleaning up \(orphans.count) orphaned Live Activit\(orphans.count == 1 ? "y" : "ies")")
            for activity in orphans {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            self.currentActivity = nil
        }
    }

    @MainActor
    private func endAllInternal() async {
        for activity in Activity<CarryRoundAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        self.currentActivity = nil
    }
}
