# Manage Members Sheet

**TL;DR:** Add Carry users (search → active row), invite by phone (`invited_phone`, status `'invited'`), remove via long-press confirm (hard DELETE). `onRefresh` callback handles SwiftUI `let allAvailable` state-propagation race (locked 2026-05-02). Dedup via partial unique index `group_members_unique_real_player`.

## Sheet entry point

| Item | Where |
|---|---|
| Sheet definition | [ManageMembersSheet.swift:5-708](../../Carry/Views/ManageMembersSheet.swift:5) |
| Invocation | [GroupManagerView.swift:322-343](../../Carry/Views/GroupManagerView.swift:322) — instantiation with `onDone` callback |
| Result type | `ManageMembersResult { selectedIDs, newGuests, nextGuestID, removedPlayerIds }` |

## Add member — Carry user (search)

| Step | Code |
|---|---|
| Debounced search | [:554-587](../../Carry/Views/ManageMembersSheet.swift:554) `debounceOnlineSearch()` → `PlayerSearchService.shared.searchPlayers()` + offline fallback |
| Result row tap | [:589-639](../../Carry/Views/ManageMembersSheet.swift:589) `onlineSearchResultRow()` appends Player to `localGuests` with `isPendingInvite = false` (auto-accept) |
| Already-added filter | [:590](../../Carry/Views/ManageMembersSheet.swift:590) — checks `localAllAvailable` for existing profileId |
| Sync to server | After Done: [GroupManagerView.swift:359](../../Carry/Views/GroupManagerView.swift:359) `inviteMember(status: "active")` |

Auto-accept rule (locked 2026-05-01): Carry users via search go directly to `status = 'active'`. See [group-invitation-flow.md](group-invitation-flow.md).

## Add member — phone (SMS)

| Step | Code |
|---|---|
| Inline TextField | [:221-254](../../Carry/Views/ManageMembersSheet.swift:221) |
| Send invite | [:643-690](../../Carry/Views/ManageMembersSheet.swift:643) `sendInvite()` builds Player with `isPendingInvite = true` |
| Server INSERT | [GroupService.swift:415-435](../../Carry/Services/GroupService.swift:415) `inviteMemberByPhone()` — writes `group_members` with `invited_phone = <digits>`, `player_id = inviter UUID placeholder`, `status = 'invited'` |
| Reconciliation | Forward (recipient adds phone) OR reverse (BEFORE INSERT trigger) — see [group-invitation-flow.md](group-invitation-flow.md) |

## Remove member

| Step | Code |
|---|---|
| Long-press → request | [:512-516](../../Carry/Views/ManageMembersSheet.swift:512) `requestRemoval()` (guards `profileId != nil`) |
| Confirm alert | [:490-502](../../Carry/Views/ManageMembersSheet.swift:490) |
| Confirm action | [:524-548](../../Carry/Views/ManageMembersSheet.swift:524) `confirmRemoval()` + `inFlightRemovalTasks` |
| Server DELETE | [GroupService.swift:653-672](../../Carry/Services/GroupService.swift:653) — **hard DELETE**, not soft `'removed'` |
| Local mutation | `locallyRemovedIds` updated immediately to suppress sheet UI |

Hard DELETE: `'removed'` status was historically used but leaked rows visible to members. DELETE removes `group_members` row entirely.

## Pending section

[:416](../../Carry/Views/ManageMembersSheet.swift:416) — filter shows BOTH:

| Flag | Visual |
|---|---|
| `isPendingInvite = true` (SMS, no app) | phone icon at [:444-451](../../Carry/Views/ManageMembersSheet.swift:444) |
| `isPendingAccept = true` (Carry user, awaiting accept) | at [:454](../../Carry/Views/ManageMembersSheet.swift:454) |

Both long-pressable for removal at [:466-468](../../Carry/Views/ManageMembersSheet.swift:466).

See [player-flags.md](player-flags.md).

## SwiftUI state-propagation race (locked 2026-05-02)

| Problem | Sheet receives `let allAvailable: [Player]` as snapshot at present-time. Parent roster changes during presentation (push refresh, etc.) don't propagate to sheet |
| Solution | [:17](../../Carry/Views/ManageMembersSheet.swift:17) `onRefresh: (() async -> Void)?` callback. Fires on sheet open ([:485-487](../../Carry/Views/ManageMembersSheet.swift:485) `.task`) AND on pull-to-refresh ([:482-484](../../Carry/Views/ManageMembersSheet.swift:482)). Callback re-runs parent's load, re-presents sheet with fresh data via SwiftUI identity-based re-render |
| Doc | Comment at [:10-16](../../Carry/Views/ManageMembersSheet.swift:10) |

## Atomicity

