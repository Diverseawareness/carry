# DB Schema Rules

**TL;DR:** 9 core tables, RLS on all. FK cascades structured to allow ephemeral guest profiles. Locked invariants: Carry-only `group_members`, ephemeral `round_players` guests, creator immutability.

## Core tables

| Table | Purpose | Key invariant |
|---|---|---|
| `profiles` | Identity (Carry users + ephemeral guest placeholders) | `is_guest = true` for ephemeral guests; auto-created via `handle_new_user()` trigger on `auth.users` INSERT |
| `skins_groups` | Group entity | `created_by` immutable post-INSERT. Carries `is_quick_game`, `handicap_percentage`, `tee_times_json`, `scorer_ids`, `winnings_display`, `recurrence`, `guest_roster_json` (post 2026-05-10) |
| `group_members` | Junction (group_id × player_id × status) | **Carry-only** (locked 2026-05-01) |
| `rounds` | Per-round state | `created_by` + `group_id` (optional). Status: `'active'`, `'concluded'`, `'completed'`, `'cancelled'` |
| `round_players` | Per-round roster (incl. guests via denormalized fallback) | **No FK on `player_id`** — UUID survives guest profile wipe |
| `scores` | Per-hole gross scores | Same FK-less pattern as `round_players` |
| `holes` | Course tee box hole data | Stroke index = `hcp` column |
| `tee_boxes` | Tee box metadata | `course_rating`, `slope_rating`, `par`, `holes_json` |
| `device_tokens` | APNs registrations | RLS: own only |

Key migrations:

| Migration | Purpose |
|---|---|
| [20260322000000_complete_base_schema.sql](../../supabase/migrations/20260322000000_complete_base_schema.sql) | Most schema |
| [20260320000000_skins_groups.sql](../../supabase/migrations/20260320000000_skins_groups.sql) | `skins_groups` table |
| [20260328000002](../../supabase/migrations/20260328000002_quick_game_flag.sql) | `is_quick_game` column |
| [20260330000003](../../supabase/migrations/20260330000003_group_scorer_ids.sql) | `scorer_ids` column |
| [20260501000001](../../supabase/migrations/20260501000001_ephemeral_quick_game_guests.sql) | Ephemeral guests + FK drops |
| [20260510000000](../../supabase/migrations/20260510000000_skins_groups_guest_roster.sql) | `guest_roster_json` column |

## Architectural invariants

| Invariant | Locked | Enforcement |
|---|---|---|
| **Carry-only `group_members`** — Skins Groups never have guest rows | 2026-05-01 | Server-side: `convert_quick_game_to_group` calls `delete_quick_game_guests` to wipe guests before flipping `is_quick_game = false`. Client-side: `loadSingleGroup` filters wiped-guest UUIDs from current roster ([GroupService.swift:1234-1240](../../Carry/Services/GroupService.swift:1234)) |
| **Ephemeral guests** — guest profiles only in `round_players` for active rounds; survive round end via denormalized `guest_display_name` + `guest_handicap` | 2026-05-01 | `delete_quick_game_guests(round_id)` denormalizes name+handicap onto round_players + scores then DELETEs guest profile rows. Between-round roster persists in `skins_groups.guest_roster_json` (post 2026-05-10). See [guest-lifecycle.md](guest-lifecycle.md) |
| **Round lifecycle** | — | Status state machine `'active' → 'concluded' \| 'completed' \| 'cancelled'`. Only round creator can mutate post-INSERT (RLS) |
| **Creator immutability** | — | `skins_groups.created_by` set at INSERT, never updated. No UPDATE policy modifies the column. Creator is only DELETE-authorized user |
| **No FK on `round_players.player_id` / `scores.player_id`** | 2026-05-01 | Dropped in [20260501000001:66-68](../../supabase/migrations/20260501000001_ephemeral_quick_game_guests.sql:66) so guest profile wipes don't cascade. Denormalized fallback fields preserve display data for missing-profile rows |

