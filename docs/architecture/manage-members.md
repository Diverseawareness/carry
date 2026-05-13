# Manage Members Sheet

**TL;DR:** Add Carry users (search → active row), invite by phone (`invited_phone`, status `'invited'`), remove via long-press confirm (hard DELETE). `onRefresh` callback handles SwiftUI `let allAvailable` state-propagation race (locked 2026-05-02). Dedup via partial unique index `group_members_unique_real_player`.

> **Scope reminder:** ManageMembersSheet is the ONLY member-management surface for Skins Groups. SG has no scorer concept in `.everyone` mode (v1 default), so there's no scorer-assignment UI here — just add Carry users via search, invite phones via SMS, remove via long-press. See [scorer-rules.md §"Foundational premise"](scorer-rules.md) for the Carry-only invariant that makes pending-phone-invites stay here (not on the tee sheet) until they accept.

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
| Inline TextField | [:248-264](../../Carry/Views/ManageMembersSheet.swift:248) |
| Send invite | [:711-820](../../Carry/Views/ManageMembersSheet.swift:711) `sendInvite()` builds Player with `isPendingInvite = true` + `inviteMemberId = UUID()` (mints stable row id client-side) |
| Server INSERT | [GroupService.swift:460-479](../../Carry/Services/GroupService.swift:460) `reservePhoneInvite(id:groupId:phone:invitedBy:groupNum:inviteeName:)` → RPC `create_phone_invite`. 1.0.9 switch (commit `d6a50f6`) — was `inviteMemberByPhone` which didn't persist `invitee_name` |
| Re-anchor on dedup | RPC may return a different id when `(group_id, invited_phone)` already exists. iOS patches `localGuests[idx].inviteMemberId = returnedId` at [:779-785](../../Carry/Views/ManageMembersSheet.swift:779). See [group-invitation-flow.md §"create_phone_invite RPC dedup behavior"](group-invitation-flow.md) |
| Typed name plumbing | `memberSearchText` (the search field) is captured at [:733](../../Carry/Views/ManageMembersSheet.swift:733) and passed to the RPC as `inviteeName`. Server persists to `invitee_name` column. Pending chip + tee row render the typed name instead of "Invited" / digits |
| Reconciliation | Forward (recipient adds phone) OR reverse (BEFORE INSERT trigger) — see [group-invitation-flow.md](group-invitation-flow.md) |

### Self-invite block

[ManageMembersSheet.swift:720-725](../../Carry/Views/ManageMembersSheet.swift:720) — typed digits checked against `authService.currentUser?.phone` (last-10-digit comparison). Toast + early return on match. Mirrors ScorerAssignmentView's existing guard. Without it, the reverse-reconcile trigger collapses the new row immediately into the inviter's profile → silent double-add.

### SMS body encoding

Same `?&=#`-stripped `urlQueryAllowed` pattern as the other two SMS-composer call sites at [:796-799](../../Carry/Views/ManageMembersSheet.swift:796). See [group-invitation-flow.md §"SMS body encoding"](group-invitation-flow.md) for the load-bearing rule.

## Remove member

| Step | Code |
|---|---|
| Long-press → request | [:553-561](../../Carry/Views/ManageMembersSheet.swift:553) `requestRemoval()` — accepts `profileId != nil` OR `inviteMemberId != nil`. Self-removal blocked at [:556-559](../../Carry/Views/ManageMembersSheet.swift:556) (toast: "use Leave/Delete Group") |
| Confirm alert | iOS-native confirm |
| Confirm action | [:569-605](../../Carry/Views/ManageMembersSheet.swift:569) `confirmRemoval()` + `inFlightRemovalTasks` |
| Server DELETE — confirmed Carry member | [GroupService.swift `removeMember`](../../Carry/Services/GroupService.swift) — **hard DELETE** by `(group_id, player_id)` |
| Server DELETE — pending phone-invite (1.0.9) | Direct delete by row id at [:585-589](../../Carry/Views/ManageMembersSheet.swift:585) — `(group_id, player_id)` would either miss (placeholder UUID) or hit the inviter's regular row, so use `eq("id", inviteMemberId)` |
| Local mutation | `locallyRemovedIds` updated immediately to suppress sheet UI; rolled back on server error |

Hard DELETE: `'removed'` status was historically used but leaked rows visible to members. DELETE removes `group_members` row entirely.

### Self-removal block (1.0.9, commit `1991f8d`)

