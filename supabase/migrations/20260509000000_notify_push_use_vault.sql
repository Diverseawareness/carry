-- ============================================================================
-- Migration: Move all push-trigger auth from GUC to Supabase Vault
-- Date:      2026-05-09
-- ============================================================================
-- Background
-- ----------
-- Four Postgres functions call the `send-push-notification` Edge Function
-- via pg_net:
--
--   1. public.notify_push()                       (20260330..., 20260501...)
--   2. public.send_handicap_reminders()           (20260502000000)
--   3. public.reconcile_phone_invites_for_profile() (20260502000002)
--   4. public.reconcile_phone_invite_at_insert()  (20260502000004)
--
-- Each one copy-pastes the same URL + anon-key resolution that reads from
-- `app.settings.supabase_url` / `app.settings.supabase_anon_key`. Supabase
-- managed Postgres locks down the `app.*` GUC namespace to a platform admin
-- role we don't have access to as `postgres` — both `ALTER DATABASE` and
-- `ALTER ROLE` fail with `permission denied to set parameter` (42501). The
-- GUCs are NULL in practice, every push call sent `Authorization: Bearer `
-- (empty), and the Edge Function rejected 100% of calls with 401.
--
-- Worked-around 2026-05-09 by toggling `Verify JWT with legacy secret` OFF
-- on the `send-push-notification` Edge Function — pushes flow but the
-- function URL is publicly callable.
--
-- Fix
-- ---
-- Read the anon key + URL from Supabase Vault (`vault.decrypted_secrets`).
-- Vault is platform-managed, accessible to SECURITY DEFINER functions, and
-- is the documented pattern for trigger-readable secrets.
--
-- Per-environment setup (run ONCE per project, NOT in this migration —
-- `INSERT INTO vault.secrets` is blocked from the SQL Editor user; use the
-- `vault.create_secret(secret, name)` API instead):
--
--   -- Dev (gbhljwtbobbxervekxkg)
--   SELECT vault.create_secret('<dev anon key>', 'supabase_anon_key');
--   SELECT vault.create_secret(
--     'https://gbhljwtbobbxervekxkg.supabase.co/functions/v1/send-push-notification',
--     'supabase_push_url'
--   );
--
--   -- Prod (seeitehizboxjbnccnyd)
--   SELECT vault.create_secret('<prod anon key>', 'supabase_anon_key');
--   SELECT vault.create_secret(
--     'https://seeitehizboxjbnccnyd.supabase.co/functions/v1/send-push-notification',
--     'supabase_push_url'
--   );
--
-- After secrets are inserted, the Verify-JWT toggle on the Edge Function can
-- be flipped back ON. Triggers send a real Bearer token and the function URL
-- is no longer publicly callable.
--
-- Compatibility / rollback
-- ------------------------
-- All 4 functions call shared helpers (`_push_notification_url`,
-- `_push_notification_anon_key`) that follow Vault → GUC → empty fallbacks.
-- If Vault read fails for any reason (extension missing, permissions
-- revoked, secret not yet inserted) the helpers silently fall back to the
-- prior GUC behavior. So this migration is safe to apply BEFORE inserting
-- secrets — pushes continue working under the verify-jwt-off workaround
-- until secrets land.
-- ============================================================================