## RLS policies — quick reference

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `profiles` | any authenticated | `auth.uid() = id` | `auth.uid() = id` | (none — keep history) |
| `skins_groups` | members + invitees + creator | `auth.uid() = created_by` | creator only | creator only |
| `group_members` | own row + members of own group | creator-add OR self-join (`player_id = auth.uid()`) | creator OR self-status | creator OR self-leave |
| `rounds` | creator + participants + group members | `auth.uid() = created_by` | creator only | (none typically — soft cancel via status) |
| `scores` | round participants | round participants | round participants | (none) |
| `device_tokens` | own | own | own | own |

## Foreign key cascade rules

| FK | Constraint | Why |
|---|---|---|
| `group_members.player_id → profiles.id` | ON DELETE CASCADE | Safe: guests never here; Carry user profile delete cascades |
| `round_players.player_id → profiles.id` | **DROPPED** | UUID survives guest wipe; denormalized fallback used |
| `scores.player_id → profiles.id` | **DROPPED** | Same rationale |
| `rounds.group_id → skins_groups.id` | (no CASCADE declared) | Group delete would orphan rounds — never auto-delete groups with active/concluded rounds |
| `group_members.group_id → skins_groups.id` | ON DELETE CASCADE | Group delete cleans up members |
| `rounds.created_by → profiles.id` | (RESTRICT-style) | User delete should not cascade rounds |

## JSON column conventions

| Convention | iOS field shape | Postgres column type | Examples |
|---|---|---|---|
| Pre-serialized JSON (iOS owns the schema) | `String?` containing JSON text | `text` | `tee_times_json`, `holes_json`, `last_tee_box_holes_json`, `guest_roster_json` |
| Natively Codable Swift type | concrete type like `[Int]?` | `jsonb` | `scorer_ids` |
| ⚠️ Inconsistent (works but mismatches) | `String?` | `jsonb` | `recurrence` — should be `text` for consistency, but Postgres scalar round-trip preserves content |

When adding a new JSON column, pick one convention and stick to it. Don't mix.

## Custom types / enums

All as `text` columns with implicit constraints (no PostgreSQL enums):

| Column | Values |
|---|---|
| `rounds.status` | `'active'`, `'concluded'`, `'completed'`, `'cancelled'` |
| `group_members.status` | `'active'`, `'invited'`, `'declined'`, `'removed'` |
| `round_players.status` | `'accepted'`, others |
| `winnings_display` | `'gross'`, `'net'` (CHECK constraint) |

## Key indexes

| Index | Purpose |
|---|---|
| `idx_profiles_phone` | Partial on `phone` non-null — fast phone-invite reconciliation |
| `group_members_unique_real_player` | Partial unique on `(group_id, player_id) WHERE invited_phone IS NULL OR ''` — dedupes real memberships, allows multiple phone-invites |
| `idx_group_members_player` | `player_id WHERE status = 'active'` — fast group lookup for a user |
| `idx_group_members_invited` | `player_id WHERE status = 'invited'` — pending invites view |
| `idx_rounds_group` | `group_id WHERE NOT NULL` — list rounds in a group |
| `idx_rounds_status` | `(status, created_at DESC)` — recent active/concluded list |
| `idx_round_players_player_status` | `(player_id, status)` — what rounds is this user in? |
| `idx_scores_round`, `idx_scores_round_player_hole` | Score lookup paths |

## Database functions / RPCs

