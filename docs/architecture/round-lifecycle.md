# Round Lifecycle State Machine

**TL;DR:** `rounds.status` has 4 values: `'active' → 'concluded' | 'completed' | 'cancelled'`. Concluded is transient. Completed is terminal + triggers guest wipe + convert prompt. Cancelled is terminal + hard-deletes scores. `force_completed = true` flags creator-driven non-natural ends. All transitions go through `RoundService.updateRoundStatus`.

## Status field

[SupabaseModels.swift:144](../../Carry/Models/SupabaseModels.swift:144) — `var status: String`:

| Status | Semantic | Terminal? |
|---|---|---|
| `active` | Round in progress | No |
| `concluded` | All players scored all holes (or creator force-ended) — pending Save/Discard | No (can soft-revert via "Restart Round") |
| `completed` | "Save Round Results" tapped — guest profiles wiped, convert prompt fires | Yes |
| `cancelled` | End Game (destructive) — scores hard-deleted | Yes |

## Single transition entry point

[RoundService.swift:186-194](../../Carry/Services/RoundService.swift:186) `updateRoundStatus(roundId:status:)`. **Always go through this.**

| Side effect | Trigger |
|---|---|
| UPDATE `rounds.status` | Always |
| `GuestProfileService.deleteQuickGameGuests()` | If `status == 'completed'` (see [guest-lifecycle.md](guest-lifecycle.md)) |
| Postgres trigger → push notification dispatch | UPDATE fires it (see [push-trigger-chain.md](push-trigger-chain.md)) |

## State diagram

```
                          ┌────────────────────┐
                          │      active        │
                          └─────────┬──────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              │                     │                     │
   all groups finished       creator: End &        creator: End
   (auto, 0.8s delay)        Save Results         (destructive)
              │                     │                     │
              ▼                     ▼                     ▼
       ┌──────────────┐      ┌──────────────┐      ┌──────────────┐
       │  concluded   │      │  concluded   │      │  cancelled   │
       │              │      │ +force=true  │      │ +force=true  │
       └──────┬───────┘      └──────┬───────┘      │  scores wiped│
              │                     │              └──────────────┘
              │                     │
        Save Round            Save Round
       Results tap           Results tap
              │                     │
              ▼                     ▼
       ┌──────────────────────────────────┐
       │           completed              │
       │   (guest wipe + convert prompt)  │
       └──────────────────────────────────┘
```

## Transitions

### `active → concluded` (natural)

| Property | Value |
|---|---|
| Trigger | `allGroupsFinished && !isRoundComplete` |
| Code | [RoundViewModel.swift:460-467](../../Carry/ViewModels/RoundViewModel.swift:460) — fires `updateRoundStatus(..., "concluded")` after 0.8s |
| `force_completed` | `false` |
| Why 0.8s | Lets last-tap animation settle, avoids race against in-flight upsert |

### `active → concluded + force_completed` (End Game & Save Results)

| Property | Value |
|---|---|
| Code | [RoundService.swift:242-254](../../Carry/Services/RoundService.swift:242) `forceEndRoundWithResults()` |
| Status | `concluded`, `force_completed = true` |
| UI entry | ScorecardView "End Game & Save Results" (creator only) |

### `active → cancelled + force_completed` (End Game destructive)

| Property | Value |
|---|---|
| Code | [RoundService.swift:220-237](../../Carry/Services/RoundService.swift:220) `endGameDestructively()` |
| Steps | DELETEs all scores via `deleteScores(roundId:)` ([:197-202](../../Carry/Services/RoundService.swift:197)), then UPDATEs `status = 'cancelled'`, `force_completed = true` |
| UI entry | ScorecardView "End Game" (destructive variant) — confirms via alert |

### `concluded → completed` (Save Round Results)

| Property | Value |
|---|---|
| Code | [RoundCompleteView.swift:706-738](../../Carry/Views/RoundCompleteView.swift:706) — Save Round Results tap → `updateRoundStatus(roundId, "completed")` + `advanceScheduledDateIfRecurring` |
| Side effect (always) | `delete_quick_game_guests(round_id)` denormalizes guest names + handicaps onto `round_players`+`scores`, DELETEs guest profile rows |
| Side effect (gated) | Convert prompt fires ONLY when `isQuickGame && !forceCompleted && isPremium`. Force-end dismisses silently. Non-subscribed → paywall. See [game-types.md](game-types.md) §"When the convert prompt fires" |

### `concluded → active` ("Restart Round")

