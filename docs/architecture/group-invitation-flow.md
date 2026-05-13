# Group Invitation Flow

**TL;DR:** Three invite paths: search-add Carry users (auto-active), SMS phone (active when reconciled), QG → SG conversion (auto-accept). Phone reconciliation has 2 directions (forward + reverse triggers). 30-day staleness guard. All paths converge on `group_members.status = 'active'`.

## SMS body encoding — load-bearing

[ScorerAssignmentView.swift:430-444](../../Carry/Views/ScorerAssignmentView.swift:430), [ManageMembersSheet.swift:740-756](../../Carry/Views/ManageMembersSheet.swift:740), [GroupsListView.swift:3817-3833](../../Carry/Views/GroupsListView.swift:3817).

All three SMS-composer call sites build the body as:
```swift
let body = "Join my skins game on Carry! https://carryapp.site/invite?group=<uuid>"
var allowed = CharacterSet.urlQueryAllowed
allowed.remove(charactersIn: "?&=#")
let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
if let url = URL(string: "sms:\(digits)&body=\(encoded)") { … }
```

**Why the custom CharacterSet:** `.urlQueryAllowed` permits `?`, `&`, `=`, `#` raw. The deep-link's own `?group=<uuid>` query, embedded inside the SMS body, would chunk the outer `sms:` URL's query string and Messages would drop everything after `/invite`. Removing those four chars forces them to percent-escape (`%3F`, `%26`, `%3D`, `%23`) inside the body. Recipient's iOS percent-decodes once when parsing the link, leaving the deep link intact.

**Regression history:** Pre-`593cce8`, the encoding used vanilla `.urlQueryAllowed` and the recipient saw `https://carryapp.site/invite` (no group_id). Install bridge failed to route into the right group. Diagnosed via the Daniel/Ziggy E2E test on 2026-05-13. Fix applied to all three call sites. PlayerGroupsSheet's inline phone invite uses a body without a `?` query (just the homepage URL) — not affected.

## Self-invite block

[ScorerAssignmentView.swift:398-402](../../Carry/Views/ScorerAssignmentView.swift:398), [ManageMembersSheet.swift:687-697](../../Carry/Views/ManageMembersSheet.swift:687).

Both SMS-composer paths check the typed digits against the inviter's profile phone (last-10-digits comparison to tolerate leading `1` country-code variance):
```swift
if let selfDigits = authService.currentUser?.phone?.filter({ $0.isNumber }),
   selfDigits.suffix(10) == digits.suffix(10),
   !selfDigits.isEmpty {
    ToastManager.shared.error("You can't invite yourself …")
    return
}
```

**Why:** Without the guard, the reverse-reconcile trigger collapses the new `group_members` row immediately into the inviter's profile → silent double-add (already a member as creator, now also briefly as a reconciled invite). For QG SMS-invite-as-scorer it'd ALSO orphan the iOS scorer slot pointing at the locally-minted UUID. Block early in the UI.

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

Two server-side write paths exist:

| Caller | Server entry | Notes |
|---|---|---|
| ManageMembersSheet `sendInvite` (1.0.9), PlayerGroupsSheet step 3c, ScorerAssignmentView | [GroupService.swift:460-479](../../Carry/Services/GroupService.swift:460) `reservePhoneInvite(id:groupId:phone:invitedBy:groupNum:inviteeName:)` → RPC `create_phone_invite` | Caller mints the row UUID + passes typed `inviteeName`. Returned id may differ from supplied id on dedup hit (callers re-anchor — see below) |
| Legacy direct INSERT path | [GroupService.swift:415-435](../../Carry/Services/GroupService.swift:415) `inviteMemberByPhone` | Still present but no longer called from the three SMS-composer surfaces |

Both paths produce the same row shape:
```sql
INSERT INTO group_members
  (group_id, player_id, invited_phone, status, joined_at, invitee_name, group_num)
VALUES
  (<group>, <inviter UUID placeholder>, <digits-only phone>, 'invited', now(),
   <typed name or null>, <group_num or 1>)
```

`player_id` is a placeholder until reconciliation. Real signal: `invited_phone` + `status = 'invited'`.