### Add (Carry user)

| # | Action |
|---|---|
| 1 | User selects → appended to `localGuests` (sheet local state) |
| 2 | Done → `onDone(ManageMembersResult)` fires |
| 3 | Parent: `inviteMember(status: "active")` per new guest at [GroupManagerView.swift:359](../../Carry/Views/GroupManagerView.swift:359) |
| 4 | Each INSERT fires `notify_push()` trigger → push to invited user (`memberAdded`) |

### Add (phone)

| # | Action |
|---|---|
| 1 | User types phone + sends → INSERT via `inviteMemberByPhone` |
| 2 | If reverse-direction trigger fires (phone already on profile) → INSERT promoted to `active` mid-trigger → push fires |
| 3 | Else: `'invited'` row sits, awaits forward-direction reconciliation |

### Remove

| # | Action |
|---|---|
| 1 | Long-press → confirm → DELETE |
| 2 | `inFlightRemovalTasks` accumulates; Done awaits all before returning ([:117-118](../../Carry/Views/ManageMembersSheet.swift:117)) |
| 3 | No push fired (DELETE has no Postgres trigger) |

## Dedup

Server-side partial unique index ([db-schema-rules.md](db-schema-rules.md)):
```sql
group_members_unique_real_player UNIQUE (group_id, player_id)
WHERE invited_phone IS NULL OR invited_phone = ''
```

Blocks duplicate (group, real-player) rows. Allows multiple phone-invite rows for same recipient (legitimate: different channels before reconciliation).

Client-side:
| Check | Where |
|---|---|
| Search results filtered by `isAlreadyAdded` | [:590](../../Carry/Views/ManageMembersSheet.swift:590) |
| Phone invites checked for existing match | [GroupService.swift:417-423](../../Carry/Services/GroupService.swift:417) |

## Toast baselines

Cross-session "X joined — tap Manage to add to tee sheet" at [GroupManagerView.swift:1011-1037](../../Carry/Views/GroupManagerView.swift:1011) is gated by a per-group, per-device baseline stored in UserDefaults.

| Field | Value |
|---|---|
| Key | `seenActiveMemberPlayerIds_<groupId>` |
| Type | Set of `profileId` UUID strings (NOT `group_members.id`) |
| Update | Every `refreshGroupData` writes the current active-player set after computing the diff |
| First visit | Baseline is nil → no toast fires; baseline is established |
| Subsequent | Diff = currentPlayerIds − baseline → toast fires once per new playerId |

**Anchor on `playerId`, not row id.** `group_members` can have multiple active rows for the same person (phone-invite reconciliation keeps `invited_phone` set, sidestepping `group_members_unique_real_player`'s partial unique index). `dedupeMembers` collapses them client-side via dictionary `Array(.values)` — but iteration order is non-deterministic, so the chosen row's `id` swaps between refreshes → row-id baselines refire on every poll. See [bug-archive 2026-05-10 "X joined toast refires every refresh"](bug-archive.md).

**Transient-empty guard.** If `fetchGroupMembers` returns empty AND the saved baseline is non-empty, skip both diff and save — treat as a transient failure (network blip, RLS race, server hiccup). Members realistically can't go from N → 0 in normal use. Without this guard, the empty save would stomp the baseline and the next successful refresh would toast every existing member as if they just joined.

**Trade-off:** leave-and-rejoin on the same device no longer re-fires the toast (the playerId UUID is stable across a fresh `group_members` insert). Acceptable because (a) immediate "Members added!" action toast at [GroupManagerView.swift:370](../../Carry/Views/GroupManagerView.swift:370) covers the local-add case, (b) server push handles cross-device.

If the rejoin-fires-toast case ever becomes important, fix at the remove site: clear the player's UUID from the baseline. Don't switch back to row-id baselines.

## Common bugs / gotchas

| Bug | Notes |
|---|---|
| Optimistic-remove + immediate re-invite race | Sheet stays open after remove; immediate re-invite may not have propagated DELETE. `onRefresh` + `inFlightRemovalTasks.await` handle it |
| Removing self | Guard with `profileId != currentUserId` upstream of long-press. Member-side "Leave Group" uses different path |
| Phone invite that becomes Carry user later | Handled by forward-direction trigger. Don't manual-flip `status` from client |
| `isPendingInvite` AND `isPendingAccept` both true | Should not happen. SMS-invite has no profileId; search-add has profileId. Both true → server promotion partial. Investigate via [push-trigger-chain.md](push-trigger-chain.md) |

## Last verified

2026-05-10 — added "Toast baselines" section codifying the playerId-UUID rule for cross-session new-member toasts (see [bug-archive 2026-05-10 "X joined toast refires"](bug-archive.md)).
