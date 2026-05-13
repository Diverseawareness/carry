# Architecture Playbook

**Read this first.** The blueprint docs in this directory are reference cards. The playbook tells you *which cards to read in what order* before touching code, so you don't introduce a regression by missing a hidden invariant.

## 🔒 Load-bearing principle — no patches without permission

🔒 Locked 2026-05-10.

**Default to long-term solutions, not patches.** When a bug is reported, the first job is to identify the *bug class* — the structural reason this and similar bugs are reachable — and close the class. Only as a last resort, when the class can't be closed in scope, fall back to a targeted patch. **In that case, the patch MUST be flagged and verified by the user BEFORE landing.**

What counts as a patch:

| Pattern | Long-term version |
|---|---|
| Adding a guard at one call site that fixes today's symptom | Eliminate the unsafe code path everywhere, OR add a constructor/precondition guard so misuse fails fast |
| Adding a check inside a loop or refresh handler to suppress a wrong toast / wrong write | Fix the upstream baseline / source-of-truth so the wrong value never enters the loop |
| Defaulting an Optional to a "safe" fallback string | Trace why the Optional is nil — likely the real fix is upstream of the fallback |
| Adding a 30-second timeout to mask a race condition | Find the actual race and order the mutations correctly |
| "Fix" that requires the user to clear data, restart, or avoid a flow | Stop |

Decision flow when surfacing a fix:

1. **What is the bug class** (the architectural reason this bug is reachable)?
2. **Can the class be closed in scope** (eliminate path / add precondition / restructure)?
3. If yes → ship the structural fix.
4. If no → describe the patch + the class it doesn't close + the residual risk → wait for user to verify before landing.

The patches are the second-leading source of regressions in this codebase (right behind silent prop-wiring drift). See [bug-archive 2026-05-10 "Home-tab Quick Game entry: Restart Round breaks drag + back navigation"](bug-archive.md) — three layered structural fixes were needed because the previous "patch only" pass left the trap path reachable.

## How to use this directory

1. Identify the area you're changing (lookup table below).
2. Read the listed docs **in the order shown** — order matters because dependencies layer.
3. Walk the **pre-flight checklist** for the affected area before writing code.
4. After the change ships, walk the **post-change checklist** to keep docs in sync.

If the symptom doesn't match a row, default to: read [README.md](README.md), then the doc whose name best matches your code path, then trace dependencies via the cross-links.

## Format rule for blueprints

The topic docs (everything in `docs/architecture/` except `README.md`, `playbook.md`, `bug-archive.md`) are a machine-readable index for Claude to load into context — not narrative reading material for humans. Optimize for:

- **Tables** over paragraphs
- **`file:line` citations** for every claim
- **Verbatim code quotes** when stating what code does — don't paraphrase
- **Terse rule lists** in "Common bugs / gotchas" sections — not stories
- **Cut** motivational framing, "why this exists" paragraphs, editorial commentary

Keep: TL;DR (entry hint), Last Verified (freshness marker), section headings (navigation).

When the user asks what a doc says, translate the dense reference into natural language for them on the spot — don't pre-translate in the doc itself. Pre-translation drifts from code as the codebase evolves; on-demand translation stays accurate because it's grounded in the current doc + current code.

Existing blueprints get converted to this format when next touched (the post-change checklist enforces re-reading the section anyway). No bulk rewrite needed.

## When something doesn't persist or reverts

🔒 First stop: [source-of-truth.md](source-of-truth.md). Maps every editable persisted field to its canonical store, write path, read path, and race guard. If the field misbehaves, that table tells you which layer to start debugging.

## Lookup table — "I'm changing X"

