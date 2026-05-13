-- ============================================================================
-- 20260513000005_add_invitee_name_to_group_members.sql
-- ============================================================================
-- Adds `invitee_name text` to group_members so SMS-invite rows can carry the
-- name the inviter typed at slot-time. Without this, iOS loadSingleGroup
-- rebuilds the phone-invite Player with `name = phone digits` — the row
-- displays as "Invited" / digits in the tee sheet instead of the
-- recipient's real name + formatted phone.
--
-- Nullable, no default. Pre-existing rows (none on prod per the 2026-05-12
-- SMS-invite audit) and SG rows where invitee_name doesn't apply both leave
-- it NULL. Reconciliation triggers (forward + reverse) do NOT clear this
-- field — it stays as the originally-invited name even after the recipient
-- onboards, in case the iOS client wants to surface "you invited as X" UI.
--
-- The create_phone_invite RPC gains a p_invitee_name parameter (next).
-- ============================================================================

ALTER TABLE public.group_members
    ADD COLUMN IF NOT EXISTS invitee_name text;

COMMENT ON COLUMN public.group_members.invitee_name IS
    'Display name typed by the inviter when sending an SMS invite. Used by iOS to render the pending-invite scorer slot with a recognizable name (vs raw phone digits). NULL for non-SMS-invite rows and pre-2026-05-13 SMS-invite rows.';

-- Update create_phone_invite RPC to accept + store p_invitee_name.
-- Drop the existing (id, group_id, phone, invited_by, group_num) signature
-- and replace with a (..., invitee_name) variant. Old callers can pass NULL.
DROP FUNCTION IF EXISTS public.create_phone_invite(uuid, uuid, text, uuid, text);

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
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    _group_num := coalesce(p_group_num, '1')::int;

    -- Dedup by phone within this group.
    SELECT id INTO _existing_id
    FROM public.group_members
    WHERE group_id = p_group_id
      AND invited_phone = p_phone
    LIMIT 1;

    IF _existing_id IS NOT NULL THEN
        RETURN _existing_id;
    END IF;

    INSERT INTO public.group_members (
        id, group_id, player_id, role, status, invited_phone, group_num, invitee_name
    ) VALUES (
        p_id, p_group_id, p_invited_by, 'member', 'invited', p_phone, _group_num,
        nullif(trim(coalesce(p_invitee_name, '')), '')
    );

    RETURN p_id;
END;
$$;

COMMENT ON FUNCTION public.create_phone_invite(uuid, uuid, text, uuid, text, text) IS
    'SECURITY DEFINER insert path for phone-invite group_members rows. p_invitee_name carries the inviter-typed display name (nullable; trimmed-empty → NULL). See migration body.';

GRANT EXECUTE ON FUNCTION public.create_phone_invite(uuid, uuid, text, uuid, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
