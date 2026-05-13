# Game Types — Quick Game vs Skins Group

**TL;DR:** `isQuickGame: Bool` is the master flag. Quick Games: ephemeral, can have guests, convertible. Skins Groups: persistent, recurring, Carry-only, never convert.

## Master flag

| Source | Where |
|---|---|
| Client `RoundConfig.isQuickGame` | [RoundConfig.swift:51](../../Carry/Models/RoundConfig.swift:51) |
| Client `SavedGroup.isQuickGame` | [GroupsListView.swift:2689](../../Carry/Views/GroupsListView.swift:2689) |
| Server column | `skins_groups.is_quick_game` — added in [20260328000002_quick_game_flag.sql](../../supabase/migrations/20260328000002_quick_game_flag.sql) |
| DTO mapping | [SupabaseModels.swift:422, 500, 545](../../Carry/Models/SupabaseModels.swift:422) |

## Lifecycle comparison

| Stage | Quick Game | Skins Group |
|---|---|---|
| Creation | `QuickStartSheet` → `handleQuickGameCreate` | `GroupService.createGroup(isQuickGame: false)` |
| Members in `group_members` | Carry users only | Carry users only (Carry-only invariant) |
| Members in `round_players` | Carry users + guests | Carry users only |
| Round count | Single (current) | Multi-round, recurring |
| Recurrence fields | n/a | `recurrence` jsonb, `scheduled_date` |
| Convertible | ✓ via `convert_quick_game_to_group` RPC | ✗ |
| Auto-deletes on End Game | ✓ creator only | ✗ |
| History preserved | Round survives in History only after Save Results | Always |

## `isQuickGame` check sites

~60+ branches. Hotspots:

| File:line | What it gates |
|---|---|
| [GroupManagerView.swift:128, 165](../../Carry/Views/GroupManagerView.swift:128) | View constructor accepts flag, propagates to children |
| [GroupManagerView.swift:468](../../Carry/Views/GroupManagerView.swift:468) | Skins Group only: advance past pending scorer in `syncScorerIDs` |
| [GroupManagerView.swift:850-855](../../Carry/Views/GroupManagerView.swift:850) | Quick Game guest preservation in `refreshGroupData` |
| [GroupManagerView.swift:1483](../../Carry/Views/GroupManagerView.swift:1483) | "Invite & Manage" → `showPlayerGroups` (QG) vs `showManageMembers` (SG) |
| [GroupManagerView.swift:2282-2298](../../Carry/Views/GroupManagerView.swift:2282) | `onChange(of: isQuickGame)` — flag flip false (conversion) clears guests + UserDefaults snapshot |
| [PlayerGroupsSheet.swift:67, 474, 586, 966](../../Carry/Views/PlayerGroupsSheet.swift:67) | QG member auto-active on add; SG member is `isPendingAccept` |
| [ScorecardView.swift:549, 724](../../Carry/Views/ScorecardView.swift:549) | "Change Scorer" hidden for QG; scorecard tap-gate for non-creator scorers |

## Conversion flow (Quick Game → Skins Group)

### Trigger sequence

| # | Event | Code |
|---|---|---|
| 1 | Last hole scored | `allGroupsFinished` becomes true |
| 2 | 0.8s later: status `active → concluded` | [RoundViewModel.swift:460-467](../../Carry/ViewModels/RoundViewModel.swift:460) |
| 3 | RoundCompleteView auto-presents | (no user tap) |
| 4 | User taps "Save Round Results" | [RoundCompleteView.swift:705](../../Carry/Views/RoundCompleteView.swift:705) |
| 5 | Convert sheet appears | iff gating below passes |

`allGroupsFinished` is hole-count-agnostic ("every player has scored every hole"). Not hardcoded to 18.

### Force-end variants

| User action | `status` | `force_completed` | Reaches Save Round Results? | Convert prompt? |
|---|---|---|---|---|
| Score every hole naturally | `concluded` | `false` | Yes | ✅ if QG + subscribed |
| End Game & Save Results | `concluded` | `true` | Yes | ❌ `playedFullRound = false` |
| End Game (destructive) | `cancelled` (scores DELETEd) | `true` | No (round cancelled) | ❌ |

See [round-lifecycle.md](round-lifecycle.md) §"`force_completed` semantics".

### Gating logic

[RoundCompleteView.swift:725-738](../../Carry/Views/RoundCompleteView.swift:725):

