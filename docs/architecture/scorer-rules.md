# Scorer Rules

**TL;DR:** `scorerIDs[gi]: Int` is the per-group scorer marker (0 = unassigned). Creator is locked as scorer of their own group. `canScore` filters eligibility.

## 🔒 Foundational premise — every tee group must have a Carry-user scorer

Universal rule across game types: a tee group **cannot exist without a Carry-user scorer**. Guests, pending invites, and SMS invitees CANNOT be scorers — they don't have an app account, can't authenticate, can't write scores to Supabase.

| Game type | How the rule holds |
|---|---|
| Skins Group | Trivially satisfied — SGs are Carry-only by the Skins-Groups-Carry-only invariant (no guests possible in `group_members`). Every member is a Carry user, so any of them can be a scorer. |
| Quick Game | Enforced explicitly — guests CAN appear in QGs but never as scorers. `canSave` validation in [QuickStartSheet.swift:116](../../Carry/Views/QuickStartSheet.swift:116) blocks Create when any populated group's slot 0 has no `existingProfileId` and isn't a pending invite. |

Mid-round defenses (apply to both):

| Surface | Enforcement |
|---|---|
| Mid-round scorer reassignment | `syncScorerIDs` rule 4 — wipes permanent-guest scorer assignments to 0, surfacing the missing-scorer banner |
| `canScore` predicate | [Player.swift:83-85](../../Carry/Models/Player.swift:83) — single source of truth: `profileId != nil && !isGuest && !isPendingInvite && !isPendingAccept` |

This means downstream code can SAFELY ASSUME every populated tee group has a Carry user as scorer. Defensive backstops that "ensure a Carry user exists" (like the prior `prefillFromRecentGame` overwrite at QuickStartSheet:411-417) are unnecessary — `canSave` already blocks any state that violates the premise on the QG side, and SGs structurally cannot violate it.

## Eligibility predicate

[Player.swift:83-85](../../Carry/Models/Player.swift:83):
```swift
var canScore: Bool {
    profileId != nil && !isGuest && !isPendingInvite && !isPendingAccept
}
```

| Eligible | Ineligible |
|---|---|
| Confirmed Carry users (have profileId, not guest, accepted invite) | Guests, SMS-invitees pre-install, search-added users awaiting accept |

Single source of truth for scorer eligibility. See [player-flags.md](player-flags.md).

## Per-group scorer state

| Field | Where |
|---|---|
| Client `scorerIDs: [Int]` | [GroupManagerView.swift:60](../../Carry/Views/GroupManagerView.swift:60) — one Int per group, 0 = unassigned |
| Init value | [GroupManagerView.swift:214](../../Carry/Views/GroupManagerView.swift:214) — `safeGrouped.map { $0.first?.id ?? 0 }` |
| Server column | `skins_groups.scorer_ids` jsonb — [20260330000003](../../supabase/migrations/20260330000003_group_scorer_ids.sql) |
| Race guard | `scorerIdsLastSavedAt` — [GroupManagerView.swift:92](../../Carry/Views/GroupManagerView.swift:92). 8s window. See [refresh-race-guards.md](refresh-race-guards.md) §1 |

## `syncScorerIDs()` rules

[GroupManagerView.swift:422-493](../../Carry/Views/GroupManagerView.swift:422). Six rules in order:

| # | Rule | Lines |
|---|---|---|
| 1 | Expand to match group count — append default scorer (first canScore in new group, or 0) | [:422-430](../../Carry/Views/GroupManagerView.swift:422) |
| 2 | Trim to group count — when groups shrink, remove tail entries | [:431-433](../../Carry/Views/GroupManagerView.swift:431) |
| 3 | Wipe if scorer no longer in group — set to 0 (missing-scorer banner prompts reassign) | [:455-461](../../Carry/Views/GroupManagerView.swift:455) |
| 4 | Wipe permanent guests — guests can't score, set to 0. Pending-invite guests preserved | [:462-467](../../Carry/Views/GroupManagerView.swift:462) |
| 5 | Skins Group only: advance past pending scorer to next confirmed Carry user. Quick Games allow pending (assignment IS the playing-today signal) | [:468-476](../../Carry/Views/GroupManagerView.swift:468) |
| 6 | **Creator-locked invariant** — for every group containing the creator, `scorerIDs[i] = creatorId`. Applied LAST so it overrides earlier wipes. Uses `creatorId`, not `currentUserId` | [:478-492](../../Carry/Views/GroupManagerView.swift:478) |

## `PlayerGroupsSheet.scorerSlotBinding` setter

[PlayerGroupsSheet.swift:816-893](../../Carry/Views/PlayerGroupsSheet.swift:816). Branches:

