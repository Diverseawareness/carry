-- ============================================================
-- Migration: Drop blocking FK constraint on round_players
-- Date: 2026-04-01
-- The round_players.player_id FK to profiles blocks account
-- deletion. Replace with a soft reference (no FK constraint).
-- Also drop scores.player_id FK for the same reason.
-- Also drop group_members.player_id FK.
-- ============================================================

-- Drop the FK constraints that block profile deletion
ALTER TABLE public.round_players DROP CONSTRAINT IF EXISTS round_players_player_id_fkey;
ALTER TABLE public.scores DROP CONSTRAINT IF EXISTS scores_player_id_fkey;
ALTER TABLE public.group_members DROP CONSTRAINT IF EXISTS group_members_player_id_fkey;

-- Also drop rounds.created_by FK (we already made it nullable)
ALTER TABLE public.rounds DROP CONSTRAINT IF EXISTS rounds_created_by_fkey;

-- Also drop skins_groups.created_by FK
ALTER TABLE public.skins_groups DROP CONSTRAINT IF EXISTS skins_groups_created_by_fkey;

-- Also drop courses.created_by FK
ALTER TABLE public.courses DROP CONSTRAINT IF EXISTS courses_created_by_fkey;

-- Recreate the delete function without needing RLS bypass
CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _uid uuid := auth.uid();
BEGIN
    IF _uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Delete all user data (no FK constraints blocking anymore)
    DELETE FROM public.scores WHERE player_id = _uid;
    DELETE FROM public.round_players WHERE player_id = _uid;
    DELETE FROM public.group_members WHERE player_id = _uid;
    UPDATE public.rounds SET created_by = NULL WHERE created_by = _uid;
    UPDATE public.skins_groups SET created_by = NULL WHERE created_by = _uid;
    UPDATE public.courses SET created_by = NULL WHERE created_by = _uid;
    DELETE FROM public.profiles WHERE created_by = _uid AND is_guest = true;
    DELETE FROM public.profiles WHERE id = _uid;
END;
$$;

ALTER FUNCTION public.delete_user_account() OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;
