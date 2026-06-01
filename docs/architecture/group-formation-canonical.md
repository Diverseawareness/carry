# Group Formation — Canonical Source of Truth (refactor target 2026-05-10)

**Status:** target architecture; minimal-risk version executed 2026-05-10. **Sufficiency reviewed 2026-05-31 — reconciler is HOLDING; full refactor NOT needed (see below).**

## Sufficiency review (2026-05-31) — is the reconciler enough?

This doc's open question was: *"verify the reconciler is enough before doing the full collapse."* Reviewed against the bug archive + a mutation-site audit. **Verdict: the minimal reconciler is sufficient. Do NOT escalate to the full `commitGroupsChange` migration.**

Evidence:
- **Timeline:** Every drift-class bug in [bug-archive.md](bug-archive.md) (edit-reverts, drag-snap-back, guest-resurrect, pills-mismatch, stale `Player.group`) is dated **on or before 2026-05-10**, when the reconciler shipped. **Zero drift-class regressions are dated after it.** The class stopped recurring.
- **No bypass paths:** all `groups = …` assignments (regroup, refresh-rebuild, refresh-fallback, PlayerGroupsSheet onSave, swap) and the drop-handler array mutations trigger `.onChange(of: groups)` via SwiftUI value-type tracking → the reconciler always runs. The "every mutation goes through one path" guarantee the full refactor would enforce is already met in practice.
- **The 1.1.2 duplicate-guest bug was NOT a counter-example.** Its root cause was guest *identity instability* (server minted a fresh UUID on each recreate → two `stableId`s for one human), fixed by the stable-UUID architecture. That's orthogonal to `Player.group`-vs-index drift; the reconciler never claimed to cover identity. Don't read it as a reconciler leak.

Follow-up — **DONE 2026-05-31.** The reconciler's normalization is extracted to a pure `static func GroupManagerView.normalizedGroupNums(_:)` ([GroupManagerView.swift:345](../../Carry/Views/GroupManagerView.swift:345)) — the `.onChange(of: groups)` handler calls it verbatim (behavior unchanged, build + full suite green). The `Player.group == arrayIndex + 1` invariant is now guarded by [GroupFormationReconcilerTests.swift](../../CarryTests/GroupFormationReconcilerTests.swift) across drop / regroup-collapse / swap / refresh-rebuild / idempotence / empty-group shapes, so the pre-push hook catches any future regression of the drift class.

## What was actually shipped (2026-05-10)

The full refactor in this doc would touch ~12 mutation sites across multiple files. Per the user's "we cannot change anything that breaks something else" rule, the executed version is minimal:

- `groups[][]` remains canonical for tee-group arrangement
- `Player.group` is auto-corrected to match index via the `.onChange(of: groups)` reconciler at [GroupManagerView.swift:2875-2954](../../Carry/Views/GroupManagerView.swift:2875)
- Mutation sites stay as-is (drop handler, regroup, refresh rebuild, swap, moveGroup) — they don't need to update `Player.group` themselves
- The reconciler does a self-stable rewrite: if any player's `.group` doesn't match index, it rewrites `groups` with corrected values and early-returns (SwiftUI re-fires `.onChange`); on the re-fire, no rewrite is needed and the rest of the handler runs (mirror to `allMembers`/`guests`, persist QG snapshot, schedule server sync)
- This is functionally equivalent to forcing every mutation site through `commitGroupsChange` but without rewriting any mutation site

The full migration plan below remains the long-term target if the reconciler approach proves insufficient.

