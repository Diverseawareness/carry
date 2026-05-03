-- ============================================================================
-- Migration: Reverse-direction reconcile — auto-claim at invite time
-- Date:      2026-05-02
-- ============================================================================
-- Closes the remaining gap in phone-on-profile: when a sender invites a
-- phone number that's ALREADY on someone's profile, we should
-- immediately attach the invite to that profile (status='active') instead
-- of leaving it pending forever.
--
-- Companion to 20260502000002 (which fires the OTHER direction:
-- recipient adds phone → existing pending invites claim). Together the
-- two triggers guarantee phone invites just work in both orderings:
--
--   (a) recipient adds phone first, then sender invites them by phone
--   (b) sender invites first, then recipient adds phone
--   (c) NEW: sender invites a phone that's already on a profile      ← this trigger
--
-- Trigger fires BEFORE INSERT on group_members so we mutate NEW directly
-- (no second UPDATE round-trip) and the row inserts as already-active.
-- The existing on_group_member_change AFTER INSERT trigger then fires
-- notify_push() which sends the standard memberJoined push to the
-- creator. Separately, this function POSTs phoneInviteReconciled to the
-- recipient via the Edge Function — same shape as the receiver-side
-- trigger.
--
-- Dedupe: if the matched profile is already a member of this group
-- (any status) via a non-phone row, we skip the insert entirely
-- (RETURN NULL) — matches the partial unique index in 20260426000000
-- which forbids duplicate (group_id, player_id) for non-phone rows.
-- The sender-side dedupe in GroupService.inviteMemberByPhone only
-- catches duplicate phone-invites; this trigger covers the case where
-- the matched profile is already in the group some other way.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.reconcile_phone_invite_at_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _normalized text;
    _matched_id uuid;
    _existing_id uuid;
    _group_name text;
    _url text;
    _anon_key text;
    _payload jsonb;
BEGIN
    -- Only fire for phone invites in 'invited' status.
    IF NEW.invited_phone IS NULL OR NEW.invited_phone = '' THEN
        RETURN NEW;
    END IF;
    IF NEW.status IS DISTINCT FROM 'invited' THEN
        RETURN NEW;
    END IF;

    _normalized := regexp_replace(NEW.invited_phone, '[^0-9]', '', 'g');
    IF length(_normalized) < 10 THEN
        RETURN NEW;
    END IF;

    -- Look up profile by normalized phone. If multiple profiles share
    -- the same phone (test accounts, family devices), claim the most
    -- recently updated one — matches the spec decision in
    -- phone_on_profile_1_1_0_spec.md.
    SELECT id INTO _matched_id
    FROM public.profiles
    WHERE phone = _normalized
    ORDER BY updated_at DESC NULLS LAST
    LIMIT 1;

    IF _matched_id IS NULL THEN
        RETURN NEW; -- no profile match; insert as pending phone invite
    END IF;

    -- Dedupe: if matched profile is already a member of this group via
    -- a non-phone row (any status), skip the insert. The sender already
    -- has them in the group; a phone-invite duplicate would either
    -- violate the partial unique index or create a confusing second row.
    SELECT id INTO _existing_id
    FROM public.group_members
    WHERE group_id = NEW.group_id
      AND player_id = _matched_id
      AND (invited_phone IS NULL OR invited_phone = '')
    LIMIT 1;

    IF _existing_id IS NOT NULL THEN
        RETURN NULL; -- silent no-op; user is already in the group
    END IF;

    -- Promote NEW to an active membership for the matched profile.
    -- on_group_member_change AFTER INSERT will then fire memberJoined
    -- push to the creator (existing behavior, no change needed there).
    NEW.player_id := _matched_id;
    NEW.invited_phone := '';
    NEW.status := 'active';

    -- Lookup group name for the recipient push body.
    SELECT name INTO _group_name FROM public.skins_groups WHERE id = NEW.group_id;

    -- Resolve Edge Function URL + anon key (same pattern as notify_push
    -- and reconcile_phone_invites_for_profile).
    _url := rtrim(current_setting('app.settings.supabase_url', true), '/') || '/functions/v1/send-push-notification';
    IF _url IS NULL OR _url = '' OR _url = '/functions/v1/send-push-notification' THEN
        _url := 'https://seeitehizboxjbnccnyd.supabase.co/functions/v1/send-push-notification';
    END IF;
    _anon_key := current_setting('app.settings.supabase_anon_key', true);
    IF _anon_key IS NULL OR _anon_key = '' THEN
        _anon_key := coalesce(current_setting('supabase.anon_key', true), '');
    END IF;

    _payload := jsonb_build_object(
        'type', 'phoneInviteReconciled',
        'user_id', _matched_id,
        'group_id', NEW.group_id,
        'group_name', _group_name,
        'body', 'You''ve been added to ' || _group_name || '!'
    );

    PERFORM net.http_post(
        url := _url,
        body := _payload,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || _anon_key
        )
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reconcile_phone_invite_at_insert ON public.group_members;
CREATE TRIGGER reconcile_phone_invite_at_insert
BEFORE INSERT ON public.group_members
FOR EACH ROW EXECUTE FUNCTION public.reconcile_phone_invite_at_insert();

NOTIFY pgrst, 'reload schema';
