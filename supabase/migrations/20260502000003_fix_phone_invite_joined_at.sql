-- ============================================================================
-- Migration: Fix phone-invite functions referencing nonexistent gm.created_at
-- Date:      2026-05-02
-- ============================================================================
-- Both 20260502000001 (find_pending_invites_by_phone) and 20260502000002
-- (reconcile_phone_invites_for_profile) referenced `gm.created_at` on the
-- group_members table — but the actual timestamp column is `joined_at`
-- (set by default value to now() on INSERT). PostgreSQL does NOT validate
-- function bodies at CREATE FUNCTION time, only at call time, so both
-- migrations deployed cleanly but failed at first call:
--
--   PostgrestError code 42703: "column gm.created_at does not exist"
--   hint: "Perhaps you meant to reference the column 'sg.created_at'."
--
-- This migration uses CREATE OR REPLACE FUNCTION to swap both bodies
-- in-place to use `gm.joined_at` instead. No schema changes; no data
-- migration. Idempotent.
-- ============================================================================

-- ─── 1. find_pending_invites_by_phone — fix `gm.created_at` references ─────

CREATE OR REPLACE FUNCTION public.find_pending_invites_by_phone(p_phone text)
RETURNS TABLE (
    membership_id uuid,
    group_id uuid,
    group_name text,
    invited_by_id uuid,
    invited_by_name text,
    is_quick_game boolean,
    invited_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _normalized_phone text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required to look up invites by phone';
    END IF;

    _normalized_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');

    IF length(_normalized_phone) < 10 THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        gm.id AS membership_id,
        sg.id AS group_id,
        sg.name AS group_name,
        sg.created_by AS invited_by_id,
        coalesce(p.display_name, 'A friend') AS invited_by_name,
        sg.is_quick_game,
        gm.joined_at AS invited_at
    FROM public.group_members gm
    JOIN public.skins_groups sg ON sg.id = gm.group_id
    LEFT JOIN public.profiles p ON p.id = sg.created_by
    WHERE gm.invited_phone = _normalized_phone
      AND gm.status = 'invited'
    ORDER BY gm.joined_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.find_pending_invites_by_phone(text) TO authenticated;

-- ─── 2. reconcile_phone_invites_for_profile — fix `gm.created_at` reference ─

CREATE OR REPLACE FUNCTION public.reconcile_phone_invites_for_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _normalized_phone text;
    _url text;
    _anon_key text;
    _reconciled record;
    _payload jsonb;
BEGIN
    IF NEW.phone IS NULL OR NEW.phone = '' THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.phone IS NOT DISTINCT FROM NEW.phone THEN
        RETURN NEW;
    END IF;

    _normalized_phone := regexp_replace(NEW.phone, '[^0-9]', '', 'g');
    IF length(_normalized_phone) < 10 THEN
        RETURN NEW;
    END IF;

    _url := rtrim(current_setting('app.settings.supabase_url', true), '/') || '/functions/v1/send-push-notification';
    IF _url IS NULL OR _url = '' OR _url = '/functions/v1/send-push-notification' THEN
        _url := 'https://seeitehizboxjbnccnyd.supabase.co/functions/v1/send-push-notification';
    END IF;
    _anon_key := current_setting('app.settings.supabase_anon_key', true);
    IF _anon_key IS NULL OR _anon_key = '' THEN
        _anon_key := coalesce(current_setting('supabase.anon_key', true), '');
    END IF;

    -- Step 1: DELETE orphan phone-invite rows where the matched profile
    -- already has a non-phone membership in the same group (recipient
    -- joined earlier via SMS link, then later added phone). Prevents
    -- partial-unique-index conflict in the UPDATE below. See
    -- 20260502000005 for full context.
    DELETE FROM public.group_members gm
    WHERE gm.invited_phone = _normalized_phone
      AND gm.status = 'invited'
      AND EXISTS (
        SELECT 1 FROM public.group_members gm2
        WHERE gm2.group_id = gm.group_id
          AND gm2.player_id = NEW.id
          AND (gm2.invited_phone IS NULL OR gm2.invited_phone = '')
      );

    -- Step 2: 30-day staleness guard uses gm.joined_at (the actual
    -- column on group_members; created_at does not exist on this table).
    FOR _reconciled IN
        UPDATE public.group_members gm
        SET player_id = NEW.id,
            invited_phone = '',
            status = 'active'
        FROM public.skins_groups sg
        WHERE gm.invited_phone = _normalized_phone
          AND gm.status = 'invited'
          AND gm.joined_at > now() - interval '30 days'
          AND sg.id = gm.group_id
        RETURNING gm.id AS membership_id, gm.group_id, sg.name AS group_name
    LOOP
        _payload := jsonb_build_object(
            'type', 'phoneInviteReconciled',
            'user_id', NEW.id,
            'group_id', _reconciled.group_id,
            'group_name', _reconciled.group_name,
            'body', 'You''ve been added to ' || _reconciled.group_name || '!'
        );

        PERFORM net.http_post(
            url := _url,
            body := _payload,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || _anon_key
            )
        );
    END LOOP;

    RETURN NEW;
END;
$$;

-- Trigger DDL stays the same — only the function body changed.

NOTIFY pgrst, 'reload schema';
