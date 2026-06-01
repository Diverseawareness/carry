# Stability Hardening — Progress Log

**Branch:** `feature/stability-hardening` (cut from `hotfix/1.1.2`)
**Started:** 2026-05-31
**Status:** 🟢 In progress — 16 commits landed, full suite green. Plan #1 (test invariants) COMPLETE; Plan #2 (safe shrinkage) in progress. Last pushed at commit `e6dbd03` (commits 1–6) — **commits 7–16 are unpushed.** Resume rule: read this top-to-bottom first.

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

## What's done — commit ledger

| # | Commit | What | Plain English |
|---|---|---|---|
| 1 | `10e790c` | Fixed 21 stale `RoundStatsLineTests` (`·`→`+`) | The tests silently broken by 1.1.2 — now green |
| 2 | `e83f31d` | Pre-push hook + `scripts/run-tests.sh` | Tests run automatically before every push; a red suite is blocked |
| 3 | `1737588` | `scripts/prod-release-smoke-check.sql` + playbook "Pre-release gate" | Self-verdicting SQL catches the prod-vs-app RPC-drift incident class |
| 4 | `185395d` | Reconciler-sufficiency review in group-formation-canonical.md | Answered "do we need the big rewrite?" → NO, evidence-backed |
| 5 | `d480a10` | Extracted `normalizedGroupNums(_:)` + `GroupFormationReconcilerTests` | Invariant 1 under test (Player.group == index) |
| 6 | `e6dbd03` | This progress log created | _(last pushed commit)_ |
| 7 | `8d04a4a` | Extracted `resolvedScorerIDs(...)` + `ScorerRulesTests` (12 tests) | Invariant 2 under test (scorer rules + creator-lock) |
| 8 | `11a3142` | Anchored-citation upgrade to `check-blueprint-citations.sh` | Closes the doc-citation-drift bug class (catch + auto-heal) |
| 9 | `55b2448` | `GuestSnapshotFilterTests` (8 tests) | Invariant 3 under test (guest disease-string defense) → **Plan #1 done** |
| 10 | `d64ed39` | Deleted dead `VenmoLogo.swift` + `venmoBlue` | Plan #2 — first dead-code removal |
| 11 | `7d4995a` | Consolidated 8 money formatters → 1 free `moneyText` + `MoneyTextTests` | Plan #2 — duplication |
| 12 | `d50a4bf` | Removed the fully-dead Venmo subsystem (settlement island + `venmoUsername` ~40 sites) | Plan #2 — net −83 lines |

