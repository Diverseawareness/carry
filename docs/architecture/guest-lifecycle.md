# Guest Lifecycle

**TL;DR:** Quick Game guests live in `round_players` only, never in `group_members` (locked 2026-05-01). On round end, profile rows are wiped; `round_players` UUIDs survive via denormalized `guest_display_name` + `guest_handicap`. Between-round roster persists in `skins_groups.guest_roster_json` + UserDefaults (locked 2026-05-10).

## What is a guest

| Property | Value |
|---|---|
| Server | `profiles` row with `is_guest = true`, no auth account |
| Client | `Player` with `isGuest = true` |
| `Player.isGuest` | [Player.swift:21](../../Carry/Models/Player.swift:21) |
| `Player.profileId` | [Player.swift:22](../../Carry/Models/Player.swift:22) — guests DO have a `profileId` |
| `Player.canScore` | [Player.swift:83-85](../../Carry/Models/Player.swift:83) — false for guests |

## Creation paths

| Path | Site |
|---|---|
| QuickStartSheet (slot-based) | [QuickStartSheet.swift:1393](../../Carry/Views/QuickStartSheet.swift:1393) — `isGuest = (slot.existingProfileId == nil && !slot.isPendingInvite)` |
| `addGuest()` inline form | [GroupManagerView.swift:4271](../../Carry/Views/GroupManagerView.swift:4271) — appends to `guests` @State, persists to `QuickGameGuestStorage` |
| PlayerGroupsSheet save | [PlayerGroupsSheet.swift:1195, 1249](../../Carry/Views/PlayerGroupsSheet.swift:1195) — `GuestProfileService.createGuestProfiles()` then client append |

## Server-side storage

Locked rule: guests in `round_players` only. **Never** in `group_members`.

| Table | Stores guests? | How |
|---|---|---|
| `profiles` | Yes (ephemeral) | `is_guest = true` row, lifetime = round |
| `group_members` | No | Migration [20260501000001:14](../../supabase/migrations/20260501000001_ephemeral_quick_game_guests.sql:14) |
| `round_players` | Yes | UUID + denormalized `guest_display_name`, `guest_handicap` ([20260501000001:48-50](../../supabase/migrations/20260501000001_ephemeral_quick_game_guests.sql:48)) |
| `scores` | Yes | UUID + denormalized fallback ([20260501000001:52-54](../../supabase/migrations/20260501000001_ephemeral_quick_game_guests.sql:52)) |
| `skins_groups.guest_roster_json` | Between-round snapshot | text (JSON-encoded array). Migration [20260510000000](../../supabase/migrations/20260510000000_skins_groups_guest_roster.sql). Matches `tee_times_json` pattern |

FKs on `round_players.player_id` and `scores.player_id` were dropped at [20260501000001:66-68](../../supabase/migrations/20260501000001_ephemeral_quick_game_guests.sql:66) — guest profile delete must NOT cascade-wipe history.

## `loadSingleGroup` rule

[GroupService.swift:1234-1240](../../Carry/Services/GroupService.swift:1234) comment block:

> Wiped guests (round_players UUIDs whose profiles no longer exist) are intentionally NOT synthesized into the group's roster — they belong to historical rounds only and are reconstructed inside `buildHomeRound`. Synthesizing them here would resurrect deleted players in current-roster views (Tee Times, Manage Members), violating the Carry-only rule.

Mechanism: `loadSingleGroup` only re-includes guest UUIDs in current roster if their profile still exists (via `round_players` backfill at [:1199-1208](../../Carry/Services/GroupService.swift:1199)). Wiped UUIDs filtered out.

## `loadSingleGroup` QG between-rounds backfill (added 2026-05-10)

Separate from the round_players backfill above. For Quick Games where **no** active/concluded/completed round exists (`backfillRoundDTO == nil`), `loadSingleGroup` synthesizes guests from `skins_groups.guest_roster_json` so the Games tab card pills + spectator views show the full roster across all QG states.

