# Testing — strategy + inventory

This is the living index. For per-release manual test plans, see [Per-release plans](#per-release-plans).

## Layers

| Layer | Where | Purpose |
|---|---|---|
| **iOS unit tests** | `CarryTests/*.swift` | Pure-function regression coverage of math, encoding, models. Fast, deterministic, run on every build. |
| **Server-side SQL tests** | `supabase/tests/db/*.sql` | Plain-SQL pass/fail tests for Postgres functions (helpers, triggers). Wrapped in BEGIN…ROLLBACK so production DB is untouched. Runnable from Studio SQL Editor. |
| **Manual test plans** | `docs/test-plan-YYYY-MM-DD.md` | Step-by-step device flows for each release that lands user-facing changes. Not automated. |
| **Server-side SQL audits** | embedded in test plans | One-shot SQL queries to confirm migrations / schema / triggers are in the expected shape post-deploy. |

We do **not** currently have:
- UI snapshot tests (no library wired up; existing tests are pure-function only)
- Integration tests against a Supabase test project
- Automated end-to-end push delivery tests

## How to run tests

### iOS unit tests
```bash
cd /path/to/carry
xcodebuild test -scheme Carry -destination 'platform=iOS Simulator,name=iPhone 15' -enableCodeCoverage NO
```

The `-enableCodeCoverage NO` is required — there's a known PLCrashReporter linker bug surfacing as `Undefined symbol: ___llvm_profile_runtime` when coverage is on. Tracked in MEMORY.md; flip back to default when PLCrashReporter is updated or replaced.

### Server-side SQL tests
For each file in `supabase/tests/db/*.sql`:
1. Open Supabase Studio → SQL Editor for the target project (dev or prod)
2. Paste the file contents
3. Run

Each file wraps everything in `BEGIN…ROLLBACK`, so test fixtures (Vault secrets, scratch rows) are reverted. Production data is untouched.

Each test file emits one row per test (`PASS` or `FAIL` with actual vs. expected) plus a summary line. Run on **both** dev and prod after any migration that touches the tested area — outputs should match.

Files:
- `supabase/tests/db/notify_push_helpers_test.sql` — Vault helpers + helper-wiring regression on the 4 push-firing functions (14 tests)

## Unit-test inventory

12 files, ~124 tests, ~1,720 LOC as of 2026-05-09 (after the index% / plus-HC additions).

| File | Tests | What it covers |
|---|---|---|
| [PopsComputationTests.swift](../CarryTests/PopsComputationTests.swift) | 11 | `TeeBox.playingHandicap(forIndex:percentage:)` formula + percentage allowance, plus-handicap clamping, fallback to rounded index when tee box missing |
| [SkinsCalculationTests.swift](../CarryTests/SkinsCalculationTests.swift) | 13 | Outright wins, tied-hole squash (carries=false), carry-forward (carries=true), provisional/incomplete holes, gross/net split, scoring mode, **handicap allowance percentage** (70% / 0%), **plus-handicap give-back on easiest holes** |
| [PotCalculationTests.swift](../CarryTests/PotCalculationTests.swift) | 5 | Pot calculation, skin-value denominator (squashed vs carried holes), winnings distribution across skins |
| [TeeTimesPersistenceTests.swift](../CarryTests/TeeTimesPersistenceTests.swift) | 8 | JSON encode/decode round-trip for tee times array, nil preservation, ISO8601 formats, independent gap preservation |
| [HolesPipelineTests.swift](../CarryTests/HolesPipelineTests.swift) | 10 | `Hole.fromAPI` validation (18-hole requirement, par bounds), fallback to position when handicap nil, demo tee box integrity |
| [PlayerModelTests.swift](../CarryTests/PlayerModelTests.swift) | 9 | Handicap filtering, short-name format, stable UUID→Int mapping, player-from-ProfileDTO, homeClub preservation |
| [InviteStatusTests.swift](../CarryTests/InviteStatusTests.swift) | 14 | `isPendingInvite` / `isPendingAccept` flag combinations for guests/scorers/members, avatar color (green vs orange), homeClub flow |
| [SkinsGroupUpdateEncodingTests.swift](../CarryTests/SkinsGroupUpdateEncodingTests.swift) | 5 | `SkinsGroupUpdate` JSON serialization — omit unset fields, `clearTeeTimesJson` null flag, tee-times-json round-trip |
| [OfflineResilienceTests.swift](../CarryTests/OfflineResilienceTests.swift) | 10 | Local score persistence, offline skins calculation, active-hole advancement, scoring-block state |
| [RoundStatsLineTests.swift](../CarryTests/RoundStatsLineTests.swift) | 24 | Score stats formatting (front/back split, category pluralization, eagles/doubles/albatross edge cases) |
| [PaywallTriggerTests.swift](../CarryTests/PaywallTriggerTests.swift) | 7 | Context line strings for each `PaywallTrigger` case |
| [StoreServiceHadPremiumTests.swift](../CarryTests/StoreServiceHadPremiumTests.swift) | 8 | `hadPremium` stickiness, UserDefaults persistence, isPremium flip behavior, debug setter |

## Coverage gaps

### Critical (shipped behavior — coverage status)

1. ✅ **Handicap percentage end-to-end through skins calc.** Resolved 2026-05-09 — `SkinsCalculationTests.makeConfig()` now takes `handicapPercentage` + `playerIndices` parameters; tests at 70% and 0% verify the allowance flows through to per-hole stroke allocation.

2. **Race-guard 8-second windows.** `teeTimesLastSavedAt`, `handicapPercentageLastSavedAt`, and `scorerIdsLastSavedAt` all guard `refreshGroupData` from clobbering recent local saves ([GroupManagerView.swift:100](../Carry/Views/GroupManagerView.swift:100), :104). **STILL UNTESTED** — logic lives inside a SwiftUI view's private `async` method. Needs extraction to a pure helper function (`isRecentSave(stamp: Date?, window: TimeInterval) -> Bool`) for unit-testing, or ViewInspector.

3. **Score Keeper creator-lock invariant.** `PlayerGroupsSheet` rejects writes when creator is in the group ([:833](../Carry/Views/PlayerGroupsSheet.swift:833)) and `syncScorerIDs` re-asserts creator-as-scorer ([:1152](../Carry/Views/PlayerGroupsSheet.swift:1152)). **STILL UNTESTED** — same testability constraint as #2.

4. **Quick Game guest preservation across refreshes** — the `refreshGroupData` re-merge ([GroupManagerView.swift:850-855](../Carry/Views/GroupManagerView.swift:850)) and the `onChange(of: isQuickGame)` clear-and-refresh ([:2282](../Carry/Views/GroupManagerView.swift:2282)). **STILL UNTESTED** — view-state logic, same constraint as #2.

5. **Restart Round `postCancelMembers` capture.** `RoundCoordinatorView` snapshot at [RoundCoordinatorView.swift:315](../Carry/Views/RoundCoordinatorView.swift:315). **STILL UNTESTED**.

6. **`loadSingleGroup` Carry-only filter.** Architectural rule (locked 2026-05-01): server-side group load excludes guests. Logic at [GroupService.swift:1234-1240](../Carry/Services/GroupService.swift:1234) and the round_players backfill at :1199-1208. **STILL UNTESTED** at the unit level — tested in production by absence of "ghost guests in current roster".

### Nice-to-have

7. ✅ **Plus-handicap stroke allocation in skins.** Resolved 2026-05-09 — `testPlusHandicap_givesStrokesBackOnEasiestHoles` verifies a plus-3 player nets gross+1 on hole 18 (hcp 18) and breaks ties to hand the skin to a 0-HC opponent.

8. **Multi-group with different tee boxes / different percentages.** Current skins tests assume one tee box for all groups. Untested.

9. **Single-scorer mode in skins.** `SkinsCalculationTests` defaults to `.everyone` scoring mode; the single-scorer path (Quick Game pattern) isn't directly exercised. Untested.

## Patterns + conventions

- **Pure-function bias.** Existing tests favor pure-function units (no mocks, no async). Where logic lives in SwiftUI view closures, the convention has been to skip — leaving a real gap that #2-#5 above expose.
- **Helpers over copy-paste.** `makeConfig()`, `makeTeeBox()`, `makePlayer()` builders in `SkinsCalculationTests` are the right pattern; extend rather than duplicate when adding tests.
- **One file per logical area.** Skins math, pops, encoding, etc. — each in its own file. Don't add to `RoundStatsLineTests.swift` for an unrelated concern.
- **Naming.** `test_<scenario>_<expected>` (e.g. `test_outrightWin_assignsSkin`). Matches the existing style.

## Per-release plans

Each release that touches user-facing behavior gets a one-shot test plan documenting what changed and how to verify before archive.

- [test-plan-2026-05-01](test-plan-2026-05-01.md) — `notify_push` per-table dispatcher fix + Quick Game scorer race fix + ephemeral-guests Phase 2
- [test-plan-2026-05-09](test-plan-2026-05-09.md) — 1.0.7 hotfix bundle (index %, Restart Round, score-keeper lock, guest preservation) + Vault push-trigger hardening

## Backlog

- Wire **ViewInspector** so the SwiftUI view-state gaps (#2-#5 above) become unit-testable without refactoring every view into helpers.
- **Server-side automated tests** — partial coverage as of 2026-05-09:
   - ✅ The 3 helper functions (`_vault_secret_or_default`, `_push_notification_url`, `_push_notification_anon_key`) are covered by `supabase/tests/db/notify_push_helpers_test.sql` (14 tests, includes regression check that all 4 trigger functions still call the helpers).
   - **Still untested:** the trigger functions themselves (`notify_push`, `send_handicap_reminders`, `reconcile_phone_invites_for_profile`, `reconcile_phone_invite_at_insert`) — their per-table dispatch logic, payload construction, and pg_net call shape are not unit-tested. Fire-and-forget `net.http_post` is hard to mock from in-DB SQL. Options:
     - **pgTAP + a fake `net.http_post`** — override pg_net for the duration of a test, capture calls, assert payload shape.
     - **Supabase CLI integration tests** against a local stack — covers triggers firing + pg_net queue end-to-end. Heavier setup.
     - **iOS-side integration tests** against a real Supabase test project — covers the round-trip end-to-end but doesn't directly assert helper behavior.
- Set up a **Supabase test project** for integration tests against real DB triggers / RPCs (would catch things like the GUC + Vault auth break before prod).
- Investigate **PLCrashReporter** replacement so code coverage can run cleanly — currently disabled per known linker bug.