| Branch | Lines | Action |
|---|---|---|
| Creator-in-group guard | [:827-833](../../Carry/Views/PlayerGroupsSheet.swift:827) | Early return — lock icon, not editable. Uses `creatorId` (2026-05-09 fix) |
| Profile picked | [:839-881](../../Carry/Views/PlayerGroupsSheet.swift:839) | Build from `ScorerSlot.asPlayer`. Set `isPendingAccept = (player.id != currentUserId)`. Remove from any other group. Drop within-group non-scorer copy. Append + `scorerIDs[groupIndex] = player.id` |
| Pending invite | [:882-885](../../Carry/Views/PlayerGroupsSheet.swift:882) | SMS invite created. Append + assign as scorer |
| Empty state | [:886-889](../../Carry/Views/PlayerGroupsSheet.swift:886) | `scorerIDs[groupIndex] = 0`. Player demotes to non-scorer slot, not removed |

## `PlayerGroupsSheet.syncScorerIDs` (local)

[PlayerGroupsSheet.swift:1137-1155](../../Carry/Views/PlayerGroupsSheet.swift:1137). Lighter than GroupManagerView version: expand/trim + creator-lock only. No defensive wipes.

## Score Keeper UI

[PlayerGroupsSheet.swift:417-427](../../Carry/Views/PlayerGroupsSheet.swift:417):

| State | Trigger | UI |
|---|---|---|
| `readOnly = true` | `groups[groupIndex].contains { $0.id == creatorId }` ([:424](../../Carry/Views/PlayerGroupsSheet.swift:424)) | Lock icon, no X button |
| `readOnly = false` | Otherwise | X button to clear, search field to assign |

X button behavior: clears scorer slot, demotes player to non-scorer slot in same group. Does NOT remove player from group.

## `scoringMode`

| Mode | Default for | Behavior |
|---|---|---|
| `.single` | Quick Game | One scorer per group. ScorecardView tap-gate at [:724](../../Carry/Views/ScorecardView.swift:724) blocks non-scorers |
| `.everyone` | Skins Group | All players score in parallel. No tap-gate |

Stored at `RoundConfig.scoringMode` ([RoundConfig.swift:50](../../Carry/Models/RoundConfig.swift:50)).

## Scorer anchoring (drag rules)

[GroupManagerView.swift:3284](../../Carry/Views/GroupManagerView.swift:3284) computes `scorerAnchored` per `GroupDropDelegate`:
```swift
scorerAnchored: isQuickGame || scoringMode != .everyone
```

| Game type | scoringMode | scorerAnchored | Drag a scorer? |
|---|---|---|---|
| Quick Game | `.single` (default) | true | **Blocked** — toast: "Scorers are anchored — change scorers in Manage Members." |
| Skins Group v1 | `.everyone` (default) | false | Allowed — every player is interchangeable |
| Skins Group legacy `.single` | `.single` | true | Blocked, same as QG |

[GroupDropDelegate.performDrop:5328-5334](../../Carry/Views/GroupManagerView.swift:5328):
```swift
if scorerAnchored,
   sourceGroup < scorerIDs.count,
   scorerIDs[sourceGroup] == player.id {
    ToastManager.shared.error("Scorers are anchored — change scorers in Manage Members.")
    return false
}
```

**Implication:** when scorer-anchoring is on, the only way to move a scorer to a different group is via `PlayerGroupsSheet` (the Manage Members sheet for QGs). The picker's setter handles the slot reassignment + creator-lock invariant + sync. See `PlayerGroupsSheet.scorerSlotBinding` rules above.

**Why anchoring exists in QG:** in single-scorer mode, the scorer is structurally meaningful — they're the designated keeper for that group. Dragging them elsewhere mid-setup would orphan the group's scorer slot. Forcing the explicit picker path keeps the user in the right mental model.

**Why SG v1 does NOT anchor:** everyone-scores mode means every player has equal scoring authority. No slot to anchor.

## Full-group drop behavior

[GroupDropDelegate.performDrop:5345-5352](../../Carry/Views/GroupManagerView.swift:5345) — when target group is full (`playerCount >= maxGroupSize`):

| Mode | Behavior |
|---|---|
| Scorer-anchored (QG, single-scorer SG) | Open swap picker — user explicitly chooses who to bump out. Picker filters the anchored scorer from the swap-out list |
| Everyone-scores (default SG v1) | Reject drop with toast (no swap UI) — every player is equal so the swap UX adds confusion |

## Swap picker sheet

UI that lets the user choose who to bump out when dropping into a full scorer-anchored group.

### State

| `@State` field | Type | Purpose |
|---|---|---|
| `showSwapPicker` | `Bool` | Sheet presentation flag |
| `pendingSwapPlayer` | `Player?` | The dragged player coming IN |
| `pendingSwapFrom` | `Int?` | Source group index (where dragged player came from) |
| `pendingSwapTo` | `Int?` | Destination full group index |

Declared at [GroupManagerView.swift:56-59](../../Carry/Views/GroupManagerView.swift:56). Reset to nil after sheet action or dismiss.

### Trigger

[GroupDropDelegate.performDrop:5345-5352](../../Carry/Views/GroupManagerView.swift:5345):
```swift
if playerCount >= maxGroupSize {
    pendingSwapPlayer = player       // dragged player
    pendingSwapFrom = sourceGroup
    pendingSwapTo = groupIndex       // full target
    showSwapPicker = true
    resetDrag()
    return true
}
```