[GroupService.swift:1259-1275](../../Carry/Services/GroupService.swift:1259):

| Condition | Action |
|---|---|
| `group.isQuickGame == true` | Required (rule only applies to QGs) |
| `backfillRoundDTO == nil` | No qualifying round → round_players backfill skipped → synthesize from `guest_roster_json` instead |
| `group.guestRosterJson != nil` | Decode `[QuickGameGuestStorage.GuestSnapshot]` from the column |
| Filter | Skip ids already in `players` (avoid double-add) |
| Append | Synthesized guests added to `players` array (in-memory only, NOT written to DB) |

This does NOT violate the Carry-only `group_members` invariant — synthesized guests live only in the in-memory `SavedGroup.members` array, not in any DB table. They surface in the Games tab card pills and `SavedGroup` consumers but never get persisted to `group_members`.

## Games tab card pills — contract

🔒 **Pills are 1:1 with the in-app roster.** Every player visible in the GroupManagerView tee sheet must also appear as a pill on the Games tab card. No exceptions.

[GroupsListView.swift:1238](../../Carry/Views/GroupsListView.swift:1238) — pills source:
```swift
ForEach(group.members) { player in PlayerAvatar(player: player, size: 28) ... }
```

`group.members` is populated from FOUR paths. All four must respect the 1:1 contract for it to hold:

| # | Path | Where | Contract role |
|---|---|---|---|
| 1 | `loadSingleGroup` Carry-only base | [GroupService.swift:1113](../../Carry/Services/GroupService.swift:1113) | Carry users from `group_members` (always) |
| 2 | `loadSingleGroup` round_players backfill | [GroupService.swift:1213-1257](../../Carry/Services/GroupService.swift:1213) | Guests when active/concluded/completed round exists. Profiles still alive |
| 3 | `loadSingleGroup` between-rounds backfill | [GroupService.swift:1259-1275](../../Carry/Services/GroupService.swift:1259) | Guests synthesized from `guest_roster_json` when no qualifying round (post 2026-05-10) |
| 4 | `refreshGroupData` `localized.members` merge | [GroupManagerView.swift:1224-1233](../../Carry/Views/GroupManagerView.swift:1224) | Local QG guests merged into `localized` before pushing to parent. Covers the same-session window where local edits haven't round-tripped to `guest_roster_json` yet (post 2026-05-10) |

**By group state:**

| Group state | Sources used | Pills show |
|---|---|---|
| Skins Group (any state) | #1 only — Carry-only invariant | Carry users |
| Quick Game with active/concluded/completed round | #1 + #2 | All players |
| Quick Game between rounds (post-cancel, fresh setup), guest_roster_json populated | #1 + #3 | All players |
| Quick Game between rounds, guest_roster_json NULL but local guests in session | #1 + #4 (via refreshGroupData) | All players |
| Quick Game between rounds, guest_roster_json NULL AND fresh app launch (no local state) | #1 only | ❌ Carry only — irrecoverable for OLD pre-migration QGs whose round was cancelled before guest_roster_json was populated |

**Recovery for irrecoverable pre-migration QGs:** the user must re-add guests via PlayerGroupsSheet (which calls `QuickGameGuestStorage.save`, populating `guest_roster_json` going forward). Going forward, all guest mutations populate the column so the pill contract holds across sessions.

## `buildHomeRound` rule

[GroupService.swift:1565-1568](../../Carry/Services/GroupService.swift:1565) — when reconstructing a historical round, missing-profile UUIDs trigger the wiped-guest fallback.

**Lookup priority** (load-bearing — see [bug-archive 2026-05-10 "Guest profiles stale at round-start"](bug-archive.md)):

