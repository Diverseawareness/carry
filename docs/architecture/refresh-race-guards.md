# Refresh Race Guards

**TL;DR:** Five `<field>LastSavedAt` stamps + 8-second guard windows prevent refresh paths from clobbering local edits before they replicate to the server.

## Pattern

```
1. User mutates field
2. .onChange fires:
   <field>LastSavedAt = Date()  ← stamp BEFORE async write
   Task { await GroupService().updateGroup(...) }
3. Independently, refresh fires (30s timer / push / pull-to-refresh)
4. refresh checks: Date().timeIntervalSince(<field>LastSavedAt) < 8 ?
   YES → skip field's sync from server (local wins)
   NO  → adopt server value
```

8s window covers Supabase write→replicate→read latency (~500ms-1s) + 0.8s `.onChange` debounce + safety margin.

## Seven instances

### 1. `scorerIdsLastSavedAt`

| Property | Value |
|---|---|
| Declaration | [GroupManagerView.swift:92](../../Carry/Views/GroupManagerView.swift:92) |
| Stamped | `saveScorerIds()` at [:1207](../../Carry/Views/GroupManagerView.swift:1207) before async `updateGroup(scorerIds:)` |
| Checked | refreshGroupData at [:1033-1036](../../Carry/Views/GroupManagerView.swift:1033) |
| Guards | Scorer reconciliation branch at [:1037-1067](../../Carry/Views/GroupManagerView.swift:1037) — skips `syncScorerIDs()` + rebuild-from-server logic |
| Also stamped at | PlayerGroupsSheet `onSave` ([:2101](../../Carry/Views/GroupManagerView.swift:2101)) |

### 2. `teeTimesLastSavedAt`

| Property | Value |
|---|---|
| Declaration | [GroupManagerView.swift:100](../../Carry/Views/GroupManagerView.swift:100) |
| Stamped | `.onChange(of: teeTimes)` at [:2401](../../Carry/Views/GroupManagerView.swift:2401) before 0.8s debounce |
| Checked | refreshGroupData at [:1099-1102](../../Carry/Views/GroupManagerView.swift:1099) |
| Guards | Recompute fallback at [:1104-1110](../../Carry/Views/GroupManagerView.swift:1104) |

### 3. `handicapPercentageLastSavedAt`

| Property | Value |
|---|---|
| Declaration | [GroupManagerView.swift:104](../../Carry/Views/GroupManagerView.swift:104) (added 2026-05-08) |
| Stamped | Game Options sheet save at [:1891](../../Carry/Views/GroupManagerView.swift:1891) before async `updateGroup(handicapPercentage:)` |
| Checked | refreshGroupData at [:1160-1163](../../Carry/Views/GroupManagerView.swift:1160) |
| Guards | Handicap sync line at [:1165](../../Carry/Views/GroupManagerView.swift:1165) |

### 4. `groupNumLastSavedAt`

| Property | Value |
|---|---|
| Declaration | [GroupManagerView.swift:114](../../Carry/Views/GroupManagerView.swift:114) (added 2026-05-09) |
| Stamped | `.onChange(of: groups)` at [:2442](../../Carry/Views/GroupManagerView.swift:2442) before 1s debounce |
| Checked | refreshGroupData at [:961-964](../../Carry/Views/GroupManagerView.swift:961) |
| Guards | Authoritative rebuild-from-server-`group_num` branch at [:898-960](../../Carry/Views/GroupManagerView.swift:898) |
| Localized patch (always-on as of 2026-05-10) | [:1193-1230](../../Carry/Views/GroupManagerView.swift:1193) — patches each visible player's `.group` in `localized.members` from local `groups[][]` UNCONDITIONALLY (was 8s-gated; race-guard window only matters for the `groups[][]` rebuild itself, not the localized push). Local `groups[][]` is ground truth for visible players regardless of timing — if rebuild just ran from server, local matches server and patch is no-op; if user has recent edit, patch overrides server's stale state. Plus QG-only: append any local guests missing from `localized.members` (server-write race window for `guest_roster_json`) |
| Required model change | `SavedGroup.members` flipped `let → var` at [GroupsListView.swift:2677](../../Carry/Views/GroupsListView.swift:2677) |
| Local-state mirror (added 2026-05-10) | `.onChange(of: groups)` ALSO writes per-player `Player.group` into both `allMembers` and `guests` ([:2453-2474](../../Carry/Views/GroupManagerView.swift:2453)) + persists QG snapshot via `QuickGameGuestStorage.save`. Without this, the refresh's `preservedGuests` filter pulls QG guests with stale `Player.group` and the rebuild reverts the drag after the 8s window. Carry users don't need this mirror because their server `group_num` is authoritative; QG guests have no server authority outside `round_players` |

### 5. `quickGameGuests_<uuid>_savedAt`

UserDefaults-resident stamp (not @State) — `QuickGameGuestStorage` is a static enum without view-scoped state. Survives process death along with the data it guards.

