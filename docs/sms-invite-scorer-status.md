# SMS-Invite-as-Scorer — Status Checkpoint

**Branch:** `hotfix/1.0.9` @ `966e048`
**Captured:** 2026-05-13 (mid-session)
**Goal:** Ship the SMS-invite-as-scorer reconciliation fix as part of 1.0.9.

## What ships in 1.0.9

### Stage 0 — QG missing-scorer CTA fixes (pre-existing, already cherry-picked)
| Commit | What |
|---|---|
| `21aa57f` | `canStartRound` for QG ANDs `missingScorerGroupIndex == nil` so the "Group N needs scorer" CTA actually blocks |
| `9898f7c` | CTA tap routes to PlayerGroupsSheet when missing-scorer is the blocker |
| `00e4584` | scorer-rules.md + game-types.md + playbook.md updated to reflect the new CTA contract |
| `9d5e82b` | MARKETING_VERSION 1.0.9, build 82 |

### Stage 1 — SQL helper `scorer_ids_uuid_at` (vestigial after pivot to int-path)
- `091e568` — `supabase/migrations/20260513000000_scorer_ids_uuid_format.sql` adds `scorer_ids_uuid_at(jsonb, int) -> uuid` helper. Still installed but unused after the int-path pivot. Harmless.
- Test: `supabase/tests/db/scorer_ids_uuid_at_test.sql` (10 PASS on dev).

### Stage 2 — `reservePhoneInvite` + `GroupMemberInsert.id`
- `2e44fcd` — `GroupMemberInsert` gains optional `id: UUID?`. `GroupService.reservePhoneInvite(id:groupId:phone:invitedBy:groupNum:) async throws -> UUID` lets the iOS slot supply the row's PK at insert time.

### Stage 3a (vestigial) — UUID-shape trigger extension
- `bc13292` — `supabase/migrations/20260513000001_reconcile_extends_scorer_ids.sql`. Superseded by Stage 3b below.

### Stage 3b — **Path A int-path triggers** (load-bearing)
- `453fa83` — Pivot to int-path. Two migrations:
  - `20260513000002_player_stable_id_sql.sql` — `player_stable_id(uuid) -> bigint` replicates iOS `Player.stableId(from:)` bit-shift formula in SQL.
  - `20260513000003_reconcile_scorer_ids_int_path.sql` — Both phone-invite reconciliation triggers (`reconcile_phone_invites_for_profile` forward + `reconcile_phone_invite_at_insert` reverse) rewrite `scorer_ids` int-in-place from `player_stable_id(placeholder_uuid)` to `player_stable_id(profile_uuid)` via helper `_reconcile_scorer_ids_int`. Wire format stays `[Int]` — non-breaking for clients on older app versions.
- Tests: `supabase/tests/db/player_stable_id_test.sql` (7 PASS), `supabase/tests/db/reconcile_scorer_ids_int_path_test.sql` (multi-assertion PASS).

### Stage 4a/b/c — Client-side UUID threading
- `1627b3d` — `ScorerSlot.inviteMemberId: UUID?` + `Player.inviteMemberId: UUID?` + `ScorerSlot.asPlayer` derivation uses `inviteMemberId ?? profileId ?? UUID()` for `Player.id`. `QuickStartSheet`'s `PlayerSlot` + bridge + `createQuickGame` thread `inviteMemberId` through.
- `78ad41e` — `GroupsListView.handleQuickGameCreate` calls `reservePhoneInvite(id: inviteMemberId, …)` for SMS-invite slots (was previously `.insert()` with server-generated id).
- `ee1248b` — `handleQuickGameCreate`'s guest-rebuild `map` skips `isPendingInvite` slots so SMS-invite players aren't accidentally converted to guest profiles.
- `ebb9cd8` — `PlayerGroupsSheet.saveAndDismiss` adds new step 3c: walks `cleanResult.groups`, calls `reservePhoneInvite` for each pending-invite Player with an `inviteMemberId`. Closes the worse-half of the bug where PlayerGroupsSheet previously made zero server calls for SMS-invite scorer slots.

