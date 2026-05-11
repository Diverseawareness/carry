# Group Invitation Flow

**TL;DR:** Three invite paths: search-add Carry users (auto-active), SMS phone (active when reconciled), QG → SG conversion (auto-accept). Phone reconciliation has 2 directions (forward + reverse triggers). 30-day staleness guard. All paths converge on `group_members.status = 'active'`.

## Three invite paths

| Path | Initial status | Reconciliation |
|---|---|---|
| Search-add Carry user | `'active'` (auto-accept) | None |
| SMS phone invite | `'invited'` + `invited_phone` set | Forward (recipient adds phone) OR reverse (sender invites existing-phone) trigger flips to `'active'` |
| Quick Game → Skins Group | `'active'` for Carry users; guests wiped | Implicit via `convert_quick_game_to_group` RPC |

## Search-add (Carry user)

ManageMembersSheet "search → tap → done" writes `status = 'active'` directly. **No invitation step.** Auto-accept rule locked 2026-05-01.

| Pre-lock | Post-lock |
|---|---|
| Path produced `'invited'` row → recipient saw "Joined" invite card on Home → had to tap accept | Search-add equivalent to "creator added you, you're in" |

Distinct from phone-invite: SMS-invited users have no app yet, must go through `'invited'` until they sign up + reconcile. Search-add only shows existing Carry users.

[GroupManagerView.swift:346-350](../../Carry/Views/GroupManagerView.swift:346) confirms behavior.

## SMS phone invite

[GroupService.swift:415-435](../../Carry/Services/GroupService.swift:415) `inviteMemberByPhone(groupId:phone:)`:
```sql
INSERT INTO group_members
  (group_id, player_id, invited_phone, status, joined_at)
VALUES
  (<group>, <inviter UUID placeholder>, <digits-only phone>, 'invited', now())
```

`player_id` is a placeholder until reconciliation. Real signal: `invited_phone` + `status = 'invited'`.

### Forward reconciliation — receiver adds phone

[20260502000002_phone_on_profile.sql:36-126](../../supabase/migrations/20260502000002_phone_on_profile.sql:36) `reconcile_phone_invites_for_profile()`:

| # | Step | Line |
|---|---|---|
| 1 | Trigger AFTER INSERT/UPDATE phone on `profiles` | :30 |
| 2 | Find pending `invited_phone` matching NEW.phone | :91 |
| 3 | Orphan cleanup (recipient already in group via non-phone row → DELETE phone-invite) | :78-86 |
| 4 | UPDATE pending: `player_id = NEW.id`, `invited_phone = ''`, `status = 'active'` | :91-100 |
| 5 | 30-day staleness guard | :98 |
| 6 | Push via `notify_push()` | — |

### Reverse reconciliation — sender invites existing-phone profile

[20260502000004_reverse_phone_invite_at_insert.sql:35-132](../../supabase/migrations/20260502000004_reverse_phone_invite_at_insert.sql:35) `reconcile_phone_invite_at_insert()`:

| # | Step | Line |
|---|---|---|
| 1 | Trigger BEFORE INSERT on `group_members` | :30 |
| 2 | If `invited_phone` set, look up profile by phone | :67-71 |
| 3 | Dedupe: skip if profile already in group via non-phone row | :81-90 |
| 4 | Mutate NEW: `player_id = matched_id`, `invited_phone = ''`, `status = 'active'` | :95-97 |
| 5 | INSERT proceeds with active status | — |

Net result of either direction: row ends identical. `player_id = real profile UUID`, `invited_phone = ''`, `status = 'active'`. iOS `loadSingleGroup` returns user as regular member.

### 30-day staleness guard

[20260502000002:98](../../supabase/migrations/20260502000002_phone_on_profile.sql:98) — `AND gm.joined_at > now() - interval '30 days'`. Prevents recycled phone numbers from auto-claiming stale invites. Stale invites need explicit `claim_phone_invite` RPC.

## Quick Game → Skins Group conversion