| What you're touching | Read in this order |
|---|---|
| Group setup UI (GroupManagerView, PlayerGroupsSheet) | [game-types.md](game-types.md) → [player-flags.md](player-flags.md) → [scorer-rules.md](scorer-rules.md) → [refresh-race-guards.md](refresh-race-guards.md) |
| Quick Game guests (add/remove/persist) | [guest-lifecycle.md](guest-lifecycle.md) → [game-types.md](game-types.md) → [player-flags.md](player-flags.md) |
| Drag-and-drop tee groups / swap picker | [scorer-rules.md](scorer-rules.md) §"Scorer anchoring" + §"Swap picker sheet" → [group-formation-canonical.md](group-formation-canonical.md) |
| Quick Game → Skins Group conversion | [game-types.md](game-types.md) → [guest-lifecycle.md](guest-lifecycle.md) → [db-schema-rules.md](db-schema-rules.md) (RPC `convert_quick_game_to_group`) |
| Round start / phase transitions | [phase-transitions.md](phase-transitions.md) → [game-types.md](game-types.md) → [scorer-rules.md](scorer-rules.md) |
| Restart Round / Cancel Round | [phase-transitions.md](phase-transitions.md) (order-of-mutations rule) → [guest-lifecycle.md](guest-lifecycle.md) (preservation) |
| Adding a user-editable field that persists | [refresh-race-guards.md](refresh-race-guards.md) (the `<field>LastSavedAt` recipe) |
| Score entry / persistence | [score-pipeline.md](score-pipeline.md) → [push-trigger-chain.md](push-trigger-chain.md) → [db-schema-rules.md](db-schema-rules.md) |
| Scoring permissions / scorer assignment | [scorer-rules.md](scorer-rules.md) → [player-flags.md](player-flags.md) |
| Skins / handicap math | [skins-math.md](skins-math.md) → [db-schema-rules.md](db-schema-rules.md) (tee_boxes, holes) |
| Tee times | [tee-time-sovereignty.md](tee-time-sovereignty.md) → [refresh-race-guards.md](refresh-race-guards.md) |
| Push / notifications | [push-trigger-chain.md](push-trigger-chain.md) → [db-schema-rules.md](db-schema-rules.md) (RLS, trigger sources) |
| Member invites (search/SMS/phone) | [group-invitation-flow.md](group-invitation-flow.md) → [push-trigger-chain.md](push-trigger-chain.md) → [db-schema-rules.md](db-schema-rules.md) |
| Account / sign-in / onboarding | [onboarding-and-auth.md](onboarding-and-auth.md) → [db-schema-rules.md](db-schema-rules.md) (`handle_new_user`) |
| Manage Members sheet | [manage-members.md](manage-members.md) → [player-flags.md](player-flags.md) → [group-invitation-flow.md](group-invitation-flow.md) |
| Results / share / post-round | [results-share.md](results-share.md) → [phase-transitions.md](phase-transitions.md) (round end) |
| Deep links (`carry://...`) | [deep-link-routing.md](deep-link-routing.md) → [game-types.md](game-types.md) |
| Recurring rounds | [recurring-rounds.md](recurring-rounds.md) → [db-schema-rules.md](db-schema-rules.md) (`recurrence`, `scheduledDate`) |
| Round lifecycle (active → concluded → completed → cancelled) | [round-lifecycle.md](round-lifecycle.md) → [phase-transitions.md](phase-transitions.md) → [push-trigger-chain.md](push-trigger-chain.md) |
| Migrations / RLS / triggers | [db-schema-rules.md](db-schema-rules.md) → [push-trigger-chain.md](push-trigger-chain.md) (if any trigger touched) |

**Account linking** (auth-v2 work) is documented in [account-linking.md](account-linking.md) as a forward-looking spec — code is on `feature/auth-v2`, not in main.

## Living invariants — re-verify before any change in scope

These are hard-locked rules. Breaking one is always a bug. **Enforced by** lists the test(s) that fail when the invariant breaks. Where it says "🚧 coverage gap," the invariant is enforced only by code review + manual testing — those are the highest-priority places to add a test.

