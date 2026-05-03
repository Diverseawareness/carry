-- ============================================================================
-- Migration: Clean up orphaned phone-invite rows during reconcile
-- Date:      2026-05-02
-- ============================================================================
-- Closes a latent bug in reconcile_phone_invites_for_profile (from
-- 20260502000002, fixed in 20260502000003). Symptom: a user can't save
-- their phone to profile if there's a stale phone-invite row in the DB
-- AND they're already a member of that group.
--
-- How users get into this state:
--   1. Sender invites recipient by phone → DB row inserts as 'invited'
--      with invited_phone set, player_id = inviter UUID placeholder
--   2. Recipient has Carry installed + no phone on profile, taps the
--      SMS link → app opens → handleIncomingURL → joinGroupViaInvite
--      → adds them as a SECOND row (status='active', real player_id,
--      no invited_phone)
--   3. The original phone-invite row from step 1 stays orphaned in
--      the DB — recipient joined via a different mechanism, the trigger
--      never had a chance to claim it because phone wasn't on profile yet
--
-- Failure later:
--   4. Months later, recipient sees the migration banner / adds phone
--      via Settings
--   5. reconcile_phone_invites_for_profile fires
--   6. Tries to UPDATE the orphan row to status='active', player_id=NEW.id,
--      invited_phone=''
--   7. Conflicts with the partial unique index group_members_unique_real_player
--      (added in 20260426000000): the recipient already has an active row
--      for that group, can't have a second
--   8. UPDATE fails → entire profiles.phone update rolls back → user
--      sees "Update Failed" with no clue why
--
-- Fix: BEFORE the UPDATE that claims pending invites, DELETE any orphan
-- phone-invite rows where the matched profile already has a non-phone
-- membership in the same group. The orphan was a side-effect of the
-- earlier SMS-link join; cleaning it up is the right outcome.
-- ============================================================================

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

    -- ─── Step 1: DELETE orphan phone-invite rows ──────────────────────────
    -- Any phone-invite row matching the user's normalized phone where the
    -- user already has a non-phone membership in the same group is an
    -- orphan from an earlier SMS-link join. Drop it so step 2's UPDATE
    -- doesn't conflict with the partial unique index. No push fires for
    -- the orphan — the user was already in the group.
    DELETE FROM public.group_members gm
    WHERE gm.invited_phone = _normalized_phone
      AND gm.status = 'invited'
      AND EXISTS (
        SELECT 1 FROM public.group_members gm2
        WHERE gm2.group_id = gm.group_id
          AND gm2.player_id = NEW.id
          AND (gm2.invited_phone IS NULL OR gm2.invited_phone = '')
      );

    -- ─── Step 2: Reconcile non-conflicting phone-invite rows ──────────────
    -- 30-day staleness guard: only auto-claim recent invites. Older rows
    -- might be from a phone number the user no longer owns.
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

NOTIFY pgrst, 'reload schema';
