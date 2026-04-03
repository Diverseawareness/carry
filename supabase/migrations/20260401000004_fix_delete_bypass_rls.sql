-- ============================================================
-- Migration: Fix delete_user_account — bypass RLS explicitly
-- Date: 2026-04-01
-- SECURITY DEFINER alone may not bypass RLS on Supabase hosted.
-- Temporarily disable RLS for the delete operations.
-- ============================================================

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

    -- Temporarily bypass RLS for cleanup
    SET LOCAL row_security = off;

    -- Delete ALL scores referencing this user (any round)
    DELETE FROM public.scores WHERE player_id = _uid;

    -- Delete ALL round_players referencing this user (any round)
    DELETE FROM public.round_players WHERE player_id = _uid;

    -- Delete ALL group memberships
    DELETE FROM public.group_members WHERE player_id = _uid;

    -- Nullify ownership on shared resources
    UPDATE public.rounds SET created_by = NULL WHERE created_by = _uid;
    UPDATE public.skins_groups SET created_by = NULL WHERE created_by = _uid;
    UPDATE public.courses SET created_by = NULL WHERE created_by = _uid;

    -- Delete guest profiles created by this user
    DELETE FROM public.profiles WHERE created_by = _uid AND is_guest = true;

    -- Delete the user's own profile
    DELETE FROM public.profiles WHERE id = _uid;

    -- Re-enable RLS
    SET LOCAL row_security = on;
END;
$$;

-- Ensure function is owned by postgres (required for RLS bypass)
ALTER FUNCTION public.delete_user_account() OWNER TO postgres;