**Why this exists:** the previous architecture had 8 parallel structures (`groups[][]`, `allMembers`, `guests`, `Player.group`, `group_members.group_num`, `round_players.group_num`, `skins_groups.guest_roster_json`, UserDefaults `quickGameGuests_<uuid>`). Every mutation needed to update most of them; every read consulted a different subset. Drift between structures produced a steady stream of regressions (Bug #0, the QG guest persistence chain, the pill display gaps). Each "fix" added more sync code, which added more drift surface. The refactor collapses to a single canonical source per concern.

## Canonical sources

| Concern | Canonical source | Everything else |
|---|---|---|
| **Tee-sheet arrangement (which player is in which group)** | `groups: [[Player]]` @State in GroupManagerView | Derived from `groups[][]`'s outer-array index |
| **Per-player group_num** | The player's index in `groups[][]` (+ 1) | `Player.group` field is redundant — kept for compatibility but never set directly; always derived |
| **Visible roster (everyone the user sees)** | `groups.flatMap { $0 }` (a computed property, NOT @State) | `allMembers` becomes a computed property over groups + deselected pool + pending pool |
| **Selection state** | `selectedIDs: Set<Int>` @State | Independent — players in `selectedIDs` but not in `groups[][]` are the deselected pool |
| **Pending invitees (not yet visible in tee sheet)** | `pendingPool: [Player]` @State (NEW) | Players awaiting accept; rendered separately in Manage Members; not in `groups[][]` |
| **Per-group scorer** | `scorerIDs: [Int]` @State | One Int per group; index aligns with `groups[][]` outer array |
| **Server tee-group state** | `group_members.group_num` (Carry-only) + `round_players.group_num` (incl. guests for active rounds) | Mirrored from `groups[][]` via single `syncGroupArrangementToServer()` function |
| **Server between-rounds guest snapshot** | `skins_groups.guest_roster_json` (jsonb) | Mirrored from `groups[][]` (filtering for guests) via single function |
| **iOS local guest cache** | UserDefaults `quickGameGuests_<uuid>` | Same source as above; written synchronously |

## Mutation rule

🔒 **Single mutation path: `commitGroupsChange(_ newGroups: [[Player]])`.**

Every change to tee-sheet arrangement goes through this function. Direct assignment to `groups` is forbidden outside this function.

```swift
private func commitGroupsChange(_ newGroups: [[Player]]) {
    // 1. Stamp race guard
    groupNumLastSavedAt = Date()

    // 2. Update Player.group on each player to match new arrangement
    var withGroupNums = newGroups
    for (idx, _) in withGroupNums.enumerated() {
        for j in withGroupNums[idx].indices {
            withGroupNums[idx][j].group = idx + 1
        }
    }

    // 3. Trim trailing empty groups but preserve at least one
    while withGroupNums.last?.isEmpty == true && withGroupNums.count > 1 {
        withGroupNums.removeLast()
    }

    // 4. Single state assignment
    groups = withGroupNums

    // 5. For QGs, persist guest snapshot (writes UserDefaults sync + server async via debounced task)
    if isQuickGame, let groupId = supabaseGroupId {
        QuickGameGuestStorage.save(
            groupId: groupId,
            isQuickGame: true,
            allRosterPlayers: visibleRoster
        )
    }

    // 6. Schedule debounced server sync of group_members + round_players group_num
    scheduleServerArrangementSync()
}
```

Callers:
- Drag-and-drop in `GroupDropDelegate.performDrop`
- `regroup()` (recompute via autoGroup)
- `addGuest()` post-append
- `PlayerGroupsSheet.onSave` post-update
- `Manage Members` add/remove flows
- `refreshGroupData` rebuild branch (server-driven)

Forbidden:
- Direct `groups = ...` outside `commitGroupsChange`
- Mutating `groups[i].append(...)` or `groups[i].remove(...)` outside `commitGroupsChange`

## Computed properties (NOT @State)

```swift
/// Everyone the user sees on the tee sheet right now.
var visibleRoster: [Player] {
    groups.flatMap { $0 }
}

/// Carry users in the visible roster.
var visibleCarryUsers: [Player] {
    visibleRoster.filter { $0.profileId != nil && !$0.isGuest }
}

/// Guests in the visible roster.
var visibleGuests: [Player] {
    visibleRoster.filter { $0.isGuest }
}
```

These replace `allMembers` and `guests` @State. The compiler enforces freshness — every read computes from the current `groups[][]`.

## Read rule

| Consumer | What they need | Where they get it |
|---|---|---|
| Tee-sheet UI | The 2D arrangement | `groups[][]` directly |
| Pills on Games tab card | Full visible roster | `SavedGroup.members` (mirrored from `groups[][]` via `onGroupRefreshed`) |
| Scorecard | Active round's player list | `RoundConfig.players` (built from `groups[][]` at round start) |
| Pops display | Per-player group + pops | `groups[][]` directly |
| Manage Members sheet | Visible + pending pools | `visibleRoster` (computed) + `pendingPool` (separate @State) |
| Server sync | Each player's `group_num` | `groups[][]` via `commitGroupsChange` |

No consumer reads `Player.group` directly. No consumer reads `allMembers` (it's gone). No consumer reads `guests` (it's gone).

## Refresh path

`refreshGroupData` becomes:

```swift
1. Fetch via loadSingleGroup → freshGroup
2. Filter recentlyRemovedIds
3. Build pendingPool from freshGroup's pending invitees
4. If groupNumLastSavedAt is recent (<8s):
     - Skip rebuild — keep local groups[][]
   Else:
     - Rebuild groups[][] from server's group_num for each player
       (Carry users from group_members; guests from round_players if active OR guest_roster_json if between-rounds)
     - Call commitGroupsChange(rebuilt)  — single state update
5. Push localized SavedGroup to parent (members = visibleRoster + pendingPool)
```

The race guard remains — it gates whether to rebuild from server. Once we decide to rebuild, the rebuild itself goes through `commitGroupsChange`.

## Migration plan

The refactor is incremental. Each step keeps the build + tests green.

| Step | Action | Risk |
|---|---|---|
| 1 | Add `commitGroupsChange(_:)` function. Don't call it yet | None — additive |
| 2 | Replace direct `groups = X` with `commitGroupsChange(X)` one site at a time | Low — same behavior, just wrapped |
| 3 | Move `Player.group` mirroring into `commitGroupsChange` (delete the .onChange handler) | Low — simpler code |
| 4 | Replace `allMembers` @State with computed property | Medium — touches every read site |
| 5 | Replace `guests` @State with computed property | Medium — same |
| 6 | Add `pendingPool` @State for non-visible pending invitees | Medium |
| 7 | Audit `refreshGroupData` for any remaining direct group mutations | Low |
| 8 | Delete `.onChange(of: groups)` (logic now in `commitGroupsChange`) | None — code that's been moved |
| 9 | Run full test suite | Verification |

## Site inventory (mutation points to convert)

To be filled during step 2 of the migration.

| File:line | Current code | Replacement |
|---|---|---|
| GroupManagerView.swift `regroup()` | `groups = Self.autoGroup(playing)` | `commitGroupsChange(Self.autoGroup(playing))` |
| GroupManagerView.swift drop handler | `groups[sourceGroup].removeAll`, `groups[groupIndex].append`, `groups.removeAll { isEmpty }` | Build new arrangement, then `commitGroupsChange(...)` |
| GroupManagerView.swift `addGuest()` | direct mutation | `commitGroupsChange(...)` |
| GroupManagerView.swift refresh rebuild branch | `groups = rebuilt` | `commitGroupsChange(rebuilt)` |
| PlayerGroupsSheet.swift various | per-binding mutations | onSave returns new arrangement; parent calls `commitGroupsChange` |

## Test invariants (added with the refactor)

| # | Invariant | Test |
|---|---|---|
| 1 | After `commitGroupsChange`, every player's `Player.group == its index in groups[][] + 1` | Unit test |
| 2 | After drag, `Player.group` on the moved player matches new array index | Unit test |
| 3 | `commitGroupsChange` writes UserDefaults synchronously for QGs | Unit test |
| 4 | `visibleRoster.count == groups.flatMap { $0 }.count` | Computed property test |
| 5 | Pills shown on Games tab card == `visibleRoster.count` for the corresponding group | Integration test |

## Success criteria

| Criterion | How verified |
|---|---|
| Drag-and-drop sticks across nav-out + back | Manual device test |
| Drag-and-drop sticks across 30s refresh | Manual device test |
| Pills show 1:1 with in-app roster regardless of QG round state | Manual device test |
| All existing Swift tests pass | Test suite |
| Citation script: 0 broken | Script |

## Last verified

2026-05-10 — refactor target written; minimal reconciler shipped.
2026-05-31 — sufficiency review: reconciler holding, full refactor deferred (no drift regressions post-2026-05-10). Reconciler citation re-anchored to current line range (:2875-2954).
