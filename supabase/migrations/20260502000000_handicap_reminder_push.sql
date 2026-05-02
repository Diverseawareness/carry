-- ============================================================================
-- Migration: Handicap reminder push notification
-- Date:      2026-05-02
-- ============================================================================
-- Daily push at 02:00 UTC (~7 PM ET / 4 PM PT — the "approximately 8 PM
-- night-before" model) reminding users to verify their handicap in Carry
-- before tomorrow's tee time.
--
-- Recipients: any non-guest profile with `status='active'` membership in a
-- Skins Group whose `tee_times_json` contains a timestamp in the next ~12-36
-- hours. Same path catches Quick Games (they also live in `skins_groups`
-- with `tee_times_json` populated).
--
-- Personalization: each recipient's current handicap is substituted into the
-- body string. Format is one decimal always (e.g., "6.5", "0.0", "12.0");
-- plus handicaps render as "+1.2" not "-1.2".
--
-- Final body: "Almost game time — Carry has you at <X.X>. Still right?"
--
-- ============================================================================
-- Prerequisites (one-time, may already be enabled on this Supabase project):
--   * `pg_cron` extension — enable via Supabase dashboard if not already
--     active. https://supabase.com/docs/guides/database/extensions/pg_cron
--   * `pg_net` extension — already enabled (used by notify_push()).
--
-- Edge Function `send-push-notification` REQUIRES a follow-up update to
-- handle the new `type = 'handicapReminder'` branch:
--
--   1. Read `payload.user_id` (UUID) and `payload.body` (text) from the
--      request body.
--   2. Look up device tokens for that user from `device_tokens` table
--      (or wherever Carry stores them — see notify_push() Edge Function
--      for the existing lookup path).
--   3. Send APNs push with title = "Carry" (or app default), body =
--      `payload.body`. No deep-link userInfo needed for v1 — tap just
--      opens the app to wherever the user left off.
--
-- The migration below works without the Edge Function update — it'll POST
-- payloads that the Edge Function ignores until the new branch is added.
-- Recommended: deploy the migration AND the Edge Function update together
-- so users start seeing pushes immediately.
-- ============================================================================

-- ─── 1. The recipient + format function ────────────────────────────────────
-- One PL/pgSQL function called by pg_cron. Iterates eligible recipients,
-- formats each one's handicap, builds the body string, POSTs to the
-- send-push-notification Edge Function once per recipient.

CREATE OR REPLACE FUNCTION public.send_handicap_reminders()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _url text;
    _anon_key text;
    _recipient record;
    _formatted_handicap text;
    _body text;
    _payload jsonb;
    _sent_count int := 0;
BEGIN
    -- Mirror the Edge Function URL resolution logic from notify_push() so
    -- this works in any environment (dev, staging, prod) that has the
    -- standard supabase_url setting.
    _url := rtrim(current_setting('app.settings.supabase_url', true), '/') || '/functions/v1/send-push-notification';
    IF _url IS NULL OR _url = '' OR _url = '/functions/v1/send-push-notification' THEN
        _url := 'https://seeitehizboxjbnccnyd.supabase.co/functions/v1/send-push-notification';
    END IF;
    _anon_key := current_setting('app.settings.supabase_anon_key', true);
    IF _anon_key IS NULL OR _anon_key = '' THEN
        _anon_key := coalesce(current_setting('supabase.anon_key', true), '');
    END IF;

    -- Find every (user_id, handicap) pair where the user is an active
    -- member of a Skins Group (or Quick Game — same table) whose
    -- tee_times_json contains a timestamp in the next 12-36 hours. The
    -- 12h floor avoids double-pushing when the cron fires near a tee
    -- time boundary; the 36h ceiling catches all "tomorrow" tee times
    -- across US timezones (PT to ET spans 3h, plus the 8 PM target window).
    --
    -- DISTINCT ON (user_id) ensures one push per user even if they're in
    -- multiple groups with tomorrow tee times.
    FOR _recipient IN
        SELECT DISTINCT ON (p.id)
            p.id AS user_id,
            p.handicap
        FROM public.profiles p
        JOIN public.group_members gm ON gm.player_id = p.id
        JOIN public.skins_groups sg ON sg.id = gm.group_id
        WHERE gm.status = 'active'
          AND p.is_guest = false
          AND sg.tee_times_json IS NOT NULL
          AND EXISTS (
              SELECT 1
              FROM jsonb_array_elements_text(sg.tee_times_json::jsonb) AS tt(value)
              WHERE tt.value ~ '^\d{4}-\d{2}-\d{2}'
                AND tt.value::timestamptz BETWEEN now() + interval '12 hours'
                                             AND now() + interval '36 hours'
          )
    LOOP
        -- Format handicap: one decimal always, plus handicaps as "+X.X".
        -- DB stores plus handicaps as negative doubles per the iOS convention
        -- (see Player.handicap docs). Display strips the sign and prepends "+".
        IF _recipient.handicap < 0 THEN
            _formatted_handicap := '+' || to_char(abs(_recipient.handicap), 'FM999.0');
        ELSE
            _formatted_handicap := to_char(_recipient.handicap, 'FM999.0');
        END IF;

        _body := 'Almost game time — Carry has you at ' || _formatted_handicap || '. Still right?';

        _payload := jsonb_build_object(
            'type', 'handicapReminder',
            'user_id', _recipient.user_id,
            'body', _body
        );

        PERFORM net.http_post(
            url := _url,
            body := _payload,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || _anon_key
            )
        );

        _sent_count := _sent_count + 1;
    END LOOP;

    RETURN _sent_count;
END;
$$;

-- Grant execute to the cron user (Supabase's pg_cron runs as `postgres`,
-- which already owns the function via SECURITY DEFINER, so no extra grant
-- needed for cron itself). Granting authenticated for manual testing /
-- ad-hoc admin trigger.
GRANT EXECUTE ON FUNCTION public.send_handicap_reminders() TO authenticated;

-- ─── 2. Schedule the daily cron ────────────────────────────────────────────
-- 02:00 UTC daily = 7 PM ET / 4 PM PT. Targets the "approximately 8 PM
-- night-before tee time" window. Per-user-timezone refinement is a future
-- improvement; v1 uses fixed UTC for simplicity (no schema migration needed
-- for user timezone storage).
--
-- pg_cron's schedule API: https://github.com/citusdata/pg_cron
-- Cron syntax: minute hour day-of-month month day-of-week

SELECT cron.schedule(
    'handicap-reminder-daily',
    '0 2 * * *',
    $$ SELECT public.send_handicap_reminders(); $$
);

-- ─── 3. Reload PostgREST schema cache ──────────────────────────────────────
NOTIFY pgrst, 'reload schema';