```swift
let playedFullRound = isQuickGame && !viewModel.forceCompleted
if playedFullRound {
    if storeService.isPremium {
        onCreateGroup?()
    } else {
        showPaywall = true
    }
} else {
    onExitRound() ?? onDismiss()
}
```

| Condition | Required because |
|---|---|
| `isQuickGame == true` | Skins Groups already Carry-only |
| `viewModel.forceCompleted == false` | Force-end is a "done" signal, not an upgrade signal |
| `storeService.isPremium == true` | Recurring Skins Groups are paid; non-subscribed → paywall first |

Paywall path: subscribe → paywall `onDisappear` → `onCreateGroup` fires.

### Subscription state

Binary, not tiered.

| Flag | Meaning | Source |
|---|---|---|
| `storeService.isPremium` | Currently subscribed (incl. trial). False after expiry | StoreKit transactions, `checkEntitlements` ([StoreService.swift:129+](../../Carry/Services/StoreService.swift:129)) |
| `storeService.hadPremium` | Sticky: ever seen `isPremium = true`. Never resets | UserDefaults `hadPremium` + `isEligibleForIntroOffer` ([StoreService.swift:91-100](../../Carry/Services/StoreService.swift:91)) |

`isPremium` gates feature access. `hadPremium` only changes paywall copy ("Try it Free" vs "Subscribe").

### Code wiring chain

| # | Where | What |
|---|---|---|
| 1 | [RoundCompleteView.swift:705](../../Carry/Views/RoundCompleteView.swift:705) | Save Round Results Button action |
| 2 | [:715-723](../../Carry/Views/RoundCompleteView.swift:715) | Async `updateRoundStatus(roundId, "completed")` + `advanceScheduledDateIfRecurring` |
| 3 | [:725](../../Carry/Views/RoundCompleteView.swift:725) | `playedFullRound = isQuickGame && !viewModel.forceCompleted` |
| 4 | [:726-738](../../Carry/Views/RoundCompleteView.swift:726) | Branch: `onCreateGroup?()` / `showPaywall` / dismiss |
| 5 | [RoundCompleteView.swift:75](../../Carry/Views/RoundCompleteView.swift:75) | `var onCreateGroup: (() -> Void)?` declared |
| 6 | [RoundCoordinatorView.swift:303-305](../../Carry/Views/RoundCoordinatorView.swift:303) | Coordinator passes a closure that calls its own `onCreateGroup?()` to RoundCompleteView |
| 7 | [RoundCoordinatorView.swift:13](../../Carry/Views/RoundCoordinatorView.swift:13) | `var onCreateGroup: (() -> Void)?` declared |
| 8 | [RoundCoordinatorView.swift:72, :103](../../Carry/Views/RoundCoordinatorView.swift:72) | Init accepts + stores the closure |
| 9 | Entry-point closure (Games tab inline OR Home tab AppRouter handoff) | See "Branch by entry point" |

Home-tab path duplicates the `updateRoundStatus` call (step 2 + inline closure both fire it). Idempotent.

### Branch by entry point

| Entry point | Closure provided | Effect |
|---|---|---|
| Games tab → group card → round | [GroupsListView.swift:944-953](../../Carry/Views/GroupsListView.swift:944) | Marks completed, dismisses overlay, sets `convertSheetPhase = .prompt`, `showConvertSetupSheet = true` after 0.55s |
| Home tab → Active Round card | [HomeView.swift:656-679](../../Carry/Views/HomeView.swift:656) (Bug A 2026-05-09) | Marks completed, switches `selectedTab = .skinGames`, sets `appRouter.pendingConvertGroupId = groupId` after 0.55s |
| Home-tab handoff caught by | [GroupsListView.swift:118-128](../../Carry/Views/GroupsListView.swift:118) | `.onChange(of: appRouter.pendingConvertGroupId)` — clears field, sets `completedGroupId`, `convertSheetPhase = .prompt`, `showConvertSetupSheet = true` |

### Sheet presentation

| Component | Citation |
|---|---|
| `@State showConvertSetupSheet` | [GroupsListView.swift:37](../../Carry/Views/GroupsListView.swift:37) |
| `enum ConvertSheetPhase { .prompt, .setup, .inviteCrew }` + state | [:52-53](../../Carry/Views/GroupsListView.swift:52) |
| Sheet modifier | [:2046-2059](../../Carry/Views/GroupsListView.swift:2046) |
| Sheet body | `convertSetupSheet` computed property — branches on `convertSheetPhase` |
| Dismiss | `.inviteCrew` reached → `finishConvertFlow()`. Else → reset state, cancel |