### Stage 5 — Cross-language regression test
- `bd64632` — `CarryTests/PlayerModelTests` adds 4 cases verifying `Player.stableId(from:)` matches `player_stable_id(uuid)` SQL for known UUIDs (all-zero → 0; `01020304-0506-0708-...` → 22176636; all-FF → 4294967295; bytes beyond index 7 ignored). Updated SQL test to match. Tests committed in `45d0f48` + `3ecad51`.

### Root-cause fix — `saveGroupNums` scope
- `8ea03a4` — `GroupService.saveGroupNums` adds `.or("invited_phone.is.null,invited_phone.eq.")` so the UPDATE doesn't stomp SMS-invite rows whose `player_id` placeholder equals the inviter's UUID. **This was the actual root cause of every "group_num=1 instead of 2" symptom**; PostgREST was never dropping the field — `saveGroupNums` was overwriting it 1 second post-insert because the WHERE clause matched both rows.
- New migration `20260513000004_create_phone_invite_rpc.sql` — adds SECURITY DEFINER `create_phone_invite(p_id, p_group_id, p_phone, p_invited_by, p_group_num text) -> uuid` RPC. iOS `reservePhoneInvite` calls the RPC instead of `.insert()`. This was originally added as a workaround for the misdiagnosed PostgREST issue; it's still useful (clean server-side write contract) but no longer load-bearing now that the real fix is in `saveGroupNums`.

### Pre-reconciliation UX fix
- `966e048` — `GroupManagerView` init + refreshGroupData filter splits by `isQuickGame`: QG includes `isPendingInvite` in default Playing roster + newly-active members so the SMS-invitee shows up in Group 2's scorer slot before they onboard. SG keeps excluding (Carry-only invariant).

## Verified on dev

| Path | Status |
|---|---|
| Direct SQL INSERT preserves `group_num` | ✅ |
| RPC `create_phone_invite` inserts with supplied id + group_num | ✅ |
| iOS `Player.stableId` matches SQL `player_stable_id` for known UUIDs | ✅ (Swift + SQL tests pass) |
| **Reverse trigger** (invitee already has phone-on-profile → reconciles at INSERT) | ✅ Daniel's phone was on his profile; invite landed as active + scorer immediately |
| **Forward trigger** (invitee onboards later → phone added → reconciles) | ✅ Daniel deleted his profile, onboarded fresh, scorer slot reconciled |
| Post-reconciliation: Ziggy sees Daniel as Group 2 scorer with lock icon | ✅ |
| Post-reconciliation: Daniel's iPhone sees QG on Home + can score Group 2 | ✅ |
| `scorer_ids` round-trip aligned between client + server stable-ints | ✅ Verified `[1316978173, 533855954]` = `[stableId(Ziggy.profileId), stableId(SMS_row.id)]` |

## Pre-reconciliation visibility — VERIFIED live (Session 2 evening)

After temporarily clearing the recipient's `profile.phone` via SQL, Daniel created a fresh QG with SMS invite. Observed on Ziggy:
- Group 2 Score Keeper slot rendered with **orange avatar + phone number, both dimmed** ✅
- "Invited" state visually distinct from the missing-scorer state ✅
- (Untested live but committed: button label `"Waiting for Scorer to Join"` + greyed/inactive — commit `31d220b`. See below.)

## Final fix landed late session — pending live verify

`31d220b` updates `groupHasValidScorer` to count pending-invite slots as filled (not missing). Effect on the CTA:
- Before: button said "Group N needs scorer" + tappable (wrong — there IS a scorer, just pending)
- After: button says **"Waiting for Scorer to Join"** + greyed out / not tappable

**Not verified live yet.** Daniel asked to leave it as-committed and verify tomorrow. To test:
1. Cmd+R on Ziggy to rebuild with `31d220b`
2. Either re-test the pre-reconciliation scenario (clear phone again, create fresh QG with SMS invite) OR find the existing pending QG in this state
3. Confirm: orange dimmed scorer slot, button = "Waiting for Scorer to Join", button is greyed and not tappable

## Known issues / follow-ups

