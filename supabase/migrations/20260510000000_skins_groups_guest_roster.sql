-- 20260510000000_skins_groups_guest_roster.sql
--
-- ⚠️ APPLICATION HISTORY: Applied to dev project (gbhljwtbobbxervekxkg) via
-- Supabase Studio SQL editor on 2026-05-10, NOT via `supabase db push`.
-- Reason: `db push` is blocked by the squash-branch migration drift
-- (see auto-memory MEMORY.md "Infra gotchas"). The migration is idempotent
-- (`ADD COLUMN IF NOT EXISTS`); when the squash branch eventually merges
-- to main and `db push` is restored, this file will execute cleanly,
-- skip the column add (already exists), and insert its tracking row.
-- Verify reconciliation as part of the squash-merge cleanup.
--
-- ⚠️ COLUMN TYPE CORRECTION 2026-05-10: this column was originally declared
-- as `jsonb`, but the iOS encoding pattern (`String?` field on
-- `SkinsGroupUpdate` containing a JSON-encoded array string) only round-trips
-- correctly through a `text` column. With `jsonb`, Postgres parsed the
-- incoming string value and stored it as a JSON-string SCALAR, not an array
-- — so reads got garbage names ("Guest", handicap 0.0). Same encoding pattern
-- as `tee_times_json` (also `text`). Dev was patched live in Studio:
--   ALTER TABLE skins_groups DROP COLUMN guest_roster_json;
--   ALTER TABLE skins_groups ADD COLUMN guest_roster_json text;
-- This file now reflects the corrected target schema.
--
-- Adds `guest_roster_json` column to `skins_groups` to persist Quick Game
-- guest rosters between rounds across app delete + reinstall and across
-- multiple devices.
--
-- Background
-- ----------
-- Quick Game guests live in `round_players` only when a round is active
-- (locked 2026-05-01: ephemeral guest rule). Between rounds — Quick Game
-- in setup, no active round — guests had no server home. iOS held a
-- UserDefaults snapshot via QuickGameGuestStorage but it was wiped on
-- app delete + reinstall and didn't sync across devices.
--
-- This column closes the gap: a JSON-encoded text snapshot of the QG's
-- between-round roster (array of {id, name, initials, color, handicap,
-- avatar, group, profileId}). Writes happen on every guest add/remove.
-- Reads happen on first load of a Quick Game.
--
-- Why on `skins_groups` and not a separate table:
--   - Lifecycle is identical to the group row (created, deleted together)
--   - Avoids a join on every Quick Game load
--   - Per row, payload is small (typical 2-4 guests, < 1KB)
--
-- Why `text` not `jsonb`:
--   - iOS sends the array as a JSON-encoded String (matches `tee_times_json`)
--   - With `text`, Postgres stores the string verbatim and iOS decodes it on read
--   - With `jsonb`, Postgres parses the incoming string and stores a string scalar
--     (not an array), corrupting the round-trip
--
-- This does NOT violate any locked invariant:
--   - `group_members` stays Carry-only (separate table)
--   - Guest profile rows still get wiped on round end (ephemeral guest rule intact)
--   - `created_by` immutability untouched
--
-- RLS: column-level access follows the existing row-level policy on
-- `skins_groups` — only the creator can UPDATE.

ALTER TABLE skins_groups
  ADD COLUMN IF NOT EXISTS guest_roster_json text;

COMMENT ON COLUMN skins_groups.guest_roster_json IS
  'Quick Game between-round guest roster snapshot. JSON-encoded array of {id, name, initials, color, handicap, avatar, group, profileId}. NULL for Skins Groups (which never have guests by architectural invariant). Written by iOS on guest add/remove; read on first load. Matches `tee_times_json` pattern.';

-- No default. Existing rows have NULL until the next iOS write.
-- No CHECK constraint on shape — iOS owns the schema.
