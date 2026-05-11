# Player Flags — Decision Matrix

**TL;DR:** Four flags determine state: `profileId`, `isPendingInvite`, `isPendingAccept`, `isGuest`. Two derived predicates: `canScore` (scorer eligibility) + `isCarryUser` (UI rendering).

## Flags

[Player.swift:19-22](../../Carry/Models/Player.swift:19):

| Flag | Type | Meaning |
|---|---|---|
| `profileId` | `UUID?` | Server profile UUID. Nil = client-only placeholder |
| `isPendingInvite` | `Bool` | SMS-invited by phone, hasn't installed Carry |
| `isPendingAccept` | `Bool` | Added via Carry search, hasn't accepted invite |
| `isGuest` | `Bool` | Quick Game guest (`profiles.is_guest = true`). Always has `profileId` |

## Decision matrix

| profileId | isPendingInvite | isPendingAccept | isGuest | Meaning | UI | canScore |
|---|---|---|---|---|---|---|
| set | false | false | false | Confirmed Carry user | green avatar | ✓ |
| set | false | true | false | Search-added, awaiting accept | orange avatar | ✗ |
| set | false | false | true | Quick Game guest | colored 6-palette avatar | ✗ |
| nil | true | false | false | SMS-invited (placeholder until install) | orange avatar | ✗ |
| nil | false | false | false | **Invalid** — placeholder with no signal | — | — |
| set | true | * | * | **Invalid** — Carry user can't have pending SMS | — | — |
| nil | * | * | true | **Invalid** — guests always have profileId | — | — |
| nil | false | true | * | **Invalid** — pending-accept requires profileId | — | — |
| set | true | * | true | **Invalid** — guests don't get SMS-invited | — | — |

## `canScore` (strictest)

[Player.swift:83-85](../../Carry/Models/Player.swift:83):
```swift
var canScore: Bool {
    profileId != nil && !isGuest && !isPendingInvite && !isPendingAccept
}
```

True only for confirmed Carry users. Single source of truth for scorer eligibility — see [scorer-rules.md](scorer-rules.md).

## `isCarryUser` (looser, UI rendering)

[PlayerGroupsSheet.swift:469](../../Carry/Views/PlayerGroupsSheet.swift:469):
```swift
let isCarryUser = player.profileId != nil && !player.isPendingInvite && !player.isGuest
```

True for Carry users incl. pending-accept. Gates avatar+name vs guest TextField rendering.

Quick Game override at [:474-480](../../Carry/Views/PlayerGroupsSheet.swift:474):
```swift
if isQuickGame && isCarryUser && isPendingAccept {
    // render displayPlayer with isPendingAccept = false → green avatar
}
```

## Read sites per flag

| Flag | Read site | Purpose |
|---|---|---|
| `profileId` | `canScore`, `isCarryUser`, server-sync, scorer pickers | Identity check |
| `isPendingInvite` | `isCarryUser`, [GroupManagerView.swift:468](../../Carry/Views/GroupManagerView.swift:468) (scorer-pending advance), [ScorerAssignmentView.swift:121](../../Carry/Views/ScorerAssignmentView.swift:121) (invitedRow) | Phone-invite state |
| `isPendingAccept` | `canScore`, [GroupService.swift:1305-1335](../../Carry/Services/GroupService.swift:1305) (active filter), scorer pending advance | Search-add-not-accepted |
| `isGuest` | `canScore`, `isCarryUser`, slot rendering, all-time leaderboard filter | Ephemerality |

## Write sites per flag

| Flag | Write site |
|---|---|
| `profileId` | [Player.swift:97](../../Carry/Models/Player.swift:97) `Player(from: ProfileDTO)`, `ScorerSlot.asPlayer`, [QuickStartSheet.swift:1393](../../Carry/Views/QuickStartSheet.swift:1393) slot conversion |
| `isPendingInvite` | [QuickStartSheet.swift:1004](../../Carry/Views/QuickStartSheet.swift:1004) phone-invite slot, `loadSingleGroup` when `invited_phone != null` |
| `isPendingAccept` | [PlayerGroupsSheet.swift:845](../../Carry/Views/PlayerGroupsSheet.swift:845) — `(player.id != currentUserId)`, `loadSingleGroup` when `status='invited'`, ManageMembersSheet save flow |
| `isGuest` | `Player(from: ProfileDTO)` (from `profiles.is_guest`), [QuickStartSheet.swift:40](../../Carry/Views/QuickStartSheet.swift:40), [PlayerGroupsSheet.swift:1195, 1249](../../Carry/Views/PlayerGroupsSheet.swift:1195), `QuickGameGuestStorage.GuestSnapshot.asPlayer` (always true) |

## Server `group_members` mapping

| Server | Client |
|---|---|
| `status = 'active'` | `isPendingAccept = false` |
| `status = 'invited'` | `isPendingAccept = true` |
| `status = 'declined'` | filtered out of active |
| `status = 'removed'` | filtered out, triggers "Removed from group" alert |
| `invited_phone` non-null | `isPendingInvite = true`, `profileId = nil` |
| `profiles.is_guest = true` | `isGuest = true` |

`status` ↔ `isPendingAccept` translation in `loadSingleGroup`.

## Phone-invite reconciliation

| Step | Action |
|---|---|
| 1 | Creator types phone → `inviteMemberByPhone` creates `group_members` row with `invited_phone = phone, player_id = inviter UUID placeholder, status='invited'` |
| 2 | Recipient opens SMS deep link → app installs / opens |
| 3 | Client calls `claim_phone_invite(membership_id, phone)` RPC: sets `player_id = auth.uid(), invited_phone = '', status='active'` |
| 4 | Or: recipient adds phone to profile → `reconcile_phone_invites_for_profile()` trigger fires → same row update |

After: next client refresh sees `isPendingInvite = false`, real player. See [group-invitation-flow.md](group-invitation-flow.md).

## Quick Game vs Skins Group on member add

[PlayerGroupsSheet.swift:966](../../Carry/Views/PlayerGroupsSheet.swift:966):
```swift
isPendingAccept: isQuickGame ? false : true
```

| Type | New member's `isPendingAccept` |
|---|---|
| Quick Game | `false` (auto-active) |
| Skins Group | `true` (until they accept) |

## Usage heuristics

| Need | Use |
|---|---|
| Scorer eligibility | `canScore` |
| UI rendering (avatar vs TextField) | `isCarryUser` (+ Quick Game auto-active override) |
| Real Carry user with profile | `profileId != nil && !isGuest` |
| Active member count | `!isPendingAccept && !isPendingInvite` |
| Promote guest to scorer | Don't — `syncScorerIDs` wipes assignment to 0 |

## Common bugs / gotchas

| Bug | Cause | Fix |
|---|---|---|
| Ghost guests (2026-05-01) | `loadSingleGroup` synthesized wiped-guest UUIDs into current roster | Split `loadSingleGroup` (Carry-only) vs `buildHomeRound` (history-only with denormalized fallback). See [guest-lifecycle.md](guest-lifecycle.md) |
| QG pending-accept wedge | QG scorers get `isPendingAccept=true` on search-add; displayPlayer override hides visually but underlying flag persists. Downstream filters that don't check `isQuickGame` may misbehave | Most QG flows treat pending scorers as active |
| `isPendingAccept` vs `isPendingInvite` confusion | Look similar, mean different things | Phone, no Carry account = pending-invite. Carry account exists, not accepted to this group = pending-accept |

## Last verified

2026-05-10 — converted to machine-readable format.
