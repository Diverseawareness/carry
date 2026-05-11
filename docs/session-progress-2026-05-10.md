# Session Progress — 2026-05-10

Live progress doc for this session. Resume from here in next session if needed.

## TL;DR

| Status | Count |
|---|---|
| ✅ Fixed + verified on device | 3 (Bug A, Bug H, Bug J) |
| ✅ Fixed in code, pending device verification | 7 (Bug #0 drag-stick reconciler, Bug C dead-code purge, Bug E guest persistence on reinstall, "Back to Groups" splash removed, QG card pills 1:1 contract, Guest+0.0 corruption-cycle 3-point hardening, **"X joined" toast refire — switched baseline to playerId UUID**) |
| ⏸ Pending decision | Group formation refactor (minimal-risk reconciler executed; full migration only if reconciler fails) |
| 🔬 Backlog with diagnoses | 4 (Bug F, G, I, D) |
| 📚 Documentation | 22 architecture docs in machine-readable format + bug archive + refactor target |

## What was verified on device

| Bug | Symptom | Fix | Verified |
|---|---|---|---|
| A | Quick Game convert prompt missing from Home-tab entry | AppRouter `pendingConvertGroupId` plumbing through HomeView → GroupsListView | ✅ |
| H | Back from setup view post-cancel landed on Course Selection | Added `groupId != nil` to exit condition in [RoundCoordinatorView.swift:170-193](../Carry/Views/RoundCoordinatorView.swift:170) | ✅ |
| J | Start Round button flag icon popped in after text on QG entry | Always-render with opacity toggle at [GroupManagerView.swift:1715-1722](../Carry/Views/GroupManagerView.swift:1715) | ✅ |

## What's fixed in code, pending device verification

These all build clean and have full doc coverage. Need rebuild + retest on device.

### Bug #0 — Drag-and-drop tee-group persistence (multi-layered fix)

Earlier in session: race guard added (`groupNumLastSavedAt`, 4th instance of pattern). User reported guest drag still didn't stick across nav-out + back.

Layered fixes applied:
1. `.onChange(of: groups)` mirrors arrangement into `allMembers` + `guests` (writes `Player.group` from index) + saves to `QuickGameGuestStorage`
2. `loadSingleGroup` between-rounds backfill: synthesize guests from `guest_roster_json` when no qualifying round
3. `localized.members` patch unconditional (was 8s-gated): always patch `.group` from local `groups[][]` for visible players
4. `.onAppear` override: when hydrating from `QuickGameGuestStorage`, override existing entries' `Player.group` from saved snapshot (was only adding missing entries)

User has reported this bug class STILL not sticking in some scenarios. Status when session paused: latest layered fix may or may not solve it. **Next step: rebuild, repro original drag scenario (you + 1 guest in 2 groups, drag guest to your group, nav out, nav back).**

If still broken → refactor (see "Group formation refactor" below).

### Bug C — HomeView Invites dead-code cleanup

~470 lines deleted across HomeView, RoundService, SupabaseModels (inviteCard, acceptInvite, declineInvite, loadInvites, paywall onChange handler, all 4 @State vars, demoInvited static, RoundService Invites section + 3 InviteDTO/InviteRoundDTO/InviteCourseDTO structs).

Pending: smoke test Home tab (load, pull-to-refresh, 30s auto-refresh, tap active round + back, tap recent round + back).

### Bug E — Quick Game guests lost on app delete + reinstall

Server-side `skins_groups.guest_roster_json` JSONB column. Migration `20260510000000_skins_groups_guest_roster.sql` **applied to dev only** (via Supabase Studio SQL editor; `supabase db push` blocked by squash drift, see "Squash drift" below). NOT applied to prod yet.

iOS code: `QuickGameGuestStorage` rewrote with debounce + retry-with-backoff + race guard (5th instance of `<field>LastSavedAt` pattern). `GroupService.saveGuestRoster` + `loadSingleGroup` hydrate.

Pending: full reinstall test — create QG with guests, delete app, reinstall, verify guests survive.

### "Back to Groups" splash button removed

User confirmed: button at `RoundCoordinatorView.swift:610-626` was a UX trap (settings edits persisted but roster changes were partial — adding a member inserted `group_members` row but NOT `round_players`, so new player didn't appear in scorecard; removals left orphan `round_players`). Removed; users return to setup via scorecard `...` menu.

### "X joined" toast refire (cross-session new-member toast)

User saw the toast firing repeatedly inside group details, including a delayed one in the scorecard. Root cause: baseline at [GroupManagerView.swift:1011](../Carry/Views/GroupManagerView.swift:1011) was keyed on `group_members.id` (row UUID); `dedupeMembers` is non-deterministic and the chosen row's `id` swaps across refreshes when there are multiple active rows for the same player.

Fix: baseline switched to `playerId` UUID set (`seenActiveMemberPlayerIds_<groupId>`). One toast per user per device per group, ever. Trade-off: leave-and-rejoin on the same device won't re-fire (server push covers cross-device). Documented in [bug-archive.md](architecture/bug-archive.md) + [manage-members.md §Toast baselines](architecture/manage-members.md).

### "Guest"+0.0 root cause — three-point hardening (corruption cycle break)

**Updated 2026-05-10 evening** after first fix only partially worked (1 of 4 guests recovered). Full root cause is a **corruption cycle**: literal "Guest"+0.0 fallback at `buildHomeRound:1599` poisons iOS roster → snapshot save persists "Guest" → reconciliation reads snapshot → creates profile named "Guest" → denormalized server-side. Three-point hardening:

1. **`createSupabaseRound` reconciliation** ([RoundCoordinatorView.swift:430-503](../Carry/Views/RoundCoordinatorView.swift:430)) — pulls canonical names from `QuickGameGuestStorage` snapshot (matched by profileId, then by id) NOT from possibly-corrupted `Player.name`
2. **`buildHomeRound` wiped-fallback** ([GroupService.swift:1589-1620](../Carry/Services/GroupService.swift:1589)) — consults snapshot before falling back to literal "Guest"
3. **`QuickGameGuestStorage` corruption guards** ([QuickGameGuestStorage.swift](../Carry/Services/QuickGameGuestStorage.swift)) — `save()` filters out `name == "Guest"`; `load()` filters on read. Defense-in-depth — corruption can't enter or leave the snapshot

**Existing corrupted state unrecoverable** — affected groups need fresh round with fresh guest entries. Future games are immune.

Full bug archive entry: [bug-archive.md](architecture/bug-archive.md) "Guest profiles stale at round-start ('Guest'+0.0 root cause + corruption-cycle fix)".

### "Guest"+0.0 root cause — guest profile reconciliation at round-start (initial fix, partial)

User reported guest names showing as `"Guest"` and handicaps as `0.0` everywhere (pills, scorecard list, tee-time table, PlayerGroupsSheet, active card, index column).

Root cause via SQL on dev: active `round_players` referenced **deleted** guest profiles. After `Restart Round` triggered `delete_quick_game_guests` (per the ephemeral-guest invariant), guest profileIds in iOS roster became stale. New round_players rows pointed at non-existent profiles. iOS `buildHomeRound` wiped-guest fallback at [GroupService.swift:1599](../Carry/Services/GroupService.swift:1599) substitutes `name = rp.guestDisplayName ?? "Guest"` and `handicap = rp.guestHandicap ?? 0.0` — but denormalized fields are NULL because denormalization only fires on round termination, not on creation. → "Guest" + 0.0 everywhere.

The architectural rule was implemented asymmetrically: cleanup at round-end exists; recreation at round-start did not. Guests were being treated as round-scoped (correct) but the round-start path wasn't recreating profiles for guests with stale IDs (gap).

Fix: added a guest profile reconciliation block at the start of `createSupabaseRound` in [RoundCoordinatorView.swift:430+](../Carry/Views/RoundCoordinatorView.swift:430). For each guest in the roster:
1. Query `profiles` for which candidate `profileId`s exist as `is_guest = true`
2. Recreate missing ones via `GuestProfileService.createGuestProfiles`
3. Update `configForRound.players` with new profileIds before building `playerTuples`

Required `RoundConfig.players` to be flipped from `let` to `var` ([RoundConfig.swift:41](../Carry/Models/RoundConfig.swift:41)).

Build clean. Documented in [bug-archive.md](architecture/bug-archive.md) entry "Guest profiles stale at round-start (the actual 'Guest'+0.0 root cause)". Pending device verification: rebuild → Restart Round on QG with guests → start new round → confirm names/handicaps real.

### QG card pills 1:1 contract

🔒 Locked invariant: pills on Games tab card MUST be 1:1 with the in-app roster. Four paths populate `group.members`; all must respect the contract. Documented in [docs/architecture/guest-lifecycle.md §"Games tab card pills — contract"](architecture/guest-lifecycle.md).

Two-part fix:
- `loadSingleGroup` synthesizes guests from `guest_roster_json` when no qualifying round (cross-session, multi-device)
- `refreshGroupData` `localized.members` merges in local QG guests from `allMembers` for the same-session window

Pending: verify pills consistency across active round / between rounds / post-cancel states.

## Group formation refactor — minimal-risk version EXECUTED

`.onChange(of: groups)` is now a self-consistent reconciler at [GroupManagerView.swift:2477-2553](../Carry/Views/GroupManagerView.swift:2477). After every mutation to `groups[][]`, it auto-corrects each player's `Player.group` field to match its array index. If correction was needed, it rewrites `groups` and SwiftUI re-fires `.onChange` once with the corrected values; on re-fire, the rest of the handler runs (mirror to `allMembers`/`guests`, persist QG snapshot, schedule server sync).

This is functionally equivalent to forcing every mutation site through a single `commitGroupsChange` function — but without rewriting any mutation site, so risk surface stays minimal per the user's "no breakages allowed" rule.

Build clean, 128 tests pass. Documented in [bug-archive.md](architecture/bug-archive.md) (new entry "Group formation single-source-of-truth refactor") + [group-formation-canonical.md](architecture/group-formation-canonical.md) (status section at top).

**Pending device verification:** rebuild + retest the drag-stick scenario. The reconciler's correctness depends on `.onChange(of: groups)` firing reliably for nested array mutations (insert/remove on `groups[i]`). If it doesn't fire in some path, the full migration in `group-formation-canonical.md` becomes necessary.

## Backlog (diagnosed, not fixed)

| Bug | Symptom | Status |
|---|---|---|
| Bug F | Quick Game: removing the last player in a 2-group setup doesn't persist across nav-out + back | Likely same race-guard pattern as Bug #0; if Bug #0 layered fix solves it, F may also be resolved |
| Bug G | Home tab shows empty state after declining convert prompt | Likely same shape as 1.0.4 `b379270` "Skipped Quick Game preserves to Recent Games" fix |
| Bug I | End Game destructive on Quick Game may not auto-dismiss to Games tab | Might be a misattributed Restart Round path. Capture which button next time |
| Bug D | "X joined" toast may fire after Restart Round | Need exact text via Xcode console capture |

## Squash drift (still active)

`supabase db push` blocked because squash branch is divergent from active hotfix line. Workaround: apply migrations via Supabase Studio SQL editor (`ALTER TABLE ... IF NOT EXISTS` is idempotent; tracking row reconciles on next clean push after squash merge). Bug E migration applied to dev via Studio.

When the squash branch eventually merges to main, `db push` is restored. The 20260510000000 migration file's `IF NOT EXISTS` will skip cleanly and the tracking row will record itself.

**Do NOT** run `supabase migration repair`; it breaks the auth-v2 quarantine condition. **Do NOT** press Reset on the Supabase dashboard without merging squash → main first.

## Files modified this session

| File | Change |
|---|---|
| `Carry/Views/RoundCoordinatorView.swift` | Removed "Back to Groups" splash button; fixed Bug H (back from setup → Games tab when groupId != nil); **added guest profile reconciliation block in `createSupabaseRound` (Guest+0.0 root cause fix)** |
| `Carry/Models/RoundConfig.swift` | `players` flipped `let → var` to allow guest profileId reconciliation at round-start |
| `Carry/Views/HomeView.swift` | Bug A convert routing; Bug C ~280 lines of Invites dead code deleted |
| `Carry/Views/GroupsListView.swift` | Bug A convert handler; `SavedGroup.members` flipped `let → var`; new `.onChange(of: appRouter.pendingConvertGroupId)` |
| `Carry/Views/GroupManagerView.swift` | Bug #0 race guard + many follow-ups (mirror in `.onChange`, `.onAppear` override, localized patch unconditional, Bug J flag opacity) |
| `Carry/Models/SupabaseModels.swift` | Added `guestRosterJson` to SkinsGroupDTO + SkinsGroupUpdate (with clear flag + custom encoder); Bug C InviteDTO/InviteRoundDTO/InviteCourseDTO removed |
| `Carry/Services/RoundService.swift` | Bug C: removed entire Invites section (~133 lines) |
| `Carry/Services/GroupService.swift` | New `saveGuestRoster` method; `loadSingleGroup` hydrates `QuickGameGuestStorage` + between-rounds backfill from `guest_roster_json` |
| `Carry/Services/QuickGameGuestStorage.swift` | Rewrote with debounce + retry-with-backoff + UserDefaults stamp + hydrate guard |
| `Carry/Services/AppRouter.swift` | Added `pendingConvertGroupId` |
| `CarryTests/SkinsGroupUpdateEncodingTests.swift` | 4 new tests for `guestRosterJson` encoding |
| `supabase/migrations/20260510000000_skins_groups_guest_roster.sql` | NEW migration — `guest_roster_json` column + comment |

## Documentation written this session

| File | Purpose |
|---|---|
| `docs/architecture/playbook.md` | Entry point + lookup table + invariants + symptom map |
| `docs/architecture/bug-archive.md` | Every prod regression: symptom → root cause → fix → blueprint that should have prevented it |
| `docs/architecture/onboarding-and-auth.md` | Pre-condition for resuming auth-v2 work |
| `docs/architecture/skins-math.md` | USGA course-handicap formula, stroke allocation, skins determination |
| `docs/architecture/score-pipeline.md` | Tap → @State → ScoreStorage → Supabase upsert → realtime + 15s poll |
| `docs/architecture/round-lifecycle.md` | The 4 status values + transitions + force_completed semantics |
| `docs/architecture/tee-time-sovereignty.md` | Single-writer rule (1.0.6 fix) |
| `docs/architecture/recurring-rounds.md` | GameRecurrence + advancement |
| `docs/architecture/manage-members.md` | Add/remove flow + state-propagation race |
| `docs/architecture/group-invitation-flow.md` | Three invite paths + reconciliation triggers |
| `docs/architecture/results-share.md` | RoundCompleteView + ResultsShareCard + Venmo deep link |
| `docs/architecture/deep-link-routing.md` | `carry://` + Universal Links |
| `docs/architecture/account-linking.md` | Forward-looking spec for auth-v2 |
| `docs/architecture/group-formation-canonical.md` | **Refactor target if drag-stick still broken** |
| All 8 pre-existing topic docs | Converted to machine-readable format |
| `scripts/check-blueprint-citations.sh` | CI script catching structural decay (file:line) |
| `docs/test-plan-1.0.8.md` | Per-release manual test plan |

376 citations valid as of session pause.

## How to resume in next session

1. **Read `MEMORY.md`** — auto-loaded; gives session-style preferences + locked invariants + bug list
2. **Read this file** — session-specific progress
3. **Read `docs/architecture/playbook.md`** — entry point for any code change
4. **First action: rebuild + test the Guest+0.0 fix.** Open QG with guests → Restart Round → start new round → verify names/handicaps real on pills, scorecard list, tee-time table, PlayerGroupsSheet, active card.
   - If guests show real names → fix confirmed, move to Bug E reinstall test
   - If still "Guest"+0.0 → reconciliation block isn't firing or `createGuestProfiles` is silently failing; check console for `❌` logs

## Last verified

2026-05-10 — session paused after coding the Guest+0.0 root cause fix (guest profile reconciliation in `createSupabaseRound`). Build clean, citations clean, pending device verification.
