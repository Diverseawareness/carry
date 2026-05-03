-- ============================================================================
-- Migration: Phone on profile + auto-reconcile pending invites
-- Date:      2026-05-02
-- ============================================================================
-- Builds on the 1.0.3 PhoneInviteFinderSheet (manual modal where the user
-- types phone to find pending invites). This migration moves the same
-- reconciliation server-side, triggered automatically when a user enters
-- their phone via onboarding, Settings, or the migration banner. Net effect:
-- once a user's phone is set on their profile, any future phone invite
-- (Skins Group OR Quick Game scorer) auto-claims with zero modal interaction.
-- A dedicated push fires to the recipient telling them they were added.
-- ============================================================================

-- ─── 1. profiles.phone column + index ──────────────────────────────────────
-- Stored as digits-only normalized (e.g., "4155551234"). iOS strips
-- formatting characters before write. Index is partial (only non-null) to
-- keep it small — most users may skip the optional onboarding step.

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone text;
CREATE INDEX IF NOT EXISTS idx_profiles_phone ON public.profiles(phone) WHERE phone IS NOT NULL AND phone <> '';

-- ─── 2. Reconcile trigger ──────────────────────────────────────────────────
-- When a profile's phone is set or changes, find any pending phone-invite
-- rows that match and reconcile them in one atomic update. The row's
-- player_id flips to this profile's id, invited_phone clears, status
-- becomes 'active'. The existing on_group_member_change trigger then
-- fires notify_push() which sends the standard memberJoined push to the
-- group creator. Separately, this function POSTs a phoneInviteReconciled
-- push directly to the recipient (via the Edge Function) for each
-- reconciled row.
--
-- Stale-invite guard: only auto-reconciles rows created within the last
-- 30 days. Older invites might be from a phone number the user no longer
-- owns; requiring an explicit retry prevents accidental claims.

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
    -- Skip if phone wasn't actually set or changed.
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

    -- Resolve Edge Function URL + anon key — same logic as notify_push().
    _url := rtrim(current_setting('app.settings.supabase_url', true), '/') || '/functions/v1/send-push-notification';
    IF _url IS NULL OR _url = '' OR _url = '/functions/v1/send-push-notification' THEN
        _url := 'https://seeitehizboxjbnccnyd.supabase.co/functions/v1/send-push-notification';
    END IF;
    _anon_key := current_setting('app.settings.supabase_anon_key', true);
    IF _anon_key IS NULL OR _anon_key = '' THEN
        _anon_key := coalesce(current_setting('supabase.anon_key', true), '');
    END IF;

    -- Reconcile + collect group info for the recipient push.
    -- 30-day staleness guard: don't auto-claim invites older than that.
    FOR _reconciled IN
        UPDATE public.group_members gm
        SET player_id = NEW.id,
            invited_phone = '',
            status = 'active'
        FROM public.skins_groups sg
        WHERE gm.invited_phone = _normalized_phone
          AND gm.status = 'invited'
          AND gm.created_at > now() - interval '30 days'
          AND sg.id = gm.group_id
        RETURNING gm.id AS membership_id, gm.group_id, sg.name AS group_name
    LOOP
        -- One push per reconciled membership. Recipient sees:
        -- "Added to {Group Name}". Tap opens app (deep-link to the group
        -- is a future polish — for now lands on Home/Games tab where the
        -- group is now visible).
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

DROP TRIGGER IF EXISTS reconcile_phone_invites ON public.profiles;
CREATE TRIGGER reconcile_phone_invites
AFTER INSERT OR UPDATE OF phone ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.reconcile_phone_invites_for_profile();

-- ─── 3. Reload PostgREST schema cache ──────────────────────────────────────
NOTIFY pgrst, 'reload schema';
