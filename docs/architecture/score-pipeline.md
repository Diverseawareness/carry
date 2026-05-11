# Score Persistence Pipeline

**TL;DR:** Tap → @State → ScoreStorage UserDefaults → Supabase upsert → realtime + 15s poll. Three layers: read-your-writes locally, multi-device sync via realtime, drift correction via poll. `.everyone` scoring mode adds propose-then-resolve flow.

## End-to-end path

[ScorecardView.swift:987](../../Carry/Views/ScorecardView.swift:987) — score tap in `ScoreInputSheet` → `viewModel.enterScore(playerId:holeNum:score:)`.

[RoundViewModel.swift:375-433](../../Carry/ViewModels/RoundViewModel.swift:375) `enterScore()`:

| # | Line | Action |
|---|---|---|
| 1 | [:397](../../Carry/ViewModels/RoundViewModel.swift:397) | `scores[playerId, default: [:]][holeNum] = score` (local @State; leaderboard recomputes) |
| 2 | [:398](../../Carry/ViewModels/RoundViewModel.swift:398) | `ScoreStorage.shared.save(scores:forKey: roundKey)` |
| 3 | [:404](../../Carry/ViewModels/RoundViewModel.swift:404) | `roundService.upsertScore(roundId:playerId:holeNum:score:)` |
| 4 | [:418](../../Carry/ViewModels/RoundViewModel.swift:418) | On network failure: `SyncQueue.shared.enqueueScore(...)` |
| 5 | implicit | `calculateSkins()` reruns, new wins fire celebration sheets |
| 6 | [:460-467](../../Carry/ViewModels/RoundViewModel.swift:460) | If `allGroupsFinished && !isRoundComplete`: `updateRoundStatus(..., "concluded")` after 0.8s |

## Layer 1: UserDefaults (`ScoreStorage`)

[ScoreStorage.swift:1-47](../../Carry/Services/ScoreStorage.swift:1) — JSON-encoded `[Int: [Int: Int]]` (player → hole → score), key `carry.scores.<round-uuid>`.

| Lifecycle | Where |
|---|---|
| Written | Every `enterScore()` ([:398](../../Carry/ViewModels/RoundViewModel.swift:398)) |
| Read | `RoundViewModel.init` when re-attaching to existing round |
| Cleared | `ScoreStorage.shared.clear(forKey:)` on round end |

## Layer 2: Server upsert

[RoundService.swift:444-451](../../Carry/Services/RoundService.swift:444) — Supabase `.upsert()` with conflict key `(round_id, player_id, hole_num)`. **One row per (round, player, hole)** — no attempt history. Re-scoring overwrites.

[SupabaseModels.swift:292-304](../../Carry/Models/SupabaseModels.swift:292) — `ScoreInsert` DTO.

RLS: `scores` SELECT/INSERT/UPDATE gated to round participants. See [db-schema-rules.md](db-schema-rules.md).

## Layer 3: Realtime + 15s poll

### Realtime

[RoundService.swift:384-413](../../Carry/Services/RoundService.swift:384) `subscribeToScores(roundId:onChange:)` registers `postgresChange` for INSERT ([:393](../../Carry/Services/RoundService.swift:393)) and UPDATE ([:399](../../Carry/Services/RoundService.swift:399)) on `scores`. Decoded to `ScoreDTO`, fanned to callback on `MainActor`.

### 15s polling fallback

[RoundViewModel.swift:562-577](../../Carry/ViewModels/RoundViewModel.swift:562) `startScorePolling()` → `pollAndDetectNewSkins()` ([:580-595](../../Carry/ViewModels/RoundViewModel.swift:580)) → `RoundService.fetchScores(roundId:)` ([:436-442](../../Carry/Services/RoundService.swift:436)).

Reconciles:
| Failure mode | Recovery |
|---|---|
| Missed realtime events (network blip) | Next 15s poll catches |
| Stale proposals not cleared by realtime NULL push | Same |
| Cross-group skin wins | Polled detection on creator's device |

## Score dispute / proposal flow (`.everyone` mode)

| Step | Code |
|---|---|
| Propose (overwriting existing different score) | [RoundViewModel.swift:375-394](../../Carry/ViewModels/RoundViewModel.swift:375) `proposeScoreChange()` |
| Persist proposal | [RoundService.swift:322-331](../../Carry/Services/RoundService.swift:322) — sets `proposed_score` + `proposed_by` on existing row |
| Resolve | [RoundViewModel.swift:489-523](../../Carry/ViewModels/RoundViewModel.swift:489) `resolveActiveProposal(accept:)` |
| Server-side resolve | [RoundService.swift:333-381](../../Carry/Services/RoundService.swift:333). Accept: set `score` + clear proposal fields. Reject: clear proposal fields only |
| Push fan-out | Edge function `handleScoreDispute` — see [push-trigger-chain.md](push-trigger-chain.md) |
| Stale-proposal reconcile | [RoundViewModel.swift:532-542](../../Carry/ViewModels/RoundViewModel.swift:532) — 15s poll catches NULL proposal that realtime missed |

Invariant: active proposal blocks new score writes for that cell. Must resolve first.

## All-groups-active detection

[RoundViewModel.swift:320-326](../../Carry/ViewModels/RoundViewModel.swift:320) — `var allGroupsFinished: Bool`. True when every player (or `activePlayers` if `forceCompleted`) has scored every hole.

When true and round not yet complete, [:460-467](../../Carry/ViewModels/RoundViewModel.swift:460) fires `updateRoundStatus(..., "concluded")` after 0.8s. Push on status UPDATE (different from `handleAllGroupsActive` which fires earlier when first score lands in each group).

## Cleanup on round cancellation

[RoundService.swift:220-237](../../Carry/Services/RoundService.swift:220) `endGameDestructively()`:

| # | Action |
|---|---|
| 1 | `deleteScores(roundId:)` ([:197-202](../../Carry/Services/RoundService.swift:197)) — DELETE all scores |
| 2 | UPDATE `rounds.status = 'cancelled'`, `force_completed = true` |

Scores are **hard-deleted**. Round row preserved (history / push-source).

## Where scoring data flows

| Consumer | Source |
|---|---|
| ScorecardView grid | `RoundViewModel.scores[playerId][holeNum]` (local @State) |
| Leaderboard | `RoundViewModel.cachedSkins` + `skinsWonByPlayer()` |
| Pots / money | `RoundViewModel.moneyTotals()` |
| Final results | `FinalResultsHero`, `FinalResultsWinnerRow` |
| HomeView Active Round card | `HomeRound.playerWinnings` + `playerWonHoles` (precomputed by `buildHomeRound`) |

Scores → skins → money: see [skins-math.md](skins-math.md).

## Common bugs / gotchas

| Bug | Likely cause |
|---|---|
| Score appears then reverts | Realtime broadcast lost the write but UserDefaults caught it. 15s poll reconciles. Persists past 15s → check RLS / upsertScore error logs |
| Score doesn't appear on other devices | Realtime subscription not active (re-subscribe on app foreground). 15s poll is safety net |
| Two devices race-edit same cell | Last-write-wins on server (no CRDT). Propose flow only kicks in for *different* scores; identical no-op |
| All-groups-active push fires twice | Historical: pre-2026-04-26 cleanup had 2× trigger setup. See project memory `prod_db_drift_legacy_triggers.md` |
| Score writes during round cancellation | DELETE precedes status UPDATE; a score INSERT can land between. Orphan score has valid `round_id` but cancelled round; UI filters by status |

## Last verified

2026-05-10 — converted to machine-readable format. Realtime + 15s poll dual-redundant.
