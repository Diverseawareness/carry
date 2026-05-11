# Test Plan — 1.0.8 Bundle

Manual device test plan for the changes in flight. Run on **dev** first (Apple ID: dev profile, project ref `gbhljwtbobbxervekxkg`). Apply Bug E migration to dev BEFORE testing it.

## Automated — already verified

- ✅ Full Swift test suite: 0 failed
- ✅ Build clean
- ✅ Citation audit: 323 cited, 0 broken

## Manual — Bug #0: Drag-and-drop tee group persistence

**Setup:** Skins Group with ≥4 players in 2+ groups. Be the creator (drag is creator-only).

| Test | Steps | Pass criteria |
|---|---|---|
| Persists across navigation | Drag player from Group 1 to Group 2 → wait 2s for debounce → tap Done → re-enter group | Player still in Group 2 |
| Persists across 30s refresh | Drag player → stay on group detail → wait 30 seconds (auto-refresh fires) | Player stays in moved group, doesn't snap back |
| Other edits don't revert drag | Drag player → immediately edit handicap % | Player stays in moved group |
| Sync to other devices | Drag on iPhone → wait 30s → check on iPad (same Apple ID) | Player appears in moved group on iPad |

**Regression check:** sort within a group (drag up/down within Group 1) should still work the same way.

---

## Manual — Bug A: Quick Game convert prompt from Home tab

**Setup:** Quick Game where you can play a full 18-hole round to natural completion. Currently subscribed (active sub or in trial — `storeService.isPremium == true`) on this device. Enter via the Home tab Active Round card (not Games tab).

> ⚠️ **Convert prompt only fires when ALL THREE are true:** game is Quick Game, round was naturally completed (all 18 holes scored — NOT force-ended via "End Game"), AND user is currently subscribed. There is no "premium tier" — `isPremium` is binary subscribed-or-not (trial counts). See [docs/architecture/game-types.md §"When the convert prompt fires"](architecture/game-types.md) + §"Subscription state — terminology". If you tested with a partial round or force-end, the silent dismiss is expected behavior, not Bug A.

| Test | Steps | Pass criteria |
|---|---|---|
| Convert from Home tab | Home tab → tap Active Round card → score all 18 holes naturally → "Save Round Results" | Convert sheet appears (was silent no-op before Bug A fix) |
| Convert from Games tab still works | Games tab → tap Quick Game → score all 18 → "Save Round Results" | Convert sheet appears (regression check) |
| Cancel convert | Convert sheet appears → swipe down | Sheet dismisses, group still shows on Games tab |
| Force-end dismisses silently (expected) | Score 5 holes → tap End Game & Save Results | Round saves, no convert sheet — by design |

**Regression check:** the Active Round card on Home should still tap into the round normally.

---

## Manual — Bug C: HomeView Invites cleanup

**This is the higher-risk change** — 470 lines deleted across HomeView, RoundService, SupabaseModels.

| Test | Steps | Pass criteria |
|---|---|---|
| Home tab loads | Cold-start app, sign in, land on Home tab | No crash, Active Rounds + Recent Games sections render |
| Pull to refresh | Pull down on Home tab | Refresh fires, no error |
| 30s auto-refresh | Stay on Home tab for 35 seconds | Active rounds update if any state changed; no crash |
| Active Round flow | Tap an active round → enter → exit | Returns to Home tab cleanly |
| Recent Games flow | Tap a recent round → see results | Sheet opens, dismiss works |
| Paywall on group invite | If you can trigger a group-invite paywall path elsewhere (Games tab decline-then-rejoin?), verify it still works | No regression — paywall flow is independent of the deleted invite handlers |

**Specifically what was deleted (so you know what NOT to expect anywhere):**
- The Invites section on Home was already removed in 1.0.4; this PR removes the supporting code
- `acceptInvite`, `declineInvite`, `loadInvites`, `inviteCard` in HomeView — gone
- `RoundService.fetchInvites`, `loadPendingInviteRounds`, `acceptInvite`, `declineInvite`, `subscribeToInvites`, `invitePlayer`, `fetchRoundPlayersWithProfiles` — gone
- `InviteDTO`, `InviteRoundDTO`, `InviteCourseDTO` — gone

If you tap something and expect an old Invite UI to appear → it shouldn't. This is by design; the UI was removed in 1.0.4 already, this just cleans up the code.

---

## Manual — Bug E: Quick Game guest persistence on app delete