### Sheet body

[GroupManagerView.swift:2808-2899](../../Carry/Views/GroupManagerView.swift:2808) `swapPickerSheet`:

| Element | Notes |
|---|---|
| Header | "Swap Player" + body text "Group X is full. Pick a player to swap with \<player.shortName\>" |
| Candidates list | `groups[destIdx]` filtered by scorer-anchoring rule below |
| Per-row | Avatar + name + pops (or "Pending" badge) + swap icon |
| Disabled rows | Pending invitees (`isPendingInvite || isPendingAccept`) can't be swapped — tap is no-op, shows "Pending" pill |

### Swap-out candidate filter

[GroupManagerView.swift:2829-2833](../../Carry/Views/GroupManagerView.swift:2829):
```swift
let anchorScorer = isQuickGame || scoringMode != .everyone
let destScorerId = destIdx < scorerIDs.count ? scorerIDs[destIdx] : 0
let swapCandidates = anchorScorer
    ? groups[destIdx].filter { $0.id != destScorerId }
    : groups[destIdx]
```

| Mode | Candidates |
|---|---|
| Scorer-anchored | All players in destination group EXCEPT the anchored scorer |
| Everyone-scores | All players (note: full-group drop in everyone-scores rejects with toast before this sheet opens, so this branch is theoretical) |

### Performing the swap

[GroupManagerView.swift:2901-2917](../../Carry/Views/GroupManagerView.swift:2901) `performSwap(incoming:outgoing:)`:

| # | Step |
|---|---|
| 1 | `groups[fromIdx].removeAll { $0.id == incoming.id }` — remove dragged player from source |
| 2 | `groups[fromIdx].append(outgoing)` — drop swapped-out player into source's slot |
| 3 | `groups[toIdx].removeAll { $0.id == outgoing.id }` — remove swapped-out from dest |
| 4 | `groups[toIdx].append(incoming)` — place dragged player in dest |
| 5 | `syncScorerIDs()` — re-validate scorer assignments (the swap may invalidate a non-scorer's group membership) |
| 6 | Reset `showSwapPicker`, `pendingSwap*` state |

The post-mutation reconciler at `.onChange(of: groups)` ([GroupManagerView.swift:2477-2553](../../Carry/Views/GroupManagerView.swift:2477)) auto-corrects `Player.group` on the swapped players to match their new array indices. See [group-formation-canonical.md](group-formation-canonical.md).

### Common bugs / gotchas

| Issue | Notes |
|---|---|
| Pending invitees in candidate list | Visible but disabled (gray pill, tap no-op). Avoids accidentally swapping out a member who hasn't accepted yet |
| Anchored scorer in candidate list | Filtered out by the `anchorScorer` check. Without this, user could "swap out" the scorer, breaking the creator-locked invariant |
| Swap leaves source group empty | `.onChange(of: groups)` reconciler doesn't trim — only the GroupDropDelegate's trim runs (`groups.removeAll { $0.isEmpty }`). performSwap doesn't trim because both groups end up with the same player count after the swap (1-for-1) |
| User dismisses sheet without picking | `showSwapPicker = false` via swipe-down. State resets implicitly. No swap occurs. Dragged player stays in source group (drop was already cancelled by `resetDrag()` before sheet opened) |

## "Quick Game scorer wedge" bug (commit `2c295c2`, 2026-05-05)

| Field | Value |
|---|---|
| Symptom | Non-creator scorer of group 2+ in a QG taps a score → swallowed. Console: `[Scorecard.tap] BLOCKED` |
| Root cause | RoundCoordinatorView `.active` branch overwrote `roundConfig` AFTER `buildRoundConfig` populated `scorerPlayerIds` → blew away populated array → ScorecardView received nil → rejected taps |
| Fix 1 | `GroupManagerView.buildRoundConfig` sets both `scorerPlayerIds` (array) + `scorerPlayerId` (single, first nonzero) |
| Fix 2 | `RoundCoordinatorView.active` defense-in-depth: if local `roundConfig.scorerPlayerIds` is nil, repopulate from `initialRoundConfig` ([:272-277](../../Carry/Views/RoundCoordinatorView.swift:272)) |

## Common bugs / gotchas

| Bug | Cause | Fix |
|---|---|---|
| `currentUserId` vs `creatorId` conflation | Binding setter + `syncScorerIDs` both used `currentUserId`. Lock broke on non-creator devices and when `currentUserId` defaulted to init's `1` sentinel | All four sites switched to `creatorId` (2026-05-09) |
| Race guard absence | Without `scorerIdsLastSavedAt`, 30s poll could overwrite just-made local assignment with stale server state | 8s skip window in `syncScorerIDs` |
| `creatorId` param missing | `PlayerGroupsSheet` requires `creatorId` (added 2026-05-09); GroupManagerView passes at [:2059](../../Carry/Views/GroupManagerView.swift:2059). Missing → lock semantics break |

## Last verified

2026-05-10 — converted to machine-readable format.