[20260501000002_convert_quick_game_carry_only_auto_accept.sql:23-80](../../supabase/migrations/20260501000002_convert_quick_game_carry_only_auto_accept.sql:23) `convert_quick_game_to_group(p_group_id, p_group_name)`:

| # | Action | Line |
|---|---|---|
| 1 | Wipe ephemeral guests via `delete_quick_game_guests(round_id)` | [:62](../../supabase/migrations/20260501000002_convert_quick_game_carry_only_auto_accept.sql:62) |
| 2 | UPDATE `skins_groups.is_quick_game = false`, set name | [:66-69](../../supabase/migrations/20260501000002_convert_quick_game_carry_only_auto_accept.sql:66) |
| 3 | Carry users stay `active` (no demote) | [:71-78](../../supabase/migrations/20260501000002_convert_quick_game_carry_only_auto_accept.sql:71) |

Carry-only auto-accept rule. Mirrors search-add rule.

## Decline path

`group_members.status = 'declined'`. UI: Home tab invite card OR ManageMembersSheet long-press (creator removing). `loadSingleGroup` filters declined from member view.

## Manual claim — `claim_phone_invite` RPC

[GroupService.swift:391-400](../../Carry/Services/GroupService.swift:391) `claim_phone_invite(p_membership_id, p_phone)`. Explicit claim outside auto-reconcile.

Called from:
| Caller | When |
|---|---|
| PhoneInviteFinderSheet post-onboarding | User taps specific pending invite |
| Stale invites bypassing 30-day guard | User explicitly opts in |

## Player flags during reconciliation

| State | `profileId` | `isPendingInvite` | `isPendingAccept` |
|---|---|---|---|
| Active member | set | false | false |
| Search-added Carry user (transient) | set | false | true |
| SMS-invited (no app) | nil | true | false |
| Reconciled SMS invite | set | false | false |

Server mapping:
| Client | Server condition |
|---|---|
| `isPendingInvite = true` | `invited_phone != ''` |
| `isPendingAccept = true` | `status = 'invited' AND invited_phone = ''` |

See [player-flags.md](player-flags.md).

## Push fired

| Event | Handler | Recipient | Pref gate |
|---|---|---|---|
| `group_members` INSERT, status=invited, no phone | `handleGroupInvite` | Invitee | `notif_game_alerts` |
| `group_members` INSERT, status=active, no phone (search-add) | `handleMemberAdded` | Added user | `notif_game_alerts` |
| `group_members` INSERT, status=invited, with phone | none — invitee has no app | — | — |
| INSERT/UPDATE → status=active via reverse trigger | `handleMemberAdded` | Reconciled user | `notif_game_alerts` |
| UPDATE status=invited→active (forward reconcile) | `handleMemberJoined` | Creator | `notif_group_activity` |
| UPDATE *→declined | `handleMemberDeclined` | Creator | `notif_group_activity` |

See [push-trigger-chain.md](push-trigger-chain.md).

## Common bugs / gotchas

| Bug | Notes |
|---|---|
| Pending phone-invite never reconciles | Usually the staleness guard. Check `joined_at` vs now; if >30 days, claim manually OR sender re-invites |
| Same person added twice | Partial unique index `group_members_unique_real_player` blocks duplicate (group, real-player) rows but allows multiple phone-invite rows. Orphan-cleanup branch DELETEs redundant phone row post-reconciliation |
| "Removed from group" false-positive on conversion | Fixed 2026-04-20. Post-conversion, members' rows briefly go `active → invited → active`. MainTabView checks actual status before firing alert |
| Sender invites own phone | Reverse trigger would auto-promote sender to active in own group. Guard upstream in `inviteMemberByPhone` (verify code) |
| Phone normalization mismatch | Both invite-write and reconcile-read must use same normalization (digits-only, 10-char). Fixed 1.0.5 across 7 input fields |

## Last verified

2026-05-10 — converted to machine-readable format. Forward + reverse triggers stable.