### Phase progression

| Phase | Content | Transition trigger |
|---|---|---|
| `.prompt` | "Convert game into a recurring Skins Group?" Y/N | Yes → `.setup`. No / swipe → dismiss |
| `.setup` | name input, tee-time pick | Create → RPC fires; success → `.inviteCrew` |
| `.inviteCrew` | share link / QR / member list | Done / swipe → `finishConvertFlow()` opens new SG |

Phase mutation points: [GroupsListView.swift:127, :377, :431, :458](../../Carry/Views/GroupsListView.swift:127).

### Server RPC

`convert_quick_game_to_group(p_group_id, p_group_name)` — [20260501000002](../../supabase/migrations/20260501000002_convert_quick_game_carry_only_auto_accept.sql).

iOS entry: [GroupsListView.swift:260-289 `convertQuickGame`](../../Carry/Views/GroupsListView.swift:260) → `GroupService.convertQuickGameToGroup(groupId:groupName:)`.

| Step | Action |
|---|---|
| 1 | Auth check: `created_by = auth.uid()` |
| 2 | Wipe guests via `delete_quick_game_guests(round_id)` for most recent round |
| 3 | Set `is_quick_game = false`, optionally rename |
| 4 | Carry users keep `active` status (no demote — 2026-05-01 fix) |

### Post-convert iOS

| Step | Action |
|---|---|
| 1 | 3s delay before `refreshGroupData` reload |
| 2 | `onChange(of: isQuickGame)` in GroupManagerView clears guests + UserDefaults snapshot |
| 3 | Active-round card swaps icon (calendar → recurrence indicator) |

## Member rules

| Role | Quick Game | Skins Group |
|---|---|---|
| Creator | Required | Required |
| Carry user | Status `active` immediately on add | Status `invited` until they accept |
| Guest | `round_players` only (locked 2026-05-01) | Never allowed (locked 2026-05-01) |
| Phone invite | `status='invited'` + `invited_phone`; reconciled via `reconcile_phone_invites_for_profile()` trigger | Same |

## Round behavior

| Behavior | Quick Game | Skins Group |
|---|---|---|
| Default scoring mode | `.single` | `.everyone` |
| Scorer eligibility | Allows pending Carry users | Requires `canScore = true` |
| Scorecard tap gate | `isCurrentUserScorerForOwnGroup` for non-creator scorers ([ScorecardView.swift:724](../../Carry/Views/ScorecardView.swift:724)) | No gate |
| Default tee-time interval | 10 min (`QuickStartSheet`) | 8 min (`GroupManagerView`) |
| Restart Round flow | Wipes scores + `delete_quick_game_guests` | Wipes scores only |
| Scorer drag (tee-sheet) | **Blocked** ([GroupDropDelegate:5328-5334](../../Carry/Views/GroupManagerView.swift:5328)) — must move scorers via PlayerGroupsSheet | Allowed (everyone-scores mode) |
| Full-group drop on target | Opens swap picker | Rejects with toast |

## Auto-grouping rules

[GroupManagerView.swift:255-292](../../Carry/Views/GroupManagerView.swift:255) `static func autoGroup(_ players: [Player]) -> [[Player]]`. Decides initial tee-group layout. Doc comment at [:253-254](../../Carry/Views/GroupManagerView.swift:253) declares: "Splits players into balanced groups of 3-4 (foursomes preferred)."

Decision order:

| # | Branch | Output |
|---|---|---|
| 1 | `n == 0` | `[]` |
| 2 | `players.map(\.group).max() ?? 1 > 1` (any player has explicit `group > 1`) | Build N groups (N = max). Strip ALL empty groups (not just trailing). Fall back to `[players]` if all empty |
| 3 | `n ≤ 4` | 1 group: `[players]` |
| 4 | `n > 4` | `numGroups = (n + 3) / 4` (ceil), `baseSize = n / numGroups`, first `n % numGroups` groups get `baseSize + 1` |

Explicit count → split mapping (from code comment):

| n | Split |
|---|---|
| 1–4 | 1 group |
| 5 | 3 + 2 |
| 6 | 3 + 3 |
| 7 | 4 + 3 |
| 8 | 4 + 4 |
| 9 | 3 + 3 + 3 |
| 10 | 4 + 3 + 3 |
| 11 | 4 + 4 + 3 |
| 12 | 4 + 4 + 4 |
| 13+ | continues `ceil(n/4)` groups |

