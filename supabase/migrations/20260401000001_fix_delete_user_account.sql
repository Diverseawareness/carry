-- ============================================================
-- Migration: Fix delete_user_account RPC
-- Date: 2026-04-01
-- Properly handles FK constraints and shared resources.
-- Does NOT delete auth.users (handled by client-side signOut).
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

    -- 1. Delete scores entered BY this user (their own scores in any round)
    DELETE FROM public.scores WHERE player_id = _uid;

    -- 2. Delete round_players entries for this user
    DELETE FROM public.round_players WHERE player_id = _uid;

    -- 3. Delete group memberships for this user
    DELETE FROM public.group_members WHERE player_id = _uid;

    -- 4. Nullify created_by on rounds so other players' data survives
    UPDATE public.rounds SET created_by = '00000000-0000-0000-0000-000000000000' WHERE created_by = _uid;

    -- 5. Nullify created_by on skins_groups so group survives for other members
    UPDATE public.skins_groups SET created_by = '00000000-0000-0000-0000-000000000000' WHERE created_by = _uid;

    -- 6. Nullify created_by on courses
    UPDATE public.courses SET created_by = NULL WHERE created_by = _uid;

    -- 7. Delete guest profiles created by this user (they have no real account)
    DELETE FROM public.profiles WHERE created_by = _uid AND is_guest = true;

    -- 8. Delete the user's own profile
    DELETE FROM public.profiles WHERE id = _uid;
END;
$$;
