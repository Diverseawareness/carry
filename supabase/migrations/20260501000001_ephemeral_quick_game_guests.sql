-- ============================================================================
-- Migration: Ephemeral Quick Game guests + history denormalization
-- Date:      2026-05-01
-- ============================================================================
-- Architectural rule (locked 2026-05-01, see memory/quick_game_guest_lifecycle.md):
--
--   Guest profiles (is_guest=true) live for the duration of ONE Quick Game
--   round only. On every Quick Game termination path — skip / save results /
--   end / force-end / convert-to-group — the guest's profile row is deleted.
--   Round History preserves the guest's name + handicap by denormalizing
--   those fields onto round_players and scores BEFORE the delete.
--
--   Skins Groups are Carry-only. Guests never appear in a Skins Group's
--   group_members table at all. (See memory file.)
--
-- This migration installs the schema + RPC needed to implement that rule.
-- The iOS hooks that CALL the RPC ship in a follow-up pass; this is purely
-- the server foundation.
-- ============================================================================
-- IMPORTANT design note:
--
-- We DROP the FK constraint on round_players.player_id and scores.player_id
-- (rather than ON DELETE SET NULL). Reasoning:
--
--   * SET NULL would leave round_players.player_id = NULL after wipe, breaking
--     the UUID-match between scores and round_players that the rendering path
--     relies on. Score-to-player attribution would have to fall back to name-
--     matching, which is fragile.
--
--   * With NO FK, the player_id UUID stays unchanged after profile delete.
--     Both round_players.player_id and scores.player_id retain their original
--     UUID — the join continues to work. iOS profile-fetch returns nothing
--     for that UUID; the render path uses the denormalized guest_display_name
--     and guest_handicap as fallback.
--
--   * group_members FK stays CASCADE because Skins Groups are Carry-only;
--     wiping a guest profile should clean up the (legacy) group_members row.
--
-- iOS DTO impact: NONE for the playerId column — stays non-optional UUID.
-- Only additive: new optional guest_display_name + guest_handicap fields.
-- ============================================================================

-- ─── 1. Denormalize columns ─────────────────────────────────────────────────
-- Storing the guest's display_name + handicap on every round_players row
-- (and every scores row) lets us delete the guest's profile while preserving
-- a complete view of historical rounds.

ALTER TABLE public.round_players
    ADD COLUMN IF NOT EXISTS guest_display_name text,
    ADD COLUMN IF NOT EXISTS guest_handicap double precision;

ALTER TABLE public.scores
    ADD COLUMN IF NOT EXISTS guest_display_name text,
    ADD COLUMN IF NOT EXISTS guest_handicap double precision;

-- ─── 2. Adjust FKs so guest profile deletion is allowed ────────────────────
-- round_players + scores: DROP the FK entirely. The player_id UUID stays as
-- a soft reference even after the profile is deleted, so the UUID join key
-- between scores and round_players keeps working for wiped guests. iOS
-- profile-fetch returns nothing for those UUIDs; render path falls back to
-- denormalized guest_display_name / guest_handicap.
-- group_members: CASCADE — Skins Groups are Carry-only by rule, so any
-- guest group_members row is legacy/transient and safe to remove on guest
-- profile delete.

ALTER TABLE public.round_players DROP CONSTRAINT IF EXISTS round_players_player_id_fkey;

ALTER TABLE public.scores DROP CONSTRAINT IF EXISTS scores_player_id_fkey;

ALTER TABLE public.group_members DROP CONSTRAINT IF EXISTS group_members_player_id_fkey;
ALTER TABLE public.group_members
    ADD CONSTRAINT group_members_player_id_fkey
    FOREIGN KEY (player_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- ─── 3. The wipe RPC ────────────────────────────────────────────────────────
-- iOS calls this once at every Quick Game termination point. Returns the
-- count of profiles deleted (informational; iOS doesn't currently surface
-- this number to the user — it's mostly useful for logs and tests).

CREATE OR REPLACE FUNCTION public.delete_quick_game_guests(p_round_id uuid)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    deleted_count int;
BEGIN
    -- Authorization: only the round creator can wipe guests for this round.
    -- SECURITY DEFINER bypasses RLS, so we enforce the gate explicitly.
    IF NOT EXISTS (
        SELECT 1 FROM rounds
        WHERE id = p_round_id AND created_by = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Not authorized — only the round creator can delete guests for round %', p_round_id;
    END IF;

    -- Step 1: denormalize display_name + handicap onto every round_players
    -- row that references one of this round's guests. We update across ALL
    -- rounds (not just p_round_id) so legacy guests-in-multiple-rounds — which
    -- shouldn't exist under the new ephemeral rule, but may exist in current
    -- prod data — also keep their history intact when their profile is wiped.
    UPDATE round_players rp
    SET guest_display_name = p.display_name,
        guest_handicap = p.handicap
    FROM profiles p
    WHERE rp.player_id = p.id
      AND p.is_guest = true
      AND p.id IN (
          SELECT DISTINCT player_id FROM round_players
          WHERE round_id = p_round_id AND player_id IS NOT NULL
      );

    -- Step 2: same denormalization for scores. This makes scorecard rendering
    -- after the wipe work without needing to JOIN through round_players to
    -- recover the guest's name.
    UPDATE scores s
    SET guest_display_name = p.display_name,
        guest_handicap = p.handicap
    FROM profiles p
    WHERE s.player_id = p.id
      AND p.is_guest = true
      AND p.id IN (
          SELECT DISTINCT player_id FROM round_players
          WHERE round_id = p_round_id AND player_id IS NOT NULL
      );

    -- Step 3: delete the guest profiles. Cascades:
    --   round_players.player_id → SET NULL (denormalized fields preserve display)
    --   scores.player_id        → SET NULL (denormalized fields preserve display)
    --   group_members           → CASCADE  (row removed entirely)
    DELETE FROM profiles
    WHERE is_guest = true
      AND id IN (
          SELECT DISTINCT player_id FROM round_players
          WHERE round_id = p_round_id AND player_id IS NOT NULL
      );

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_quick_game_guests(uuid) TO authenticated;

-- ─── 4. Reload PostgREST schema cache ───────────────────────────────────────
NOTIFY pgrst, 'reload schema';