| Property | Value |
|---|---|
| Declaration | [QuickGameGuestStorage.swift](../../Carry/Services/QuickGameGuestStorage.swift) `savedAtKey(_:)` (added 2026-05-10) |
| Stamped | `save(groupId:isQuickGame:allRosterPlayers:)` before 0.8s debounce |
| Re-stamped | After all retries (1s/2s/4s) fail — extends guard so stale-server hydrate doesn't clobber local |
| Checked | `hydrateFromServer(groupId:json:)` |
| Guards | Hydrate-from-server overwrite called from `loadSingleGroup` ([GroupService.swift:1344](../../Carry/Services/GroupService.swift:1344)) |
| Server retry | 3 attempts with exponential backoff (1s, 2s, 4s). Logged outside DEBUG |
| Debounce | 0.8s (mirrors tee-time sync) |

### 6. `guestProfileEditsLastSavedAt`

@State (parent: GroupManagerView). Guards guest profile edits (display_name, initials, handicap) made via PlayerGroupsSheet.

| Property | Value |
|---|---|
| Declaration | [GroupManagerView.swift:115+](../../Carry/Views/GroupManagerView.swift:115) (added 2026-05-10) |
| Stamped | PlayerGroupsSheet onSave handler ([GroupManagerView.swift:2196+](../../Carry/Views/GroupManagerView.swift:2196)) — BEFORE the async `update_guest_profile` RPC writes fire |
| Checked | `refreshGroupData` `filteredFreshMembers` patch ([:850+](../../Carry/Services/GroupService.swift:850)) |
| Guards | Server-side `profiles.display_name` / `profiles.handicap` for guest profiles. Without this, refresh during the RPC's replication window pulls stale values via `Player(from: profile)` and stomps the local edit |
| Skins impact | Load-bearing. Skins payouts are handicap-weighted; silent reversion = wrong winnings |
| Persistence path | `update_guest_profile` RPC (SECURITY DEFINER, `WHERE is_guest = true`). Guards Carry users from being touched even if iOS sent a wrong UUID |

See [guest-lifecycle.md §"Guest profile edits — the four-layer persistence chain"](guest-lifecycle.md) for the full edit lifecycle. The race guard is layer 4 of 4.

### 7. `skinGameGroupsLocallyMutatedAt`

@State in MainTabView. Guards against `loadGroups` returning a transient empty array right after a local mutation (e.g., `archiveConcludedRound` post-convert-decline). Without this, the Home tab showed empty state for ~15s until the next non-empty poll. Bug G fix.

| Property | Value |
|---|---|
| Declaration | [MainTabView.swift:63+](../../Carry/Views/MainTabView.swift:63) (added 2026-05-10) |
| Stamped | `.onReceive(Notification.didLocallyArchiveRound)` at [MainTabView.swift:288+](../../Carry/Views/MainTabView.swift:288) |
| Notification posted from | [HomeView.swift onDeclineGroup](../../Carry/Views/HomeView.swift:686), [GroupsListView.swift onDeclineGroup](../../Carry/Views/GroupsListView.swift:970), [GroupsListView.swift convertPromptDecline](../../Carry/Views/GroupsListView.swift:1481) |
| Checked | 15s poll's empty-result branch ([MainTabView.swift:244+](../../Carry/Views/MainTabView.swift:244)) |
| Guards | Transient-empty assignment to `skinGameGroups`. If `groups.isEmpty && !skinGameGroups.isEmpty && isRecentLocalMutation`, skip |
| Window | 10s — long enough to bridge the convert-flow status replication, short enough that legitimate empty results (last group deleted) are eventually accepted |

Differs from instances 1-6: those guard a specific field's value being overwritten by stale server data. This one guards the entire collection's identity from being stomped by a transient-empty result.

## Localized snapshot trick

[GroupManagerView.swift:1171-1179](../../Carry/Views/GroupManagerView.swift:1171):
```swift
var localized = freshGroup
if recentHcSave {
    localized.handicapPercentage = handicapPercentage
}
onGroupRefreshed?(localized)
```

Without patch: parent's `groups[idx].handicapPercentage` stays stale during replication window. Re-mount uses stale value.

## `recentlyRemovedIds` (related but separate)

[GroupManagerView.swift:137](../../Carry/Views/GroupManagerView.swift:137):

| Field | Value |
|---|---|
| Type | `Set<Int>` |
| Race | Swipe deletes player → local update + async server delete. 30s poll lands BEFORE server delete completes → fresh snapshot still includes player → re-merge |
| Filter | [:840](../../Carry/Views/GroupManagerView.swift:840) — `freshGroup.members.filter { !recentlyRemovedIds.contains($0.id) }` |
| Cleared | [:2095](../../Carry/Views/GroupManagerView.swift:2095) on PlayerGroupsSheet save |

## `refreshGroupData` flow

[GroupManagerView.swift:807-1210](../../Carry/Views/GroupManagerView.swift:807):

