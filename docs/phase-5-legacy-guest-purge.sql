-- ============================================================================
-- Phase 5 — One-time legacy guest profile purge
-- Run AFTER:
--   * 20260501000001_ephemeral_quick_game_guests.sql is applied to prod
--   * 20260501000002_convert_quick_game_carry_only_auto_accept.sql is applied
--   * The iOS build with the Phase 2 changes is shipped and confirmed working
--   * You've run a few real Quick Games to validate the wipe path end-to-end
--
-- What this does:
--   1. Backfills guest_display_name + guest_handicap onto round_players + scores
--      for every legacy is_guest=true profile (so historical Round History
--      keeps showing those guests by name once the profiles are deleted).
--   2. Hard-deletes every is_guest=true profile in the DB. The dropped FK on
--      round_players + scores means the player_id UUIDs survive — denormalized
--      fields on those tables preserve the rendering. group_members rows for
--      these profiles cascade-delete (Skins Groups are Carry-only by rule).
--
-- This is destructive. Run in a transaction so you can rollback if a sanity
-- check fails. Do NOT run pieces individually — the backfill and delete must
-- happen in one transaction or you lose history for any guest deleted before
-- the backfill ran.
-- ============================================================================

BEGIN;

-- ─── Sanity check: how many guests are we about to wipe? ──────────────────
-- Eyeball the count before committing. Should be a sensible number (< a few
-- hundred for v1.0.x). If it's surprisingly large, investigate before commit.
SELECT count(*) AS legacy_guest_count
FROM public.profiles
WHERE is_guest = true;

-- ─── Backfill round_players with guest names ──────────────────────────────
UPDATE public.round_players rp
SET guest_display_name = p.display_name,
    guest_handicap = p.handicap
FROM public.profiles p
WHERE rp.player_id = p.id
  AND p.is_guest = true
  AND rp.guest_display_name IS NULL;

-- ─── Backfill scores with guest names ─────────────────────────────────────
UPDATE public.scores s
SET guest_display_name = p.display_name,
    guest_handicap = p.handicap
FROM public.profiles p
WHERE s.player_id = p.id
  AND p.is_guest = true
  AND s.guest_display_name IS NULL;

-- ─── Hard delete every legacy guest profile ───────────────────────────────
-- group_members rows for these profiles cascade-delete via the FK changed
-- in migration 20260501000001. round_players + scores keep their player_id
-- UUIDs (FK was dropped); the denormalized fields above preserve the names.
DELETE FROM public.profiles
WHERE is_guest = true;

-- ─── Sanity checks before commit ──────────────────────────────────────────
-- a. Confirm all is_guest=true profiles are gone.
SELECT count(*) AS remaining_guest_profiles FROM public.profiles WHERE is_guest = true;
-- Expect: 0

-- b. Confirm round_players denormalize fields are populated for any orphaned
--    UUID (where the profile no longer exists).
SELECT count(*) AS orphaned_rp_with_no_name
FROM public.round_players rp
WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = rp.player_id)
  AND rp.guest_display_name IS NULL;
-- Expect: 0

-- c. Same check on scores.
SELECT count(*) AS orphaned_scores_with_no_name
FROM public.scores s
WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = s.player_id)
  AND s.guest_display_name IS NULL;
-- Expect: 0

-- ─── If all three checks pass, commit. Otherwise ROLLBACK. ────────────────
-- COMMIT;
-- ROLLBACK;
--
-- Don't auto-commit. Read the counts above first.
