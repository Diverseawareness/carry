-- ============================================================================
-- 20260513000006_create_phone_invite_update_on_dedup.sql
-- ============================================================================
-- Bugfix for `create_phone_invite` RPC: when a row with the same
-- (group_id, invited_phone) already exists, the previous version returned
-- the existing id WITHOUT updating any fields. Stale state from prior
-- bugs persisted indefinitely (wrong group_num from a 1.0.8 race, stale
-- invitee_name from an earlier typo, status='removed' from a soft-delete).
-- Re-inviting the same phone in the same group silently kept the old
-- broken state instead of refreshing it with the new caller-supplied
-- values.
--
-- Fix: on dedup hit, UPDATE the existing row's group_num + invitee_name
-- and re-arm status='invited' (in case it was 'removed' or auto-collapsed
-- to 'active' by a prior reconciliation that has since become stale).
-- Returns the existing id either way, so iOS callers that re-anchor on
-- the returned id (vs the supplied id) keep working.
-- ============================================================================

DROP FUNCTION IF EXISTS public.create_phone_invite(uuid, uuid, text, uuid, text, text);

CREATE OR REPLACE FUNCTION public.create_phone_invite(
    p_id uuid,
    p_group_id uuid,
    p_phone text,
    p_invited_by uuid,
    p_group_num text,
    p_invitee_name text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _existing_id uuid;
    _group_num int;
    _trimmed_name text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    _group_num := coalesce(p_group_num, '1')::int;
    _trimmed_name := nullif(trim(coalesce(p_invitee_name, '')), '');

    -- Dedup by phone within this group.
    SELECT id INTO _existing_id
    FROM public.group_members
    WHERE group_id = p_group_id
      AND invited_phone = p_phone
    LIMIT 1;

    IF _existing_id IS NOT NULL THEN
        -- Refresh the existing row with the new caller-supplied values
        -- so re-invites behave as if a fresh row had been created. Keep
        -- the existing id (anchored client-side) — only the editable
        -- fields update.
        UPDATE public.group_members
        SET group_num = _group_num,
            invitee_name = coalesce(_trimmed_name, invitee_name),
            status = 'invited'
        WHERE id = _existing_id;
        RETURN _existing_id;
    END IF;

    INSERT INTO public.group_members (
        id, group_id, player_id, role, status, invited_phone, group_num, invitee_name
    ) VALUES (
        p_id, p_group_id, p_invited_by, 'member', 'invited', p_phone, _group_num,
        _trimmed_name
    );

    RETURN p_id;
END;
$$;

COMMENT ON FUNCTION public.create_phone_invite(uuid, uuid, text, uuid, text, text) IS
    'SECURITY DEFINER insert path for phone-invite group_members rows. On dedup hit (same group_id + invited_phone), UPDATEs the existing row''s group_num + invitee_name + re-arms status=''invited'' rather than returning a stale row.';

GRANT EXECUTE ON FUNCTION public.create_phone_invite(uuid, uuid, text, uuid, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
