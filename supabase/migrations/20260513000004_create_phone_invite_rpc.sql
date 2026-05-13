-- ============================================================================
-- 20260513000004_create_phone_invite_rpc.sql
-- ============================================================================
-- Structural fix for the SMS-invite-as-scorer reconciliation flow:
-- PostgREST silently drops `group_num` from iOS-side INSERT request bodies
-- to group_members, even when the JSON payload contains it (verified via
-- iOS JSONEncoder debug print). Direct SQL INSERT preserves the value.
-- Root cause TBD, tracked as follow-up; symptom is that any non-default
-- group_num (i.e. anything != 1) sent via the PostgREST INSERT path lands
-- as 1 in the row.
--
-- Fix: replace the iOS `client.from("group_members").insert(...)` call in
-- GroupService.reservePhoneInvite with an RPC to this SECURITY DEFINER
-- function. The body is plain SQL, so the column write goes through the
-- non-broken path. Same end behavior (insert a phone-invite row with
-- explicit id + group_num) but uses RPC instead of REST insert.
--
-- Dedup-by-phone behavior mirrors the iOS-side dedup: same phone in same
-- group → return existing row's id; otherwise insert new row with
-- supplied params.
--
-- Reverse trigger reconcile_phone_invite_at_insert continues to fire
-- BEFORE INSERT (trigger DDL unchanged; only the INSERT issuing path
-- changes). NEW.id is the supplied p_id, NEW.group_num is p_group_num,
-- so all Stage 3 reconciliation logic continues to operate correctly.
-- ============================================================================

-- Drop the old int-typed signature if present (idempotent — first deploy
-- doesn't have it). The new signature accepts p_group_num as text so the
-- iOS client can pass it via AnyJSON.string and we cast inside the
-- function, sidestepping a Supabase-swift / PostgREST handling quirk
-- where AnyJSON.integer was being silently coerced to the column default
-- on the wire.
DROP FUNCTION IF EXISTS public.create_phone_invite(uuid, uuid, text, uuid, int);

CREATE OR REPLACE FUNCTION public.create_phone_invite(
    p_id uuid,
    p_group_id uuid,
    p_phone text,
    p_invited_by uuid,
    p_group_num text
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
    -- Caller must be authenticated. Matches RLS gate for direct INSERT
    -- ("Authenticated users can insert members": auth.uid() IS NOT NULL).
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    _group_num := coalesce(p_group_num, '1')::int;
    RAISE LOG '[create_phone_invite] p_id=% p_group_num text=% _group_num int=%', p_id, p_group_num, _group_num;

    -- Dedup by phone within this group, mirroring the iOS-side check that
    -- was in GroupService.reservePhoneInvite before this RPC existed. If
    -- a row with this phone is already invited to this group, return its
    -- id so the caller can re-anchor the slot.
    SELECT id INTO _existing_id
    FROM public.group_members
    WHERE group_id = p_group_id
      AND invited_phone = p_phone
    LIMIT 1;

    IF _existing_id IS NOT NULL THEN
        RETURN _existing_id;
    END IF;

    -- INSERT in plain SQL — group_num is preserved here (verified). The
    -- reverse trigger reconcile_phone_invite_at_insert fires BEFORE INSERT
    -- and may mutate NEW.player_id / invited_phone / status if the phone
    -- matches an existing profile. NEW.id stays p_id. NEW.group_num stays
    -- the cast _group_num.
    -- TEMP DIAGNOSTIC (commit version): still hardcode 99 but let the
    -- transaction commit. Confirmed earlier that INSERT preserves 99
    -- inside the transaction. If the final stored value is != 99,
    -- something post-commit is mutating the column.
    INSERT INTO public.group_members (
        id, group_id, player_id, role, status, invited_phone, group_num
    ) VALUES (
        p_id, p_group_id, p_invited_by, 'member', 'invited', p_phone, 99
    );

    RETURN p_id;
END;
$$;

COMMENT ON FUNCTION public.create_phone_invite(uuid, uuid, text, uuid, text) IS
    'SECURITY DEFINER insert path for phone-invite group_members rows. Called by GroupService.reservePhoneInvite via RPC to bypass a PostgREST quirk that silently drops group_num from JSON INSERT bodies. p_group_num is passed as text (cast inside) because AnyJSON.integer was being silently coerced on the iOS wire. See migration body for full context.';

GRANT EXECUTE ON FUNCTION public.create_phone_invite(uuid, uuid, text, uuid, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
