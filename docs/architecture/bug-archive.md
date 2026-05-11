# Bug Archive

**TL;DR:** Every prod regression of consequence, listed with symptom → root cause → fix → blueprint that should have prevented it (or "new rule discovered, blueprint X created"). Use this when a new bug looks familiar — find the prior one, check whether it regressed vs. is a new variant. Use it during retro to spot patterns.

**Discipline:** when a fix lands, add an entry here. Cite the commit. Tag the blueprint. If no blueprint maps cleanly, that's a doc gap — add or update one.

---

## 2026-05-10 — Guest profile edits silently revert on refresh (handicap + name)

| Field | Value |
|---|---|
| Symptom | In a Quick Game, edit a guest player's name or handicap via the players sheet → save → values show correct briefly. Within 30 seconds (or after any refresh-triggering action like changing the index allowance), edit reverts to the original value. Skins payouts were silently wrong (handicap-weighted), and renamed guests appeared with their old name in pills/scorecard |
| Root cause | TWO compounding bugs: (1) **No server write.** PlayerGroupsSheet's onSave handler at [GroupManagerView.swift:2184+](../../Carry/Views/GroupManagerView.swift:2184) updated local `@State` (groups, allMembers) and the `guest_roster_json` snapshot — but **never UPDATEd `profiles.display_name` or `profiles.handicap`** server-side. RLS policy on profiles is `auth.uid() = id` ([20260322000000_complete_base_schema.sql:33-37](../../supabase/migrations/20260322000000_complete_base_schema.sql:33)) forbids creator from direct profile UPDATEs. (2) **Stale `allMembers` in result.** PlayerGroupsSheet edits via picker / name TextField only mutate `groups[i][j]` — they do NOT touch the sheet's separate `allMembers` @State. `buildResult()` at [PlayerGroupsSheet.swift:1422+](../../Carry/Views/PlayerGroupsSheet.swift:1422) returned `allMembers: allMembers` directly, so `result.allMembers` arrived at the parent with stale values. Even after the (1) fix landed, the diff logic (old `allMembers` vs new `result.allMembers`) saw both as the ORIGINAL value → diff empty → RPC never fired |
| Audit findings | Surveyed every user-editable Player field across the app. Two gaps in PlayerGroupsSheet ([L569 handicap](../../Carry/Views/PlayerGroupsSheet.swift:569), [L775 name](../../Carry/Views/PlayerGroupsSheet.swift:775)). All other paths (QuickStartSheet → createGuestProfiles RPC; ProfileSheetView → authService.updateProfile; group fields → updateGroup) persist correctly |
| Fix (4 layers) | (1) **PlayerGroupsSheet `buildResult` reconciles allMembers from groups** at [PlayerGroupsSheet.swift:1422+](../../Carry/Views/PlayerGroupsSheet.swift:1422) — copies name/initials/handicap from `cleanGroups` onto the corresponding allMembers entries. Fixes the stale-result root cause; without this, no diff logic upstream can detect the change. (2) **`guestNameBinding` updates initials too** so the avatar bubble doesn't show stale initials. (3) **New SECURITY DEFINER RPC** [update_guest_profile](../../supabase/migrations/20260510000001_update_guest_profile_handicap.sql) — accepts `p_display_name`, `p_initials`, `p_handicap` (all optional). Bypasses RLS but enforces `created_by = auth.uid()`. Auto-derives initials from display_name when not passed. (4) **iOS persistence + race guard** at [GroupManagerView.swift:2196+](../../Carry/Views/GroupManagerView.swift:2196): onSave diffs old vs new for each guest, sends one RPC per guest with whichever fields changed; `guestProfileEditsLastSavedAt` stamp + 8s window in refresh preserves local values until replication |
| Diagnostic that found it | User-reported: edit handicap → save → refresh → reverts. Code audit confirmed the gap in PlayerGroupsSheet onSave. Wider audit found the sibling name-edit gap |
| Blueprint | [refresh-race-guards.md](refresh-race-guards.md) — adds 6th race-guard instance. [guest-lifecycle.md](guest-lifecycle.md) — guest profile fields (name, handicap) are server-authoritative; must persist on edit, not just snapshot |
| Lesson (meta) | Doc passes are descriptive by default — they capture patterns that exist, not patterns that *should* exist. The race-guard doc captured the 5 existing guards but didn't audit whether each one was paired with the persistence write it presupposes. **Going forward: every doc pass must also be an audit pass.** For every user-editable field, verify it persists to source-of-truth at the save site |
| Lesson (concrete) | "Local @State + snapshot" is NOT sufficient persistence for any field whose canonical source-of-truth is server-side. The snapshot is a between-rounds backup; active-round read paths go through `profiles`. Anywhere a user edits an authoritative field, the save handler MUST persist to the authoritative source synchronously (or with a known-completion semantic) — local-only mutations get stomped on every refresh |

---

## 2026-05-10 — Home-tab Quick Game entry: Restart Round breaks drag + back navigation

