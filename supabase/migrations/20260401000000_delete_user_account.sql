-- ============================================================
-- Migration: delete_user_account RPC
-- Date: 2026-04-01
-- Deletes all user data across all tables, then removes the
-- auth user. Called from the iOS app's "Delete Account" button.
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

    -- 1. Delete scores the user entered
    DELETE FROM public.scores WHERE player_id = _uid;

    -- 2. Delete round_players entries
    DELETE FROM public.round_players WHERE player_id = _uid;

    -- 3. Delete rounds the user created (cascade deletes scores + round_players for those rounds)
    DELETE FROM public.rounds WHERE created_by = _uid;

    -- 4. Delete group memberships
    DELETE FROM public.group_members WHERE player_id = _uid;

    -- 5. Delete skins groups the user created
    DELETE FROM public.skins_groups WHERE created_by = _uid;

    -- 6. Delete guest profiles created by this user
    DELETE FROM public.profiles WHERE created_by = _uid AND is_guest = true;

    -- 7. Delete the user's own profile
    DELETE FROM public.profiles WHERE id = _uid;

    -- 8. Delete the auth user (requires service_role, handled by SECURITY DEFINER)
    DELETE FROM auth.users WHERE id = _uid;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;