## How groups grow / shrink in the UI

| Path | Effect |
|---|---|
| QuickStartSheet slot assignment | Writes explicit `Player.group` per slot. QGs can launch with N groups regardless of player count |
| Drag from Group A → Group B (existing) | Player moves; source group may auto-trim if empty |
| Drag from Group A → empty space | No effect. There is no drop-zone that creates a new group |
| `autoGroup` on `n > 4` first load | Splits into `ceil(n/4)` groups |
| Add players via Manage Members until n > 4 | Triggers re-grouping on next `autoGroup` invocation |

**No "Add Group" button** exists. Drop targets only render for already-existing groups ([:3274](../../Carry/Views/GroupManagerView.swift:3274) `view.onDrop(... GroupDropDelegate(groupIndex: index, ...))`). `GroupDropDelegate.performDrop` ([:5294-5360](../../Carry/Views/GroupManagerView.swift:5294)) reorders within / moves between existing groups; never appends a new group.

**Implication:** a Skins Group with ≤4 players cannot have >1 tee group via UI. To force 2 groups in a Skins Group:
| Approach | Works? |
|---|---|
| Add 5+ players | Yes — autoGroup splits |
| Drag a player out of the only group | No — no new-group drop target |
| Manually edit somewhere | No UI path found |

A Quick Game can have 2 groups with 2 players because `QuickStartSheet` assigns `Player.group` explicitly per slot during creation, before `autoGroup` ever runs.

This is current code state; if you ever want a "Split into 2 groups" button for sub-5-player Skins Groups, it'd need a new UI path that writes `Player.group = 2` for the moved player and triggers `syncGroupNumsToSupabase`.

## UI differences

| Sheet / view | Quick Game | Skins Group |
|---|---|---|
| Roster builder | `QuickStartSheet` (slot-based, inline guest entry) | Skins Group create sheet (Carry search only) |
| Mid-game roster edit | `PlayerGroupsSheet` (slots + per-group scorer) | `ManageMembersSheet` (Carry users only) |
| Active-round card | "Quick Game · Today · 8:24 AM" | Group name + recurrence indicator |
| End/Delete affordances | "Delete Game" (creator pre-round) — hard-deletes group + round | "Delete Group" (only if no round history) |
| "Convert to Recurring" button | Visible iff `isCreator && !isLiveRound && !roundStarted` ([GroupManagerView.swift:640](../../Carry/Views/GroupManagerView.swift:640)) | Never |

## Invariants

| Rule | Enforced by |
|---|---|
| Skins Groups are Carry-only | `convert_quick_game_to_group` (guest wipe step); `loadSingleGroup` filters wiped-guest UUIDs |
| Quick Game scorer-only | ScorecardView tap gate; `RoundConfig.scorerPlayerIds` |
| **Every tee group's scorer slot must be filled by a Carry user OR a pending invitee (SMS or accept-pending) who will become one.** Only permanent guests (name + handicap only, no app-account intent) are disallowed. SG satisfies it trivially (Carry-only members, no guests). QG enforces it via `canSave`. | `canSave` validation in [QuickStartSheet.swift:116](../../Carry/Views/QuickStartSheet.swift:116) (blocks Create when slot 0 has no `existingProfileId` AND isn't a pending invite — note `!isPendingInvite` allows the pending case); `syncScorerIDs` rule 4 wipes permanent-guest scorer assignments mid-round; SG members are Carry-only by the Skins-Groups-Carry-only invariant |
| Conversion is one-way | No reverse RPC exists |

## Common bugs / gotchas

| Bug | File | Notes |
|---|---|---|
| Quick Game scorer wedge (commit `2c295c2`, 2026-05-05) | RoundCoordinatorView | `.active` branch overwrote `roundConfig` after `buildRoundConfig` set `scorerPlayerIds` → non-creator scorer's taps blocked. Fix: defense-in-depth merge scorer IDs from `initialRoundConfig` |
| Conversion losing Carry users (pre 2026-05-01) | `convert_quick_game_to_group` | RPC demoted `active → invited`. Removed |
| `isQuickGame` branch drift | 60+ sites | Adding game-type-specific behavior requires search-every-reference |

## Last verified

2026-05-10 — converted to machine-readable format.