| Function | Purpose | Migration |
|---|---|---|
| `handle_new_user()` | Auto-create profile row on auth.users INSERT | [20260322:316-340](../../supabase/migrations/20260322000000_complete_base_schema.sql:316) |
| `convert_quick_game_to_group(p_group_id, p_group_name)` | Atomic Quick Game → Skins Group conversion | [20260501000002](../../supabase/migrations/20260501000002_convert_quick_game_carry_only_auto_accept.sql) |
| `delete_quick_game_guests(p_round_id)` | Creator-only guest cleanup | [20260501000001:80-142](../../supabase/migrations/20260501000001_ephemeral_quick_game_guests.sql:80) |
| `find_pending_invites_by_phone(p_phone)` | Phone-invite lookup for post-onboarding modal | [20260502000001](../../supabase/migrations/20260502000001_phone_invite_lookup.sql) |
| `claim_phone_invite(p_membership_id, p_phone)` | Reconcile pending phone invite to authenticated user | same |
| `reconcile_phone_invites_for_profile()` | Auto-reconcile on profile.phone change | [20260502000002](../../supabase/migrations/20260502000002_phone_on_profile.sql) |
| `reconcile_phone_invite_at_insert()` | Reverse: claim invite at INSERT time if profile already has matching phone | [20260502000004](../../supabase/migrations/20260502000004_reverse_phone_invite_at_insert.sql) |
| `notify_push()` | Per-table dispatcher → posts to send-push-notification Edge Function | [20260509000000](../../supabase/migrations/20260509000000_notify_push_use_vault.sql) |
| `send_handicap_reminders()` | pg_cron daily handicap reminder | same |
| `_vault_secret_or_default()`, `_push_notification_url()`, `_push_notification_anon_key()` | Shared Vault read helpers | same |

## Squashed baseline (2026-05-06)

| Field | Value |
|---|---|
| Squash | 48 migrations → single `20260101000000_baseline.sql` (pg_dump of prod) |
| Branch | `infra/squash-migrations-baseline`, commit `02db5c0` |
| Status as of 2026-05-10 | Behind active hotfix branches; squash branch + hotfix/1.0.6 diverged in both directions |
| Dev schema | baseline + post-squash migrations applied via Supabase CLI |
| Prod schema | full migration history; `supabase migration repair` ran 2026-05-06 |
| Drift workaround | `supabase db push` blocked. New migrations applied via Supabase Studio SQL editor (idempotent). Tracking row reconciles on next clean push after squash merge |

## Vault schema

| Object | Purpose |
|---|---|
| `vault.secrets` | UNIQUE name; encrypted secret column; insert via `vault.create_secret(secret, name)` API |
| `vault.decrypted_secrets` (view) | Read-only decrypt of `vault.secrets` |
| Per-environment setup | One-time `SELECT vault.create_secret('<value>', '<name>')` per env |

`INSERT INTO vault.secrets` directly from SQL Editor errors `42501: permission denied for function _crypto_aead_det_noncegen`. Use the API.

## Phone invite reconciliation flow (server-side)

| Step | Action |
|---|---|
| 1 | Sender invites by phone → `group_members` INSERT with `invited_phone`, `player_id = inviter UUID placeholder`, `status='invited'` |
| 2a | **Receiver-side:** recipient adds phone to profile → `reconcile_phone_invites_for_profile()` trigger → orphan-row cleanup ([20260502000005](../../supabase/migrations/20260502000005_cleanup_orphan_phone_invites_on_reconcile.sql)) → UPDATE pending invite to `active` → push fires |
| 2b | **Sender-side:** sender invites phone already on profile → `reconcile_phone_invite_at_insert()` trigger BEFORE INSERT → mutates NEW row to `active` → push fires |
| 3 | 30-day staleness guard on auto-reconcile (older invites require explicit retry) |

See [group-invitation-flow.md](group-invitation-flow.md).

## Common bugs / gotchas

| Bug | Notes |
|---|---|
| The 42703 cross-binding bug | `notify_push()` referencing `NEW.player_id` outside table guards broke every `rounds` INSERT for two days in TF 60. Fix: per-table dispatcher |
| `group_members_unique_real_player` partial index | Without `WHERE invited_phone IS NULL OR ''`, multiple phone-invite rows for same recipient (legitimate) would conflict. Partial index lets phone invites stack while non-phone rows stay deduped |
| Squash drift | 48 migrations squashed to baseline, but squash branch diverged from main. Eventually requires reconciliation pass; do NOT run `supabase migration repair` shortcut without first merging squash → main (would re-apply broken pre-squash migrations). Workaround for new migrations: apply via Studio SQL editor |
| No CASCADE on `rounds.group_id` | Deleting group with rounds would orphan them. Pattern: never auto-delete groups with round history |

## Last verified

2026-05-10 — converted to machine-readable format. `guest_roster_json` column added (text, matches `tee_times_json` pattern; jsonb attempted first then corrected — see bug-archive entry).
