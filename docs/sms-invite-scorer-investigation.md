# SMS-Invite-to-Scorer Reconciliation — Active Investigation

**Status:** unverified. Code reading suggests a real gap; needs end-to-end test on dev to confirm.

**Started:** 2026-05-12 (during prefill-creator-placement audit on `hotfix/1.0.8`)

**Why this matters:** the demo ship and B+ prefill fix surfaced a deeper question about whether SMS-invited scorers actually transition correctly to active scorers post-onboard. Before shipping fixes that touch this area, verify what's actually broken vs. theoretical.

## TL;DR

Two related gaps, distinct severity:

| Gap | Status | Severity |
|---|---|---|
| **#1 Prefill duplicate creator** (Recent Setups places creator in 2 groups) | Verified bug, user-observed. B+ fix ready (~5 lines, not yet committed) | Real, in production |
| **#2 SMS-invite scorer survival** (when SMS invitee onboards, do they stay as scorer?) | Theoretical per code reading. Untested in production (all real users signed up via direct download, not SMS-link) | Latent, possibly real |

1.0.7 is live in App Store. Neither gap is a 1.0.7 regression.

## Gap 1 — Prefill duplicate creator (verified)

**Symptom**: User taps a Recent Setup card to restart a QG. The creator (themselves) ends up in Group 2 with an "X" icon (no scorer-lock) AND ALSO appears in Group 1 slot 0 (visually).

**Root cause** (`Carry/Views/QuickStartSheet.swift:411-417`): the prefill loop unconditionally overwrites Group 1 slot 0 with creator's info, regardless of whether the creator was actually in Group 1 last round. If creator was in Group 2 last round, they end up in BOTH groups (Group 1 via overwrite + Group 2 via the original placement). Two players with the same `Player.id` poisons `syncScorerIDs` rule 6 (creator-lock).

**Fix (B+, approved, not yet committed):**
- Compute `creatorAlreadyInRoster` once before the slot loop
- Only fire the overwrite if creator is NOT in the rosterSource
- File: `Carry/Views/QuickStartSheet.swift`, function `prefillFromRecentGame`, ~7 lines added/modified
- Audit thread: see chat history. Two paused doc updates flagged for after Gap 2 is sorted.

## Gap 2 — SMS-invite scorer survival (theoretical, untested)