Long-press on the logged-in user's own row toasts "You can't remove yourself — use Leave/Delete Group." and early-returns. Without this guard, a creator could long-press themselves and leave the group in a creator-less state. The Member-side "Leave Group" path (separate UI) is the canonical self-removal route.

## Pending section

[:443-507](../../Carry/Views/ManageMembersSheet.swift:443) — filter shows BOTH:

| Flag | Visual |
|---|---|
| `isPendingInvite = true` (SMS, no app) | phone icon at [:471-482](../../Carry/Views/ManageMembersSheet.swift:471) |
| `isPendingAccept = true` (Carry user, awaiting accept) | avatar at [:480-481](../../Carry/Views/ManageMembersSheet.swift:480) |

Both long-pressable for removal at [:500-502](../../Carry/Views/ManageMembersSheet.swift:500).

Chip label uses `pendingChipLabel(for:)` — prefers the typed `invitee_name` (carried via `Player.name` from `loadSingleGroup`), falls back to formatted phone for legacy pre-`invitee_name` rows or chips where the inviter didn't type a name. Truncated to 8 chars + ellipsis (commit `7c5c927`) to match scorecard truncation.

See [player-flags.md](player-flags.md).

## Search-result hide-already-added (1.0.9, commit `de2cde1`)

[ManageMembersSheet.swift:230-231](../../Carry/Views/ManageMembersSheet.swift:230) — Carry-user search results filtered against `Set(localAllAvailable.compactMap(\.profileId))`. Anyone already in the group (any status) is hidden from the result list entirely. They appear in All Members above; surfacing them as disabled rows below was clutter that confused users searching themselves.

The remaining `isAlreadyAdded` check at [:647-648](../../Carry/Views/ManageMembersSheet.swift:647) is defensive — handles the rare race where a member appears in `localAllAvailable` between filter compute and tap. If hit, the row renders with a state pill (`Added` / `Pending` / `Invited`) per [:653-658](../../Carry/Views/ManageMembersSheet.swift:653) and the tap is a no-op.

## Pending chip dedup rule (1.0.9, commit `198ad40`)

[ManageMembersSheet.swift:67-89](../../Carry/Views/ManageMembersSheet.swift:67) `localAllAvailable` computed property. Two collision cases when merging `localGuests` (sheet-local stubs) with `allAvailable` (server-loaded Players):

| Case | Local id | Server id | Match key |
|---|---|---|---|
| SMS invite | `nextGuestID` (small int) + `inviteMemberId` set | `Player.stableId(inviteMemberId)` (huge int) — different from local | `inviteMemberId` UUID |
| Search-added Carry user | `Player.stableId(profile.id)` | Same — `Player.stableId(profile.id)` | `Player.id` (set-union dedups naturally) |

Without the inviteMemberId match, the SMS-invite case rendered double pending chips (one from localGuests, one from allAvailable) until force-quit. The dedup keeps the local stub visible until the server version arrives, then drops it.

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
| Removing self | Blocked at [:556-559](../../Carry/Views/ManageMembersSheet.swift:556) (1.0.9). Member-side "Leave Group" uses different path |
| Self-SMS-invite | Blocked at [:720-725](../../Carry/Views/ManageMembersSheet.swift:720) (1.0.9). Without it, reverse-reconcile collapses the row into the inviter's own profile → silent double-add |
| Phone invite that becomes Carry user later | Handled by forward-direction trigger. Don't manual-flip `status` from client |
| `isPendingInvite` AND `isPendingAccept` both true | Should not happen. SMS-invite has no profileId; search-add has profileId. Both true → server promotion partial. Investigate via [push-trigger-chain.md](push-trigger-chain.md) |
| Double pending chip after re-invite to same phone | Pre-1.0.9. Server's `create_phone_invite` RPC dedup'd to existing row id but iOS local stub kept the freshly-minted UUID → `localAllAvailable` saw two distinct invites. Fixed by inviteMemberId-based dedup ([:67-89](../../Carry/Views/ManageMembersSheet.swift:67), commit `198ad40`) + RPC-returned-id re-anchor ([:779-785](../../Carry/Views/ManageMembersSheet.swift:779), commit `aa4da69`) |

## Last verified

2026-05-13 — patched for 1.0.9 commits: switched SMS path from `inviteMemberByPhone` to `reservePhoneInvite` with typed `invitee_name`, long-press delete handles phone-invite rows by id, self-invite + self-removal blocks, search hides already-added members, pending chip dedup-by-inviteMemberId. SwiftUI race + toast baselines unchanged.