**Pre-step:** apply migration to dev FIRST.

> ⚠️ **2026-05-10 note:** `supabase db push` is currently blocked by the squash-branch migration drift (see MEMORY "Infra gotchas"). Apply via Supabase Studio SQL editor instead — pasting the `ALTER TABLE` directly is functionally identical and idempotent. When the squash branch eventually merges to main and `db push` is restored, the migration file will reconcile its tracking row automatically. The same workaround applies for prod when ready.

**Workaround steps:**

1. Open https://supabase.com/dashboard/project/gbhljwtbobbxervekxkg → SQL Editor → New query
2. Paste:

```sql
ALTER TABLE skins_groups
  ADD COLUMN IF NOT EXISTS guest_roster_json jsonb;

COMMENT ON COLUMN skins_groups.guest_roster_json IS
  'Quick Game between-round guest roster snapshot. Array of {id, name, initials, color, handicap, avatar, group, profileId}. NULL for Skins Groups. Written by iOS on guest add/remove; read on first load.';
```

3. Run. Should report `Success. No rows returned.`

For when db push is restored later:

```bash
cd /Users/danielsigvardsson/Documents/Developer/carry
supabase link --project-ref gbhljwtbobbxervekxkg
supabase db push
# This will hit `IF NOT EXISTS` (no-op on column) and just record the migration tracking row.
```

Verify it applied:
```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'skins_groups' AND column_name = 'guest_roster_json';
-- expect: guest_roster_json | jsonb
```

Then test on dev:

| Test | Steps | Pass criteria |
|---|---|---|
| New Quick Game saves guests to server | Create QG with 2-3 guests | Server `skins_groups.guest_roster_json` is populated within ~1s (check via Supabase dashboard SQL editor) |
| Survives app delete + reinstall | Create QG with guests → delete app → reinstall → sign in same Apple ID | Guests appear on the Quick Game (was the bug) |
| Survives force-quit | Create QG with guests → force-quit → reopen | Guests appear (already worked via UserDefaults; verify regression) |
| Multi-device sync | Create QG with guests on iPhone → open same QG on iPad (same Apple ID) | Guests appear on iPad |
| Conversion clears server roster | Convert QG → Skins Group | Server `guest_roster_json` is NULL (clear ran) |
| Removing a guest persists | QG with 3 guests → remove 1 via Manage Members → close app → reopen | Removed guest stays gone |

**SQL to inspect server state:**
```sql
SELECT id, name, is_quick_game, guest_roster_json
FROM skins_groups
WHERE created_by = '<your dev profile UUID>'
ORDER BY created_at DESC LIMIT 5;
```

**Failure mode that's actually fine:** if the server write 401s or the column is missing (migration not yet applied), the iOS code falls through to UserDefaults-only behavior. Logged in console as `[QuickGameGuestStorage] server save failed`. Nothing breaks for the user; you just don't get the new persistence guarantee.

---

## Production rollout sequence (after dev passes)

1. Apply migration to **prod**: `supabase link --project-ref seeitehizboxjbnccnyd && supabase db push`
2. Verify column exists in prod
3. Bump build number, archive, upload to ASC
4. Phased release as usual

**Critical:** do NOT ship the iOS build to TestFlight/App Store before the prod migration is applied. Otherwise users get the iOS code calling a non-existent column → silent failure → no data loss but no upgrade either.

---

## If anything fails

Each bug fix is independently revertable:

| Bug | Files to revert |
|---|---|
| #0 drag-and-drop | `Carry/Views/GroupManagerView.swift` (~30 lines added), `Carry/Views/GroupsListView.swift` (`var members` → `let members`) |
| A convert prompt | `Carry/Services/AppRouter.swift`, `Carry/Views/HomeView.swift` (the new `onCreateGroup` closure), `Carry/Views/GroupsListView.swift` (the new `.onChange` handler) |
| C Invites cleanup | `git checkout HEAD~N -- Carry/Views/HomeView.swift Carry/Services/RoundService.swift Carry/Models/SupabaseModels.swift` (replacing N with the right commit) — this is the largest revert |
| E guest persistence | `git checkout HEAD~N -- Carry/Models/SupabaseModels.swift Carry/Services/GroupService.swift Carry/Services/QuickGameGuestStorage.swift CarryTests/SkinsGroupUpdateEncodingTests.swift supabase/migrations/20260510000000_skins_groups_guest_roster.sql` |

Don't apply prod migration until dev test passes.
