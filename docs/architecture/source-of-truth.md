# Source of Truth

**TL;DR:** When a field misbehaves (silent revert, stale display, write doesn't stick), this doc tells you WHERE the canonical value lives, WHO can write it, and what guards/race protections exist. One-stop debug reference.

🔒 Locked 2026-05-10. Every user-editable persisted field MUST have a row here. When adding a new editable field, append it before merging — see [playbook.md §Pre-flight checklist](playbook.md).

## The four-question framework

When a value behaves oddly, ask:

1. **Where does it live canonically?** (table.column / pre-serialized JSON / UserDefaults / @State)
2. **Who/what can write it?** (RLS policy or RPC, plus the iOS save site)
3. **What reads it on display?** (the iOS path that pulls into a Player struct or @State)
4. **What guards it during the write→replicate→read window?** (race guard? defense-in-depth filter?)

If any of those answers is unclear when reading the code, the doc is incomplete — fix the doc as part of your change.

## Profile fields (`profiles` table)

| Field | Canonical store | Who can write | Write path | Read path | Race guard |
|---|---|---|---|---|---|
| `display_name` (Carry user) | `profiles.display_name` | Owner only (RLS `auth.uid() = id`) | [ProfileSheetView.swift:1166](../../Carry/Views/ProfileSheetView.swift:1166) (full save) / [:1438](../../Carry/Views/ProfileSheetView.swift:1438) | `Player(from: profile)` in buildHomeRound, refreshGroupData | None — own-profile only, no cross-write |
| `display_name` (Guest) | `profiles.display_name` | Creator only via RPC (`is_guest = true` clause) | [GroupManagerView.swift:2196+ onSave](../../Carry/Views/GroupManagerView.swift:2196) → `update_guest_profile` RPC | Same — `Player(from: profile)` | `guestProfileEditsLastSavedAt` 8s — see [guest-lifecycle.md §"four-layer persistence chain"](guest-lifecycle.md) |
| `handicap` (Carry user) | `profiles.handicap` | Owner only | [ProfileSheetView.swift:371](../../Carry/Views/ProfileSheetView.swift:371) | `Player(from: profile)` | None |
| `handicap` (Guest) | `profiles.handicap` | Creator only via RPC | Same as guest display_name path | Same | Same — `guestProfileEditsLastSavedAt` |
| `initials` | `profiles.initials` | Auto-derived from display_name (server-side in RPC; iOS in [PlayerGroupsSheet.swift:guestNameBinding](../../Carry/Views/PlayerGroupsSheet.swift)) | Tracks display_name | Same | Same |
| `phone` | `profiles.phone` | Owner only | [ProfileSheetView.swift:1341](../../Carry/Views/ProfileSheetView.swift:1341) + [PhoneInviteFinderSheet.swift:279](../../Carry/Views/PhoneInviteFinderSheet.swift:279) | `phone-invite reconcile triggers` (server) — see [group-invitation-flow.md](group-invitation-flow.md) | Server triggers reconcile invites |
| `home_club` / `home_club_id` / `is_club_member` | `profiles.{home_club,home_club_id,is_club_member}` | Owner only | [ProfileSheetView.swift:1703](../../Carry/Views/ProfileSheetView.swift:1703) | Profile read only | None |
| `ghin_number` | `profiles.ghin_number` | Owner only | [ProfileSheetView.swift:1438](../../Carry/Views/ProfileSheetView.swift:1438) | Profile read only | None |
| `avatar_url` | `profiles.avatar_url` | Owner only | [ProfileSheetView.swift:508](../../Carry/Views/ProfileSheetView.swift:508) (set) / [:530](../../Carry/Views/ProfileSheetView.swift:530) (clear) | `Player(from: profile)` | None |
| `notification_prefs_*` | `profiles.notification_prefs_*` | Owner only | [ProfileSheetView.swift:1834](../../Carry/Views/ProfileSheetView.swift:1834) (`pushPref`) | Server-side `notify_push` reads — see [push-trigger-chain.md](push-trigger-chain.md) | None |
| `is_guest` | `profiles.is_guest` | Set on creation only (via `create_guest_profiles` or default false). **Never UPDATEd post-INSERT** | [GuestProfileService.createGuestProfiles](../../Carry/Services/GuestProfileService.swift) | All guest-related code paths | Architectural — never mutated, no race possible |
| `created_by` (Guest creator) | `profiles.created_by` | Set on creation, immutable | Same as is_guest | Used by `update_guest_profile` and `delete_quick_game_guests` auth checks | Architectural |

## Skins Group fields (`skins_groups` table)

| Field | Canonical store | Who can write | Write path | Read path | Race guard |
|---|---|---|---|---|---|
| `name` | `skins_groups.name` | Creator only (RLS) | [GroupManagerView Game Options onSave](../../Carry/Views/GroupManagerView.swift:1995) → `updateGroup` | `loadSingleGroup` | None — direct, immediate |
| `buy_in` | `skins_groups.buy_in` | Creator only | Same Game Options path | Same | None |
| `handicap_percentage` (Index Allowance) | `skins_groups.handicap_percentage` | Creator only | Same Game Options path | Same | `handicapPercentageLastSavedAt` 8s — see [refresh-race-guards.md §3](refresh-race-guards.md) |
| `winnings_display` ('gross'/'net') | `skins_groups.winnings_display` | Creator only | Same | Same | None |
| `recurrence` | `skins_groups.recurrence` (text JSON) | Creator only | Same Game Options path / picker sheet | Same | None |
| `tee_times_json` | `skins_groups.tee_times_json` (text JSON) | Creator only — **single writer rule** (only the per-group tee-time picker writes; Game Options doesn't touch it) | Per-group picker Done button | `loadSingleGroup` decode | `teeTimesLastSavedAt` 8s — see [tee-time-sovereignty.md](tee-time-sovereignty.md) |
| `scorer_ids` (jsonb) | `skins_groups.scorer_ids` | Creator OR per-group scorer (depends on UI path) | PlayerGroupsSheet save | `loadSingleGroup` | `scorerIdsLastSavedAt` 8s — see [refresh-race-guards.md §1](refresh-race-guards.md) |
| `is_quick_game` | `skins_groups.is_quick_game` | Set at creation. UPDATE only via `convert_quick_game_to_group` RPC | `convert_quick_game_to_group` | Read everywhere | Architectural — atomic conversion only |
| `holes_json` (course/teebox holes) | `skins_groups.holes_json` (text JSON) | Creator (via course-selection persistence) | `persistCourseSelection` | buildHomeRound + `fetchPersistedHoles` safety net | None — course changes are rare |
| `last_tee_box_id` / `last_course_id` | `skins_groups.last_*` | Creator | Course selection sheet | Used to restore preselected tee box on group entry | None |
| `guest_roster_json` (QG only) | `skins_groups.guest_roster_json` (text JSON) | Creator — debounced server write from `QuickGameGuestStorage.save` | UserDefaults stamp + retry | `loadSingleGroup` hydrate | `quickGameGuests_<uuid>_savedAt` 8s — see [refresh-race-guards.md §5](refresh-race-guards.md) |
| `created_by` | `skins_groups.created_by` | Set at INSERT, **never UPDATEd** | INSERT only | RLS uses for creator gates | Architectural |
| `scheduled_date` / `tee_time_interval` | `skins_groups.scheduled_date` / `_tee_time_interval` | Creator | Tee-time picker / Game Options date | `loadSingleGroup` | None (covered by tee-time guard transitively) |

## Round fields (`rounds` table)

| Field | Canonical store | Who can write | Write path | Read path | Race guard |
|---|---|---|---|---|---|
| `status` ('active'/'concluded'/'completed'/'cancelled') | `rounds.status` | Creator only | `RoundService.updateRoundStatus`, `endGameDestructively`, `forceEndRoundWithResults`, `deleteRound` | `loadSingleGroup`, `buildHomeRound` | None — state machine (see [round-lifecycle.md](round-lifecycle.md)) |
| `force_completed` | `rounds.force_completed` | Creator only | `endGameDestructively`, `forceEndRoundWithResults` | Read everywhere | None |
| `scoring_mode` | `rounds.scoring_mode` | Creator at round start | `createRound` | Read for scorer gate | None — set at INSERT |
| `is_quick_game` (denormalized) | `rounds.is_quick_game` | Set at INSERT from group | `createRound` | Read for QG-specific UI | None |
| `tee_box_id` / `course_id` | `rounds.tee_box_id` / `course_id` | Set at INSERT | `createRound` | Read for handicap math | None |

## Round-player fields (`round_players` table)

| Field | Canonical store | Who can write | Write path | Read path | Race guard |
|---|---|---|---|---|---|
| `group_num` (tee-group assignment) | `round_players.group_num` | Creator (drag) — debounced | `syncGroupNumsToSupabase` after `.onChange(of: groups)` | `buildHomeRound`, refreshGroupData | `groupNumLastSavedAt` 8s — see [refresh-race-guards.md §4](refresh-race-guards.md) |
| `sort_order` | `round_players.sort_order` | Same as group_num | Same | Same | Same guard |
| `guest_display_name` / `guest_handicap` (denormalized) | `round_players.guest_*` | Set by `delete_quick_game_guests` RPC at termination | RPC | `buildHomeRound` wiped-fallback ([:1599](../../Carry/Services/GroupService.swift:1599)) | None — written once, read on history |

## Group-member fields (`group_members` table — Carry-only)

| Field | Canonical store | Who can write | Write path | Read path | Race guard |
|---|---|---|---|---|---|
| `status` ('active'/'invited'/'declined'/'removed') | `group_members.status` | Creator OR self (RLS) | `inviteMember`, member self-leave/decline | `fetchGroupMembers`, refreshGroupData | None |
| `invited_phone` | `group_members.invited_phone` | Set at invite, reconciled by triggers | INSERT | RLS / phone-invite reconcile triggers — see [group-invitation-flow.md](group-invitation-flow.md) | Server triggers |
| Toast baseline (per-device, not server) | `UserDefaults.seenActiveMemberPlayerIds_<groupId>` | Refreshes update | `refreshGroupData` toast block | Same block on next refresh | Transient-empty guard (see [manage-members.md §"Toast baselines"](manage-members.md)) |

## Score fields (`scores` table)

| Field | Canonical store | Who can write | Write path | Read path | Race guard |
|---|---|---|---|---|---|
| `gross_strokes` | `scores.gross_strokes` | Round participants (RLS) | `ScoreStorage.upsertScore` | `RoundService.fetchScores`, realtime subscription | Idempotent UPSERT (see [score-pipeline.md](score-pipeline.md)) |
| `guest_display_name` / `guest_handicap` (denormalized) | `scores.guest_*` | `delete_quick_game_guests` RPC | RPC | Render path | Architectural |

## Local-only state (no server canonical store)

These are device-local. Loss is acceptable; they don't affect skins math or persistence guarantees.

| Field | Store | Used for |
|---|---|---|
| `recentlyRemovedIds` | @State (per view instance) | Refresh race guard — drops just-removed members from refresh result |
| `disclaimerAccepted` | UserDefaults | Onboarding gate (mirrored from server `is_onboarded`) |
| Coachmark `seen` flags | UserDefaults | One-time hint dismissal |
| `pendingConvertGroupId` | AppRouter @State | Cross-tab navigation handoff (Bug A) |

## How to use this doc

| Symptom | First step |
|---|---|
| "Edit doesn't stick" | Find field → check write path is wired AND race guard exists |
| "Wrong user's value got changed" | Check who-can-write column → verify RLS or RPC WHERE clause prevents cross-user writes |
| "Value reverts on refresh" | Check race guard — is it stamped? Is it consulted in `filteredFreshMembers` patch? |
| "Field missing from server" | Check write path — is there an actual server INSERT/UPDATE call, or only local @State mutation? |
| "Cross-device inconsistency" | Check canonical store — is the field server-resident? If only UserDefaults, it's expected |

## Adding a new editable field

1. Add a row to the right table above (profiles / skins_groups / rounds / round_players / group_members / scores)
2. If it's editable by a non-owner: write a SECURITY DEFINER RPC mirroring `update_guest_profile` (auth check + WHERE clause restricting targets)
3. If a user-edit refresh race exists: add a 7th instance to [refresh-race-guards.md](refresh-race-guards.md), wire the stamp + check
4. Verify the buildResult/save handler reconciles all fields from the canonical local state (no stale @State source like the [PlayerGroupsSheet allMembers bug](bug-archive.md))
5. Run the citation audit — all `file:line` references in the new row must resolve

## Last verified

2026-05-10 — initial creation. Captures all editable persisted fields known to the audit pass that surfaced the silent-handicap-reversion bug class.