| # | Invariant | Source of truth | Enforced by |
|---|---|---|---|
| 1 | **Carry-only `group_members`** — guests never have a row here | [db-schema-rules.md](db-schema-rules.md), [guest-lifecycle.md](guest-lifecycle.md) | 🚧 coverage gap — add SQL test asserting INSERT of `is_guest = true` profile into `group_members` is blocked by RLS or trigger |
| 2 | **Ephemeral guests** — guest profiles only exist in `round_players` for active rounds; survive round end via denormalized `guest_display_name` + `guest_handicap` | [guest-lifecycle.md](guest-lifecycle.md) | 🚧 coverage gap — add SQL test that `delete_quick_game_guests(round_id)` denormalizes name+handicap onto round_players and scores before DELETE |
| 3 | **Creator-locked-as-scorer** — wherever the creator sits in the tee sheet, that group's scorer is the creator | [scorer-rules.md](scorer-rules.md) | 🚧 coverage gap — add Swift test on `syncScorerIDs` ensuring creator's group cannot be assigned a non-creator scorer |
| 3a | **Scorer must be a Carry user** — every tee group has a `canScore == true` player as scorer; guests, pending invites, SMS invitees never become scorers. Universal: SG via Carry-only members, QG via canSave. | [scorer-rules.md](scorer-rules.md) §"Foundational premise" + [game-types.md](game-types.md) §Invariants | QG: `canSave` validation in [QuickStartSheet.swift:116](../../Carry/Views/QuickStartSheet.swift:116). SG: Skins-Groups-Carry-only invariant (Inv #1 family). 🚧 worth a Swift test asserting `canSave` returns false when slot 0 has no profileId |
| 4 | **Creator immutability** — `skins_groups.created_by` never changes after INSERT | [db-schema-rules.md](db-schema-rules.md) | 🚧 coverage gap — add SQL test asserting UPDATE of `created_by` is rejected by RLS |
| 5 | **Phase transitions** — change `phase` first inside `withAnimation`, defer cleanup; never mutate `roundConfig` in the same closure as a phase change | [phase-transitions.md](phase-transitions.md) | 🚧 coverage gap — runtime behavior; would require UI test or snapshot test of `onCancelToSetup` closure ordering |
| 6 | **8-second race guard** — every user-editable field that persists must have a `<field>LastSavedAt` stamp + skip-window in `refreshGroupData` | [refresh-race-guards.md](refresh-race-guards.md) | 🚧 coverage gap — add Swift test injecting `Date()` to verify guard window suppresses the relevant sync line |
| 7 | **Verify JWT for push triggers** — Vault-backed; helpers `_push_notification_url()` + `_push_notification_anon_key()` are the only auth path | [push-trigger-chain.md](push-trigger-chain.md) | ✅ [supabase/tests/db/notify_push_helpers_test.sql](../../supabase/tests/db/notify_push_helpers_test.sql) — 17 tests covering helper resolution + JWT shape + per-function helper usage |
| 8 | **Auth-v2 quarantine** — Google/Email/account-linking never merge into `main` or `release/*` until linking is built+tested AND a separate dev DB exists | [onboarding-and-auth.md](onboarding-and-auth.md) + project memory | 🚧 coverage gap — add CI guard: fail PR check if `GoogleSignInService.swift` or `EmailAuthSheet.swift` is present in `main` |

**6 of 8 invariants currently have no automated enforcement.** Each "coverage gap" is a candidate test to add. Treat the gap as a real liability — the recurring race-guard regressions (4 instances of the same pattern before it was documented) happened in part because nothing was failing CI.

Adjacent test coverage that defends related code paths:

| Doc | Tests |
|---|---|
| [skins-math.md](skins-math.md) | [SkinsCalculationTests](../../CarryTests/SkinsCalculationTests.swift), [PopsComputationTests](../../CarryTests/PopsComputationTests.swift), [PotCalculationTests](../../CarryTests/PotCalculationTests.swift) |
| [score-pipeline.md](score-pipeline.md) | [OfflineResilienceTests](../../CarryTests/OfflineResilienceTests.swift) |
| [results-share.md](results-share.md) | [RoundStatsLineTests](../../CarryTests/RoundStatsLineTests.swift) |
| [tee-time-sovereignty.md](tee-time-sovereignty.md) | [TeeTimesPersistenceTests](../../CarryTests/TeeTimesPersistenceTests.swift) |
| [game-types.md](game-types.md) / paywall flow | [PaywallTriggerTests](../../CarryTests/PaywallTriggerTests.swift), [StoreServiceHadPremiumTests](../../CarryTests/StoreServiceHadPremiumTests.swift) |
| [group-invitation-flow.md](group-invitation-flow.md) | [InviteStatusTests](../../CarryTests/InviteStatusTests.swift) |
| [player-flags.md](player-flags.md) | [PlayerModelTests](../../CarryTests/PlayerModelTests.swift) |
| [db-schema-rules.md](db-schema-rules.md) (encoding) | [SkinsGroupUpdateEncodingTests](../../CarryTests/SkinsGroupUpdateEncodingTests.swift) |
| Course / hole pipeline | [HolesPipelineTests](../../CarryTests/HolesPipelineTests.swift) |

Citations decay. If you find a stale `file:line` while consulting a doc, fix the doc as part of the same PR — and run `./scripts/check-blueprint-citations.sh` before committing.

## Pre-flight checklist (before any non-trivial change)

Walk the questions for your area. If you can't answer one, you haven't read enough yet.

**Always:**
- [ ] Which invariants from the table above does this code path touch?
- [ ] Does this change introduce or modify a save handler for a user-editable persisted field? → **(a) verify it persists to the authoritative source-of-truth (server table or RPC) at the save site, AND (b) add a race guard.** Missing (a) = silent reversion bug class. Missing (b) = race window stomps the edit. See [guest-lifecycle.md §"Guest profile edits — the four-layer persistence chain"](guest-lifecycle.md) and [refresh-race-guards.md](refresh-race-guards.md)
- [ ] If the field is on `profiles` and the editor is NOT the field's owner: route through a SECURITY DEFINER RPC (RLS forbids cross-user UPDATEs). Mirror the `update_guest_profile` pattern — auth check + WHERE clause that restricts targets structurally
- [ ] Does this change mutate state during a phase transition? → review the order-of-mutations rule
- [ ] Does this touch `group_members`, `round_players`, or `scores`? → review FK / cascade rules
- [ ] Does this fire a push? → review the dispatch + recipient rules
- [ ] Does this view have a `buildResult()`-like exit point? → verify it reconciles all output fields from the canonical local state. Multiple @State sources for the same data is a footgun (see [PlayerGroupsSheet.swift:1422+](../../Carry/Views/PlayerGroupsSheet.swift:1422))

**For Quick Game / guest changes:**
- [ ] Is the Carry-only `group_members` invariant preserved?
- [ ] Are guests cleared on conversion? Are guests preserved across refresh and process death?
- [ ] Does `loadSingleGroup` filter wiped-guest UUIDs from the current roster?

**For scoring / scorer changes:**
- [ ] Does `canScore` still gate write paths?
- [ ] Does `syncScorerIDs` still enforce creator-as-scorer?
- [ ] Are score writes idempotent against retry?

**For auth / onboarding changes:**
- [ ] Is the auth-v2 quarantine rule satisfied (branch target, dev DB present)?
- [ ] Does `handle_new_user` fire? Does AuthService fallback handle the missing-trigger case?
- [ ] Does session restore route to the correct screen (onboarding vs main)?

## Post-change checklist (after the change lands)

**Docs are part of the change. A code change that doesn't update the relevant blueprint is incomplete — stale docs mislead and become liability rather than asset.**

- [ ] Update every cited `file:line` in the affected blueprints. Stale docs are worse than no docs.
- [ ] **Re-read each affected blueprint section against the cited code, line by line.** The citation script catches structural drift (file renamed, line out of bounds) but not semantic drift (right line, wrong description). When in doubt, quote the code verbatim instead of paraphrasing.
- [ ] **Run `./scripts/check-blueprint-citations.sh`** — verifies all `file:line` references still resolve. Fails fast on structural decay. Run this before every commit that touches `Carry/`, `supabase/`, or `docs/architecture/`.
- [ ] If a new rule emerged, add it to the **Living invariants** table above.
- [ ] If a new flag was added, add it to the relevant decision matrix.
- [ ] If a new bug surfaced and got fixed, add an entry to [bug-archive.md](bug-archive.md) — symptom, root cause, fix, blueprint that should have prevented it (or the new blueprint section).
- [ ] Bump the **Last verified** date in each touched blueprint.

## Common symptoms → likely blueprint

| Symptom | First place to look |
|---|---|
| User edit visually reverts after ~1 sec | [refresh-race-guards.md](refresh-race-guards.md) — missing `lastSavedAt` |
| Convert-to-Skins-Group prompt doesn't appear after Save Round Results | [game-types.md](game-types.md) §"When the convert prompt fires" — three gating conditions (Quick Game + natural completion + premium); force-end and partial rounds dismiss silently |
| Push not delivered, no error | [push-trigger-chain.md](push-trigger-chain.md) — Vault helper resolution + `net._http_response` histogram |
| Guest disappears after navigate-out + back | [guest-lifecycle.md](guest-lifecycle.md) — UserDefaults snapshot, `allMembers` vs `guests` bucket |
| "Couldn't connect" toast on transition | [phase-transitions.md](phase-transitions.md) — order-of-mutations rule |
| Quick Game convert sheet doesn't appear | [game-types.md](game-types.md) — `onCreateGroup` plumbing through `RoundCoordinatorView` |
| Scorer reverts to default mid-round | [scorer-rules.md](scorer-rules.md), [refresh-race-guards.md](refresh-race-guards.md) |
| 42703 PL/pgSQL error | [push-trigger-chain.md](push-trigger-chain.md) — per-table dispatch rule |
| Pending invite never reconciles | group-invitation-flow.md *(planned)*, [push-trigger-chain.md](push-trigger-chain.md) |
| Creator can't play, member sees wrong roster | [player-flags.md](player-flags.md), [scorer-rules.md](scorer-rules.md) |

## When the playbook is wrong

If you followed the playbook and still hit a regression, the playbook missed a dependency. Add a row to the lookup table or the symptom map as part of the fix. The playbook is a living index — it gets better when you correct it.

## Last verified

2026-05-09 — initial playbook + 18-doc blueprint set in flight.
