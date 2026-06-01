# Stability Hardening — Progress Log

**Branch:** `feature/stability-hardening` (cut from `hotfix/1.1.2`)
**Started:** 2026-05-31
**Status:** 🟢 In progress — 5 commits landed, full suite green, pushed once. Resume rule: read this top-to-bottom first.

---

## Why this exists

Two production incidents in one week exposed the real gap: **the app is stable because a careful human tests by hand, not because the code catches its own breaks.**
1. 1.1.2 shipped with **21 silently-red tests** — our own `·`→`+` separator change broke its own assertions, and nobody knew because the suite was never run.
2. The `create_guest_profiles` migration **broke guest creation for live users** — dev passed, prod didn't (signature-changed overload → `function is not unique`, 42725).

Neither was bad luck. Both were a missing safety net. This branch builds the nets, then starts hardening the engine's load-bearing rules.

## The plan (ranked by value)

1. **Test the load-bearing invariants** — the playbook admits 7 of 9 core invariants have NO automated enforcement. Each one we test becomes a bug class the pre-push hook guards forever. ← _highest value, in progress_
2. **Safe shrinkage** — ~350 lines of confirmed duplication + 1 dead file (VenmoLogo.swift). Mechanical, low risk.
3. **Decompose GroupManagerView** at clean seams (leaderboard, tee-time picker, scorer picker, guest-entry sheets) — only AFTER #1, so a slip gets caught.

**Explicitly NOT doing** (research-backed, see group-formation-canonical.md sufficiency review + group-engine doc pass):
- ❌ Full GroupStore / `commitGroupsChange` rewrite — reconciler is holding, no drift regressions post-2026-05-10.
- ❌ Merge the two roster sheets (PlayerGroupsSheet / ManageMembersSheet) — structurally impossible cleanly (2D-slot vs flat, QG-guest vs SG-Carry-only).
- ❌ Consolidate tee-time writers — would break the intentional sovereignty model.

---

## What's done

| # | Commit | What | Plain English |
|---|---|---|---|
| 1 | `10e790c` | Fixed 21 stale `RoundStatsLineTests` (`·`→`+`) | The tests that were silently broken by 1.1.2 — now green |
| 2 | `e83f31d` | Pre-push hook + `scripts/run-tests.sh` | Tests run automatically before every push; a red suite is blocked |
| 3 | `1737588` | `scripts/prod-release-smoke-check.sql` + playbook "Pre-release gate" | Self-verdicting SQL catches the prod-vs-app RPC-drift incident class |
| 4 | `185395d` | Reconciler-sufficiency review in group-formation-canonical.md | Answered "do we need the big rewrite?" → NO, evidence-backed |
| 5 | `d480a10` | Extracted `normalizedGroupNums(_:)` + `GroupFormationReconcilerTests` | First load-bearing invariant now under test (Player.group == index) |

### Key decisions locked
- **Pre-push hook over CI** (commit 2): Daniel is solo → the failure mode is *his* machine pushing untested code; a hook aims exactly there, runs instantly, free, never rots. Logic lives in `scripts/run-tests.sh` so CI can call it verbatim when a teammate is added. **One-time setup per machine: `git config core.hooksPath scripts`** (local config doesn't travel with clones).
- **Manual self-verdicting SQL over a service-key script** (commit 3): migrations apply by hand in Studio here (`db push` squash-blocked), and no prod service-role key lives locally *by design* (security win). Gate lives where the migration work already happens; returns literal `PASS`/`FAIL` so there's nothing to misread.
- **Extraction was behavior-identical** (commit 5): pulled the reconciler's normalization loop out of the `.onChange(of: groups)` closure into a pure `static func`; the handler calls it verbatim. Build + full suite green confirmed no behavior change before adding the test.

---

## Tooling / safety nets now in place

| Tool | What it guards | How to run |
|---|---|---|
| `scripts/run-tests.sh` | (the runner) | `./scripts/run-tests.sh` — Carry scheme, coverage off (PLCrashReporter linker bug), auto-picks a simulator |
| `scripts/pre-push` | red suite reaching origin | auto (on `git push`); skips doc/site-only pushes; override `git push --no-verify` |
| `scripts/prod-release-smoke-check.sql` | prod RPC signatures vs what the app calls | paste into LIVE Studio SQL editor before release; every row must say `PASS` |
| `scripts/check-blueprint-citations.sh` | doc `file:line` drift (pre-existing) | `./scripts/check-blueprint-citations.sh` |

---

## Invariant coverage tracker (the #1 plan)

| Invariant | Doc | Tested? |
|---|---|---|
| `Player.group == array index + 1` (group-formation reconciler) | group-formation-canonical.md | ✅ `GroupFormationReconcilerTests` (commit `d480a10`) |
| Scorer rules 1–6 incl. creator-lock | scorer-rules.md | ✅ `ScorerRulesTests` (extracted `resolvedScorerIDs(...)`) |
| Guest 4-layer persistence (a guest edit never silently reverts) | guest-lifecycle.md | ⬜ |
| Skins payout math | skins-math.md | ✅ pre-existing (SkinsCalculationTests, PotCalculationTests) |
| Pops / handicap | skins-math.md | ✅ pre-existing (PopsComputationTests) |
| Guest canonical identity | guest-lifecycle.md | ✅ pre-existing (GuestCanonicalIdentityTests) |

---

## Next steps (resume here)

1. **Scorer creator-lock test** — the rule that `scorerIDs[i] = creatorId` for any group containing the creator (scorer-rules.md). Likely needs the same extraction pattern (the logic lives in `syncScorerIDs`). Verify it's behavior-identical first.
2. **Guest 4-layer persistence test** — harder (involves async RPC + race guard); may only be partially unit-testable.
3. Then drop to plan #2 (safe shrinkage): `formatMoney` 8→1, `PlayerStatRow` 4→1, `LeaderboardSheet` 3→1, delete `VenmoLogo.swift`.

## Open / not-yet-decided
- **Merge target:** branch is dev-infrastructure (test scripts + docs + one behavior-identical extraction). When/whether it reaches `main` or a release branch is Daniel's call. Pushed to origin once (hook ran green).
- **GroupManagerView decomposition (plan #3):** deferred until more invariants are under test.
