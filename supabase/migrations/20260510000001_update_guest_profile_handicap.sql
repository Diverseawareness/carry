-- Guest profile UPDATE RPC (creator-authorized, name + handicap)
--
-- Background
-- ----------
-- The RLS policy on profiles is `auth.uid() = id`, which means a creator
-- cannot directly UPDATE a guest profile's row. Until this migration, guest
-- name and handicap edits in PlayerGroupsSheet only mutated local @State + the
-- guest_roster_json snapshot — NEVER `profiles.display_name` /
-- `profiles.handicap`. The next refreshGroupData call would pull stale values
-- from `profiles` and stomp the local edit. Skins payouts are
-- handicap-weighted, so the corruption affected actual money math.
-- Display names showing as the original guest name (or "Guest" if profile was
-- wiped) was the visible symptom.
--
-- Fix
-- ---
-- New SECURITY DEFINER RPC that bypasses RLS but enforces creator-authorization
-- explicitly. Mirrors the create_guest_profiles + delete_quick_game_guests
-- pattern from the 2026-05-01 ephemeral-guest migration.
--
-- Optional parameters: pass NULL for any field you don't want to update.
-- This lets iOS send a single RPC per guest with whichever fields changed.
-- Initials auto-derive from p_display_name when display_name is provided
-- and p_initials is NULL.
--
-- Idempotency
-- -----------
-- IF NOT EXISTS / OR REPLACE everywhere — safe to run multiple times.
-- Migration is additive only; no data backfill needed.

CREATE OR REPLACE FUNCTION public.update_guest_profile(
    p_profile_id uuid,
    p_display_name text DEFAULT NULL,
    p_initials text DEFAULT NULL,
    p_handicap double precision DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_initials text;
BEGIN
    -- Auth: only the guest's creator can update.
    -- SECURITY DEFINER bypasses RLS, so we enforce the gate explicitly.
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = p_profile_id
          AND is_guest = true
          AND created_by = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Not authorized — only the guest profile creator can update profile %', p_profile_id;
    END IF;

    -- Auto-derive initials from display_name if name provided but initials weren't.
    -- Mirrors the iOS Player.initials logic: take first 2 uppercase chars of
    -- the name (or however many exist).
    v_initials := p_initials;
    IF v_initials IS NULL AND p_display_name IS NOT NULL THEN
        v_initials := upper(substring(p_display_name from 1 for 2));
    END IF;

    UPDATE profiles
    SET display_name = COALESCE(p_display_name, display_name),
        initials = COALESCE(v_initials, initials),
        handicap = COALESCE(p_handicap, handicap),
        updated_at = now()
    WHERE id = p_profile_id
      AND is_guest = true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_guest_profile(uuid, text, text, double precision) TO authenticated;

COMMENT ON FUNCTION public.update_guest_profile(uuid, text, text, double precision) IS
    'Creator-authorized profile update for guest profiles (name / initials / handicap). Bypasses the auth.uid()=id RLS policy via SECURITY DEFINER but enforces created_by = auth.uid() explicitly. Pass NULL for fields not being updated. Called from iOS PlayerGroupsSheet onSave when any of these fields change.';
