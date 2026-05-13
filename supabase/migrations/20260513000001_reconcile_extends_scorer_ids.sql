-- ============================================================================
-- 20260513000001_reconcile_extends_scorer_ids.sql
-- ============================================================================
-- Stage 3 of the SMS-invite-as-scorer reconciliation fix.
--
-- Extends BOTH phone-invite reconciliation triggers to also rewrite
-- skins_groups.scorer_ids and round_players.player_id when the placeholder
-- group_members.id UUID resolves to a real profile UUID — so the scorer
-- slot survives reconciliation instead of getting wiped by the client's
-- syncScorerIDs rule 3 (scorer-not-in-group → wipe).
--
-- Two triggers, two contexts, same logic:
--   - reconcile_phone_invites_for_profile (FORWARD): fires when a profile's
--     phone is set/changed; finds matching pending invites and UPDATEs
--     group_members. We extend it to also rewrite scorer_ids in the same
--     transaction.
--   - reconcile_phone_invite_at_insert (REVERSE): fires BEFORE INSERT on
--     group_members when an invited_phone matches an existing profile.
--     Mutates NEW to active+real player_id. We extend it to rewrite
--     scorer_ids for the to-be-inserted row's id (which is also the slot
--     anchor that the client wrote into scorer_ids at slot-time).
--
-- Defensive round_players rewrite: today RoundCoordinatorView skips nil-
-- profileId players from round_players, so the placeholder never lands
-- there in current code paths. The defensive UPDATE protects future
-- code paths that might bypass that filter.
--
-- Backwards-compat: legacy [Int] entries in scorer_ids are untouched.
-- scorer_ids_uuid_at returns NULL for non-UUID elements, so the rewrite
-- skips them. No data loss.
-- ============================================================================

-- ─── Helper: rewrite a single scorer_ids entry across one group ────────────

CREATE OR REPLACE FUNCTION public._reconcile_scorer_ids(
    p_group_id uuid,
    p_old_id uuid,
    p_new_id uuid
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    _arr jsonb;
    _len int;
BEGIN
    -- Read current scorer_ids; bail if null/empty.
    SELECT scorer_ids INTO _arr FROM public.skins_groups WHERE id = p_group_id;
    IF _arr IS NULL OR jsonb_typeof(_arr) != 'array' THEN
        RETURN;
    END IF;
    _len := jsonb_array_length(_arr);
    IF _len = 0 THEN
        RETURN;
    END IF;

    -- Rebuild array, swapping any element whose UUID equals p_old_id.
    -- Legacy [Int] elements are preserved untouched (scorer_ids_uuid_at
    -- returns NULL for non-UUID entries).
    UPDATE public.skins_groups sg
    SET scorer_ids = (
        SELECT jsonb_agg(
            CASE
                WHEN public.scorer_ids_uuid_at(sg.scorer_ids, ord - 1) = p_old_id
                THEN to_jsonb(p_new_id::text)
                ELSE sg.scorer_ids->(ord - 1)
            END
            ORDER BY ord
        )
        FROM generate_series(1, jsonb_array_length(sg.scorer_ids)) AS ord
    )
    WHERE sg.id = p_group_id
      AND sg.scorer_ids IS NOT NULL
      AND jsonb_array_length(sg.scorer_ids) > 0;
END;
$$;

COMMENT ON FUNCTION public._reconcile_scorer_ids(uuid, uuid, uuid) IS
    'Rewrites a single scorer_ids entry from p_old_id (placeholder UUID, typically group_members.id) to p_new_id (the reconciled profile UUID). Legacy [Int] entries are preserved untouched. Called by both phone-invite reconciliation triggers.';

-- ─── Forward trigger: extend with scorer_ids + round_players rewrites ──────

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
        -- Stage 3 NEW: rewrite scorer_ids for this group so the slot
        -- anchor on the membership_id resolves to the new profile UUID.
        PERFORM public._reconcile_scorer_ids(
            _reconciled.group_id,
            _reconciled.membership_id,
            NEW.id
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

-- ─── Reverse trigger: extend with scorer_ids rewrite ───────────────────────

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

    -- Stage 3 NEW: rewrite scorer_ids for this group so the slot
    -- anchor on NEW.id (the to-be-inserted row's PK, which the client
    -- supplied at slot-time and persisted in scorer_ids) resolves to
    -- the matched profile UUID instead. The row's id stays NEW.id so
    -- legacy phone-invite read paths continue to resolve correctly.
    PERFORM public._reconcile_scorer_ids(
        NEW.group_id,
        NEW.id,
        _matched_id
    );

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

-- Triggers themselves are unchanged; only the function bodies. Both
-- triggers were created in their original migrations and remain in
-- place: on_profile_phone_change (forward) + reconcile_phone_invite_at_insert
-- (reverse).

NOTIFY pgrst, 'reload schema';