| Issue | Notes |
|---|---|
| **"user4 x 2" duplicate guest row** in Group 2 details (observed mid-session) | Daniel reported the typed Group 2 slot-1 guest ("user4") appeared duplicated in QG details. Root cause not investigated — could be iOS rendering, or the `allMembers = filteredFreshMembers + preservedGuests` merge introducing dups when ids match between local + server. **Repro + diagnose before ship.** Start with the diagnostic SQL in this doc and compare local-side and server-side member counts. |
| Pre-reconciliation scorer-slot styling shows raw phone digits, not the typed name | Daniel asked: "have the orange state, with invited in the scorer slot, until I auto join so the invite feels like it was successful". Today's phone-invite Player has `name = phone_digits`, no typed name stored. Fix: add `invitee_name text` column to `group_members`, plumb the typed name from `ScorerAssignmentView.sendInvite` through `reservePhoneInvite` → RPC. `loadSingleGroup` phone-invite Player uses `invitee_name` when present. Queued for 1.0.10. |
| Debug prints left in code | `[QuickStart.createQuickGame] SMS slot`, `[SMS-invite] member.group`, `[reservePhoneInvite] RPC call`, `[reservePhoneInvite] RPC success`, `[reservePhoneInvite] RPC FAILED` — all in DEBUG blocks. Strip before ship OR leave for one more release cycle to aid any post-ship debugging. |
| Migration `20260513000004` still has `RAISE LOG` line | Useful for PostgreSQL log debugging, low overhead. Can stay. |
| Architecture docs (scorer-rules.md, game-types.md, playbook.md) NOT updated with SMS-invite-as-scorer behavior | Deferred until the feature is fully shipped + verified. After 1.0.9 lands, sync them in a follow-up commit. |

## Migrations to apply on prod when 1.0.9 ships

In order:
1. `20260513000000_scorer_ids_uuid_format.sql` (vestigial but harmless)
2. `20260513000001_reconcile_extends_scorer_ids.sql` (vestigial — superseded by next two)
3. `20260513000002_player_stable_id_sql.sql` (active)
4. `20260513000003_reconcile_scorer_ids_int_path.sql` (active — `CREATE OR REPLACE`s the triggers added in 20260502)
5. `20260513000004_create_phone_invite_rpc.sql` (active)

Apply via Supabase Studio SQL Editor on prod (`seeitehizboxjbnccnyd`). Dev branch is already in this state.

## Final ship steps (in order)

1. ⏳ **Rebuild on Ziggy** (Cmd+R) and verify the `31d220b` pending-state UX live: greyed-out button + "Waiting for Scorer to Join" label
2. ⏳ Repro the "user4 x 2" duplicate guest bug and either fix or document as known issue
3. ⏳ Decide on debug-print stripping (recommend: leave for now, strip in 1.0.10)
4. ⏳ Apply migrations 1–5 above on prod
5. ⏳ Bump `CURRENT_PROJECT_VERSION` from 82 → 83 (or leave at 82 if no new prod build was archived yet on 1.0.9)
6. ⏳ Archive in Xcode (Release config → prod Supabase) → upload to ASC
7. ⏳ ASC: fill "What's New" — note: still need to add Leaderboards & Stats + Share Your Round to App Description (memory says this is pending from 1.0.4)
8. ⏳ Submit for review

## Resume instructions for tomorrow

1. **Read this file end-to-end.** Especially "Final fix landed late session" and "Known issues" — that's where you stopped.
2. `git log hotfix/1.0.7..hotfix/1.0.9 --oneline` — should show ~28 commits ending at `31d220b`.
3. Check that dev DB has migrations 20260513000000–20260513000004 applied (per the migrations table above). Also confirm: Daniel's iPhone profile's phone is currently NULL on dev (cleared during late session for the pre-reconciliation test — re-add if needed).
4. **First action:** Cmd+R on Ziggy and verify the `31d220b` UX change (pending scorer = "Waiting for Scorer to Join" + greyed button). If broken, dig into `groupHasValidScorer` + `startButtonLabel` interaction.
5. **Second action:** Repro the "user4 x 2" bug. Diagnostic SQL is the one earlier in this doc — counts and lists group_members for the latest QG. If the DB has 1 row for user4 but iOS shows 2, it's an iOS dup-merge issue; if DB has 2, it's a server-side issue.
6. Once both issues are clean, ship per the "Final ship steps" list above.

## Last updated

2026-05-13 — end-of-session checkpoint. Pre-reconciliation visibility verified live (orange avatar + dimmed phone number). `31d220b` (pending-state button) committed but not verified — tomorrow's first step.
