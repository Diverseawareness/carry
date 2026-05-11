# Push Trigger Chain

**TL;DR:** Four Postgres functions call the `send-push-notification` Edge Function via `pg_net.http_post`. All authenticate via shared Vault helpers (post 2026-05-09). Edge function dispatches by record shape, gated by user notification preferences.

## Four push-firing Postgres functions

All in [20260509000000_notify_push_use_vault.sql](../../supabase/migrations/20260509000000_notify_push_use_vault.sql).

### 1. `notify_push()` — row-trigger dispatcher

| Property | Value |
|---|---|
| Triggers | `on_group_member_change` AFTER INSERT/UPDATE on `group_members` ([20260330000001](../../supabase/migrations/20260330000001_push_notification_triggers.sql)); `on_round_change` AFTER INSERT/UPDATE on `rounds` (same); `on_score_insert` AFTER INSERT on `scores` ([20260402000000](../../supabase/migrations/20260402000000_score_trigger_all_groups_active.sql), restored after 2026-04-26 drop) |
| Dispatch | Per-table IF/THEN blocks ([:139-156](../../supabase/migrations/20260509000000_notify_push_use_vault.sql:139)) guard all `NEW.<col>` references — prevents the 42703 cross-binding bug ([20260501000000](../../supabase/migrations/20260501000000_fix_notify_push_per_table_dispatch.sql)) |

Payload shape:
```jsonb
{
  "type": TG_OP,
  "table": TG_TABLE_NAME,
  "record": to_jsonb(NEW),
  "old_record": to_jsonb(OLD),    // UPDATE only
  "self_initiated": true | false  // group_members only: did auth.uid() match NEW.player_id?
}
```

### 2. `send_handicap_reminders()` — pg_cron daily

| Property | Value |
|---|---|
| Schedule | Daily 02:00 UTC. Pre-tee-time handicap reminder |
| Recipients | Profiles with active `group_members` row + `skins_groups` with `tee_times_json` timestamps in next 12-36h |
| Payload | `{type: 'handicapReminder', user_id, body}` — body: "Almost game time — Carry has you at <X.X>. Still right?" |

### 3. `reconcile_phone_invites_for_profile()` — phone-on-profile trigger

| Property | Value |
|---|---|
| Trigger | AFTER INSERT OR UPDATE OF phone on `profiles` |
| Flow | Normalize phone (digits-only, 10-char min) → DELETE orphan phone-invite rows where matched profile already in group via non-phone row → UPDATE pending invites to active → fire push per reconciled membership |
| Payload | `{type: 'phoneInviteReconciled', user_id, group_id, group_name, body}` — body: "You've been added to <Group Name>!" |
| Staleness guard | Only reconciles invites created within last 30 days |

### 4. `reconcile_phone_invite_at_insert()` — reverse-direction phone reconcile

| Property | Value |
|---|---|
| Trigger | BEFORE INSERT on `group_members` |
| Flow | When `invited_phone` set on insert, look up matching profile by phone → promote NEW row to active mid-trigger (mutate `NEW.player_id`, `NEW.invited_phone = ''`, `NEW.status = 'active'`) → fire push to reconciled user |
| Dedupe | Returns NULL (skip insert) if matched profile already in group via non-phone row |

## Shared Vault helpers (introduced 2026-05-09)

### `_vault_secret_or_default(name, default)`

[20260509000000:70-85](../../supabase/migrations/20260509000000_notify_push_use_vault.sql:70). Reads `vault.decrypted_secrets`. EXCEPTION handler silently falls back to `default` on any error. Returns `coalesce(nullif(value, ''), default)` — empty string treated as NULL.

### `_push_notification_url()`

[20260509000000:93-113](../../supabase/migrations/20260509000000_notify_push_use_vault.sql:93). Resolution chain:

| # | Source |
|---|---|
| 1 | Vault: `supabase_push_url` if non-empty |
| 2 | GUC: `app.settings.supabase_url + '/functions/v1/send-push-notification'` if non-empty |
| 3 | Hardcoded prod fallback: `https://seeitehizboxjbnccnyd.supabase.co/functions/v1/send-push-notification` |

### `_push_notification_anon_key()`

[20260509000000:115-133](../../supabase/migrations/20260509000000_notify_push_use_vault.sql:115). Resolution chain:

| # | Source |
|---|---|
| 1 | Vault: `supabase_anon_key` if non-empty |
| 2 | GUC: `app.settings.supabase_anon_key` or `supabase.anon_key` if present |
| 3 | Empty string (Bearer token empty → 401 if Verify JWT on) |

## Edge Function `send-push-notification`

[supabase/functions/send-push-notification/index.ts](../../supabase/functions/send-push-notification/index.ts).

Inbound payload shapes:

| Source | Shape |
|---|---|
| Row triggers | `{type, table, record, old_record, self_initiated}` |
| Custom callers | `{type, user_id, body, ...}` (no `record` field) |

Dispatch:

Custom-type early returns (lines ~38-45):

| Type | Handler |
|---|---|
| `handicapReminder` | `handleHandicapReminder()` |
| `phoneInviteReconciled` | `handlePhoneInviteReconciled()` |

Row-shape dispatch (~lines 70-138):