| Field | Value |
|---|---|
| Symptom | After entering a Quick Game from the Home-tab Active Round card and tapping Restart Round on the scorecard: (1) drag-and-drop of players between tee groups doesn't persist; (2) pressing Back from the setup view routes to Course Selection instead of dismissing to the Home/Games tab |
| Root cause | [HomeView.swift:617-683](../../Carry/Views/HomeView.swift:617) constructs `RoundCoordinatorView` without passing `groupId` or `skipCourseSelection`. Both default to `nil` / `false`. Consequences: (a) `supabaseGroupId` propagates as nil into `GroupManagerView`, causing `QuickGameGuestStorage.save` and `syncGroupNumsToSupabase` to no-op (drag changes don't persist server-side or to local snapshot); (b) the Bug H back-button fix at [RoundCoordinatorView.swift:176](../../Carry/Views/RoundCoordinatorView.swift:176) — `skipCourseSelection \|\| groupId != nil` — evaluates false on both sides, falling through to the brand-new-round branch that sets `phase = .courseSelection` |
| Why it surfaced now | Sibling regression to the earlier-flagged "Quick Game convert-to-group prompt missing from Home-tab entry" (MEMORY pre-2026-05-10). HomeView's coordinator wiring has been progressively diverging from GroupsListView's; each missing prop was a separate hidden footgun |
| Fix (immediate) | Pass `groupId: round.supabaseGroupId`, `skipCourseSelection: true`, and `creatorId: round.creatorId` from HomeView, mirroring [GroupsListView.swift:809-817](../../Carry/Views/GroupsListView.swift:809) |
| Fix (structural — bug class eliminated) | (1) **Back-from-setup invariant**: removed the `phase = .courseSelection` fall-through branch entirely from the back closure at [RoundCoordinatorView.swift:170-193](../../Carry/Views/RoundCoordinatorView.swift:170). Pressing Back now ALWAYS transitions to `.active` (when a round is in flight) or calls `onExit`. Course changes mid-setup go through the existing in-setup sheet at [GroupManagerView.swift:5157](../../Carry/Views/GroupManagerView.swift:5157). (2) **Constructor wiring guard**: when `groupId != nil` but caller forgot `skipCourseSelection`/`startInActiveMode`/`initialRoundConfig`, DEBUG `assertionFailure` traps the wiring mistake at the call site; production force-promotes `skipCourseSelection = true` so users never see the trap. See [phase-transitions.md §"Wiring invariant"](phase-transitions.md) |
| Blueprint | [phase-transitions.md](phase-transitions.md) — added "Wiring invariant" + "Back-from-setup invariant" sections codifying the locks |
| Lesson | A defensive fall-through branch on a state machine becomes a trap whenever its precondition (in this case "no group context") fails to hold. Three layered fixes are needed: (a) eliminate the trap path entirely, (b) trap wiring bugs at construction time, (c) document the invariant. The pattern generalizes: any "fallback to a different phase" branch in a phase-machine should be examined for the trap-when-misconfigured failure mode |

---

## 2026-05-10 — Home tab empty state after declining convert prompt (Bug G)

| Field | Value |
|---|---|
| Symptom | Complete 18 holes on a Quick Game from Home tab → convert sheet appears → tap "No, thanks" / dismiss → return to Home tab → empty state (no Recent Games). Pull-to-refresh recovers |
| Root cause | After `archiveConcludedRound()` runs locally (moves the round into `roundHistory`), MainTabView's 15s polling timer at [MainTabView.swift:246](../../Carry/Views/MainTabView.swift:246) blindly assigned `skinGameGroups = groups` from `loadGroups`. During the brief window between local archive and server status-flip replication, `loadGroups` could return an empty array (RLS race, server transient state, or replication lag). This overwrote the non-empty local state → Home renders empty state |
| Fix | New `Notification.Name.didLocallyArchiveRound` posted from all 3 `archiveConcludedRound()` call sites. MainTabView observes it and stamps `skinGameGroupsLocallyMutatedAt`. The poll's empty-result handler now guards: if `groups.isEmpty && !skinGameGroups.isEmpty && isRecentLocalMutation` (stamp <10s old), skip the assignment as transient. 7th instance of the race-guard pattern — see [refresh-race-guards.md](refresh-race-guards.md) |
| Blueprint | [refresh-race-guards.md §7](refresh-race-guards.md). [source-of-truth.md](source-of-truth.md) — `skinGameGroups` row updated |
| Lesson | The race-guard pattern is universally applicable: anytime local @State changes ahead of a server write, the next refresh's empty/stale return must be guarded. This is now the 7th instance — could be worth extracting into a reusable helper if an 8th surfaces |

---

## 2026-05-10 — Sender-side "X joined" toast fires on guest drag (MainTabView)

| Field | Value |
|---|---|
| Symptom | Dragging a guest player between tee groups in a Quick Game intermittently fires `"<guest name> joined <QG name>!"` toast on the creator's device |
| Root cause | The 15s polling timer in [MainTabView.swift:170-188](../../Carry/Views/MainTabView.swift:170) compares `prev.members` to `fresh.members` for groups the user created and toasts any newly-active profileId. The filter excluded `isPendingAccept` / `isPendingInvite` but **NOT** `isGuest`. During a drag, the local snapshot save + server write to `guest_roster_json` is in-flight; a poll landing in that window saw a transient member-list shape (e.g., the dragged guest briefly absent then returning), making the guest look "new" → fires |
| Fix | Added `&& !$0.isGuest` to both the prev-set filter and the fresh-set filter at [MainTabView.swift:175,180](../../Carry/Views/MainTabView.swift:175). The toast is meant for Carry users joining via invite-acceptance / phone reconciliation — guests are CREATED by the sender, not joiners. Restricting the comparison to Carry users eliminates the bug class entirely |
| Blueprint | [manage-members.md §"Toast baselines"](manage-members.md) — the previous fix landed the playerId-baseline + transient-empty guard for the GroupManagerView in-group toast; this entry adds the Carry-only filter for the cross-tab MainTabView toast |
| Lesson | Cross-device join toasts must restrict their comparison to Carry users (`!isGuest`). Guests are sender-created and don't have a "joined" semantic. Any future toast that detects "new member" needs the same filter — added to the source-of-truth contract |

---

## 2026-05-10 — "X joined — tap Manage to add to tee sheet" toast refires every refresh

| Field | Value |
|---|---|
| Symptom | Inside group details (Skins Group + Quick Game), the "X joined — tap Manage to add to tee sheet" toast fires repeatedly for already-existing members. One even fired delayed into the scorecard view |
| Root cause | The cross-session new-member baseline at [GroupManagerView.swift:1011-1037](../../Carry/Views/GroupManagerView.swift:1011) was keyed on `group_members.id` (membership row UUID). `dedupeMembers` ([GroupService.swift:209-221](../../Carry/Services/GroupService.swift:209)) collapses duplicates client-side via dictionary `Array(best.values)` — but Swift dictionary iteration is non-deterministic, so when the server returns multiple active rows for the same player (e.g., phone-invite reconciliation that keeps `invited_phone` set, sidestepping the partial unique index `group_members_unique_real_player`), the chosen row's `id` swaps between refreshes for the same person → diff registers them as "new" → toast fires every poll. The 30s `refreshTimer` keeps running after navigation to scorecard, so a delayed refresh fires the toast even when the setup view isn't visible |
| Fix | (1) Switched baseline key to `playerId` UUID set: `seenActiveMemberPlayerIds_<groupId>`. A given Carry user has one stable profile UUID; multiple `group_members` rows for the same person collapse to one entry. (2) Transient-empty guard: if `fetchGroupMembers` returns empty (network blip / RLS hiccup / race) AND the saved baseline is already non-empty, SKIP both diff and save. Otherwise the empty save stomps the real baseline and the next successful refresh fires toasts for every existing member as "just joined". Members realistically can't go from N → 0 in normal use. Trade-off: leave-and-rejoin on the same device no longer re-fires the toast (server push covers cross-device). |
| Blueprint | [manage-members.md](manage-members.md) — needs a "toast baselines" section codifying the playerId rule |
| Lesson | A baseline keyed off any non-canonical identifier is fragile when the producer (server response order) is non-deterministic. Anchor baselines on the most stable identifier the data model exposes. The original choice (row id) traded determinism for a niche edge case (re-fire on rejoin); the regression cost outweighed the benefit |

---

## 2026-05-10 — Guest profiles stale at round-start ("Guest"+0.0 root cause + corruption-cycle fix)

| Field | Value |
|---|---|
| Symptom | After Restart Round on a Quick Game with guests, the next round's pills/scorecard/tee sheet/PlayerGroupsSheet all showed "Guest" + handicap 0.0 for the previously-named guests. After the first fix landed, 1 guest's name came back but 3 still showed "Guest" |
| Root cause (the corruption cycle) | The literal `"Guest"` + `0.0` fallback at [GroupService.swift:1599](../../Carry/Services/GroupService.swift:1599) was a **disease** that propagated through every layer once any single break occurred: (1) Guest profile gets wiped (`delete_quick_game_guests`); (2) round_players' denormalized `guest_display_name`/`guest_handicap` happens to be NULL for that row (e.g., legacy data, or a delete that bypassed the RPC); (3) `buildHomeRound`'s wiped-fallback substitutes `Player.name = "Guest"`, `handicap = 0.0` into the iOS roster; (4) user moves a player → `.onChange(of: groups)` fires → `QuickGameGuestStorage.save` writes the corrupted "Guest"+0.0 entry into the snapshot (UserDefaults + server `guest_roster_json`); (5) at next round-start, `createSupabaseRound` reconciliation reads the snapshot and creates a new guest profile literally named "Guest". From there, `delete_quick_game_guests` denormalizes `display_name = "Guest"` onto round_players — and now the corruption is **persisted server-side**, not just in iOS state |
| Why "Restart Round" is the trigger | The locked invariant says guest profiles are ephemeral PER ROUND ([guest-lifecycle.md](guest-lifecycle.md)). `delete_quick_game_guests` wipes them on round termination. The symmetric rule — "guests are recreated at every round-start" — was ONLY implemented at initial Quick Start sheet creation, NOT at Restart Round. So Restart Round + new round used stale profileIds → first break → first "Guest"+0.0 corruption seed |
| Fix (three points, all needed) | (1) **`createSupabaseRound` reconciliation** at [RoundCoordinatorView.swift:430-503](../../Carry/Views/RoundCoordinatorView.swift:430): query `profiles` for which guest profileIds still exist; recreate missing ones via `GuestProfileService.createGuestProfiles`; pull canonical name + handicap from `QuickGameGuestStorage` snapshot (matched by profileId then by id), NOT from possibly-corrupted `Player.name`. RoundConfig.players flipped `let → var` to allow remap. (2) **`buildHomeRound` wiped-fallback** at [GroupService.swift:1589-1620](../../Carry/Services/GroupService.swift:1589): consults `QuickGameGuestStorage.load(groupId:)` matched by profileId BEFORE substituting the literal "Guest" string. Lookup priority: round_players denormalized → snapshot match → "Guest"+0.0 last resort. (3) **`QuickGameGuestStorage` corruption guards** at [QuickGameGuestStorage.swift:save+load](../../Carry/Services/QuickGameGuestStorage.swift): `save()` filters out any guest whose `name == "Guest"` or whitespace-only; `load()` filters the same on read (defends against legacy corrupted UserDefaults/server payloads). Breaks the cycle so it can never re-enter |
| Diagnostic that found it | `SELECT rp.player_id, p.id IS NOT NULL AS profile_exists, p.display_name, rp.guest_display_name FROM round_players rp LEFT JOIN profiles p ON p.id = rp.player_id WHERE round.status = 'active'` → showed Carry users had profiles, 4 guest player_ids had NO matching profile, AND `guest_display_name` was NULL on those rows. The NULL denormalized field is what triggered the "Guest"+0.0 fallback |
| Existing corrupted data is unrecoverable | Once round_players references a deleted profile AND denormalized fields are NULL AND the snapshot has been overwritten with "Guest" entries, there's no source of truth left for the original names. Affected groups need a fresh round with fresh guest entries. The three-point fix prevents new corruption from entering |
| Blueprint | [guest-lifecycle.md](guest-lifecycle.md) needs three new sections: (1) round-start reconciliation rule; (2) snapshot is the canonical source of truth between rounds; (3) "Guest" + 0.0 is a disease string, never let it reach Player.name without exhausting all upstream sources first |
| Lesson | A single defensive fallback string can become a contagious data corruption vector if it touches user-mutable state. The fix is twofold: prevent the literal from ever being chosen if any other source has data (priority chain), AND filter it out at every persistence layer (defense-in-depth). Single-point fixes only stop the next propagation; they don't stop the corruption already in flight |

---

## 2026-05-10 — `guest_roster_json` column type corrected (jsonb → text)

⚠️ **Status:** column type aligned with codebase pattern; whether this resolved the user-reported "Guest"+0.0 symptom is **unverified**. See "open question" below.

| Field | Value |
|---|---|
| Observation | After Bug E migration applied to dev, `jsonb_typeof(guest_roster_json)` returned `string`, not `array`. The data displayed in Studio table view as JSON array text but was actually stored as a JSONB string scalar |
| Root mechanism | iOS encodes `[GuestSnapshot]` to a String, sends `{"guest_roster_json": "[{...}]"}` to Supabase. Postgres `jsonb` column parses the value and stores a JSONB string scalar containing the JSON text. `text` column would store the original string verbatim |
| Why this is suspicious but maybe not user-facing | On read-back, Postgres serializes the JSONB scalar to JSON form. iOS Codable decodes back to a Swift `String?`, getting the original JSON array text. Round-trip should preserve content. Functionally equivalent to `text` for this encoding pattern |
| Fix | Changed column type to `text` for consistency with the codebase pattern (`tee_times_json`, `holes_json`, `last_tee_box_holes_json` all use `text`). Dev was patched live: `ALTER TABLE skins_groups DROP COLUMN guest_roster_json; ALTER TABLE skins_groups ADD COLUMN guest_roster_json text;`. Migration file [20260510000000](../../supabase/migrations/20260510000000_skins_groups_guest_roster.sql) updated. iOS code unchanged |
| Open question | Does the user-reported "Guest"+0.0 symptom (across pills, scorecard, tee sheet, PlayerGroupsSheet) actually trace to this column type, or is the source the `buildHomeRound` wiped-guest fallback at [GroupService.swift:1599](../../Carry/Services/GroupService.swift:1599) firing because `round_players.guest_display_name` is null after a `delete_quick_game_guests` denormalization gap? Needs server-side query results (profiles + round_players denormalized fields) to resolve |
| Blueprint | [guest-lifecycle.md](guest-lifecycle.md) + [db-schema-rules.md](db-schema-rules.md) — both note `text` type. Migration file's column-type-correction history block at top |
| Lesson 1 | The codebase has two JSON column conventions: (a) iOS `String?` field + Postgres `text` column for pre-serialized JSON, and (b) iOS Swift type + Postgres `jsonb` for natively-serializable types. Stick to one or the other. `recurrence` is an inconsistent case (jsonb + String?) that happens to work but should arguably be text. Codify this in db-schema-rules going forward |
| Lesson 2 | Don't assume a hypothesis without validation. The jsonb-vs-text difference IS architecturally inconsistent with the codebase pattern, but the round-trip mostly works either way for `String?` fields. The "Guest"+0.0 symptom likely has a different cause |

---

## 2026-05-10 — Quick Game card pills show only scorers when between rounds

| Field | Value |
|---|---|
| Symptom | Quick Game with 5 players (1 scorer + 4 guests). After cancelling a round, the Games tab card pills only displayed the scorer. Going back into the QG was fine (guests still hydrated locally), but the spectator-facing card view dropped them |
| Root cause | `GroupsListView.swift:1238` reads from `group.members`. `loadSingleGroup` builds `members` from `group_members` (Carry-only by invariant) plus a backfill from `round_players`. The backfill is gated on `backfillRoundDTO` being non-nil — only fires when an active/concluded/completed round exists. After cancel: `rounds.first` returns a `cancelled` round → backfill skips → `members = [scorer only]`. Was always the case for QGs between rounds, just surfaced now because the user's drag testing put a QG into the post-cancel state |
| Fix part 1 | After the round_players backfill, added a QG-only between-rounds branch ([GroupService.swift:1259-1275](../../Carry/Services/GroupService.swift:1259)). When `isQuickGame && backfillRoundDTO == nil && guestRosterJson != nil`, decode the snapshot and synthesize guest Players into `players`. Covers cross-session / multi-device |
| Fix part 2 | In `refreshGroupData`'s `localized.members` push to parent ([GroupManagerView.swift:1224-1233](../../Carry/Views/GroupManagerView.swift:1224)), merge in any QG guests from local `allMembers` that aren't already in `localized.members`. Covers same-session window where edits haven't round-tripped to `guest_roster_json` yet (server-write race) |
| Invariant codified | Pills are 1:1 with the in-app roster. Four paths populate `group.members`; all must respect the contract. Documented in [guest-lifecycle.md §"Games tab card pills — contract"](guest-lifecycle.md) with the per-state matrix |
| Blueprint | [guest-lifecycle.md](guest-lifecycle.md) §"`loadSingleGroup` QG between-rounds backfill" + §"Games tab card pills — contract" |
| Lesson | The Bug E `guest_roster_json` column was originally framed only as durable cross-device persistence for the GroupManagerView local state. But once the column exists, it's also the natural source for any UI that needs the QG's guest roster between rounds. The pill contract requires four paths to hold the 1:1 invariant; audit any new `group.members` consumer against the per-state matrix |
| Recovery for OLD QGs | Pre-migration QGs whose round was cancelled before `guest_roster_json` was populated have lost their guest data server-side. Local UserDefaults may still have it (`QuickGameGuestStorage.load`), in which case re-entering the GroupManagerView re-saves the snapshot to the server column. If both are gone, user must re-add guests via PlayerGroupsSheet |

---

## 2026-05-10 — Group formation single-source-of-truth refactor

| Field | Value |
|---|---|
| Symptom class | Drag-and-drop bugs kept producing regressions because mutations to `groups[][]` (drop handler, regroup, swap, refresh rebuild, etc.) only updated array structure but didn't update `Player.group` on the moved players. Downstream code reading `Player.group` saw stale values. Each "fix" added more reactive sync code, exposing more drift surface |
| Root cause | 8 parallel structures (`groups[][]`, `allMembers`, `guests`, `Player.group`, `group_members.group_num`, `round_players.group_num`, `skins_groups.guest_roster_json`, UserDefaults `quickGameGuests_<uuid>`) all describing the same domain. No single source of truth |
| Fix (minimal-risk version) | `.onChange(of: groups)` auto-corrects `Player.group` to match index: if any player's `.group` doesn't equal its array index + 1, rewrite `groups` with corrected values and early-return. SwiftUI re-fires `.onChange` with corrected groups; on re-fire, no rewrite is needed and the rest of the handler runs (mirror to `allMembers`/`guests`, persist QG snapshot, schedule server sync). Functionally equivalent to forcing every mutation site through a single `commitGroupsChange` function, without rewriting any mutation site. [GroupManagerView.swift:2477-2553](../../Carry/Views/GroupManagerView.swift:2477) |
| Architecture target | [group-formation-canonical.md](group-formation-canonical.md) — the full migration plan if/when the reconciler approach proves insufficient |
| Lesson | When reactive sync code keeps producing regressions, the root cause is multiple parallel structures without a single source of truth. The minimal-risk path is a self-consistent reconciler that runs after every mutation; the full-cost path is collapsing to one canonical structure. The reconciler costs less but assumes mutations always go through the reactive observer (`.onChange(of: groups)`); the full refactor is auditable. Verify the reconciler is enough before doing the full collapse |

---

## 2026-05-10 — Drag of Quick Game guest reverts after race-guard window (Bug #0 follow-up)

| Field | Value |
|---|---|
| Symptom | Quick Game with scorer in Group 1 + guest in Group 2. Drag the last guest from Group 2 → Group 1 (collapsing to 1 group). Drag persists ~8s, then refresh stomps it back to original arrangement |
| Root cause | Drop handler ([GroupManagerView.swift:5316-5374](../../Carry/Views/GroupManagerView.swift:5316)) updates `groups[][]` but does NOT update `Player.group` on the moved player or on the matching entry in `allMembers`/`guests`. The 8s `groupNumLastSavedAt` race guard skips the rebuild for ~8s. After the window expires, refresh's `preservedGuests` filter (line 850-855) reads from `allMembers` with stale `Player.group` from before the drag → rebuild places the guest at `rebuilt[Player.group - 1]` → drag reverted. QG-only: `loadSingleGroup` is Carry-only, so guests have no server-side group_num authority (except in `round_players` when an active round exists) — local `allMembers` is the truth |
| Fix | In `.onChange(of: groups)` ([GroupManagerView.swift:2436-2484](../../Carry/Views/GroupManagerView.swift:2436)) — mirror the new tee-group arrangement into `allMembers` and `guests` immediately. Compute `groupById = [playerId: groupNum]` from `groups[][]`, write back into both arrays. Also re-fire `QuickGameGuestStorage.save(...)` so the persisted snapshot reflects the new arrangement (UserDefaults + server `guest_roster_json`) |
| Blueprint | [refresh-race-guards.md](refresh-race-guards.md) §4 — Bug #0's `groupNumLastSavedAt` guard description was correct for Carry users (they have server `group_num` authority). Guests need the additional local-state mirror because they have no server-side authority |
| Lesson | Race guards prevent stale-server stomps but not stale-local stomps. When two parallel arrays (`groups[][]` and `allMembers`) describe the same domain (player → tee-group), every mutation must update BOTH. The drop handler is one of those mutations. Future audit: search for other places that mutate `groups[][]` without touching `allMembers` |

---

## 2026-05-10 — Start Round flag icon flickers during player drag (Bug J follow-up)

| Field | Value |
|---|---|
| Symptom | After fixing the original Bug J (flag pop on entry), a different visual issue surfaced: when dragging a player between groups, the flag icon did a "weird reset animation" — fade out then back in |
| Root cause | The drop handler runs inside `withAnimation(.easeOut(duration: 0.2))`. Any state change inside that block inherits the 0.2s easeOut animation. During a drag, `canStartRound` transiently flips false → true (e.g. when the source group temporarily has <2 players mid-mutation) → the flag's opacity changes inherit the easeOut → visible fade |
| Fix | Added `.animation(nil, value: canStartRound)` and `.animation(nil, value: isLiveRound)` modifiers on the flag Image at [GroupManagerView.swift:1715-1735](../../Carry/Views/GroupManagerView.swift:1715). Opts the opacity changes out of inherited transactions; the flag stays rendered but never animates |
| Lesson | SwiftUI's `withAnimation` block animates ALL state changes that occur inside it, including indirect computed-property changes. When a view inside the affected scope shouldn't animate (because its state change is incidental to the user's gesture), use `.animation(nil, value:)` to opt out per property |

---

## 2026-05-10 — Start Round button flag icon pops in after text (Bug J)

| Field | Value |
|---|---|
| Symptom | Entering a Quick Game from Games tab → Start Round button briefly shows just the text, then the flag icon pops in beside it. Visible jitter. **Quick Game only** — Skins Groups don't show this because `currentCourse` and members are synchronous from `preselectedCourse` + `initialMembers`, so `canStartRound` is true on first paint |
| Root cause | [GroupManagerView.swift:1715-1718](../../Carry/Views/GroupManagerView.swift:1715) conditionally rendered the icon: `if canStartRound \|\| isLiveRound { Image("flag.fill") }`. For Quick Games, guests hydrate via `QuickGameGuestStorage.load()` in `.onAppear` — a frame after first paint — so the gate flips true after initial render → icon inserts after text → layout shifts → visible pop |
| Fix | Always render the icon, toggle visibility via `.opacity(canStartRound \|\| isLiveRound ? 1 : 0)`. Layout space reserved on first paint. No layout shift when state resolves. May still show a subtle implicit opacity fade-in for QGs, but no jitter |
| Blueprint | None — pure view rendering, no system invariant. Code comment in-line for context |
| Lesson | Conditional `if` inside a SwiftUI HStack causes layout shift when the gate flips. For visibility-only toggles where layout should stay stable, use opacity/hidden modifiers instead of conditional rendering. The QG-only manifestation tracks the same async-hydration pattern that drove the guest-lifecycle work — anything gated on QG guest state will paint twice unless hydrated synchronously |

---

## 2026-05-10 — Back button from setup view lands on Course Selection (Bug H)

| Field | Value |
|---|---|
| Symptom | After canceling/restarting a round in an existing group, tapping back from the setup view landed user on `CourseSelectionView` (empty "Select Course" with no recent courses) instead of returning to Games tab. Observed twice |
| Root cause | [RoundCoordinatorView.swift:170-186](../../Carry/Views/RoundCoordinatorView.swift:170) back closure routed via `if hasStartedRound { .active } else if skipCourseSelection { onExit } else { .courseSelection }`. Restart Round clears `hasStartedRound = false`. For a live group, [GroupsListView.swift:817](../../Carry/Views/GroupsListView.swift:817) inits `skipCourseSelection: !isLive = false`. Both branches fail → fell into `.courseSelection`. Two different concerns (initial entry path + back-routing logic) shared one variable |
| Fix | Added `groupId != nil` to the exit condition. Existing groups never originated from course selection, so back from setup always exits to parent. Course selection branch now only fires for brand-new round creation flows (`groupId == nil && !skipCourseSelection`) |
| Blueprint | [phase-transitions.md](phase-transitions.md) §Transition triggers — split the `.setup → .courseSelection` row into two rows for the existing-group exit path vs the brand-new round path |
| Lesson | When a single boolean (`skipCourseSelection`) gates two different concerns (initial entry routing + back-button routing), edge cases like Restart Round can flip `hasStartedRound` and expose the conflict. Use the existence of a `groupId` as the better signal for "are we in a brand-new round flow vs an existing group?" |

---

## 2026-05-10 — Quick Game guests lost on app delete + reinstall

| Field | Value |
|---|---|
| Symptom | Quick Game guest roster vanishes when the user deletes Carry and reinstalls (or moves to a new device). Force-quit, OS reaping, App Store updates were already handled by UserDefaults snapshot but app-delete wiped UserDefaults too |
| Root cause | Quick Game guests had no server home between rounds. Local UserDefaults snapshot via `QuickGameGuestStorage` mitigated process death but not app delete |
| Fix | New `skins_groups.guest_roster_json` JSONB column (migration `20260510000000`). `QuickGameGuestStorage.save()` now writes through to BOTH UserDefaults (fast local) AND server (durable). `loadSingleGroup` calls `QuickGameGuestStorage.hydrateFromServer(...)` before GroupManagerView mounts. New `GroupService.saveGuestRoster(groupId:json:)` method. SkinsGroupUpdate gets `guestRosterJson` field with `clearGuestRosterJson` flag matching the `teeTimesJson` pattern. 4 new encoding tests in SkinsGroupUpdateEncodingTests |
| Blueprint | [guest-lifecycle.md](guest-lifecycle.md) §"Two-layer persistence" + §"Server hydrate" |
| Lesson | Local-only persistence (UserDefaults, Keychain) survives some failure modes but not all. Server-side state is the durable layer; local is the cache. Pattern reusable for any future "session state that must persist across app delete." Doesn't violate the ephemeral-guest invariant — guest *profiles* still get wiped on round end; this column is just the name+handicap snapshot for between-round reconstruction |

---

## 2026-05-09 — Drag-and-drop tee-group persistence

| Field | Value |
|---|---|
| Symptom | Press-and-drag a player from one tee group to another → they snap back to the original group on the next 30s refresh OR on navigate-out + back |
| Root cause | `.onChange(of: groups)` synced `group_num` to Supabase after a 1s debounce, but `refreshGroupData` rebuilt `groups[][]` authoritatively from the server's `group_num` value with no guard. A poll firing within ~1-8s after the drag stomped the local arrangement with stale server state. Navigate-out + back also failed because the parent's `groups[idx]` retained the stale server-authoritative `Player.group` from `onGroupRefreshed?(localized)` |
| Fix | New `groupNumLastSavedAt` race guard (4th instance of the pattern); skip the rebuild branch when the stamp is <8s old; patch `localized.members[i].group` from local arrangement when guard is active |
| Blueprint | [refresh-race-guards.md](refresh-race-guards.md) §`groupNumLastSavedAt` — added; [GroupsListView.swift:2677](../../Carry/Views/GroupsListView.swift:2677) `SavedGroup.members` flipped to `var` |
| Lesson | This was the 4th instance of the same race-guard pattern (tee-time, index %, scorer, now group_num). The doc was already there; the developer didn't read it before adding `.onChange(of: groups)`. Validates the playbook's "before adding a new user-editable persisted field" rule. Going forward: any new `.onChange(of: <field>)` that persists must add a `<field>LastSavedAt` stamp |

---

## 2026-05-09 — "Couldn't connect — starting offline" toast on Restart Round

| Field | Value |
|---|---|
| Symptom | Tap "Restart Round" mid-round → land on setup → red "Couldn't connect — starting offline" toast appears 10 seconds later, even though the user is on setup with no offline state |
| Root cause | `onCancelToSetup` was clearing `roundConfig = nil` BEFORE (or in the same `withAnimation` closure as) `phase = .setup`. SwiftUI batches state mutations within a closure and re-renders the body once with all new values. For one render tick, `phase = .active` + `roundConfig = nil`, which evaluates the `.active` branch's loading-fallback view, whose `.onAppear` schedules a 10s offline-timeout |
| Fix | Restructured `onCancelToSetup`: `phase = .setup` mutated first inside `withAnimation`, all other cleanup (roundConfig nil, hasStartedRound false, splash flags, task cancel) deferred into `DispatchQueue.main.async` |
| Blueprint | [phase-transitions.md](phase-transitions.md) §"the order-of-state-mutations rule" + canonical example section |
| Lesson | "Patch fix" of guarding the loading-fallback's `onAppear` was rejected because it didn't address the root cause (phase mutation order). User correctly flagged "no patch solutions here, that happened because you lost context, that bug is for something we established long ago." This is the canonical example of the order-of-mutations rule |

---

## 2026-05-09 — 100% push notification 401 failure

| Field | Value |
|---|---|
| Symptom | Yesterday's round had slow score updates across devices. Investigation showed `net._http_response` histogram: 274/274 = 401 over 6 hours. No pushes delivering |
| Root cause | Prod's `app.settings.supabase_anon_key` GUC was NULL → push trigger helpers returned empty string → trigger sent `Authorization: Bearer ` (empty) → Edge Function rejected 100% of calls. Permission to set the GUC was locked down to `supabase_admin` role (`ALTER DATABASE` and `ALTER ROLE` both 42501) |
| Workaround (immediate) | Toggled "Verify JWT with legacy secret" OFF on `send-push-notification` Edge Function. Pushes flow but function URL became publicly callable |
| Permanent fix | Vault-based migration `20260509000000_notify_push_use_vault.sql`. Helpers `_vault_secret_or_default`, `_push_notification_url`, `_push_notification_anon_key` read from Vault first → GUC fallback → empty fallback. Per-environment `SELECT vault.create_secret('<value>', '<name>')` calls. Verify JWT toggled back ON |
| Blueprint | [push-trigger-chain.md](push-trigger-chain.md) §"Shared Vault helpers" + §"The 401 incident (2026-05-09)" |
| Lesson | The four push-firing functions had drifted independently with their own auth-resolution blocks. Consolidating to shared helpers prevents drift. Added 17 SQL tests at [supabase/tests/db/notify_push_helpers_test.sql](../../supabase/tests/db/notify_push_helpers_test.sql) — currently the only test enforcing invariant #7 |

---

## 2026-05-01 — 42703 cross-binding bug (every Quick Game / Group round-start broken)

| Field | Value |
|---|---|
| Symptom | Every round-start INSERT failed silently for two days in TF 60. POST /rest/v1/rounds returned 400 with PostgreSQL error 42703 "column does not exist" |
| Root cause | `notify_push()` had `NEW.player_id` references at the top level, outside table-specific guards. PL/pgSQL must bind every `NEW.<col>` against the trigger's rowtype at plan time. When the trigger fired on `rounds` (no `player_id` column), binding failed → trigger errored → row INSERT rolled back |
| Fix | Migration `20260501000000_fix_notify_push_per_table_dispatch.sql` — restructured `notify_push()` with per-table IF/THEN dispatch blocks so all `NEW.<col>` references are guarded by the table check |
| Blueprint | [push-trigger-chain.md](push-trigger-chain.md) §"`notify_push()` — the row-trigger dispatcher" + §Common bugs §"the 42703 dispatch bug" |
| Lesson | Server-side, PL/pgSQL plans the body at trigger-creation time and can't tolerate "wrong-table" branches. Solution pattern: per-table IF blocks. Also reinforced: 42703 is a planner error, not a runtime one — it fires before any data check |

---

## 2026-05-08 — Skins Group tee times shift on every edit (1.0.6)

| Field | Value |
|---|---|
| Symptom | Editing tee times in Game Options → save → tee times visibly shift by minutes on next refresh |
| Root cause | Three independent UI paths mutated `teeTimes` (Game Options Save, date/recurrence picker, per-group picker). Each save stomped the others. The 30s refresh's recompute fallback also fired during the 0.8s `.onChange` debounce, pulling stale server state |
| Fix | (1) Single-writer rule: only the per-group tee-time picker writes `teeTimes`; (2) `teeTimesLastSavedAt` race guard (3rd instance of the pattern); (3) duplicate-time conflict resolution (auto-bump 8 min). Commit `f70b6d6` |
| Blueprint | [tee-time-sovereignty.md](tee-time-sovereignty.md) + [refresh-race-guards.md](refresh-race-guards.md) §`teeTimesLastSavedAt` |
| Lesson | When multiple UIs feel like they should each write the same field, pick one writer and have the others produce side-channel inputs. Also: the race-guard pattern was discovered for the 3rd time here without yet being formalized |

---

## 2026-05-07 — Index allowance % reverts to 100% mid-save (1.0.7)

| Field | Value |
|---|---|
| Symptom | Move Game Options handicap % slider to 70% → save → slider snaps back to 100% briefly before settling |
| Root cause | Same race as tee-times: the slider value persisted to server, but a refresh during replication window read back the stale 100% and clobbered local @State |
| Fix | `handicapPercentageLastSavedAt` race guard + localized snapshot patch on `onGroupRefreshed?(localized)` to keep parent's `groups[idx]` from holding stale value during replication window |
| Blueprint | [refresh-race-guards.md](refresh-race-guards.md) §`handicapPercentageLastSavedAt` + §"the localized snapshot trick" |
| Lesson | 3rd instance of the race-guard pattern. Plus: parent state propagation matters too — the `localized` patch was added because GroupsListView re-mounts GroupManagerView with `initialMembers` from `groups[idx]`, so the parent must hold the local-correct value during replication |

---

## 2026-05-07 — Scorer wedge (creator's assigned scorer reverts to default)

| Field | Value |
|---|---|
| Symptom | Creator assigned a scorer to a Quick Game group → next refresh → assignment reverted |
| Root cause | Same race pattern: `scorerIDs` persisted via `saveScorerIds` async, but `refreshGroupData` rebuilt scorer mapping from server before write replicated |
| Fix | `scorerIdsLastSavedAt` race guard (1st instance of the pattern, became the template) |
| Blueprint | [refresh-race-guards.md](refresh-race-guards.md) §`scorerIdsLastSavedAt` |
| Lesson | First time the race-guard pattern appeared. Worth noting: it took 3 more instances before the doc was created. The blueprint exists now; the playbook flags it on every "user-editable persisted field" change |

---

## 2026-05-05 — Apple Sign In `handle_new_user` trigger silently doesn't fire

| Field | Value |
|---|---|
| Symptom | First Apple Sign In on dev → AuthService received PGRST116 "Cannot coerce single JSON object" when querying profile |
| Root cause | The `handle_new_user` trigger appended to `20260101000000_baseline.sql` either didn't fire on dev OR has a permissions/search_path issue. Doesn't repro on prod (existing users have profiles) |
| Fix | None at trigger level (still under investigation). AuthService PGRST116 fallback path created a minimal profile manually, which unblocked the user |
| Blueprint | [onboarding-and-auth.md](onboarding-and-auth.md) §"Profile creation — two paths" |
| Lesson | The two-path design (server trigger + client fallback) was correct: a single-path system would have failed open. Worth a `pg_trigger` sweep on dev to confirm trigger state before next round of auth work |

---

## 2026-05-05 — App Store rejection: phone-onboarding keyboard trap

| Field | Value |
|---|---|
| Symptom | Apple reviewer entered a phone number on the OnboardingView phone step → keyboard would not dismiss → continue button unreachable. App rejected |
| Root cause | The phone-step TextField didn't have a "Done" toolbar button or tap-outside-to-dismiss handler |
| Fix | Resolved in build 67 (1.0.3 phone step) — added keyboard dismiss handler |
| Blueprint | None directly — UX detail. Could note in [onboarding-and-auth.md](onboarding-and-auth.md) §Phone step that all keyboard inputs need a dismiss path |
| Lesson | App Store reviewers test edge cases native users don't (no Bluetooth keyboard, tapping in unexpected order). Pre-archive checklist could include "tap every TextField, verify Done dismisses keyboard" |

---

## 2026-04-26 — 2× push notifications

| Field | Value |
|---|---|
| Symptom | Each `group_members` change triggered duplicate push notifications |
| Root cause | Legacy dashboard-installed triggers persisted alongside the migration-managed triggers. Two trigger paths fired the same edge function |
| Fix | `pg_trigger` sweep + manual cleanup of dashboard triggers |
| Blueprint | [db-schema-rules.md](db-schema-rules.md) — implicit; project memory `prod_db_drift_legacy_triggers.md` |
| Lesson | Production schema drift isn't always in the migrations directory. When push behavior is weird, sweep `pg_trigger` first |

---

## 2026-04-20 — "Removed from group" false-positive on Quick Game conversion

| Field | Value |
|---|---|
| Symptom | After converting a Quick Game to a Skins Group, invited members got both "You're Invited!" push (correct) AND "Removed from \<group\>" alert (incorrect) |
| Root cause | Server-side, members' `group_members.status` flips `active → invited` during conversion (auto-accept Carry users → still goes through the invited state). `fetchMyGroups` filters by `status='active'`, so members' next poll saw the group as "missing." MainTabView treated missing as "creator removed you" |
| Fix | New `GroupService.membershipStatus(groupId:userId:)` helper. MainTabView checks the user's actual status before firing the removal alert; suppresses if status is `'invited'` (demotion, not removal) |
| Blueprint | [group-invitation-flow.md](group-invitation-flow.md) §"Quick Game → Skins Group conversion" |
| Lesson | "Missing" is ambiguous server-side: could be removed, could be temporarily demoted, could be RLS hiding. Always disambiguate with an explicit status check before firing user-visible alerts |

---

## When to add an entry here

- Any prod regression that reaches users
- Any TF / dev bug that surfaces a previously-undocumented invariant
- Any fix where you ALSO created or updated a blueprint
- Any "we already fixed this once" déjà-vu — even if the fix was identical, log the recurrence

Skip:
- Pure UI polish that doesn't reflect a system invariant
- Bugs caught by existing tests during PR review (the test caught it; that's the point)
- One-off data fixes that don't change code

## Patterns visible across the archive

- **Race-guard pattern recurred 4 times** (scorer, tee-time, index %, group_num) before the playbook codified it. Same pattern would have caught all 4 if documented earlier.
- **Trigger-driven push bugs surface in pairs** (42703 cross-binding + 401 auth) — both were single-point-of-failure paths that drifted between functions. Consolidated to shared helpers.
- **State-batching SwiftUI bugs** (the toast on Restart Round) require careful ordering, not more error handling. Patches that suppress symptoms without fixing the order cause regressions later.
- **Server schema drift** (legacy dashboard triggers, missing GUC) doesn't show in migration files — `pg_trigger` and Vault inspections are needed for incident response.
- **Two-path designs survived** (handle_new_user + AuthService fallback). The fallback caught the trigger failure cleanly. Worth replicating elsewhere.

## Last updated

2026-05-09 — initial archive seeded from MEMORY.md + recent commit history. Maintain as bugs are fixed.