**Hypothesized flow:**
1. Creator (Ziggy) creates a QG. Group 2 scorer slot = SMS invite to Daniel's phone.
2. QG is created. `Player.id` for Daniel = `Player.stableId(from: slot.uuid)` (random slot UUID, not Daniel's eventual profile UUID). Stored in `skins_groups.scorer_ids`.
3. Server-side `group_members` row inserted with `player_id = Ziggy's UUID` (placeholder), `invited_phone = Daniel's phone`, `status = 'invited'`.
4. Daniel installs Carry, signs up. Profile created with his phone.
5. `reconcile_phone_invites_for_profile` trigger fires (migration `20260502000003`).
6. Trigger updates `group_members`: `player_id = Daniel's profile UUID`, `invited_phone = ''`, `status = 'active'`.
7. Trigger does NOT update `round_players` or `skins_groups.scorer_ids`.
8. Client refresh: Daniel appears as Carry user with `Player.id = stableId(profile.uuid)` — DIFFERENT Int from what `scorer_ids` has.
9. `syncScorerIDs` rule 3 ("wipe if scorer no longer in group") wipes the scorer assignment.
10. Missing-scorer banner appears. Daniel cannot score Group 2 until manually reassigned.

**Why nobody's hit this**: All real users signed up by downloading the app directly (Apple Sign In), not via SMS-invite link. So step 4 has never happened in the wild.

**What's verified**:
- ✅ Reconciliation function only updates `group_members` (read migration source)
- ✅ `Player.id` is derived from a UUID via `stableId(from:)` — slot UUID for SMS invites, profile UUID for confirmed users
- ✅ `syncScorerIDs` rule 3 wipes scorer when Player.id no longer in group
- ✅ Server stores `scorer_ids` as `[Int]` (the local Player.id values)

**What's NOT verified (need to test):**
- ❓ Does the actual flow break the way the code reads? OR is there reconciliation logic elsewhere I missed?
- ❓ Does the round_players row get reconciled separately?
- ❓ Does the client have any phone-based remapping that re-derives Player.id on load?

## Test plan (dev environment)

**Prereqs:**
1. Find Daniel's profile on dev:
   ```sql
   SELECT id, first_name, last_name, display_name, phone, created_at
   FROM profiles
   WHERE first_name ILIKE 'daniel%'
      OR display_name ILIKE '%daniel%'
   ORDER BY created_at DESC;
   ```
2. Delete Daniel from dev (to enable fresh-install reconciliation flow):
   ```sql
   DELETE FROM auth.users WHERE id = '<daniel-uuid>';
   -- profiles cascades via FK
   ```
   Or via the `delete_user_account()` RPC if signed in as Daniel.
3. Verify Ziggy account exists on dev.
4. Daniel uninstalls Carry / signs out so it's a fresh-install flow.

**Test steps:**
1. Sign in as Ziggy on dev. Create a new QG. Group 1: Ziggy. Group 2: Ziggy adds Daniel via SMS as the scorer.
2. SMS arrives on Daniel's phone with `carryapp.site/invite?group=UUID`.
3. Daniel installs Carry, signs in via Apple Sign In (creates new profile + phone).
4. Reconciliation trigger fires server-side.
5. Daniel opens the app, sees the round on Home tab.

**What to capture:**
- Daniel's view of Group 2: scorer slot shows Daniel with lock? Or empty/missing-scorer banner?
- Ziggy's view of Group 2: scorer = Daniel? Or empty?
- Can Daniel actually enter scores? Or blocked?
- `skins_groups.scorer_ids` value before vs after reconciliation
- `round_players` value for Daniel before vs after

**Decision matrix based on results:**

| Result | Implication |
|---|---|
| Scorer survives (lock shows for Daniel) | Code path I haven't found handles this. My theory wrong. Update docs to reflect actual flow. |
| Scorer broken (missing-scorer banner) | Gap 2 is real. Decide: fix in 1.0.8 (server trigger update + client remap), defer to 1.0.9, or document + ship as-is. |
| Mixed (Daniel sees one thing, Ziggy sees another) | Sync issue between client and server. Drill deeper. |

## Files in scope

| File | Why relevant |
|---|---|
| `Carry/Views/QuickStartSheet.swift` | Gap 1 prefill (B+); Gap 2 SMS slot creation + Player.id derivation |
| `Carry/Views/PlayerGroupsSheet.swift` | Alternative SMS-invite path (mid-round add) |
| `Carry/Views/GroupManagerView.swift` | `syncScorerIDs` rules — where the wipe happens |
| `Carry/Models/Player.swift` | `stableId(from: UUID)` derivation |
| `Carry/Services/GroupService.swift` | `inviteMemberByPhone` (SMS invite server INSERT) |
| `supabase/migrations/20260502000003_fix_phone_invite_joined_at.sql` | Reconciliation trigger — only updates `group_members` |
| `supabase/migrations/20260330000003_group_scorer_ids.sql` | `scorer_ids` jsonb column |
| `docs/architecture/scorer-rules.md` | Doc with paused updates pending verification |
| `docs/architecture/game-types.md` | Doc with paused updates pending verification |
| `docs/architecture/playbook.md` | Doc with paused updates pending verification |

## Decisions paused / awaiting verification

- ❌ NOT shipping B+ prefill fix yet (waiting until full picture is verified)
- ❌ NOT updating `scorer-rules.md` further with SMS-invite-scorer claims (would be aspirational not factual)
- ❌ NOT shipping demo on `hotfix/1.0.8` until SMS test clarifies whether Gap 2 needs scope
- ✅ Doc updates already shipped: foundational premise (scorer = Carry user), pending-invitee precision, prefill-overwrite footnote. These reflect verified code behavior.

## Resume instructions for a new session

1. Read this file end-to-end
2. Read the chat history if available; otherwise:
   - Read `docs/architecture/scorer-rules.md` (current state of scorer doc)
   - Read `Carry/Views/QuickStartSheet.swift` lines 343-438 (`prefillFromRecentGame`)
   - Read `supabase/migrations/20260502000003_fix_phone_invite_joined_at.sql` (reconciliation trigger)
3. Check `git log hotfix/1.0.8 ^hotfix/1.0.7` for the commits made during this investigation
4. Confirm with user where they are in the test plan above
5. If SMS test is complete, the result determines next steps per the decision matrix
6. The B+ prefill fix is documented above — implement only after Gap 2 picture is clear

## Side-quest TODOs (don't block this test)

- **SMS link preview missing on Daniel's current phone** (2026-05-12). The SMS sent from Ziggy contained `https://carryapp.site/invite` (no group UUID query param visible). Preview rendered on the OLD phone (Ziggy's device) but not on Daniel's CURRENT phone. Possible causes: (a) iOS link-preview behavior differs by device, (b) the SMS body itself is malformed/missing query params for `?group=UUID` (need to check SMS body construction in `inviteMemberByPhone` flow / QuickStartSheet send-invite path), (c) Carry app pre-installed status affects preview rendering. Investigate later — not blocking this test.

## Last updated

2026-05-12 — initial capture during chat session. Update as test progresses.