| Branch | Detection | Handler | Pref gate |
|---|---|---|---|
| Group invite | `group_members` INSERT, status='invited', no phone | `handleGroupInvite` | `notif_game_alerts` |
| Member joined | `group_members` UPDATE invited→active | `handleMemberJoined` | `notif_group_activity` |
| Member added (direct active INSERT) | `group_members` INSERT, status='active', no phone | `handleMemberAdded` | `notif_game_alerts` |
| Member declined | `group_members` UPDATE *→'declined' | `handleMemberDeclined` | `notif_group_activity` |
| Score dispute | `scores` INSERT with hole_num + proposed_score | `handleScoreDispute` | `notif_group_activity` |
| All groups active | `scores` INSERT, all group_nums have ≥1 score | `handleAllGroupsActive` | `notif_live_scoring` |
| Round started | `rounds` INSERT, status='active' | `handleRoundStarted` | `notif_game_alerts` |
| Round ended | `rounds` UPDATE → status='completed' | `handleRoundEnded` | `notif_game_alerts` |
| Game deleted | `rounds` UPDATE → status='cancelled' | `handleGameDeleted` | `notif_group_activity` |
| Game force-ended | `rounds` UPDATE force_completed=true + status='concluded' | `handleGameForceEnded` | `notif_group_activity` |
| Scorer changed | `rounds` UPDATE scorer fields changed | `handleScorerChanged` | `notif_game_alerts` |

Recipients per handler:

| Recipients | Handlers |
|---|---|
| Per-recipient | Group invite, member added, scorer changed, handicap reminder, phone invite reconciled |
| Creator only | Member joined, member declined, all-groups-active |
| All active members except creator | Round started, round ended, game deleted, game force-ended |
| All active members except proposer | Score dispute |

Auth / signing:

| Use | Auth |
|---|---|
| Internal DB queries | `SUPABASE_SERVICE_ROLE_KEY` |
| Outbound APNs calls | `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` env vars |

Stale token cleanup: on APNs response 410 OR "BadDeviceToken" / "Unregistered" body → SET `device_token = NULL` on user's profile (~lines 988-997). Logs `[Cleaned up stale device token]`.

## Vault state per project (2026-05-09)

| Project | Project ref | Secrets | Verify JWT toggle |
|---|---|---|---|
| Production | `seeitehizboxjbnccnyd` | `supabase_anon_key` + `supabase_push_url` | ON |
| Development | `gbhljwtbobbxervekxkg` | same | ON |

Setup method: `SELECT vault.create_secret(secret, name)` — NOT `INSERT INTO vault.secrets` (errors `42501: permission denied for function _crypto_aead_det_noncegen`).

## Logging + retention

| Source | Retention | Notes |
|---|---|---|
| Edge Function logs | hours+ | Supabase Dashboard → Edge Functions → send-push-notification → Logs. Diagnostic prefixes: `[dispatch]`, `[branch]`, `[apns]`, `[pref-skip]` |
| `pg_net._http_response` | ~6 hours | Used 2026-05-09 to detect 100% 401 rate |

## iOS push handling

| Event | Handler |
|---|---|
| App launch | `application(_:didFinishLaunchingWithOptions:)` registers for remote notifications, sets `UNUserNotificationCenter.current().delegate` |
| Token register | `didRegisterForRemoteNotificationsWithDeviceToken` saves hex token to `profiles.device_token` |
| Foreground present | `willPresent notification:` checks `NotificationService.shouldShowPush(type:)` against user prefs; fires custom `NotificationCenter` posts for invite/member-change |
| Tap | `didReceive response:` routes to `.didTapGroupInviteNotification`, `.didTapRoundNotification` etc. |

## The 401 incident (2026-05-09)

| Field | Value |
|---|---|
| Root cause | Prod's `app.settings.supabase_anon_key` GUC was NULL → helpers returned empty → trigger sent `Authorization: Bearer ` (empty) → Edge Function rejected 100% with 401. Permission to set GUC locked to `supabase_admin` role; `ALTER DATABASE` and `ALTER ROLE` both 42501 |
| Detection | `SELECT status_code, COUNT(*) FROM net._http_response WHERE created >= now() - interval '6 hours' GROUP BY 1` showed 274/274 = 401 |
| Workaround (immediate) | Toggled "Verify JWT with legacy secret" OFF on `send-push-notification`. Pushes flow but function URL publicly callable |
| Permanent fix | Vault-based migration (2026-05-09). Helpers read Vault first, fall back to GUC, fall back to empty. Per-environment `vault.create_secret()` calls. Verify JWT toggled back ON |

## Common bugs / gotchas

| Bug | Notes |
|---|---|
| 42703 dispatch bug | Pre 2026-05-01, `notify_push()` had `NEW.player_id` references at top level outside table guards. PL/pgSQL must bind every `NEW.<col>` against trigger's rowtype at plan time. Trigger fired on `rounds` (no player_id column) → binding failed → row INSERT rolled back → silent failure of every Quick Game / Group round-start in TF 60. Fix: dispatcher with table-keyed IF blocks |
| `pg_net._http_response` retention is short (~6h) | For older incidents, fall back to Edge Function Studio logs |
| Verify JWT toggle is per-function | Only `send-push-notification` was flipped. `send-welcome-email` (iOS-called with valid user JWT) keeps it ON |
| Adding a new function called by triggers | Must use shared helpers `_push_notification_url()` + `_push_notification_anon_key()`. Don't copy-paste resolution block — the four functions migrated to helpers 2026-05-09 specifically to prevent drift |

## Last verified

2026-05-10 — converted to machine-readable format. Vault helpers + 17 SQL tests stable.
