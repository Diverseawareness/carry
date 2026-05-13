# SMS-Invite-as-Scorer — Status Checkpoint

**Branch:** `hotfix/1.0.9` @ `cc2a6c6`
**Captured:** 2026-05-13 (end of session — E2E verified + SG parity reverted + UX polish landed)
**Goal:** Ship 1.0.9 with QG SMS-invite-as-scorer fully working. SG SMS-invite-as-scorer **deferred** — reverted to "SMS invitees stay in ManageMembersSheet's Pending section until they accept and reconcile."

---

## Where we are right now

- **QG SMS-invite-as-scorer fully working.** End-to-end test verified tonight (Daniel ran it): SMS invite link clickthrough → auto-join → scorer slot reconciles. All three triggers fired + push arrived + auto-add worked.
- **SG SMS-invite-as-scorer reverted.** The `bdeca98` (scorerPickerSheet upgrade) + `8a45db3` (refresh filter relax) commits shipped but were the wrong scope. SG has no designated scorers in `.everyone` mode (the only v1 mode), so the upgrade didn't fit the model. Reverted in `af0a84d` + `8e4ce5e`. SG SMS invites now stay in ManageMembersSheet's Pending section until they accept and reconcile.
- **Two follow-up patches landed this session:**
  - `create_phone_invite` RPC dedup now UPDATEs the existing row (group_num + invitee_name + re-arm status='invited'). iOS callers re-anchor on the returned id. ✅ shipped (commit `aa4da69` + migration `20260513000006`).
  - `preservedGuests` filter cross-checks server `guest_roster_json` so a creator removing a guest on Device A propagates to Device B. ✅ shipped (commit `386b6d0`).
- **Drag-to-create-new-tee-group safety reset.** Cancelled drag (user lifts outside any target) no longer leaves the "+ Add Tee Group" zone visible at idle. 3s Task auto-clears `dragPlayer`/`dragSourceGroup`. ✅ shipped (commit `cc2a6c6`).
- **Clipboard-detection invite paths removed.** 162 lines deleted (HomeView clipboard check + alert + 2 AppRouter flags + 2 DebugMenuView rows + DEBUG sheet). ProfileSheetView's manual "Find an Invite" entry kept as a safety net for pre-1.0.3 users without phone on profile. ✅ shipped (commit `42b2e99`).

