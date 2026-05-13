# Scorer Rules

**TL;DR:** `scorerIDs[gi]: Int` is the per-group scorer marker (0 = unassigned). Creator is locked as scorer of their own group. `canScore` filters eligibility.

## 🔒 Foundational premise — every tee group's scorer is a Carry user (or becoming one)

Universal rule across game types: a tee group's scorer slot **must be filled by a Carry user OR a pending invitee who will become one**.

| Slot 0 eligibility | Allowed? | Why |
|---|---|---|
| Confirmed Carry user (`profileId != nil`, not pending) | ✅ | Can `canScore` immediately |
| Pending SMS invitee (`isPendingInvite == true`, no profileId yet) | ✅ in QG | The assignment IS the "playing today" signal — they finish onboarding before round-start and become a real scorer. SG has no scorer concept in `.everyone` mode (v1's only mode), so this row doesn't apply to SG — SG SMS-invitees stay in ManageMembersSheet's Pending section until they accept and reconcile. SG advances past via `syncScorerIDs` rule 5 only matters in the dormant `.single` mode |
| Pending-accept Carry user (has `profileId`, `isPendingAccept == true`) | ✅ in QG | Same as above; they tap accept and become canScore-eligible |
| Permanent guest (name + handicap only, no profileId, no pending invite) | ❌ | Never has an app account, can't authenticate, can't write scores |

| Game type | How the rule holds |
|---|---|
| Skins Group | Trivially satisfied — SGs are Carry-only by the Skins-Groups-Carry-only invariant (no guests possible in `group_members`). Every member is a Carry user. Pending invitees are advanced past per `syncScorerIDs` rule 5 (SG demands confirmed) |
| Quick Game | Enforced explicitly — guests CAN appear in QGs but never as scorers. `canSave` validation in [QuickStartSheet.swift:116](../../Carry/Views/QuickStartSheet.swift:116) blocks Create when slot 0 has no `existingProfileId` AND isn't a pending invite (the `!isPendingInvite` allows the pending case) |

Mid-round defenses (apply to both):

| Surface | Enforcement |
|---|---|
| Mid-round scorer reassignment | `syncScorerIDs` rule 4 — wipes permanent-guest scorer assignments to 0, surfacing the missing-scorer banner |
| Pending advance in SG | `syncScorerIDs` rule 5 — Skins Groups advance past pending scorer to next confirmed Carry user; Quick Games preserve the pending assignment |
| `canScore` predicate | [Player.swift:83-85](../../Carry/Models/Player.swift:83) — single source of truth: `profileId != nil && !isGuest && !isPendingInvite && !isPendingAccept` |

This means downstream code can SAFELY ASSUME every populated tee group has a scorer who is — or imminently will be — a Carry user. Defensive backstops that "ensure a Carry user exists" (like the prior `prefillFromRecentGame` overwrite at QuickStartSheet:411-417) are unnecessary — `canSave` already blocks any state that violates the premise on the QG side, and SGs structurally cannot violate it.

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

| Surface | When | Where |
|---|---|---|
| `PlayerGroupsSheet` scorer slot | QG creator opens "Edit Players" from QG details | [PlayerGroupsSheet.swift:462](../../Carry/Views/PlayerGroupsSheet.swift:462) — per-group scorer slot via `ScorerAssignmentView` (search Carry users globally + SMS invite, with X-clear and self-invite block), drag-to-rearrange row above |
| `scorerPickerSheet` | QG creator taps a "Scorer" pill on a non-creator group's row | [GroupManagerView.swift:3480-3573](../../Carry/Views/GroupManagerView.swift:3480) — flat list of in-group Carry users (`.canScore` filtered) to pick from. **No SMS-invite path** — this picker assigns from the existing roster only. To SMS-invite a new scorer, use PlayerGroupsSheet's ScorerAssignmentView slot instead |

| State | Trigger | UI |
|---|---|---|
| `readOnly = true` | `groups[groupIndex].contains { $0.id == creatorId }` ([PlayerGroupsSheet:471](../../Carry/Views/PlayerGroupsSheet.swift:471)) | Lock icon, no X button |
| `readOnly = false` | Otherwise | X button to clear, search field to assign |

X button behavior: clears scorer slot, demotes player to non-scorer slot in same group. Does NOT remove player from group.

**SG has no Score Keeper UI** in `.everyone` mode (v1 default). Pills are hidden ([:4038](../../Carry/Views/GroupManagerView.swift:4038)), the missing-scorer banner is gated `scoringMode != .everyone` so it never fires for SG, and ManageMembersSheet handles all SG member roster ops. The dormant `.single`-mode SG path keeps the old scorerPickerSheet behavior in code, but the UI gate is `if false`.

### Revert history — SG scorer picker upgrade

Mid-session 2026-05-13 we shipped `bdeca98` (upgrade `scorerPickerSheet` to use `ScorerAssignmentView` for SG SMS-invite parity) and `8a45db3` (refreshGroupData filter relax to let SMS-invite scorers through for SG). Both reverted in `af0a84d` + `8e4ce5e`. Reason: **SG has no designated scorers in `.everyone` mode (the only v1 mode)** — the picker upgrade + filter relax were wrong scope. SG SMS invites stay in ManageMembersSheet's Pending section until they accept and reconcile. Current code is the pre-`bdeca98` shape: flat candidate list, no SMS-invite UI in `scorerPickerSheet`.

## `scoringMode`

| Mode | Default for | Behavior |
|---|---|---|
| `.single` | Quick Game | One scorer per group. ScorecardView tap-gate at [:724](../../Carry/Views/ScorecardView.swift:724) blocks non-scorers |
| `.everyone` | Skins Group v1 | All players score in parallel. No tap-gate |

Stored at `RoundConfig.scoringMode` ([RoundConfig.swift:50](../../Carry/Models/RoundConfig.swift:50)).

### SG single-scorer toggle dormant

The UI to flip a Skins Group from `.everyone` to `.single` is hidden behind `if false` at [GroupManagerView.swift:5385](../../Carry/Views/GroupManagerView.swift:5385) with the explicit comment: *"hidden for launch — we're shipping with 'everyone can score' as the only Skins Group model. Quick Games still use single-scorer structurally. Leaving the underlying enum + state in place so the toggle can return later without a migration, but the UI is gone for v1."*

Implication: `scoringMode == .single` is unreachable for SG in production. The paired `missingScorerBanner` ([:3574](../../Carry/Views/GroupManagerView.swift:3574)) — gated `scoringMode != .everyone && !isQuickGame` — is therefore dormant for SG, and explicitly suppressed for QG (see "Missing scorer behavior (Quick Game)" below).

**Both are kept as a matched dormant pair.** Removing one would require rewriting it when single-scorer SG returns. Plumbing stays warm: `RoundConfig` default `.single` at [:50](../../Carry/Models/RoundConfig.swift:50); server load fallback `.single` at [GroupService.swift:1730, :1918](../../Carry/Services/GroupService.swift:1730); `localScoringMode` round-trips through GameOptionsSheet.

## Missing scorer behavior (Quick Game)

When a QG has a populated group with no Carry-user scorer assigned — i.e. `scorerIDs[i] == 0`, the assigned player isn't in the group, OR the assigned player is a guest (`profileId == nil`) — the bottom CTA is the single fix surface.

### Detection predicates

| Predicate | Where |
|---|---|
| `groupHasValidScorer(index:) -> Bool` | [GroupManagerView.swift:3605](../../Carry/Views/GroupManagerView.swift:3605). Requires `scorerIDs[i] != 0` AND assigned player exists in the group AND has `profileId != nil` |
| `missingScorerGroupIndex: Int?` — first 0-indexed group missing a valid scorer | [GroupManagerView.swift:667](../../Carry/Views/GroupManagerView.swift:667). Gated `isQuickGame, isCreator, !isLiveRound, !roundStarted` |

### CTA contract

| Aspect | Behavior | Cite |
|---|---|---|
| `startButtonLabel` | Returns "Group N needs scorer" when `missingScorerGroupIndex != nil` | [:690](../../Carry/Views/GroupManagerView.swift:690) |
| `canStartRound` | Stays `false` — actual start-round path is blocked. QG branch ANDs `missingScorerGroupIndex == nil` | [:643](../../Carry/Views/GroupManagerView.swift:643) |
| `buttonEnabled` | Stays `true` so the tap fires. ORs `missingScorerGroupIndex != nil` | [:653](../../Carry/Views/GroupManagerView.swift:653) |
| Tap action | `showPlayerGroups = true` — opens PlayerGroupsSheet (the fix surface). Branch precedes the start-round path | [:1791](../../Carry/Views/GroupManagerView.swift:1791) |
| `flag.fill` icon | Hidden — opacity bound to `canStartRound \|\| isLiveRound` | [:1831](../../Carry/Views/GroupManagerView.swift:1831) |

### Banner suppressed for QG

The pink `missingScorerBanner` ([:3574](../../Carry/Views/GroupManagerView.swift:3574)) is gated `&& !isQuickGame` at the call site ([:3477](../../Carry/Views/GroupManagerView.swift:3477)). Single-CTA chosen over banner+button pair to avoid redundant signals. The CTA label + tap routing carry the full fix UX.

### Mirrors `needsTeeTimesSet` pattern

Same shape as the existing tee-times-missing CTA route ([:1799-1809](../../Carry/Views/GroupManagerView.swift:1799)): warning copy + tap opens fix sheet + `canStartRound` stays false. Reuse this pattern for any future "block-but-route-to-fix" CTA wiring.

## 🔒 Scorer anchoring (drag rules) — load-bearing architectural rule

This is the single most important QG vs SG behavioral difference. Every drag-drop / swap / move path branches on this flag.

| Game type | scoringMode | scorerAnchored | Drag a scorer to another group? |
|---|---|---|---|
| Quick Game | `.single` (default + only) | **true** | **Blocked** — toast: "Scorers are anchored — change scorers in Manage Members." Move scorers only via `PlayerGroupsSheet`. |
| Skins Group v1 | `.everyone` (default + only — `.single` toggle dormant) | **false** | Allowed — every player is interchangeable. Full-group target → swap UI (no scorer protection). |
| Skins Group legacy `.single` | `.single` | true | Theoretical only — UI to set `.everyone → .single` is gated `if false` ([:5385](../../Carry/Views/GroupManagerView.swift:5385)). Unreachable in production. |

`scorerAnchored` formula (both QG and SG paths compute it identically):
```swift
scorerAnchored: isQuickGame || scoringMode != .everyone
```

### Enforcement points

| Drop delegate | Line | Behavior |
|---|---|---|
| `GroupDropDelegate.performDrop` (drag onto an existing group card) | [:5905-5914](../../Carry/Views/GroupManagerView.swift:5905) | Rejects with toast + early-return when `scorerAnchored && scorerIDs[sourceGroup] == player.id` |
| `AddTeeGroupDropDelegate.performDrop` (drag onto the new-group dotted zone — 1.0.9) | [:6021-6027](../../Carry/Views/GroupManagerView.swift:6021) | Same guard. Without it, a creator could drag a locked QG scorer to a new group and silently bypass the invariant. |

Both call sites pass the same `scorerAnchored: isQuickGame || scoringMode != .everyone` at [:3754](../../Carry/Views/GroupManagerView.swift:3754) (GroupDropDelegate) and [:3804](../../Carry/Views/GroupManagerView.swift:3804) (AddTeeGroupDropDelegate).

### Implication for QG

When anchoring is on, the ONLY way to reassign a scorer is through:
- `PlayerGroupsSheet.scorerSlotBinding` (Edit Players sheet — per-group scorer slots with `ScorerAssignmentView`)
- The picker's setter handles slot reassignment + creator-lock invariant + immediate `saveScorerIds` sync

Dragging is blocked because in single-scorer mode the scorer is structurally meaningful — they're the designated keeper for that group. Silent drag would orphan the slot mid-setup.

### Implication for SG v1

No scorer anchoring → no per-group "designated keeper" concept. Every player can move freely between groups via drag, and a SG round-start writes everyone into `round_players` regardless of group_num (scoring mode is `.everyone`, so any player can score any hole). `scorerIDs` is still tracked in the model but unused on the SG tee sheet (pills hidden, banner gated `!isQuickGame && scoringMode != .everyone` so it's dormant). The post-revert `scorerPickerSheet` exists only for the unreachable `.single`-mode SG path.

**The full-group swap-picker behavior**: SG with a full destination group → all players in destination are swap candidates (none are "locked"). QG with full destination → swap-out list excludes the anchored scorer ([scorerAnchored gate inside SwapPickerSheet](../../Carry/Views/GroupManagerView.swift:5961-5970)).

### Why this rule has wide reach

The anchoring rule cascades through many systems:

| Surface | How it branches |
|---|---|
| `scoringMode` default | QG=`.single`, SG=`.everyone` ([RoundConfig](../../Carry/Models/RoundConfig.swift:50)) |
| Scorecard tap gate | QG enforces `isCurrentUserScorerForOwnGroup`, SG has no gate ([ScorecardView:724](../../Carry/Views/ScorecardView.swift:724)) |
| Group drag drop | `scorerAnchored` rejects locked-scorer drags |
| Add-tee-group drop | Same rejection (1.0.9) |
| Missing-scorer banner routing | QG→PlayerGroupsSheet, SG→scorerPickerSheet ([:3703-3707](../../Carry/Views/GroupManagerView.swift:3703)) |
| Scorer pill rendering | Hidden for SG when `.everyone` (pill implies a restriction that doesn't exist) ([:3910](../../Carry/Views/GroupManagerView.swift:3910)) |
| Pre-reconciliation roster filter | QG includes all pending invites (they may be scorers); SG drops all pending invites from the tee sheet — they stay in ManageMembersSheet's Pending section until they reconcile (revert of 1.0.9 `bdeca98`/`8a45db3` — SG has no designated scorers in `.everyone` mode) |

**Any new feature touching scorer / group / drag behavior MUST consult this table first.** Treating SG the same as QG (or vice-versa) is the single most common source of regression bugs in this codebase.

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

2026-05-13 — patched Score Keeper UI section for the `af0a84d`/`8e4ce5e` reverts (SG scorer picker reverted to flat-list, no SMS-invite path). Refreshed line citations for hotfix/1.0.9 code layout. Scorer-anchored rule + enforcement points unchanged.