(Numbering note: commits land in the order above; hashes are the authoritative record. 29 new tests added across #5/#7/#9/#11.)

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
| `scripts/check-blueprint-citations.sh` | doc `file:line` drift — bounds for plain cites, anchor-position for anchored (upgraded commit `11a3142`) | `./scripts/check-blueprint-citations.sh` (`--fix` auto-heals anchored drift) |

---

## Invariant coverage tracker (the #1 plan)

| Invariant | Doc | Tested? |
|---|---|---|
| `Player.group == array index + 1` (group-formation reconciler) | group-formation-canonical.md | ✅ `GroupFormationReconcilerTests` (commit `d480a10`) |
| Scorer rules 1–6 incl. creator-lock | scorer-rules.md | ✅ `ScorerRulesTests` (extracted `resolvedScorerIDs(...)`) |
| Guest disease-string defense (snapshot save/load filters "Guest"/0.0, Carry-user exclusion, canonicalKey dedup) | guest-lifecycle.md inv #3 | ✅ `GuestSnapshotFilterTests` — the pure, highest-risk layer |
| Guest 4-layer EDIT-persistence chain (async RPC + 8s race guard + buildResult) | guest-lifecycle.md inv #4 | ⚠️ NOT unit-tested — integration territory (needs live/mocked Supabase + refresh timing). Honestly out of scope for unit tests; would need a UI/integration harness. |
| Skins payout math | skins-math.md | ✅ pre-existing (SkinsCalculationTests, PotCalculationTests) |
| Pops / handicap | skins-math.md | ✅ pre-existing (PopsComputationTests) |
| Guest canonical identity | guest-lifecycle.md | ✅ pre-existing (GuestCanonicalIdentityTests) |

---

## Citation-drift bug class — closed structurally (2026-05-31)

A 4-agent audit of all 183 `GroupManagerView.swift:NNN` doc citations found ~80 stale ones — content correct, line numbers drifted (300–720 lines for the worst, mostly PRE-existing; this session's two extractions added ~70–113 more). The old checker only caught out-of-bounds, so in-bounds drift rotted silently. Hand-fixing 80 numbers = a patch that re-drifts on the next GMV edit.

**Structural fix shipped** (per Daniel "best most stable fix for the future"): upgraded `check-blueprint-citations.sh` to support **anchored citations** — a symbol in the markdown link title that must sit at/near the cited line:
`[GroupManagerView.swift:129](../../Carry/Views/GroupManagerView.swift:129 "var scorerIDs:")`
- anchor at cited line → PASS · anchor elsewhere → DRIFT (reports correct line) · anchor gone → SEMANTIC break (code changed, fix prose).
- `--fix` auto-heals drifted anchored line numbers. Proven end-to-end (detect → fix → re-clean).
- Back-compat: all 479 existing plain citations still pass (bounds-only). Migrate hot-file citations to anchored form as touched.
- Pre-push hook now runs the checker as a NON-blocking warning. Convention documented in playbook.md post-change checklist.

**Tracked debt (NOT done):** the ~80 plain citations are still numerically stale (content accurate). They're a known follow-up — fix opportunistically as docs are touched, converting to anchored form. Not blocking; the agents confirmed ~zero true semantic mismatches (code matches prose, only line numbers moved).

## Plan #1 (test the load-bearing invariants) — COMPLETE

All unit-testable invariants now covered. The reconciler, the 6 scorer rules + creator-lock, and the guest disease-string defense each went from zero coverage to guarded-by-the-hook. The one piece deliberately left untested — the async guest-EDIT persistence chain (inv #4) — is integration territory, not a unit-test gap; honestly flagged rather than faked.

## Next steps (resume here)

1. **Plan #2 — safe shrinkage** (mechanical, low risk). Started:
   - ✅ Deleted `VenmoLogo.swift` (verified truly dead — only self-refs) + `CarryColors.venmoBlue` (only used by VenmoLogo) + 4 pbxproj refs. Build green.
   - ✅ FULL Venmo removal (Daniel: "venmo is not used, remove safely" — verified-in-code first): the RoundCompleteView settlement island (`VenmoSettlement`/`venmoSettlements`/`openVenmo`/`venmoIndex`/unsigned `moneyText`) was self-referential DEAD code (`openVenmo` never called). Removed it, which made `Player.venmoUsername` write-only → then removed the field across ~40 app sites + 9 test files. Stat-row unsigned formatter preserved as `RoundStatsView.statRowMoney`. Build + full suite green. MEMORY updated (was wrongly "NOT dead" — the field looked live but its only readers were themselves dead).
   - ✅ `moneyText` 8→1: consolidated all 8 behaviorally-canonical copies into one free func in Player.swift + `MoneyTextTests`. The one outlier (RoundCompleteView's intentionally-UNSIGNED formatter) was later removed with the Venmo subsystem (#12), except the stat-row use, preserved as `RoundStatsView.statRowMoney`.
   - ⬜ Still to do: `PlayerStatRow` 4→1, `LeaderboardSheet` 3→1 (bigger — these are view structs, not pure funcs; more care + likely your eyes on the rendered result).
2. **Plan #3 — decompose GroupManagerView** at clean seams (leaderboard / tee-time picker / scorer picker / guest-entry sheets). Now safer — three core invariants are under test.
3. Opportunistic: migrate the ~80 drifted plain citations to anchored form (closes the tracked debt).
4. Optional later: an integration/UI-test harness for the guest-edit RPC + race-guard chain (inv #4), if guest-edit regressions recur.

## Open / not-yet-decided
- **Merge target:** branch is dev-infrastructure (test scripts + docs + one behavior-identical extraction). When/whether it reaches `main` or a release branch is Daniel's call. Pushed to origin once (hook ran green).
- **GroupManagerView decomposition (plan #3):** deferred until more invariants are under test.