### `create_phone_invite` RPC dedup behavior (1.0.9, migration `20260513000006`)

[20260513000006_create_phone_invite_update_on_dedup.sql:22-76](../../supabase/migrations/20260513000006_create_phone_invite_update_on_dedup.sql:22). On dedup hit (existing row with same `group_id` + `invited_phone`):

| # | Action |
|---|---|
| 1 | UPDATE `group_num` to caller-supplied value |
| 2 | UPDATE `invitee_name` to caller-supplied value (preserves prior name if caller passed null) |
| 3 | Re-arm `status = 'invited'` (covers the case where prior row was 'removed' or auto-collapsed to 'active' by a stale reconciliation) |
| 4 | RETURN the existing row's id (NOT the supplied id) |

**iOS callers re-anchor on the returned id** when it differs from the supplied UUID:
- ManageMembersSheet.sendInvite at [ManageMembersSheet.swift:779-785](../../Carry/Views/ManageMembersSheet.swift:779) — patches `localGuests[idx].inviteMemberId = returnedId`
- PlayerGroupsSheet step 3c — same pattern

Without re-anchor, the local stub's `inviteMemberId` stays the freshly-minted UUID while the server row's id is the old one. `localAllAvailable` dedup-by-`inviteMemberId` (introduced commit `198ad40`) would treat them as different invites and the Pending chip would render twice until force-quit.

Pre-`aa4da69`/migration `20260513000006`: dedup returned the existing id without updating any fields. Stale `group_num` from a 1.0.8 race + stale typo'd `invitee_name` survived re-invites indefinitely.

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

### Long-press delete on pending phone-invite chip (1.0.9)

[ManageMembersSheet.swift:553-561](../../Carry/Views/ManageMembersSheet.swift:553) `requestRemoval(of:)` accepts both confirmed Carry members AND pending SMS-invite rows. Phone-invite branch deletes by `inviteMemberId` (the row's `group_members.id`) rather than `(group_id, player_id)`:

```swift
if player.isPendingInvite, let inviteMemberId = player.inviteMemberId {
    try await client.from("group_members")
        .delete()
        .eq("id", value: inviteMemberId.uuidString)
        .execute()
}
```

A `(group_id, player_id)` delete would either miss (placeholder UUID) or accidentally hit the inviter's regular row. The per-id delete is exact.

Self-removal block at [:556-559](../../Carry/Views/ManageMembersSheet.swift:556) — long-press on a row whose `profileId == currentUser.id` toasts "use Leave/Delete Group" and returns early. Mirrors the self-invite block.

### Clipboard-detection invite path removed (1.0.9, commit `42b2e99`)

Pre-1.0.9 HomeView checked the system clipboard on `.onAppear` for a `carryapp.site/invite?group=...` URL and showed an "Open your invite?" alert. Removed in 1.0.9 because:

| Reason | Detail |
|---|---|
| Phone-on-profile (1.0.3+) supersedes it | Reverse-reconcile trigger handles the install-bridge case server-side — no clipboard hand-off needed |
| iOS 16+ paste-permission prompt UX | The clipboard read triggered a confusing system prompt unrelated to the user's intent |
| Privacy-noise in App Privacy report | Removed clipboard read narrows the privacy surface |

Removed: HomeView's `clipboardInviteAvailable` state, `checkClipboardForInvite()`, `markClipboardInviteAcknowledged()`, `consumeClipboardInvite()`, the alert, the .onAppear clipboard check, two AppRouter `@Published` flags, two DebugMenuView action rows, the DEBUG sheet for PhoneInviteFinderSheet (162 lines total).

**Kept** as a safety net for pre-1.0.3 users without a phone on profile: ProfileSheetView's manual "Find an Invite" entry → PhoneInviteFinderSheet (calls `claim_phone_invite` RPC).

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

2026-05-13 — added `create_phone_invite` RPC dedup-UPDATE behavior (migration `20260513000006`), long-press delete on pending phone-invite chips, clipboard-detection removal callout. Forward + reverse triggers + SMS body encoding stable.