NOT a status change — client-side only via `onCancelToSetup` callback in [RoundCoordinatorView](../../Carry/Views/RoundCoordinatorView.swift). Phase: `.active → .setup`. Round row stays `active` server-side; scores NOT deleted. See [phase-transitions.md](phase-transitions.md).

### Decline invite (round-player level, not round)

[RoundService.swift:334-339](../../Carry/Services/RoundService.swift:334) `declineInvite(roundPlayerId:)` sets `round_players.status = 'declined'`. Round status unchanged. Decliner excluded from leaderboards.

## `force_completed` semantics

[SupabaseModels.swift:148-166](../../Carry/Models/SupabaseModels.swift:148) `var forceCompleted: Bool`.

| Status + force | Meaning |
|---|---|
| `concluded` + false | Natural — all groups finished |
| `concluded` + true | "End & Save Results" partway through |
| `cancelled` + true | "End Game" destructive |
| `cancelled` + false | Should not occur |
| `completed` | Flag preserved from prior `concluded` state, not semantically relevant |

[RoundViewModel.swift:745-754](../../Carry/ViewModels/RoundViewModel.swift:745) — 15s poll detects server-side `force_completed = true` and updates local state.

Edge function uses flag to choose handler: `handleGameForceEnded` vs `handleGameDeleted`.

## Visibility — `isConcludedQuickGame`

[GroupsListView.swift:2730-2741](../../Carry/Views/GroupsListView.swift:2730):
```swift
var isConcludedQuickGame: Bool {
    isQuickGame && activeRound == nil && !roundHistory.isEmpty
}
```

QG with no `activeRound` and historical rounds → **hidden from Games tab**. Either: Saved (→ converted), Skipped (→ archived), or in Save/Discard window (still in `concludedRound`).

## `archiveConcludedRound()`

[GroupsListView.swift:2737-2741](../../Carry/Views/GroupsListView.swift:2737) — mutating method:
- Move `concludedRound` → `roundHistory[0]`
- Set `concludedRound = nil`

Synchronous so `isConcludedQuickGame` filter updates immediately on Skip. Async server reload would leave QG visible on Games tab for ~1s.

Callers: [HomeView.swift:686](../../Carry/Views/HomeView.swift:686), [GroupsListView.swift:956](../../Carry/Views/GroupsListView.swift:956), [GroupsListView.swift:1459](../../Carry/Views/GroupsListView.swift:1459).

## Push per transition

| Transition | Edge handler | Recipients |
|---|---|---|
| `active` (INSERT) | `handleRoundStarted` | All active members except creator |
| `active → concluded` (force_completed) | `handleGameForceEnded` | All active members except creator |
| `active → cancelled` (force_completed) | `handleGameDeleted` | All active members except creator |
| `active → completed` (auto / save) | implicit `handleRoundEnded` | All active members except creator |
| First score lands → all groups active | `handleAllGroupsActive` | Creator only |

See [push-trigger-chain.md](push-trigger-chain.md).

## Polling cadence

| View | Interval | Purpose |
|---|---|---|
| ScorecardView (`RoundViewModel.startScorePolling`) | 15s | Score changes + force-end + status changes |
| HomeView (`pollHomeData`) | 30s | New active rounds, status changes affecting cards |
| GroupManagerView (auto-refresh timer) | 30s | Status changes affecting group state |

## Common bugs / gotchas

| Bug | Notes |
|---|---|
| `concluded` is non-terminal | Allows `concluded → active` via client-side Restart Round (no server status change). Don't treat `concluded` as final — check `concludedRound` vs `activeRound` |
| Save vs Skip | Both transition out of `concluded`. Save: `updateRoundStatus(..., "completed")`. Skip: `archiveConcludedRound()` locally + `updateRoundStatus(..., "completed")`. Either way server hits `completed` |
| QG guests don't survive `completed` | `delete_quick_game_guests` runs as part of transition. Need guest data post-round → read denormalized fields on `round_players` / `scores` |
| `cancelled` deletes scores BEFORE status UPDATE | Race: late score INSERT between DELETE and UPDATE → orphan score with valid `round_id` but cancelled round. UI filters by status. `endGameDestructively` is fast enough that this is rare |
| Bypassing `updateRoundStatus` | Skips guest-wipe + push side effects. Single entry point by design |
| Restart Round historical bug (2026-05-09) | Clearing `roundConfig = nil` in same closure as `phase = .setup` rendered loading fallback for one frame → scheduled offline-toast → fired on setup screen. Fix: defer cleanup. See [phase-transitions.md](phase-transitions.md) |

## Last verified

2026-05-10 — converted to machine-readable format. State machine accurate.
