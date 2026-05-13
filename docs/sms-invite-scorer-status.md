# SMS-Invite-as-Scorer — Status Checkpoint

**Branch:** `hotfix/1.0.9` @ `7d7a041`
**Captured:** 2026-05-13 (very late session, mid SG verification + UX polish)
**Goal:** Ship the SMS-invite-as-scorer reconciliation fix as part of 1.0.9, with parity between Quick Games and Skins Groups.

---

## Where we are right now

- **All the SMS-invite plumbing is in.** Forward + reverse triggers, `player_stable_id` int path, `create_phone_invite` RPC, `inviteMemberId` threading through `ScorerSlot`/`Player`/`PlayerSlot`, X-clear + swipe-delete, self-invite block, auto-scroll above keyboard (with results + SMS section re-reveal on layout grow).
- **QG re-invite path** VERIFIED end-to-end post `7211817`.
- **SG SMS-invite-as-scorer parity** landed in `bdeca98` + filter relax `8a45db3`. Initial testing surfaced 6+ UX issues that have all been patched (chips, search pills, game card sort, time picker, etc.) — but the underlying "send invite, wait 60s, row holds in correct group" hasn't been clean-room verified yet on a fresh group.
- **Two pre-existing bugs** surfaced in testing that we deferred:
  - `preservedGuests` resurrects removed guests across devices (logic at GroupManagerView L939-944 doesn't cross-check `guest_roster_json`).
  - `create_phone_invite` RPC dedup doesn't UPDATE on hit → stale state survives a re-invite with the same phone.

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
| `779ec20` | Scorecard player labels cap at 8 chars + `…` |
| `867faaf` | Carry-only footnote on SG leaderboard sheet |
| `8a45db3` | SG `refreshGroupData` filter relax — lets pending-invite scorers through when assigned (rest of Carry-only invariant preserved) |
| `bdeca98` | **SG scorer picker upgrade** — `scorerPickerSheet` now uses `ScorerAssignmentView` so SG creator has parity with QG (search Carry users globally + SMS invite, with X-clear and self-invite block). Missing-scorer banner for SG re-routes to this picker (was sending users to ManageMembersSheet which had no scorer UI). |
| `12661ac` | ManageMembersSheet pending-chip prefers typed name over "(333) 333-..." truncated phone |
| `0143f0b` | ManageMembersSheet search-result pill reflects actual member state (Pending / Invited / Added) instead of always "Pending" |
| `de2cde1` | ManageMembersSheet hides already-added members from search results entirely (clutter — they're in All Members above) |
| `7c5c927` | Pending chip caps at 8 chars + ellipsis to match scorecard truncation rule |
| `9cf8957` | Game cards (Home + Games tab) push pending members to the END of the player pill list — preserves leader-first sort for confirmed players |
| `dedb90c` | TeeTimePickerSheet wheel frame bumped 120→180pt — time columns were getting clipped, only date column was interactable |
| `7d7a041` | ScorerAssignmentView re-fires the scroll signal when search results / SMS section appear → both stay above keyboard as user types |

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

## QG re-invite path — VERIFIED (post `7211817`)

Daniel ran the test with a fresh phone (`5550001234`) on PlayerGroupsSheet's Group 2 scorer slot. Row held through the 30s refresh tick. Then X-cleared + re-invited a different number — also held. RPC dedup case wasn't triggered (swipe-delete cleaned the prior row first), so the underlying create_phone_invite-doesn't-update-on-dedup bug is still unfixed but didn't surface in this test.

## SG SMS-invite-as-scorer parity — PARTIALLY VERIFIED + UX POLISHED

Initial wiring landed in `bdeca98`. Daniel started testing it. During the test pass we surfaced + fixed multiple UX issues:

- **Tee row roster mismatch across devices** — Daniel's Daniel-device showed phantom members (Fgggg1111, Ggggg222) that the creator had removed. Root cause is the `preservedGuests` logic at `GroupManagerView.refreshGroupData` L939-944 — it resurrects local guests that aren't in the server snapshot, but doesn't cross-check against `guest_roster_json`. Worked around for the test by SQL-marking the phantoms `status='removed'` + clearing `guest_roster_json`. Not patched in code — flagged below as a follow-up.
- **Time picker not updating** — SG `TeeTimePickerSheet` wheel was clipped at 120pt; only the date column was visible. Fixed in `dedb90c` (180pt).
- **Pending chip showing truncated phone** — fixed in `12661ac` + `7c5c927` (typed name, 8-char + ellipsis).
- **Self in search-result still showed "Pending"** — fixed in `0143f0b` (real state) + `de2cde1` (filtered out entirely).
- **Game card sort interleaved pending with confirmed** — fixed in `9cf8957` (pending at end).
- **Search results / SMS section dropping behind keyboard** — fixed in `7d7a041` (re-fire scroll on layout grow).

**Still UNVERIFIED end-to-end on a clean group:** the original "SMS invite a scorer on SG, wait 60s, row holds in correct group" test hasn't been clean-run from scratch since all the above bugs landed. Recommend Daniel:
1. Delete the polluted test group
2. Create a fresh SG with himself + Ziggy
3. From the tee sheet, tap the "Tee time needs scorer" banner OR tap a Scorer pill to open `scorerPickerSheet`
4. Send SMS invite to a fake phone with a typed name
5. Wait 60s → row stays in the correct group with name + formatted phone

---

## Known issues / follow-ups

| Issue | Notes |
|---|---|
| **`create_phone_invite` RPC dedup needs to UPDATE on hit** | When a row exists for (group_id, invited_phone), the RPC returns the existing id without updating `group_num` / `invitee_name` / `status`. Stale state from prior bugs sticks. **Fix:** UPDATE the existing row with the new values + reset status to 'invited'. iOS also needs to re-anchor its slot to the returned id when it differs from the locally-minted UUID. **Required for robust re-invite UX.** |
| **`preservedGuests` resurrects removed guests across devices** | `GroupManagerView.refreshGroupData` L939-944 preserves any local guest not in the server's freshGroup.members. Intent: protect guests during the brief window after Cancel Round when round_players is empty. Side effect: when the creator removes a guest on Device A, Device B's local allMembers still has them → preservedGuests resurrects them on next refresh. **Fix:** check guest membership against server's `guest_roster_json` before preserving — only preserve if present in the server snapshot OR the snapshot is null/empty (transient gap). Requires careful testing because this filter sits on a load-bearing path. |
| **Roster filter is per-device, not synced** | `selectedIDs` (the "playing today" filter) lives in UserDefaults per-device. Creator-side adjustments don't propagate to other members. A separate spec'd feature (cross-device "playing today" sync), not in scope for 1.0.9. |
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
2. `git log --oneline hotfix/1.0.7..hotfix/1.0.9` — should show ~50 commits ending at `7d7a041`.
3. **Current state of the server-side test data on dev:**
   - QG id: `1c04a53b-f357-4f67-b226-e2c612a5b669` is heavily polluted from today's testing. Recommend Daniel start fresh — delete this group and create a new SG with himself + Ziggy for clean verification.
   - Earlier in the session: phantom members `6183cd4c` (Fgggg1111) and `69ecfc7e` (Ggggg222) were SQL-marked `status='removed'` + `guest_roster_json` set NULL on the group. They may still appear cached in iOS @State on either device until a force-quit + relaunch.
4. **First action:** clean-room SG SMS-invite-as-scorer test on a fresh group. See "SG SMS-invite-as-scorer parity" section above for repro steps. If the row holds through 60s + reads in the assigned group, SG parity is fully verified.
5. **Second action (parallel):** patch `create_phone_invite` RPC to UPDATE on dedup hit + iOS `reservePhoneInvite` callers to re-anchor the scorer slot to the returned id. Without this, re-invite to a previously-used phone in the same group silently reverts state.
6. **Third action:** patch `preservedGuests` filter in `GroupManagerView.refreshGroupData` to cross-check `guest_roster_json` (see Known issues table). Without this, guests removed by the creator on Device A keep reappearing on Device B.
7. **Fourth action:** repro the "lost guest on QG create" bug.
7. **Final ship:** apply migrations 1-6 on prod, bump CURRENT_PROJECT_VERSION, archive, ASC.

---

## Last updated

2026-05-13 — very late session, post `7d7a041`. QG re-invite path verified. SG parity insert landed. Test group on dev is too polluted for clean verification; recommend Daniel start with a fresh SG. Two pre-existing bugs (preservedGuests + RPC dedup) flagged for follow-up; not blocking ship if known issues are acceptable.