-- ─── Vault read helper ─────────────────────────────────────────────────────
-- Returns the decrypted secret if present + non-empty; otherwise the default.
-- Wrapped in EXCEPTION so missing extension / no-grant / no-row don't break
-- the calling trigger.
CREATE OR REPLACE FUNCTION public._vault_secret_or_default(p_name text, p_default text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE _val text;
BEGIN
    SELECT decrypted_secret INTO _val
    FROM vault.decrypted_secrets
    WHERE name = p_name;
    RETURN coalesce(nullif(_val, ''), p_default);
EXCEPTION WHEN OTHERS THEN
    RETURN p_default;
END;
$$;

-- ─── Shared push-notification auth helpers ─────────────────────────────────
-- Single source of truth for the URL + anon key used by every trigger that
-- POSTs to the send-push-notification Edge Function. Future migrations that
-- add new push paths should call these instead of re-implementing the
-- resolution logic — that's how we ended up with 4 copy-pasted versions.

CREATE OR REPLACE FUNCTION public._push_notification_url()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE _url text;
BEGIN
    _url := public._vault_secret_or_default('supabase_push_url', '');
    IF _url IS NULL OR _url = '' THEN
        _url := rtrim(current_setting('app.settings.supabase_url', true), '/')
                 || '/functions/v1/send-push-notification';
        IF _url IS NULL OR _url = '' OR _url = '/functions/v1/send-push-notification' THEN
            -- Last-resort fallback — only correct on prod. Vault should
            -- always populate the right value per-environment.
            _url := 'https://seeitehizboxjbnccnyd.supabase.co/functions/v1/send-push-notification';
        END IF;
    END IF;
    RETURN _url;
END;
$$;

CREATE OR REPLACE FUNCTION public._push_notification_anon_key()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE _key text;
BEGIN
    _key := public._vault_secret_or_default('supabase_anon_key', '');
    IF _key IS NULL OR _key = '' THEN
        _key := coalesce(
            current_setting('app.settings.supabase_anon_key', true),
            current_setting('supabase.anon_key', true),
            ''
        );
    END IF;
    RETURN _key;
END;
$$;

-- ─── 1/4. notify_push() — replace inline auth resolution with helper calls ─
-- Per-table dispatch + payload + HTTP post are preserved verbatim from
-- 20260501000000_fix_notify_push_per_table_dispatch.sql.
CREATE OR REPLACE FUNCTION public.notify_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _url text;
    _payload jsonb;
    _anon_key text;
    _self_initiated boolean := false;
BEGIN
    _url := public._push_notification_url();
    _anon_key := public._push_notification_anon_key();

    -- Per-table dispatch (unchanged from 20260501000000) ────────────────
    -- All NEW.<col> references MUST live inside one of these IF blocks.
    -- See 20260501000000 migration header for the rationale.
    IF TG_TABLE_NAME = 'group_members' THEN
        IF auth.uid() IS NOT NULL AND NEW.player_id = auth.uid() THEN
            _self_initiated := true;
        END IF;

        IF NEW.status = 'invited' THEN
            PERFORM 1 FROM profiles
            WHERE id = NEW.player_id AND is_guest = true;
            IF FOUND THEN
                RETURN NEW;
            END IF;
        END IF;
    END IF;

    _payload := jsonb_build_object(
        'type',           TG_OP,
        'table',          TG_TABLE_NAME,
        'record',         to_jsonb(NEW),
        'old_record',     CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END,
        'self_initiated', _self_initiated
    );

    PERFORM net.http_post(
        url := _url,
        body := _payload,
        headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'Authorization', 'Bearer ' || _anon_key
        )
    );

    RETURN NEW;
END;
$$;

-- ─── 2/4. send_handicap_reminders() — pg_cron handicap reminder push ───────
-- Body preserved from 20260502000000_handicap_reminder_push.sql; only the
-- URL + anon-key resolution at the top changes.
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
    _url := public._push_notification_url();
    _anon_key := public._push_notification_anon_key();

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

-- ─── 3/4. reconcile_phone_invites_for_profile() — phone-on-profile trigger ─
-- Body preserved from 20260502000002_phone_on_profile.sql; only the URL +
-- anon-key resolution at the top changes.
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

    _url := public._push_notification_url();
    _anon_key := public._push_notification_anon_key();

    -- Step 1: DELETE orphan phone-invite rows (see 20260502000005 for context)
    DELETE FROM public.group_members gm
    WHERE gm.invited_phone = _normalized_phone
      AND gm.status = 'invited'
      AND EXISTS (
        SELECT 1 FROM public.group_members gm2
        WHERE gm2.group_id = gm.group_id
          AND gm2.player_id = NEW.id
          AND (gm2.invited_phone IS NULL OR gm2.invited_phone = '')
      );

    -- Step 2: Reconcile + send recipient push per reconciled membership.
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

-- ─── 4/4. reconcile_phone_invite_at_insert() — reverse-direction trigger ───
-- Body preserved from 20260502000004_reverse_phone_invite_at_insert.sql;
-- only the URL + anon-key resolution at the top changes.
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

    SELECT id INTO _matched_id
    FROM public.profiles
    WHERE phone = _normalized
    ORDER BY updated_at DESC NULLS LAST
    LIMIT 1;

    IF _matched_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT id INTO _existing_id
    FROM public.group_members
    WHERE group_id = NEW.group_id
      AND player_id = _matched_id
      AND (invited_phone IS NULL OR invited_phone = '')
    LIMIT 1;

    IF _existing_id IS NOT NULL THEN
        RETURN NULL;
    END IF;

    NEW.player_id := _matched_id;
    NEW.invited_phone := '';
    NEW.status := 'active';

    SELECT name INTO _group_name FROM public.skins_groups WHERE id = NEW.group_id;

    _url := public._push_notification_url();
    _anon_key := public._push_notification_anon_key();

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

NOTIFY pgrst, 'reload schema';
