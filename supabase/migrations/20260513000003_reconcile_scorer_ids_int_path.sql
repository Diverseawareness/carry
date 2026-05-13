-- ============================================================================
-- 20260513000003_reconcile_scorer_ids_int_path.sql
-- ============================================================================
-- Stage 3 (revised) of the SMS-invite-as-scorer reconciliation fix.
--
-- Supersedes 20260513000001_reconcile_extends_scorer_ids.sql's UUID-based
-- approach with an int-comparison approach. Same end behavior (scorer_ids
-- entry rewritten from placeholder to profile UUID's stable-int) — but the
-- wire format stays [Int] throughout, so clients on older app versions
-- (1.0.7 / 1.0.8 with strict [Int] decoders) continue to read scorer_ids
-- without breaking.
--
-- The int-comparison approach uses public.player_stable_id(uuid) (added in
-- 20260513000002) to compute the stable-int that iOS would derive from a
-- given UUID, then walks scorer_ids and swaps any matching int.
--
-- Both phone-invite reconciliation triggers are updated:
--   - reconcile_phone_invites_for_profile (FORWARD): on profile.phone set,
--     for each reconciled membership, swap player_stable_id(membership_id)
--     → player_stable_id(NEW.id) in scorer_ids.
--   - reconcile_phone_invite_at_insert (REVERSE): BEFORE INSERT on
--     group_members, after mutating NEW to active+matched_id, swap
--     player_stable_id(NEW.id) → player_stable_id(_matched_id) in scorer_ids.
--
-- The earlier UUID-based helper (_reconcile_scorer_ids from migration
-- 20260513000001) is left in place as harmless dead code — scorer_ids
-- will never contain UUID-shaped entries under this design, so the
-- helper's UPDATE statement is a no-op when called.
-- ============================================================================

-- ─── Helper: int-comparison rewrite of a single scorer_ids entry ──────────

CREATE OR REPLACE FUNCTION public._reconcile_scorer_ids_int(
    p_group_id uuid,
    p_old_int bigint,
    p_new_int bigint
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    _arr jsonb;
BEGIN
    SELECT scorer_ids INTO _arr FROM public.skins_groups WHERE id = p_group_id;
    IF _arr IS NULL OR jsonb_typeof(_arr) != 'array' OR jsonb_array_length(_arr) = 0 THEN
        RETURN;
    END IF;

    -- Rebuild array. Only swap elements that are numeric AND equal to
    -- p_old_int. Preserve any non-numeric elements (UUID strings from a
    -- hypothetical future format change, nulls, etc.) unchanged.
    UPDATE public.skins_groups sg
    SET scorer_ids = (
        SELECT jsonb_agg(
            CASE
                WHEN jsonb_typeof(sg.scorer_ids->(ord - 1)) = 'number'
                  AND (sg.scorer_ids->(ord - 1))::text::bigint = p_old_int
                THEN to_jsonb(p_new_int)
                ELSE sg.scorer_ids->(ord - 1)
            END
            ORDER BY ord
        )
        FROM generate_series(1, jsonb_array_length(sg.scorer_ids)) AS ord
    )
    WHERE sg.id = p_group_id;
END;
$$;

COMMENT ON FUNCTION public._reconcile_scorer_ids_int(uuid, bigint, bigint) IS
    'Rewrites a single scorer_ids entry from p_old_int to p_new_int in-place. Both ints must come from public.player_stable_id(uuid) — see migration 20260513000002 for the formula. Used by phone-invite reconciliation triggers to keep scorer_ids in sync after group_members reconciliation, without changing the [Int] wire format.';

-- ─── Forward trigger: replace UUID-helper call with int-helper call ──────

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
    _new_int bigint;
    _old_int bigint;
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

    _new_int := public.player_stable_id(NEW.id);

    _url := rtrim(current_setting('app.settings.supabase_url', true), '/') || '/functions/v1/send-push-notification';
    IF _url IS NULL OR _url = '' OR _url = '/functions/v1/send-push-notification' THEN
        _url := 'https://seeitehizboxjbnccnyd.supabase.co/functions/v1/send-push-notification';
    END IF;
    _anon_key := current_setting('app.settings.supabase_anon_key', true);
    IF _anon_key IS NULL OR _anon_key = '' THEN
        _anon_key := coalesce(current_setting('supabase.anon_key', true), '');
    END IF;

    -- Step 1: DELETE orphan phone-invite rows where the matched profile
    -- already has a non-phone membership in the same group. See
    -- 20260502000005 for context.
    DELETE FROM public.group_members gm
    WHERE gm.invited_phone = _normalized_phone
      AND gm.status = 'invited'
      AND EXISTS (
        SELECT 1 FROM public.group_members gm2
        WHERE gm2.group_id = gm.group_id
          AND gm2.player_id = NEW.id
          AND (gm2.invited_phone IS NULL OR gm2.invited_phone = '')
      );

    -- Step 2: 30-day staleness guard.
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
        -- Stage 3 (int path): rewrite scorer_ids for this group from
        -- the placeholder's stable-int to the new profile's stable-int.
        -- The wire format stays [Int]; clients see the same shape they
        -- already decode.
        _old_int := public.player_stable_id(_reconciled.membership_id);
        PERFORM public._reconcile_scorer_ids_int(
            _reconciled.group_id,
            _old_int,
            _new_int
        );

        -- Stage 3 NEW (defensive): rewrite round_players if the
        -- placeholder UUID ever made it there. Today RoundCoordinator
        -- skips nil-profileId from round_players, so this is usually a
        -- no-op — but covers future code paths that might bypass that
        -- filter, and keeps cross-table state consistent.
        UPDATE public.round_players
        SET player_id = NEW.id
        WHERE player_id = _reconciled.membership_id;

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

-- ─── Reverse trigger: replace UUID-helper call with int-helper call ──────

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
    _old_int bigint;
    _new_int bigint;
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

    -- Capture the slot's stable-int BEFORE the mutation flips identity.
    _old_int := public.player_stable_id(NEW.id);

    NEW.player_id := _matched_id;
    NEW.invited_phone := '';
    NEW.status := 'active';

    -- Stage 3 (int path): rewrite scorer_ids for this group so the slot
    -- anchor on NEW.id (the row's id, derived as stable-int by the client)
    -- resolves to the matched profile's stable-int instead. The row's id
    -- stays NEW.id; the wire format stays [Int].
    _new_int := public.player_stable_id(_matched_id);
    PERFORM public._reconcile_scorer_ids_int(
        NEW.group_id,
        _old_int,
        _new_int
    );

    SELECT name INTO _group_name FROM public.skins_groups WHERE id = NEW.group_id;

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

-- Trigger DDL unchanged — only function bodies. CREATE OR REPLACE
-- preserves existing trigger bindings.

NOTIFY pgrst, 'reload schema';