| Priority | Source | Used when |
|---|---|---|
| 1 | `round_players.guest_display_name` + `guest_handicap` | Denormalized by `delete_quick_game_guests` at termination — populated for any round terminated under the post-2026-05-01 ephemeral-guest rule |
| 2 | `QuickGameGuestStorage.load(groupId:)` matched by `profileId` | When (1) is NULL — typically legacy data, or any path that deleted guest profiles bypassing the RPC |
| 3 | Literal `"Guest"` + `0.0` | Last resort. **Never let this reach `Player.name` while ANY upstream source has data** — the literal is a corruption disease (see "Disease string" rule below) |

Debug log at [:1571](../../Carry/Services/GroupService.swift:1571):
```
[buildHomeRound] Added X players from profiles + Y wiped-guest fallbacks for round <UUID>
```

## Round-start reconciliation rule (added 2026-05-10)

The "guests are ephemeral PER ROUND" rule (see [Termination cleanup](#termination-cleanup) below) is only half the lifecycle. The symmetric rule:

> **Every round-start MUST reconcile guest profiles.** For each guest in the roster whose `profileId` doesn't exist server-side as `is_guest = true`, recreate it via `create_guest_profiles` and remap `Player.profileId` BEFORE inserting `round_players`.

Implemented at [RoundCoordinatorView.swift:430-503](../../Carry/Views/RoundCoordinatorView.swift:430). Without this, Restart Round → new round → round_players rows pointing at deleted profiles → `buildHomeRound` falls back to literal "Guest" → corruption.

Reconciliation MUST source canonical names + handicaps from `QuickGameGuestStorage` snapshot (matched by profileId, then by `Player.id`), NOT from in-memory `Player.name` — the in-memory roster may already be poisoned by a prior wiped-fallback run.

## Disease string rule

`"Guest"` + `0.0` is the wiped-fallback's last-resort literal at [GroupService.swift:1620](../../Carry/Services/GroupService.swift:1620). It is a contagious corruption vector. If it reaches `Player.name` and the user mutates the roster, `.onChange(of: groups)` fires `QuickGameGuestStorage.save` → snapshot now contains "Guest" → next reconciliation reads snapshot → creates a profile literally named "Guest" → denormalization writes "Guest" to `round_players` → corruption is server-side and irreversible.

Defenses (all must hold):

| Layer | Defense | File |
|---|---|---|
| Source | Wiped-fallback consults snapshot before substituting literal | [GroupService.swift:1589-1620](../../Carry/Services/GroupService.swift:1589) |
| Snapshot save | Filter out `name == "Guest"` or whitespace-only entries | [QuickGameGuestStorage.swift:save](../../Carry/Services/QuickGameGuestStorage.swift) |
| Snapshot load | Same filter on read (defense-in-depth for legacy payloads) | [QuickGameGuestStorage.swift:load](../../Carry/Services/QuickGameGuestStorage.swift) |
| Reconciliation | Pull names from snapshot, never from possibly-corrupted `Player.name` | [RoundCoordinatorView.swift:466-497](../../Carry/Views/RoundCoordinatorView.swift:466) |

If any one of these breaks, the corruption cycle re-opens.

## Guest profile edits — the four-layer persistence chain

🔒 Locked 2026-05-10. Any code change to PlayerGroupsSheet's edit flow, the `update_guest_profile` RPC, or the parent's onSave handler MUST preserve every layer below. Removing or weakening any one re-opens the silent-revert bug class (skins payouts depend on handicap; renamed guests showing wrong names is visible everywhere).

### The chain

```
User taps picker / types name in PlayerGroupsSheet
    ↓
groups[i][j].handicap (or .name + .initials) mutates  [LOCAL]
    ↓
User taps Save
    ↓
buildResult() reconciles allMembers ← cleanGroups     [LAYER 1]
    ↓
onSave fires in GroupManagerView
    ↓
allMembers = result.allMembers (now consistent)
guestProfileEditsLastSavedAt = Date()                  [LAYER 4 stamp]
QuickGameGuestStorage.save(...)                        [snapshot]
Task { for changed: updateGuestProfile RPC }           [LAYER 2 + 3]
    ↓
(refresh fires, possibly before RPC replicates)
    ↓
filteredFreshMembers patched: local handicap/name      [LAYER 4 guard]
preserved if stamp is <8s old
    ↓
allMembers reflects edit even before server replicates
    ↓
Once RPC replicates:
profiles.display_name + profiles.handicap = NEW
Refresh pulls NEW from server, matches local, no-op
```

### Layer 1 — `buildResult()` reconciles allMembers from groups

[PlayerGroupsSheet.swift:1422+](../../Carry/Views/PlayerGroupsSheet.swift:1422). Sheet edits only mutate `groups[i][j]`, NOT the sheet's separate `allMembers` @State. Without this reconciliation, `result.allMembers` arrives at the parent with stale name/handicap, and any caller diffing old-vs-new sees no change. Reconciles via id-match between `cleanGroups` and `allMembers`.

**Invariant:** `result.allMembers[i]` MUST reflect the latest values from `cleanGroups` for every player whose id matches.

### Layer 2 — server RPC `update_guest_profile`

[20260510000001_update_guest_profile_handicap.sql](../../supabase/migrations/20260510000001_update_guest_profile_handicap.sql). SECURITY DEFINER; bypasses RLS but enforces `created_by = auth.uid()` AND `is_guest = true`.

| Field | Behavior |
|---|---|
| `p_display_name` | Optional. UPDATEs `profiles.display_name`. Auto-derives `initials` if `p_initials` is NULL |
| `p_initials` | Optional. UPDATEs `profiles.initials` |
| `p_handicap` | Optional. UPDATEs `profiles.handicap` |

**Carry-user protection (load-bearing):** `WHERE id = p_profile_id AND is_guest = true` on the UPDATE. Even if iOS sends a Carry user's UUID (because of a bug somewhere), the UPDATE matches zero rows. **This is the structural reason a Carry user's `profiles.handicap` cannot be silently overwritten via this path.** The auth `EXISTS` check raises an exception in addition; both protections must remain.

### Layer 3 — iOS persistence in onSave

[GroupManagerView.swift:2196+](../../Carry/Views/GroupManagerView.swift:2196). The save handler is the canonical persistence point. Pseudo-flow:

| Step | Action |
|---|---|
| 1 | Snapshot OLD guest name+handicap from `allMembers` (before overwrite) |
| 2 | Overwrite `allMembers = result.allMembers` (which Layer 1 made consistent) |
| 3 | Stamp `guestProfileEditsLastSavedAt = Date()` (BEFORE async writes) |
| 4 | `QuickGameGuestStorage.save(...)` — UserDefaults + server snapshot |
| 5 | Diff old vs new for guests with `isGuest && profileId != nil` |
| 6 | For each changed: `updateGuestProfile(profileId:displayName:handicap:)` (one RPC call per guest, only fields that changed) |

**Filter rule:** the diff loop `.filter { $0.isGuest }` is a defense-in-depth. The RPC's WHERE clause is the actual guarantee. Both must remain.

### Layer 4 — race guard (6th instance)

[GroupManagerView.swift:850+](../../Carry/Views/GroupManagerView.swift:850). Pattern: `<field>LastSavedAt` stamp + 8s window in `refreshGroupData`'s `filteredFreshMembers` patch.

```swift
let isGuestProfileEditsRecent = guestProfileEditsLastSavedAt.map { Date().timeIntervalSince($0) < 8 } ?? false
if isQuickGame, isGuestProfileEditsRecent {
    // Patch filteredFreshMembers' guests with local name/initials/handicap
    // for any matched profileId
}
```

**Invariant:** in the window between save and replication, refresh MUST preserve local guest values, not pull stale server state.

### Why all four are needed

| Missing layer | What breaks |
|---|---|
| Layer 1 (allMembers reconciliation) | Diff sees no change, RPC never fires, edit silently reverts |
| Layer 2 (RPC) | No way for creator to UPDATE a guest's profile (RLS forbids direct UPDATE), edit local-only, refresh stomps |
| Layer 3 (onSave persistence) | Local edit, no server write, refresh stomps |
| Layer 4 (race guard) | Refresh during RPC replication window stomps the just-edited value |

### Carry-user protection summary

Two structural barriers prevent guest-edit code from touching a Carry user's profile.handicap:

| Barrier | Where | What it does |
|---|---|---|
| iOS filter | [GroupManagerView.swift onSave](../../Carry/Views/GroupManagerView.swift) — `result.allMembers.compactMap { ... guard p.isGuest ... }` | Excludes Carry users from the diff |
| SQL WHERE clause | [migration L66](../../supabase/migrations/20260510000001_update_guest_profile_handicap.sql:66) `WHERE id = p_profile_id AND is_guest = true` | Even if a Carry UUID slipped through, UPDATE matches zero rows |

The SQL barrier is the load-bearing one — iOS bugs cannot bypass it.

## Termination cleanup

`GuestProfileService.deleteQuickGameGuests(roundId:)` ([GuestProfileService.swift:38-44](../../Carry/Services/GuestProfileService.swift:38)) → server RPC `delete_quick_game_guests(p_round_id)` ([20260501000001:80-142](../../supabase/migrations/20260501000001_ephemeral_quick_game_guests.sql:80)).

| Step | Action |
|---|---|
| 1 | Auth check: round creator only |
| 2 | Denormalize `display_name` + `handicap` onto `round_players` |
| 3 | Denormalize same onto `scores` |
| 4 | DELETE `profiles` rows where `is_guest = true` and matching `round_players.player_id` |

Triggered from:
| Caller | Event |
|---|---|
| `RoundService.deleteRound` | Cancel/restart |
| End Game (destructive) | Force end with score wipe |
| End & Save Results | Force end keeping results |
| `convert_quick_game_to_group` | Conversion (calls inline) |

| Survives wipe | Wiped |
|---|---|
| `round_players` UUIDs + denormalized fields | `profiles` row |

## Client-side state buckets

| Bucket | Init | Mutated by |
|---|---|---|
| `allMembers` @State | From `initialMembers` (parent) | `refreshGroupData` (overwrites with server snapshot + preservedGuests filter) |
| `guests` @State | Empty | `addGuest()`, PlayerGroupsSheet save, restore-from-snapshot via `.onAppear` |

Union: `allAvailable = allMembers + guests` (deduped by id) at [GroupManagerView.swift:295](../../Carry/Views/GroupManagerView.swift:295).

Preservation across refreshes: [GroupManagerView.swift:850-855](../../Carry/Views/GroupManagerView.swift:850) — `refreshGroupData` filters `allMembers` for guests pre-replace, re-merges post. Skins Groups skip.

## Two-layer persistence (post 2026-05-10)

| Layer | Purpose | Survives |
|---|---|---|
| `UserDefaults` key `quickGameGuests_<uuid>` | Fast local read on app open | Process death, force-quit, OS reap, App Store updates |
| `skins_groups.guest_roster_json` jsonb | Durable + multi-device | All of above + app delete + new device |

[QuickGameGuestStorage.swift](../../Carry/Services/QuickGameGuestStorage.swift) API:

| Method | Purpose |
|---|---|
| `save(groupId, isQuickGame, allRosterPlayers)` | Filter to guests only, dedupe, encode JSON; write UserDefaults sync + fire async debounced server write via `GroupService.saveGuestRoster` |
| `load(groupId)` | Decode UserDefaults → `[Player]` |
| `hydrateFromServer(groupId, json)` | Write server payload into UserDefaults, gated by `quickGameGuests_<uuid>_savedAt` 8s race-guard |
| `clear(groupId)` | Remove UserDefaults entry + fire async server NULL write |

Save call sites in GroupManagerView:
- `.onAppear` (capture initial state)
- `addGuest()` post-append
- PlayerGroupsSheet `onSave` post-update
- `.onChange(of: groups)` (post 2026-05-10) — drag-and-drop persistence for QG guests

Hydrate site:
- `.onAppear` restores into `allMembers` (NOT `guests` — preservedGuests filter targets `allMembers`)
- **Override (post 2026-05-10):** `.onAppear` ALSO overrides `Player.group` on guest entries already in `allMembers`/`guests` from saved snapshot. Necessary because parent's `group.members` (= `initialMembers`) may carry stale `Player.group` from before the user's last edit if the server-write race hadn't resolved when parent last refreshed. UserDefaults is local truth (synchronous write)
- Server hydration happens earlier in `loadSingleGroup` (see Server hydrate)

Clear site: `onChange(of: isQuickGame)` true → false (conversion). NOT yet wired from group-delete path; server NULL via `delete_group` RPC cascade (verify on dev).

## Server hydrate

`loadSingleGroup` reads `group.guestRosterJson`. When `isQuickGame == true`, calls `QuickGameGuestStorage.hydrateFromServer(groupId:json:)` BEFORE GroupManagerView mounts, gated by 8s race-guard window. By the time `.onAppear` runs, `load(groupId)` returns server-truth.

Race rules:
| Scenario | Behavior |
|---|---|
| Two devices edit roster concurrently | Last-write-wins, no CRDT |
| Async server write fails | UserDefaults reflects change. Retries 3× (1s, 2s, 4s). On final failure, re-stamp `lastSavedAt` to extend hydrate guard. Self-heals on next successful save |

See [refresh-race-guards.md](refresh-race-guards.md) §5 for the race-guard pattern.

## Two-layer rationale

| Approach | Latency | Durability | Multi-device |
|---|---|---|---|
| UserDefaults only (pre 2026-05-10) | Fast | Lost on app delete | No |
| Server only | Slow (network on every paint) | Yes | Yes |
| Both (current) | Fast (UserDefaults paints) | Yes (server is backup) | Yes |

The `guest_roster_json` column does NOT violate the ephemeral-guest rule. It holds a snapshot (name, handicap, display fields) — no auth artifact, no FK target. When a round starts, fresh guest profiles are created from the snapshot.

## "Ghost guests" historical bug (2026-05-01)

Pre-fix: `loadSingleGroup` rebuilt current roster from `group_members` + `round_players`, including missing-profile UUIDs from `round_players`. Wiped guests reappeared in Manage Members + Tee Times.

Fix: split `loadSingleGroup` (Carry-only filter) vs `buildHomeRound` (wiped-guest fallback for historical render). Architectural invariant locked.

Test coverage: indirect — "absence of ghost guests in current roster" production observation. See [testing.md:75](../testing.md:75).

## Common bugs / gotchas

| Bug | Cause | Fix |
|---|---|---|
| Hydrate into wrong bucket | Restoring snapshot guests to `guests` @State (not `allMembers`) → `preservedGuests` filter misses them, they disappear after seconds | Hydrate into `allMembers`. Shipped 2026-05-09 |
| Snapshot timing on QuickStartSheet creation | First `.onAppear` save captures guests from `initialMembers` (via SavedGroup from `handleQuickGameCreate`); without it, fresh guests not snapshotted until first `addGuest` | Existing |
| Conversion forgets to clear snapshot | Without `onChange(of: isQuickGame)` clear, restored guests resurrect on Skins Group setup view → violates Carry-only invariant client-side | Existing |
| Server hydrate clobbers just-added guest | Without the race guard, navigate-out + back during debounce window stomps the local change | `quickGameGuests_<uuid>_savedAt` 8s guard. Shipped 2026-05-10 |

## Last verified

2026-05-10 — added round-start reconciliation rule + disease-string rule + lookup-priority chain (resolves "Guest"+0.0 corruption cycle). Plus four-layer persistence chain for guest profile edits + Carry-user protection summary (resolves the silent-handicap-reversion bug class). See [bug-archive](bug-archive.md).