| # | Step |
|---|---|
| 1 | Fetch via `loadSingleGroup` ([:814](../../Carry/Views/GroupManagerView.swift:814)) |
| 2 | Filter `recentlyRemovedIds` ([:840](../../Carry/Views/GroupManagerView.swift:840)) |
| 3 | Quick Game guest preservation ([:850-855](../../Carry/Views/GroupManagerView.swift:850)) |
| 4 | Rebuild `groups[][]` from server `group_num`, gated by `groupNumLastSavedAt` ([:898-967](../../Carry/Views/GroupManagerView.swift:898)) |
| 5 | Check `scorerIdsLastSavedAt` ([:1033](../../Carry/Views/GroupManagerView.swift:1033)) → maybe skip scorer sync |
| 6 | Check `teeTimesLastSavedAt` ([:1099](../../Carry/Views/GroupManagerView.swift:1099)) → maybe skip tee-time recompute |
| 7 | Check `handicapPercentageLastSavedAt` ([:1160](../../Carry/Views/GroupManagerView.swift:1160)) → maybe skip handicap sync |
| 8 | Localize freshGroup (patch handicap + per-member `group` if recent saves) + `onGroupRefreshed?(localized)` ([:1175-1209](../../Carry/Views/GroupManagerView.swift:1175)) |

## Refresh trigger sources

| Trigger | Cadence / event |
|---|---|
| Auto-refresh timer | 30s, started in `.onAppear` ([:1196](../../Carry/Views/GroupManagerView.swift:1196)) |
| Quick Game post-appear | 3s after `.onAppear` |
| Push-triggered | `memberJoined` / `memberDeclined` notifications |
| Explicit | After `updateGroup` writes |
| Pull-to-refresh | User-initiated gesture |

## Quick Game guest preservation

[GroupManagerView.swift:850-855](../../Carry/Views/GroupManagerView.swift:850):
```swift
let preservedGuests: [Player]
if isQuickGame {
    let freshIds = Set(filteredFreshMembers.map(\.id))
    preservedGuests = allMembers.filter { $0.isGuest && !freshIds.contains($0.id) }
} else {
    preservedGuests = []
}
allMembers = filteredFreshMembers + preservedGuests
```

QG guests live in `round_players` only when round is active. Server's `loadSingleGroup` excludes them between rounds. Preserve filter keeps them across 3s post-appear + 30s polling refreshes.

## Bug pattern history (refresh-clobbers-edit)

| # | Bug | Pre-fix |
|---|---|---|
| 1 | Tee-time bug | pull-to-refresh while editing tee times reset all times |
| 2 | Index % bug | slider snaps back to 100% mid-save |
| 3 | Scorer wedge | assigned scorer reverts to default |
| 4 | Drag-and-drop tee group (2026-05-09) | dragged player snapped back to original group on next 30s refresh AND navigate-out + back |
| 5 | Quick Game guest roster (2026-05-10) | server hydrate clobbered just-added guests when navigating out + back during debounce/replication window |

## Adding a new race-guarded field

For any new user-editable field that persists to the server:

| # | Required |
|---|---|
| 1 | `<field>LastSavedAt` stamp before async write (UserDefaults if data lives outside @State) |
| 2 | Check before field's hydrate/refresh path |
| 3 | `localized` patch if parent observes via `onGroupRefreshed` (required when field affects per-member properties; parent re-passes `members` as `initialMembers` on re-mount) |
| 4 | For server-side persistence: debounce + retry-with-backoff + re-stamp on retry exhaustion |

## Constants

| Value | Use |
|---|---|
| 8 seconds | Guard window ([:1035, 1101, 1162, 963](../../Carry/Views/GroupManagerView.swift:1035) + `QuickGameGuestStorage.hydrateGuardWindow`) |
| 0.8 seconds | Tee-time + guest-roster `.onChange` debounce |
| 1 second | Drag-and-drop `.onChange(of: groups)` debounce |
| 1s, 2s, 4s | Guest-roster server-write retry backoff |
| 3 seconds | Quick Game post-appear refresh delay |
| 30 seconds | Auto-refresh timer |

## Rejected alternatives

| Alternative | Why rejected |
|---|---|
| Write-then-read sync (await write, then fetch) | Still races against background 30s polls |
| Optimistic local-only (never refresh) | Breaks multi-device sync |
| Explicit read-sync RPC | Supabase doesn't support natively |

## Common bugs / gotchas

| Issue | Notes |
|---|---|
| Stamp order matters | Stamp BEFORE async write, not inside the Task. Inside-Task stamp may not propagate fast enough |
| Localized snapshot is per-field | Adding a new race-guarded field requires patching `localized` for that field |
| 8s window assumes "fast" network | Cellular hand-off can take longer. Extend if users report reverts |
| PlayerGroupsSheet has its own scorer write path | Stamps at [:2101](../../Carry/Views/GroupManagerView.swift:2101); easy to miss in audits |

## Last verified

2026-05-10 — converted to machine-readable format. 5th instance + retry pattern complete.