## Full commit chain since `31d220b`

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
| `7211817` | `saveGroupNums` switched to SELECT-then-UPDATE-by-id (PostgREST `.or` empty-value term wasn't being respected → was clobbering phone-invite row group_num) |
| `779ec20` | Scorecard player labels cap at 8 chars + `…` |
| `867faaf` | Carry-only footnote on SG leaderboard sheet |
| `8a45db3` | SG `refreshGroupData` filter relax — **REVERTED in `8e4ce5e`** |
| `bdeca98` | SG scorer picker upgrade with ScorerAssignmentView — **REVERTED in `af0a84d`** |
| `12661ac` | ManageMembersSheet pending-chip prefers typed name over "(333) 333-..." truncated phone |
| `0143f0b` | ManageMembersSheet search-result pill reflects actual member state (Pending / Invited / Added) instead of always "Pending" |
| `de2cde1` | ManageMembersSheet hides already-added members from search results entirely |
| `7c5c927` | Pending chip caps at 8 chars + ellipsis to match scorecard truncation rule |
| `9cf8957` | Game cards (Home + Games tab) push pending members to the END of the player pill list |
| `dedb90c` | TeeTimePickerSheet wheel frame bumped 120→180pt — time columns were getting clipped |
| `7d7a041` | ScorerAssignmentView re-fires the scroll signal when search results / SMS section appear |
| `6b3dcf5` | Drag-to-create-new-tee-group dotted zone below existing groups |
| `de1ccd9` | Scorer-anchored guard + immediate saveScorerIds in AddTeeGroupDropDelegate |
| `6b92fe7` | Docs sync for SG SMS-invite-as-scorer + drag-to-create |
| `a381f80` | Docs: elevate scorerAnchored rule to load-bearing section |
| `af0a84d` | **REVERT** `bdeca98` (SG scorer picker upgrade) |
| `8e4ce5e` | **REVERT** `8a45db3` (SG refresh filter relax) |
| `8f4325f` | Docs cleanup post-revert |
| `5e29368` | Game Options time change writes `teeTimes[0]` + shifts staggered groups |
| `d6a50f6` | ManageMembersSheet.sendInvite uses typed name + reservePhoneInvite |
| `5335853` | SMS body encoding fix in ManageMembersSheet (strip `?&=#` from urlQueryAllowed) |
| `24a30b4` | Long-press deletes pending phone invites by inviteMemberId |
| `593cce8` | SMS body encoding fix in ScorerAssignmentView + GroupsListView |
| `dbedae4` | ManageMembersSheet blocks self-SMS-invite |
| `c2387a8` | Docs: SMS body encoding + self-invite block |
| `1991f8d` | ManageMembersSheet blocks long-press self-removal |
| `198ad40` | ManageMembersSheet pending-chip dedup (local stub vs server) by inviteMemberId |
| `386b6d0` | preservedGuests cross-checks server guest_roster_json |
| `aa4da69` + migration `20260513000006` | `create_phone_invite` RPC updates on dedup hit + iOS re-anchors |
| `42b2e99` | Remove pre-phone-on-profile clipboard invite paths (162 lines) |
| `cc2a6c6` | `.onDrag` 3s safety reset for cancelled drags |

---

## Verified end-to-end

| Path | Status |
|---|---|
| Forward + reverse reconciliation triggers fire correctly | ✅ |
| iOS `Player.stableId` matches SQL `player_stable_id` for known UUIDs | ✅ |
| Pre-reconciliation orange-dimmed scorer slot visibility (QG) | ✅ |
| `"Waiting for Scorer to Join"` button state on pending scorer | ✅ |
| X-clear on pending invite removes the server row | ✅ |
| Swipe-delete on phone-invite tee row removes server row + local | ✅ |
| Typed name + formatted phone render in tee row on first invite | ✅ |
| Block self-SMS-invite with toast (QuickStartSheet + ManageMembersSheet) | ✅ |
| QuickStartSheet + PlayerGroupsSheet scorer slot auto-scrolls above keyboard | ✅ |
| **QG re-invite path** (re-invite to same phone in same group) | ✅ post `7211817` |
| **End-to-end test: SMS invite link clickthrough + auto-join + scorer reconcile** | ✅ Daniel ran tonight — all three triggers fired + push arrived + auto-add worked |
| **`create_phone_invite` RPC dedup UPDATE** | ✅ shipped `aa4da69` + migration `20260513000006` |
| **`preservedGuests` cross-checks `guest_roster_json`** | ✅ shipped `386b6d0` |
| Long-press delete on pending phone-invite chip in ManageMembersSheet | ✅ shipped `24a30b4` |
| Self-removal block in ManageMembersSheet | ✅ shipped `1991f8d` |
| Pending chip dedup (local stub vs server) | ✅ shipped `198ad40` |

## SG SMS-invite-as-scorer — REVERTED (deferred to 1.0.10+)

The SG-side parity feature shipped briefly in `bdeca98` + `8a45db3` and was reverted in `af0a84d` + `8e4ce5e`. Reason: SG has no designated scorers in `.everyone` mode (the only v1 mode). Picker upgrade + filter relax were wrong scope.

Current behavior: SG SMS invites stay in ManageMembersSheet's Pending section until they accept and reconcile. The Pending section gets the new UX polish (typed name on chip, dedup, long-press delete, 8-char truncation, push to end on game cards) but no scorer slot integration.

**If SG single-scorer mode ever returns** (the dormant `.single`-mode toggle at GroupManagerView L5385 is gated `if false` — explicitly kept warm for a future rollback to single-scorer SG), this parity work would need to be redone. The reverted commits are referenced in the architecture docs as a known-design-rejected path so future contributors don't accidentally re-implement.

---

## Known issues / follow-ups

| Issue | Status | Notes |
|---|---|---|
| **`create_phone_invite` RPC dedup needs to UPDATE on hit** | ✅ shipped | `aa4da69` + migration `20260513000006`. iOS re-anchors on returned id when it differs from supplied id |
| **`preservedGuests` cross-check `guest_roster_json`** | ✅ shipped | `386b6d0`. Cross-device guest removal now propagates |
| **Roster filter is per-device, not synced** | Out of scope | `selectedIDs` lives in UserDefaults per-device. Separate spec'd feature (cross-device "playing today" sync), not 1.0.9 |
| **Lost guest player on QG creation** | Unresolved, deferred | Daniel reported a guest in Group 2 disappeared on create. Not yet diagnosed. Repro: create a fresh QG with a guest in Group 2 — does the guest survive the creation round-trip? Flagged 2026-05-13. |
| **Group 2 scorer auto-scroll on Ziggy's older device** | Untested | After `322d0fb` (350ms delay) Daniel didn't re-verify on the smaller screen |
| Debug prints in code | Acceptable | `[QuickStart.createQuickGame] SMS slot`, `[reservePhoneInvite] RPC...`, `[PlayerGroupsSheet] saveAndDismiss` — all in DEBUG blocks. Strip in a follow-up sweep |

---

## Migrations to apply on prod when 1.0.9 ships

In order (7 total):
1. `20260513000000_scorer_ids_uuid_format.sql` (vestigial but harmless)
2. `20260513000001_reconcile_extends_scorer_ids.sql` (vestigial — superseded by next two)
3. `20260513000002_player_stable_id_sql.sql` (active)
4. `20260513000003_reconcile_scorer_ids_int_path.sql` (active)
5. `20260513000004_create_phone_invite_rpc.sql` (active)
6. `20260513000005_add_invitee_name_to_group_members.sql` (active — adds `invitee_name` column + extends RPC sig)
7. **`20260513000006_create_phone_invite_update_on_dedup.sql`** (active — UPDATE on dedup hit + re-arm status='invited')

Apply via Supabase Studio SQL Editor on prod (`seeitehizboxjbnccnyd`). Dev branch already has all of these.

---

## Resume instructions for new session

1. **Read this file end-to-end** + skim `MEMORY.md` "Active investigation" section for context.
2. `git log --oneline hotfix/1.0.7..hotfix/1.0.9` — should show ~60 commits ending at `cc2a6c6`.
3. **First action:** apply migration `20260513000006` on prod (Supabase Studio SQL Editor on `seeitehizboxjbnccnyd`). The other 6 should already be there from earlier in the session.
4. **Second action:** repro the "lost guest on QG create" bug. See "Known issues" table.
5. **Third action:** bump CURRENT_PROJECT_VERSION, archive, upload to App Store Connect, fill out ASC release notes.
6. **Out of scope for 1.0.9:** SG SMS-invite-as-scorer (reverted), cross-device "playing today" sync, the "+ Add Tee Group" affordance for SG with <5 players (deferred 2026-05-10 spec — but partial fix landed via `6b3dcf5`).

---

## Last updated

2026-05-13 — end of session, post `cc2a6c6`. QG SMS-invite-as-scorer E2E verified. SG SMS-invite-as-scorer reverted (deferred to 1.0.10+). `create_phone_invite` RPC dedup-UPDATE shipped. `preservedGuests` cross-check shipped. Clipboard-detection paths removed. Drag safety-reset shipped. Game Options time change now propagates to `teeTimes[0]`. Architecture docs (group-invitation-flow.md, manage-members.md, refresh-race-guards.md, tee-time-sovereignty.md, game-types.md, scorer-rules.md) synced with current code state.
