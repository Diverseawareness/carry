-- ============================================================
-- Migration: Allow nullable created_by for account deletion
-- Date: 2026-04-01
-- When a user deletes their account, their rounds and groups
-- should survive for other members. created_by becomes NULL.
-- ============================================================

-- Make rounds.created_by nullable
ALTER TABLE public.rounds ALTER COLUMN created_by DROP NOT NULL;

-- Make skins_groups.created_by nullable (already references profiles(id))
-- Check if NOT NULL exists first
DO $$
BEGIN
    ALTER TABLE public.skins_groups ALTER COLUMN created_by DROP NOT NULL;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- Update the delete function to use NULL instead of fake UUID
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

    -- 1. Delete scores entered BY this user
    DELETE FROM public.scores WHERE player_id = _uid;

    -- 2. Delete round_players entries for this user
    DELETE FROM public.round_players WHERE player_id = _uid;

    -- 3. Delete group memberships for this user
    DELETE FROM public.group_members WHERE player_id = _uid;

    -- 4. Nullify created_by on rounds (preserves other players' data)
    UPDATE public.rounds SET created_by = NULL WHERE created_by = _uid;

    -- 5. Nullify created_by on skins_groups (group survives for other members)
    UPDATE public.skins_groups SET created_by = NULL WHERE created_by = _uid;

    -- 6. Nullify created_by on courses
    UPDATE public.courses SET created_by = NULL WHERE created_by = _uid;

    -- 7. Delete guest profiles created by this user
    DELETE FROM public.profiles WHERE created_by = _uid AND is_guest = true;

    -- 8. Delete the user's own profile
    DELETE FROM public.profiles WHERE id = _uid;
END;
$$;
