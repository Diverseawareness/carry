# SMS-Invite-as-Scorer — Status Checkpoint

**Branch:** `hotfix/1.0.9` @ `7211817`
**Captured:** 2026-05-13 (late session, mid re-invite verification)
**Goal:** Ship the SMS-invite-as-scorer reconciliation fix as part of 1.0.9.

---

## Where we are right now

- **Most of the SMS-invite plumbing is in.** The forward + reverse triggers, `player_stable_id` int path, `create_phone_invite` RPC, `inviteMemberId` threading through `ScorerSlot`/`Player`/`PlayerSlot`, and the X-clear + swipe-delete paths are all landed and verified.
- **The 2026-05-13 re-invite bug surfaced a layered set of issues** in `PlayerGroupsSheet` (Edit Players flow) for Group 2+ SMS-invite scorers. Each layer was fixed; latest unverified fix is `7211817`.
- **Currently waiting on Daniel to retest** after cleaning the broken server row.

## Latest commit chain (since `31d220b`)

| Commit | Why |
|---|---|
| `08fe784` | Swipe-delete phone-invite: handle the `profileId=nil` case via `inviteMemberId` row id |
| `f559386` | X button on `invitedRow` to clear pending SMS-invite scorer slot |
| `fb7a13c` | `invitee_name` column + render typed name in tee sheet |
| `39df783` | HC picker focus guard |
| `fecedfa` | Clean up prior search-added Carry user when switching to SMS-invite (.confirmed → .invited) |
| `c12e370` | X-clearing confirmed Carry scorer FULLY removes (was demoting → duplicate) |
| `91740a0` | Block self-SMS-invite — server collapse otherwise orphans the slot |
| `95ccaa5` | `ScorerSlot.asPlayer` carries `phoneNumber` + `selectedIDs.insert` on .invited/.confirmed transitions |
| `9f1812d` | QuickStartSheet scorer slot auto-scrolls above keyboard on focus |
| `6146033` | `.bottom` anchor for the scorer auto-scroll |
| `816b023` | Same auto-scroll wired into PlayerGroupsSheet |
| `64f1bef` | `saveAndDismiss` step 3c derives `groupNum` from outer enumerate index, not from `Player.group` (which `asPlayer` hardcodes to 1) |
| `322d0fb` | 350ms delay on scrollTo so iOS keyboard safe-area inset lands first |
| `7211817` | `saveGroupNums` switched to SELECT-then-UPDATE-by-id (PostgREST `.or("invited_phone.is.null,invited_phone.eq.")` empty-value term wasn't being respected → was clobbering phone-invite row group_num) |

---

## The full chain of bugs we hit (in order they surfaced)

1. **Tee row showed "Invited" instead of formatted phone.**
   Cause: `ScorerSlot.asPlayer` didn't propagate `phoneNumber` → local Player had nil phone → `formatPhoneDisplay(nil) == "Invited"`. **Fixed in `95ccaa5`.**

2. **Slot disappeared after 30s refresh.**
   Cause: `.invited` and `.confirmed` branches of `scorerSlotBinding` appended to `groups[]` but never added the new player.id to `selectedIDs`. `refreshGroupData`'s rebuild filters by `selectedIDs.contains(id)` → dropped. **Fixed in `95ccaa5`.**

3. **After re-invite, scorer "moved" from Group 2 to Group 1 (visible in a guest slot).**
   Cause: `ScorerSlot.asPlayer` hardcodes `Player.group = 1`. Step 3c was using `player.group` for the `reservePhoneInvite` groupNum param → every SMS invite was persisted with `group_num=1`. **Fixed in `64f1bef`.**

4. **Even with #3 fixed, the slot STILL disappeared after refresh.**
   Cause: `saveGroupNums`'s scope (`.or("invited_phone.is.null,invited_phone.eq.")`) was supposed to exclude phone-invite rows from the UPDATE, but the empty-value `eq.` term wasn't being respected — the UPDATE still matched phone-invite rows that share the inviter's `player_id` placeholder. After `reservePhoneInvite` inserted with `group_num=2`, either step 4 in saveAndDismiss OR the parent's debounced `syncGroupNumsToSupabase` clobbered it back to 1 (the creator's group). **Fixed in `7211817`** via SELECT-then-UPDATE-by-id — fetches the rows for (group, player), filters out non-empty `invited_phone` client-side, UPDATEs each surviving row by primary key.

5. **`create_phone_invite` RPC dedup-by-phone doesn't update group_num on hit.**
   When the same phone is re-invited (e.g. user X-cleared then re-invited the same number, or test scenario where the previous broken row wasn't cleaned), the RPC's existing-row dedup returns the old id WITHOUT updating any fields. iOS minted a new UUID for the slot but the server returned the old row's id → mismatch → slot wipes anyway. **Pending — see below.**

---

## Verified end-to-end

| Path | Status |
|---|---|
| Forward + reverse reconciliation triggers fire correctly | ✅ |
| iOS `Player.stableId` matches SQL `player_stable_id` for known UUIDs | ✅ (Swift + SQL tests) |
| Pre-reconciliation orange-dimmed scorer slot visibility | ✅ |
| `"Waiting for Scorer to Join"` button state on pending scorer | ✅ |
| X-clear on pending invite removes the server row | ✅ |
| Swipe-delete on phone-invite tee row removes server row + local | ✅ |
| Typed name + formatted phone render in tee row on **first** invite | ✅ |
| Block self-SMS-invite with toast | ✅ |
| QuickStartSheet + PlayerGroupsSheet scorer slot auto-scrolls above keyboard | ✅ (newer devices); needs verification on Ziggy's older device after `322d0fb` |

## Unverified — Daniel's next test step

- Re-invite flow in **PlayerGroupsSheet** (Edit Players) for **Group 2+** scorer slot: verify the row holds in Group 2 with typed name + formatted phone through a full 30-60s refresh cycle.
- Latest test (before `7211817`) showed the row still disappearing — but the test re-used phone `5555555555` which triggered the RPC dedup path (#5 above), not the new saveGroupNums code path. Daniel asked for a different phone to retest properly.
- **Next test:** rebuild → Edit Players → Group 2 scorer → invite with phone `5550001234` (or any unused number) + typed name "Test" → Save → wait 60s.

---

## Known issues / follow-ups

| Issue | Notes |
|---|---|
| **`create_phone_invite` RPC dedup needs to UPDATE on hit** | When a row exists for (group_id, invited_phone), the RPC returns the existing id without updating `group_num` / `invitee_name` / `status`. Stale state from prior bugs sticks. **Fix:** UPDATE the existing row with the new values + reset status to 'invited'. iOS also needs to re-anchor its slot to the returned id when it differs from the locally-minted UUID. **Required for robust re-invite UX.** |
| **Lost guest player on QG creation** | Daniel reported a guest in Group 2 disappeared on create. Not yet diagnosed — could be the local Player not making it through `createQuickGame`'s slot iteration, or a separate server-side dedup hit. Flagged 2026-05-13 mid-session. Repro: create a fresh QG with a guest in Group 2 — does the guest survive the creation round-trip? |
| **Group 2 scorer auto-scroll on Ziggy's device** | After `322d0fb` (350ms delay) Daniel didn't re-verify on the smaller screen. Re-test once the re-invite flow is signed off. |
| Debug prints left in code | `[QuickStart.createQuickGame] SMS slot`, `[reservePhoneInvite] RPC...`, `[PlayerGroupsSheet] saveAndDismiss → removing N members...` — all in DEBUG blocks. Strip before ship OR leave one more cycle. |
| Architecture docs (scorer-rules.md, game-types.md, playbook.md) NOT updated with SMS-invite-as-scorer behavior | Sync as a follow-up after 1.0.9 ships. |

---

## Migrations to apply on prod when 1.0.9 ships

In order:
1. `20260513000000_scorer_ids_uuid_format.sql` (vestigial but harmless)
2. `20260513000001_reconcile_extends_scorer_ids.sql` (vestigial — superseded by next two)
3. `20260513000002_player_stable_id_sql.sql` (active)
4. `20260513000003_reconcile_scorer_ids_int_path.sql` (active)
5. `20260513000004_create_phone_invite_rpc.sql` (active)
6. `20260513000005_add_invitee_name_to_group_members.sql` (active — adds `invitee_name` column + extends RPC sig to accept `p_invitee_name`)

Apply via Supabase Studio SQL Editor on prod (`seeitehizboxjbnccnyd`). Dev branch already has all of these.

---

## Resume instructions for new session

1. **Read this file end-to-end** + skim `MEMORY.md` "Active investigation" section for context.
2. `git log --oneline hotfix/1.0.7..hotfix/1.0.9` — should show ~40 commits ending at `7211817`.
3. **Current state of the server-side test data on dev:**
   - QG id: `1c04a53b-f357-4f67-b226-e2c612a5b669` ("Quick Game", created by `4a7f79cd-...` = Daniel)
   - Phone-invite row `99f72f21-...` was DELETED (Daniel ran `DELETE ... RETURNING id` and got the id back). State is clean.
   - `scorer_ids` may still have stale int from prior tests — Daniel can `UPDATE skins_groups SET scorer_ids = '[]'::jsonb WHERE id = '1c04a53b...'` to fully reset.
4. **First action:** confirm Daniel's latest retest with a fresh phone number (not `5555555555`) on the PlayerGroupsSheet → Group 2 scorer path. If the row holds through the 30s refresh, the saveGroupNums fix is good and we move to known-issues cleanup.
5. **Second action (parallel, can be done after #1 passes):** patch `create_phone_invite` RPC to UPDATE on dedup hit (group_num + invitee_name + status='invited'), and patch iOS `reservePhoneInvite` callers to re-anchor the scorer slot to the returned id when it differs from the supplied UUID. Without this, any re-invite to a previously-used phone in the same group will silently revert state.
6. **Third action:** repro the "lost guest on QG create" bug.
7. **Final ship:** apply migrations 1-6 on prod, bump CURRENT_PROJECT_VERSION, archive, ASC.

---

## Last updated

2026-05-13 — late session, post `7211817`. Waiting on Daniel's retest with a fresh phone number to verify the saveGroupNums fix on a clean code path.
