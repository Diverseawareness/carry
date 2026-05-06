


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."claim_guest_profile"("p_guest_id" "uuid", "p_real_id" "uuid", "p_group_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    -- 1. Migrate scores: update player_id from guest to real user
    --    Skip rows where real user already has a score for same (round_id, hole_num)
    UPDATE scores s
    SET player_id = p_real_id
    WHERE s.player_id = p_guest_id
      AND NOT EXISTS (
          SELECT 1 FROM scores s2
          WHERE s2.round_id = s.round_id
            AND s2.hole_num = s.hole_num
            AND s2.player_id = p_real_id
      );

    -- Delete any remaining guest score rows (duplicates that couldn't be migrated)
    DELETE FROM scores WHERE player_id = p_guest_id;

    -- 2. Migrate round_players: update player_id from guest to real user
    --    Skip rows where real user is already in that round
    UPDATE round_players rp
    SET player_id = p_real_id
    WHERE rp.player_id = p_guest_id
      AND NOT EXISTS (
          SELECT 1 FROM round_players rp2
          WHERE rp2.round_id = rp.round_id
            AND rp2.player_id = p_real_id
      );

    -- Delete any remaining guest round_player rows
    DELETE FROM round_players WHERE player_id = p_guest_id;

    -- 3. Group membership: delete guest row, activate real user's row
    DELETE FROM group_members
    WHERE group_id = p_group_id AND player_id = p_guest_id;

    -- If real user already has a membership row (from invite link), activate it
    UPDATE group_members
    SET status = 'active'
    WHERE group_id = p_group_id AND player_id = p_real_id;

    -- If real user has no membership row, create one
    INSERT INTO group_members (group_id, player_id, role, status)
    SELECT p_group_id, p_real_id, 'member', 'active'
    WHERE NOT EXISTS (
        SELECT 1 FROM group_members
        WHERE group_id = p_group_id AND player_id = p_real_id
    );

    -- 4. Mark guest profile as claimed
    UPDATE profiles
    SET is_guest = false, created_by = NULL
    WHERE id = p_guest_id;
END;
$$;


ALTER FUNCTION "public"."claim_guest_profile"("p_guest_id" "uuid", "p_real_id" "uuid", "p_group_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."claim_phone_invite"("p_membership_id" "uuid", "p_phone" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    _user_id uuid;
    _normalized_phone text;
    _row_phone text;
    _row_status text;
    _group_id uuid;
BEGIN
    _user_id := auth.uid();
    IF _user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required to claim an invite';
    END IF;

    _normalized_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
    IF length(_normalized_phone) < 10 THEN
        RAISE EXCEPTION 'Invalid phone number';
    END IF;

    -- Lock the row + verify match.
    SELECT invited_phone, status, group_id
      INTO _row_phone, _row_status, _group_id
    FROM public.group_members
    WHERE id = p_membership_id
    FOR UPDATE;

    IF _row_phone IS NULL THEN
        RAISE EXCEPTION 'Invite not found or already claimed';
    END IF;

    IF _row_status <> 'invited' THEN
        RAISE EXCEPTION 'Invite is no longer pending (status: %)', _row_status;
    END IF;

    IF _row_phone <> _normalized_phone THEN
        RAISE EXCEPTION 'Phone does not match this invite';
    END IF;

    -- Reconcile. Mirrors GroupService.inviteMemberByPhone post-claim logic.
    UPDATE public.group_members
    SET player_id = _user_id,
        invited_phone = '',
        status = 'active'
    WHERE id = p_membership_id;

    RETURN _group_id;
END;
$$;


ALTER FUNCTION "public"."claim_phone_invite"("p_membership_id" "uuid", "p_phone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."convert_quick_game_to_group"("p_group_id" "uuid", "p_group_name" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    _round_id uuid;
BEGIN
    -- Authorization: only the group creator can convert.
    IF NOT EXISTS (
        SELECT 1 FROM skins_groups
        WHERE id = p_group_id AND created_by = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Not authorized — only the group creator can convert group %', p_group_id;
    END IF;

    -- Find the most recent round in this group, whatever its status. The
    -- iOS Create-Group button flips status to 'completed' before invoking
    -- this RPC, so a status filter would miss it. The wipe RPC's own auth
    -- check (round.created_by = auth.uid()) keeps this from being a vector
    -- to wipe arbitrary other-creators' rounds.
    SELECT id INTO _round_id
    FROM rounds
    WHERE group_id = p_group_id
    ORDER BY created_at DESC
    LIMIT 1;

    -- Wipe guest profiles for this round before flipping the group. The wipe
    -- denormalizes display_name + handicap onto round_players + scores so
    -- Round History keeps showing each guest by name. Cascades clean the
    -- guest's group_members row entirely (Skins Groups are Carry-only by rule).
    --
    -- If there's no eligible round (edge case: convert called on a fresh
    -- group with no rounds), skip the wipe — nothing to do.
    IF _round_id IS NOT NULL THEN
        PERFORM public.delete_quick_game_guests(_round_id);
    END IF;

    -- Flip the group: not a Quick Game anymore, optionally rename.
    UPDATE skins_groups
    SET is_quick_game = false,
        name = COALESCE(p_group_name, name)
    WHERE id = p_group_id;

    -- Carry users who were `active` STAY active — no demotion. The previous
    -- migration (20260330000000) used `UPDATE group_members SET status='invited'`
    -- here; that was the cold "You're Invited!" disconnect. Removed entirely.
    --
    -- Note: any group_members rows that were 'invited' or 'declined' before
    -- conversion are intentionally left alone — those represent Carry users
    -- the creator invited but never accepted, separate from the conversion
    -- itself.
END;
$$;


ALTER FUNCTION "public"."convert_quick_game_to_group"("p_group_id" "uuid", "p_group_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_guest_profiles"("p_names" "text"[], "p_initials" "text"[], "p_handicaps" double precision[], "p_colors" "text"[]) RETURNS "uuid"[]
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  result uuid[] := '{}'; new_id uuid; i int;
BEGIN
  FOR i IN 1..array_length(p_names, 1) LOOP
    new_id := gen_random_uuid();
    INSERT INTO profiles (id, display_name, initials, color, avatar,
      handicap, is_guest, created_by, created_at, updated_at)
    VALUES (new_id, p_names[i], p_initials[i], p_colors[i], '🏌️',
      coalesce(p_handicaps[i], 0.0), true, auth.uid(), now(), now());
    result := result || new_id;
  END LOOP;
  RETURN result;
END; $$;


ALTER FUNCTION "public"."create_guest_profiles"("p_names" "text"[], "p_initials" "text"[], "p_handicaps" double precision[], "p_colors" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_guest_profiles"("p_names" "text"[], "p_initials" "text"[], "p_handicaps" double precision[], "p_colors" "text"[], "p_creator_id" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"[]
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  result uuid[] := '{}'; new_id uuid; i int;
BEGIN
  FOR i IN 1..array_length(p_names, 1) LOOP
    new_id := gen_random_uuid();
    INSERT INTO profiles (id, display_name, initials, color, avatar,
      handicap, is_guest, created_by, created_at, updated_at)
    VALUES (new_id, p_names[i], p_initials[i], p_colors[i], '🏌️',
      coalesce(p_handicaps[i], 0.0), true, p_creator_id, now(), now());
    result := result || new_id;
  END LOOP;
  RETURN result;
END; $$;


ALTER FUNCTION "public"."create_guest_profiles"("p_names" "text"[], "p_initials" "text"[], "p_handicaps" double precision[], "p_colors" "text"[], "p_creator_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_group"("gid" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  DELETE FROM scores WHERE round_id IN (SELECT id FROM rounds WHERE group_id = gid);
  DELETE FROM round_players WHERE round_id IN (SELECT id FROM rounds WHERE group_id = gid);
  DELETE FROM rounds WHERE group_id = gid;
  DELETE FROM group_members WHERE group_id = gid;
  DELETE FROM skins_groups WHERE id = gid;
END;
$$;


ALTER FUNCTION "public"."delete_group"("gid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_quick_game_guests"("p_round_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    deleted_count int;
BEGIN
    -- Authorization: only the round creator can wipe guests for this round.
    -- SECURITY DEFINER bypasses RLS, so we enforce the gate explicitly.
    IF NOT EXISTS (
        SELECT 1 FROM rounds
        WHERE id = p_round_id AND created_by = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Not authorized — only the round creator can delete guests for round %', p_round_id;
    END IF;

    -- Step 1: denormalize display_name + handicap onto every round_players
    -- row that references one of this round's guests. We update across ALL
    -- rounds (not just p_round_id) so legacy guests-in-multiple-rounds — which
    -- shouldn't exist under the new ephemeral rule, but may exist in current
    -- prod data — also keep their history intact when their profile is wiped.
    UPDATE round_players rp
    SET guest_display_name = p.display_name,
        guest_handicap = p.handicap
    FROM profiles p
    WHERE rp.player_id = p.id
      AND p.is_guest = true
      AND p.id IN (
          SELECT DISTINCT player_id FROM round_players
          WHERE round_id = p_round_id AND player_id IS NOT NULL
      );

    -- Step 2: same denormalization for scores. This makes scorecard rendering
    -- after the wipe work without needing to JOIN through round_players to
    -- recover the guest's name.
    UPDATE scores s
    SET guest_display_name = p.display_name,
        guest_handicap = p.handicap
    FROM profiles p
    WHERE s.player_id = p.id
      AND p.is_guest = true
      AND p.id IN (
          SELECT DISTINCT player_id FROM round_players
          WHERE round_id = p_round_id AND player_id IS NOT NULL
      );

    -- Step 3: delete the guest profiles. Cascades:
    --   round_players.player_id → SET NULL (denormalized fields preserve display)
    --   scores.player_id        → SET NULL (denormalized fields preserve display)
    --   group_members           → CASCADE  (row removed entirely)
    DELETE FROM profiles
    WHERE is_guest = true
      AND id IN (
          SELECT DISTINCT player_id FROM round_players
          WHERE round_id = p_round_id AND player_id IS NOT NULL
      );

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;


ALTER FUNCTION "public"."delete_quick_game_guests"("p_round_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_user_account"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    _uid uuid := auth.uid();
BEGIN
    IF _uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Delete all user data (no FK constraints blocking anymore)
    DELETE FROM public.scores WHERE player_id = _uid;
    DELETE FROM public.round_players WHERE player_id = _uid;
    DELETE FROM public.group_members WHERE player_id = _uid;
    UPDATE public.rounds SET created_by = NULL WHERE created_by = _uid;
    UPDATE public.skins_groups SET created_by = NULL WHERE created_by = _uid;
    UPDATE public.courses SET created_by = NULL WHERE created_by = _uid;
    DELETE FROM public.profiles WHERE created_by = _uid AND is_guest = true;
    DELETE FROM public.profiles WHERE id = _uid;
END;
$$;


ALTER FUNCTION "public"."delete_user_account"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."find_pending_invites_by_phone"("p_phone" "text") RETURNS TABLE("membership_id" "uuid", "group_id" "uuid", "group_name" "text", "invited_by_id" "uuid", "invited_by_name" "text", "is_quick_game" boolean, "invited_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    _normalized_phone text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required to look up invites by phone';
    END IF;

    _normalized_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');

    IF length(_normalized_phone) < 10 THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        gm.id AS membership_id,
        sg.id AS group_id,
        sg.name AS group_name,
        sg.created_by AS invited_by_id,
        coalesce(p.display_name, 'A friend') AS invited_by_name,
        sg.is_quick_game,
        gm.joined_at AS invited_at
    FROM public.group_members gm
    JOIN public.skins_groups sg ON sg.id = gm.group_id
    LEFT JOIN public.profiles p ON p.id = sg.created_by
    WHERE gm.invited_phone = _normalized_phone
      AND gm.status = 'invited'
    ORDER BY gm.joined_at DESC;
END;
$$;


ALTER FUNCTION "public"."find_pending_invites_by_phone"("p_phone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_active_group_ids"("uid" "uuid") RETURNS SETOF "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT group_id FROM group_members
  WHERE player_id = uid AND status = 'active';
$$;


ALTER FUNCTION "public"."get_user_active_group_ids"("uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_created_group_ids"("uid" "uuid") RETURNS SETOF "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT id FROM skins_groups WHERE created_by = uid;
$$;


ALTER FUNCTION "public"."get_user_created_group_ids"("uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_created_round_ids"("uid" "uuid") RETURNS SETOF "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT id FROM rounds WHERE created_by = uid;
$$;


ALTER FUNCTION "public"."get_user_created_round_ids"("uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_group_ids"("user_id" "uuid") RETURNS SETOF "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT group_id FROM group_members WHERE player_id = user_id AND status = 'active';
$$;


ALTER FUNCTION "public"."get_user_group_ids"("user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_invited_group_ids"("uid" "uuid") RETURNS SETOF "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT group_id FROM group_members
  WHERE player_id = uid AND status = 'invited';
$$;


ALTER FUNCTION "public"."get_user_invited_group_ids"("uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_member_group_ids"("uid" "uuid") RETURNS SETOF "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT group_id FROM group_members
  WHERE player_id = uid AND status IN ('active', 'invited');
$$;


ALTER FUNCTION "public"."get_user_member_group_ids"("uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_memberships"("uid" "uuid") RETURNS SETOF "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT group_id FROM group_members WHERE player_id = uid;
$$;


ALTER FUNCTION "public"."get_user_memberships"("uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_round_ids"("uid" "uuid") RETURNS SETOF "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT round_id FROM round_players WHERE player_id = uid;
$$;


ALTER FUNCTION "public"."get_user_round_ids"("uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    _first_name text;
    _last_name  text;
    _email      text;
    _display    text;
    _initials   text;
BEGIN
    _first_name := coalesce(new.raw_user_meta_data ->> 'first_name', new.raw_user_meta_data ->> 'given_name', '');
    _last_name  := coalesce(new.raw_user_meta_data ->> 'last_name', new.raw_user_meta_data ->> 'family_name', '');
    _email      := coalesce(new.raw_user_meta_data ->> 'email', new.email, '');
    _display    := CASE WHEN _first_name != '' THEN _first_name ELSE 'Player' END;
    _initials   := CASE
        WHEN _first_name != '' AND _last_name != '' THEN upper(left(_first_name, 1) || left(_last_name, 1))
        WHEN _first_name != '' THEN upper(left(_first_name, 2))
        ELSE 'PL'
    END;

    INSERT INTO public.profiles (id, first_name, last_name, display_name, initials, email, color, avatar, handicap, created_at, updated_at)
    VALUES (new.id, _first_name, _last_name, _display, _initials, _email, '#D4A017', 'üèåÔ∏è', 0.0, now(), now());

    RETURN new;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_group_creator"("gid" "uuid", "uid" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (SELECT 1 FROM skins_groups WHERE id = gid AND created_by = uid);
$$;


ALTER FUNCTION "public"."is_group_creator"("gid" "uuid", "uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_round_creator"("rid" "uuid", "uid" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (SELECT 1 FROM rounds WHERE id = rid AND created_by = uid);
$$;


ALTER FUNCTION "public"."is_round_creator"("rid" "uuid", "uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_round_participant"("rid" "uuid", "uid" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (SELECT 1 FROM round_players WHERE round_id = rid AND player_id = uid);
$$;


ALTER FUNCTION "public"."is_round_participant"("rid" "uuid", "uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_username_available"("uname" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    RETURN NOT EXISTS (SELECT 1 FROM public.profiles WHERE username = lower(uname));
END;
$$;


ALTER FUNCTION "public"."is_username_available"("uname" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_push"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    _url text;
    _payload jsonb;
    _anon_key text;
    _self_initiated boolean := false;
BEGIN
    -- ─── Resolve edge function URL ────────────────────────────────────────
    _url := rtrim(current_setting('app.settings.supabase_url', true), '/')
             || '/functions/v1/send-push-notification';

    IF _url IS NULL OR _url = '' OR _url = '/functions/v1/send-push-notification' THEN
        _url := 'https://seeitehizboxjbnccnyd.supabase.co/functions/v1/send-push-notification';
    END IF;

    -- ─── Resolve anon key ─────────────────────────────────────────────────
    _anon_key := current_setting('app.settings.supabase_anon_key', true);
    IF _anon_key IS NULL OR _anon_key = '' THEN
        _anon_key := coalesce(current_setting('supabase.anon_key', true), '');
    END IF;

    -- ─── Per-table dispatch ───────────────────────────────────────────────
    -- All NEW.<col> references MUST live inside one of these IF blocks.
    -- The IF condition itself only touches TG_TABLE_NAME (a built-in trigger
    -- variable, no rowtype binding) so the planner cannot fail to bind it
    -- when the trigger fires on a different table.
    --
    -- DO NOT add NEW.<col> refs at the top level of this function or in any
    -- expression that runs unconditionally — that's how the 42703 bug
    -- (fixed by this migration) was originally introduced.

    IF TG_TABLE_NAME = 'group_members' THEN
        -- self_initiated: user QR/link-joined themselves. iOS immediately
        -- promotes the row 'invited' → 'active'; without this flag the edge
        -- function would push "You're Invited!" to the user about a group
        -- they actively joined. Set to true so handleGroupInvite skips.
        IF auth.uid() IS NOT NULL AND NEW.player_id = auth.uid() THEN
            _self_initiated := true;
        END IF;

        -- Guest invite skip: guest profiles have no device_token, so the
        -- edge-function call would no-op anyway. Skip the HTTP round-trip.
        IF NEW.status = 'invited' THEN
            PERFORM 1 FROM profiles
            WHERE id = NEW.player_id AND is_guest = true;
            IF FOUND THEN
                RETURN NEW;
            END IF;
        END IF;
    END IF;

    -- rounds and scores branches: payload is built generically below from
    -- to_jsonb(NEW); no table-specific NEW.<col> references needed here.

    -- ─── Build payload ────────────────────────────────────────────────────
    _payload := jsonb_build_object(
        'type',           TG_OP,
        'table',          TG_TABLE_NAME,
        'record',         to_jsonb(NEW),
        'old_record',     CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END,
        'self_initiated', _self_initiated
    );

    -- ─── Fire and forget ──────────────────────────────────────────────────
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


ALTER FUNCTION "public"."notify_push"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reconcile_phone_invite_at_insert"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."reconcile_phone_invite_at_insert"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reconcile_phone_invites_for_profile"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."reconcile_phone_invites_for_profile"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_handicap_reminders"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."send_handicap_reminders"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_profiles_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    new.updated_at = now();
    RETURN new;
END;
$$;


ALTER FUNCTION "public"."update_profiles_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_skins_groups_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."update_skins_groups_updated_at"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."courses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "club_name" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."courses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."group_members" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "group_id" "uuid" NOT NULL,
    "player_id" "uuid" NOT NULL,
    "role" "text" DEFAULT 'member'::"text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "joined_at" timestamp with time zone DEFAULT "now"(),
    "invited_phone" "text",
    "sort_order" integer DEFAULT 0,
    "group_num" integer DEFAULT 1 NOT NULL
);


ALTER TABLE "public"."group_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."holes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "course_id" "uuid" NOT NULL,
    "num" integer NOT NULL,
    "par" integer NOT NULL,
    "hcp" integer NOT NULL
);


ALTER TABLE "public"."holes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "display_name" "text" NOT NULL,
    "initials" "text" NOT NULL,
    "color" "text" DEFAULT '#4A90D9'::"text" NOT NULL,
    "avatar" "text" DEFAULT '🏌️'::"text" NOT NULL,
    "handicap" double precision DEFAULT 0.0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "avatar_url" "text",
    "home_club_id" integer,
    "is_club_member" boolean DEFAULT true,
    "username" "text",
    "home_club" "text",
    "email" "text",
    "first_name" "text" DEFAULT ''::"text",
    "last_name" "text" DEFAULT ''::"text",
    "ghin_number" "text",
    "device_token" "text",
    "is_guest" boolean DEFAULT false,
    "created_by" "uuid",
    "phone" "text",
    "notif_game_alerts" boolean DEFAULT true NOT NULL,
    "notif_live_scoring" boolean DEFAULT true NOT NULL,
    "notif_group_activity" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."round_players" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "round_id" "uuid" NOT NULL,
    "player_id" "uuid" NOT NULL,
    "group_num" integer DEFAULT 1 NOT NULL,
    "status" "text" DEFAULT 'accepted'::"text" NOT NULL,
    "invited_by" "uuid",
    "guest_display_name" "text",
    "guest_handicap" double precision
);


ALTER TABLE "public"."round_players" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rounds" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "course_id" "uuid" NOT NULL,
    "created_by" "uuid",
    "buy_in" integer DEFAULT 50 NOT NULL,
    "game_type" "text" DEFAULT 'skins'::"text" NOT NULL,
    "net" boolean DEFAULT true NOT NULL,
    "carries" boolean DEFAULT false NOT NULL,
    "outright" boolean DEFAULT true NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "group_id" "uuid",
    "tee_box_id" "uuid",
    "handicap_percentage" double precision DEFAULT 1.0 NOT NULL,
    "scorer_id" "uuid",
    "scoring_mode" "text" DEFAULT 'single'::"text" NOT NULL,
    "force_completed" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."rounds" OWNER TO "postgres";


COMMENT ON COLUMN "public"."rounds"."force_completed" IS 'True when the creator used End Game / End Game & Save Results to end the game early. Combined with status, disambiguates natural completion from forced end.';



CREATE TABLE IF NOT EXISTS "public"."scores" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "round_id" "uuid" NOT NULL,
    "player_id" "uuid" NOT NULL,
    "hole_num" integer NOT NULL,
    "score" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "proposed_score" integer,
    "proposed_by" "uuid",
    "guest_display_name" "text",
    "guest_handicap" double precision
);

ALTER TABLE ONLY "public"."scores" REPLICA IDENTITY FULL;


ALTER TABLE "public"."scores" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."skins_groups" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "created_by" "uuid",
    "buy_in" numeric DEFAULT 0,
    "last_course_name" "text",
    "last_course_club_name" "text",
    "scheduled_date" timestamp with time zone,
    "recurrence" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "last_tee_box_name" "text",
    "last_tee_box_color" "text",
    "handicap_percentage" double precision DEFAULT 1.0,
    "last_tee_box_course_rating" double precision,
    "last_tee_box_slope_rating" integer,
    "last_tee_box_par" integer,
    "scoring_mode" "text" DEFAULT 'single'::"text" NOT NULL,
    "is_quick_game" boolean DEFAULT false,
    "scorer_ids" "jsonb",
    "tee_time_interval" integer,
    "last_tee_box_holes_json" "text",
    "winnings_display" "text" DEFAULT 'gross'::"text" NOT NULL,
    "tee_times_json" "text",
    "today_deselected_ids" "uuid"[],
    CONSTRAINT "skins_groups_winnings_display_check" CHECK (("winnings_display" = ANY (ARRAY['gross'::"text", 'net'::"text"])))
);


ALTER TABLE "public"."skins_groups" OWNER TO "postgres";


COMMENT ON COLUMN "public"."skins_groups"."handicap_percentage" IS 'Default handicap percentage applied to rounds in this group (0.0-1.0, e.g. 0.7 = 70%). Drift-fix migration: column existed on prod outside migration tracking.';



CREATE TABLE IF NOT EXISTS "public"."tee_boxes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "course_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "color" "text" DEFAULT '#FFFFFF'::"text" NOT NULL,
    "course_rating" double precision DEFAULT 72.0 NOT NULL,
    "slope_rating" integer DEFAULT 113 NOT NULL,
    "par" integer DEFAULT 72 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "holes_json" "text"
);


ALTER TABLE "public"."tee_boxes" OWNER TO "postgres";


ALTER TABLE ONLY "public"."courses"
    ADD CONSTRAINT "courses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."group_members"
    ADD CONSTRAINT "group_members_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."holes"
    ADD CONSTRAINT "holes_course_id_num_key" UNIQUE ("course_id", "num");



ALTER TABLE ONLY "public"."holes"
    ADD CONSTRAINT "holes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_username_key" UNIQUE ("username");



ALTER TABLE ONLY "public"."round_players"
    ADD CONSTRAINT "round_players_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."round_players"
    ADD CONSTRAINT "round_players_round_id_player_id_key" UNIQUE ("round_id", "player_id");



ALTER TABLE ONLY "public"."rounds"
    ADD CONSTRAINT "rounds_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."scores"
    ADD CONSTRAINT "scores_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."scores"
    ADD CONSTRAINT "scores_round_id_player_id_hole_num_key" UNIQUE ("round_id", "player_id", "hole_num");



ALTER TABLE ONLY "public"."skins_groups"
    ADD CONSTRAINT "skins_groups_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tee_boxes"
    ADD CONSTRAINT "tee_boxes_course_id_name_key" UNIQUE ("course_id", "name");



ALTER TABLE ONLY "public"."tee_boxes"
    ADD CONSTRAINT "tee_boxes_pkey" PRIMARY KEY ("id");



CREATE UNIQUE INDEX "group_members_unique_real_player" ON "public"."group_members" USING "btree" ("group_id", "player_id") WHERE (("invited_phone" IS NULL) OR ("invited_phone" = ''::"text"));



CREATE INDEX "idx_group_members_group_status" ON "public"."group_members" USING "btree" ("group_id", "status");



CREATE INDEX "idx_group_members_invited" ON "public"."group_members" USING "btree" ("player_id") WHERE ("status" = 'invited'::"text");



CREATE INDEX "idx_group_members_player" ON "public"."group_members" USING "btree" ("player_id") WHERE ("status" = 'active'::"text");



CREATE INDEX "idx_group_members_player_status" ON "public"."group_members" USING "btree" ("player_id", "status");



CREATE INDEX "idx_holes_course" ON "public"."holes" USING "btree" ("course_id");



CREATE INDEX "idx_profiles_created_by" ON "public"."profiles" USING "btree" ("created_by");



CREATE INDEX "idx_profiles_is_guest" ON "public"."profiles" USING "btree" ("is_guest") WHERE ("is_guest" = true);



CREATE INDEX "idx_profiles_phone" ON "public"."profiles" USING "btree" ("phone") WHERE (("phone" IS NOT NULL) AND ("phone" <> ''::"text"));



CREATE INDEX "idx_profiles_username" ON "public"."profiles" USING "btree" ("username");



CREATE INDEX "idx_round_players_player_status" ON "public"."round_players" USING "btree" ("player_id", "status");



CREATE INDEX "idx_round_players_round" ON "public"."round_players" USING "btree" ("round_id");



CREATE INDEX "idx_round_players_round_status" ON "public"."round_players" USING "btree" ("round_id", "status");



CREATE INDEX "idx_round_players_status" ON "public"."round_players" USING "btree" ("player_id", "status");



CREATE INDEX "idx_rounds_group" ON "public"."rounds" USING "btree" ("group_id") WHERE ("status" = 'active'::"text");



CREATE INDEX "idx_rounds_group_status" ON "public"."rounds" USING "btree" ("group_id", "status");



CREATE INDEX "idx_rounds_status" ON "public"."rounds" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "idx_scores_round" ON "public"."scores" USING "btree" ("round_id");



CREATE INDEX "idx_scores_round_player" ON "public"."scores" USING "btree" ("round_id", "player_id");



CREATE INDEX "idx_scores_round_player_hole" ON "public"."scores" USING "btree" ("round_id", "player_id", "hole_num");



CREATE OR REPLACE TRIGGER "on_group_member_change" AFTER INSERT OR UPDATE ON "public"."group_members" FOR EACH ROW EXECUTE FUNCTION "public"."notify_push"();



CREATE OR REPLACE TRIGGER "on_round_change" AFTER INSERT OR UPDATE ON "public"."rounds" FOR EACH ROW EXECUTE FUNCTION "public"."notify_push"();



CREATE OR REPLACE TRIGGER "on_score_insert" AFTER INSERT ON "public"."scores" FOR EACH ROW EXECUTE FUNCTION "public"."notify_push"();



CREATE OR REPLACE TRIGGER "profiles_updated_at" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_profiles_updated_at"();



CREATE OR REPLACE TRIGGER "reconcile_phone_invite_at_insert" BEFORE INSERT ON "public"."group_members" FOR EACH ROW EXECUTE FUNCTION "public"."reconcile_phone_invite_at_insert"();



CREATE OR REPLACE TRIGGER "reconcile_phone_invites" AFTER INSERT OR UPDATE OF "phone" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."reconcile_phone_invites_for_profile"();



CREATE OR REPLACE TRIGGER "skins_groups_updated_at" BEFORE UPDATE ON "public"."skins_groups" FOR EACH ROW EXECUTE FUNCTION "public"."update_skins_groups_updated_at"();



ALTER TABLE ONLY "public"."group_members"
    ADD CONSTRAINT "group_members_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."skins_groups"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."group_members"
    ADD CONSTRAINT "group_members_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."holes"
    ADD CONSTRAINT "holes_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "public"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."round_players"
    ADD CONSTRAINT "round_players_invited_by_fkey" FOREIGN KEY ("invited_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."round_players"
    ADD CONSTRAINT "round_players_round_id_fkey" FOREIGN KEY ("round_id") REFERENCES "public"."rounds"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."rounds"
    ADD CONSTRAINT "rounds_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "public"."courses"("id");



ALTER TABLE ONLY "public"."rounds"
    ADD CONSTRAINT "rounds_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."skins_groups"("id");



ALTER TABLE ONLY "public"."rounds"
    ADD CONSTRAINT "rounds_tee_box_id_fkey" FOREIGN KEY ("tee_box_id") REFERENCES "public"."tee_boxes"("id");



ALTER TABLE ONLY "public"."scores"
    ADD CONSTRAINT "scores_round_id_fkey" FOREIGN KEY ("round_id") REFERENCES "public"."rounds"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tee_boxes"
    ADD CONSTRAINT "tee_boxes_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "public"."courses"("id") ON DELETE CASCADE;



CREATE POLICY "Authenticated can create tee boxes" ON "public"."tee_boxes" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can create courses" ON "public"."courses" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can create groups" ON "public"."skins_groups" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can create holes" ON "public"."holes" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can insert members" ON "public"."group_members" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Course creator can add holes" ON "public"."holes" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Course creator can update courses" ON "public"."courses" FOR UPDATE USING (("created_by" = "auth"."uid"()));



CREATE POLICY "Course creator can update tee boxes" ON "public"."tee_boxes" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."courses" "c"
  WHERE (("c"."id" = "tee_boxes"."course_id") AND ("c"."created_by" = "auth"."uid"())))));



CREATE POLICY "Courses are viewable by authenticated users" ON "public"."courses" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Creator can update rounds" ON "public"."rounds" FOR UPDATE USING (("created_by" = "auth"."uid"()));



CREATE POLICY "Creators and self can update members" ON "public"."group_members" FOR UPDATE USING (("public"."is_group_creator"("group_id", "auth"."uid"()) OR ("player_id" = "auth"."uid"())));



CREATE POLICY "Creators can delete members" ON "public"."group_members" FOR DELETE USING ((("group_id" IN ( SELECT "public"."get_user_created_group_ids"("auth"."uid"()) AS "get_user_created_group_ids")) OR ("player_id" = "auth"."uid"())));



CREATE POLICY "Creators can delete their groups" ON "public"."skins_groups" FOR DELETE USING (("created_by" = "auth"."uid"()));



CREATE POLICY "Creators can insert members" ON "public"."group_members" FOR INSERT WITH CHECK ((("group_id" IN ( SELECT "public"."get_user_created_group_ids"("auth"."uid"()) AS "get_user_created_group_ids")) OR ("player_id" = "auth"."uid"())));



CREATE POLICY "Creators can update members" ON "public"."group_members" FOR UPDATE USING ((("group_id" IN ( SELECT "public"."get_user_created_group_ids"("auth"."uid"()) AS "get_user_created_group_ids")) OR ("player_id" = "auth"."uid"())));



CREATE POLICY "Creators can update their groups" ON "public"."skins_groups" FOR UPDATE USING ((("created_by" = "auth"."uid"()) OR ("created_by" IS NULL)));



CREATE POLICY "Holes are viewable by authenticated users" ON "public"."holes" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Holes are viewable by everyone" ON "public"."holes" FOR SELECT USING (true);



CREATE POLICY "Invited users can see invited groups" ON "public"."skins_groups" FOR SELECT USING (("id" IN ( SELECT "public"."get_user_invited_group_ids"("auth"."uid"()) AS "get_user_invited_group_ids")));



CREATE POLICY "Members and creators can read their groups" ON "public"."skins_groups" FOR SELECT USING ((("created_by" = "auth"."uid"()) OR ("id" IN ( SELECT "public"."get_user_group_ids"("auth"."uid"()) AS "get_user_group_ids"))));



CREATE POLICY "Members can read group members" ON "public"."group_members" FOR SELECT USING (("group_id" IN ( SELECT "public"."get_user_active_group_ids"("auth"."uid"()) AS "get_user_active_group_ids")));



CREATE POLICY "Members can read their groups" ON "public"."skins_groups" FOR SELECT USING (("id" IN ( SELECT "public"."get_user_active_group_ids"("auth"."uid"()) AS "get_user_active_group_ids")));



CREATE POLICY "Participants can insert scores" ON "public"."scores" FOR INSERT WITH CHECK (("public"."is_round_creator"("round_id", "auth"."uid"()) OR "public"."is_round_participant"("round_id", "auth"."uid"())));



CREATE POLICY "Participants can read scores" ON "public"."scores" FOR SELECT USING (("public"."is_round_creator"("round_id", "auth"."uid"()) OR "public"."is_round_participant"("round_id", "auth"."uid"())));



CREATE POLICY "Participants can update scores" ON "public"."scores" FOR UPDATE USING (("public"."is_round_creator"("round_id", "auth"."uid"()) OR "public"."is_round_participant"("round_id", "auth"."uid"())));



CREATE POLICY "Players can read round_players" ON "public"."round_players" FOR SELECT USING ((("player_id" = "auth"."uid"()) OR "public"."is_round_creator"("round_id", "auth"."uid"())));



CREATE POLICY "Players can view their own round_players rows" ON "public"."round_players" FOR SELECT USING ((("player_id" = "auth"."uid"()) OR ("round_id" IN ( SELECT "public"."get_user_round_ids"("auth"."uid"()) AS "get_user_round_ids"))));



CREATE POLICY "Profiles are viewable by authenticated users" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Profiles are viewable by everyone" ON "public"."profiles" FOR SELECT USING (true);



CREATE POLICY "Round creators can delete players" ON "public"."round_players" FOR DELETE USING (("public"."is_round_creator"("round_id", "auth"."uid"()) OR ("player_id" = "auth"."uid"())));



CREATE POLICY "Round creators can insert players" ON "public"."round_players" FOR INSERT WITH CHECK (("public"."is_round_creator"("round_id", "auth"."uid"()) OR ("player_id" = "auth"."uid"())));



CREATE POLICY "Round creators can invite players" ON "public"."round_players" FOR INSERT WITH CHECK ((("round_id" IN ( SELECT "public"."get_user_created_round_ids"("auth"."uid"()) AS "get_user_created_round_ids")) OR ("player_id" = "auth"."uid"())));



CREATE POLICY "Round creators can update players" ON "public"."round_players" FOR UPDATE USING (("public"."is_round_creator"("round_id", "auth"."uid"()) OR ("player_id" = "auth"."uid"())));



CREATE POLICY "Round participants can insert scores" ON "public"."scores" FOR INSERT WITH CHECK ((("round_id" IN ( SELECT "public"."get_user_round_ids"("auth"."uid"()) AS "get_user_round_ids")) OR ("round_id" IN ( SELECT "public"."get_user_created_round_ids"("auth"."uid"()) AS "get_user_created_round_ids"))));



CREATE POLICY "Round participants can read rounds" ON "public"."rounds" FOR SELECT USING ((("created_by" = "auth"."uid"()) OR ("id" IN ( SELECT "public"."get_user_round_ids"("auth"."uid"()) AS "get_user_round_ids")) OR (("group_id" IS NOT NULL) AND ("group_id" IN ( SELECT "public"."get_user_active_group_ids"("auth"."uid"()) AS "get_user_active_group_ids")))));



CREATE POLICY "Round participants can read scores" ON "public"."scores" FOR SELECT USING ((("round_id" IN ( SELECT "public"."get_user_round_ids"("auth"."uid"()) AS "get_user_round_ids")) OR ("round_id" IN ( SELECT "public"."get_user_created_round_ids"("auth"."uid"()) AS "get_user_created_round_ids"))));



CREATE POLICY "Round participants can update scores" ON "public"."scores" FOR UPDATE USING ((("round_id" IN ( SELECT "public"."get_user_round_ids"("auth"."uid"()) AS "get_user_round_ids")) OR ("round_id" IN ( SELECT "public"."get_user_created_round_ids"("auth"."uid"()) AS "get_user_created_round_ids"))));



CREATE POLICY "Tee boxes are viewable by everyone" ON "public"."tee_boxes" FOR SELECT USING (true);



CREATE POLICY "Users can create rounds" ON "public"."rounds" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete guest profiles they created" ON "public"."profiles" FOR DELETE USING ((("created_by" = "auth"."uid"()) AND ("is_guest" = true)));



CREATE POLICY "Users can delete their own profile" ON "public"."profiles" FOR DELETE USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can delete their own scores" ON "public"."scores" FOR DELETE USING (("player_id" = "auth"."uid"()));



CREATE POLICY "Users can delete their rounds" ON "public"."rounds" FOR DELETE USING ((("created_by" = "auth"."uid"()) OR ("id" IN ( SELECT "public"."get_user_round_ids"("auth"."uid"()) AS "get_user_round_ids"))));



CREATE POLICY "Users can insert own profile" ON "public"."profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Users can insert their own profile" ON "public"."profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Users can read rounds" ON "public"."rounds" FOR SELECT USING ((("created_by" = "auth"."uid"()) OR "public"."is_round_participant"("id", "auth"."uid"())));



CREATE POLICY "Users can see own membership rows" ON "public"."group_members" FOR SELECT USING ((("player_id" = "auth"."uid"()) OR ("group_id" IN ( SELECT "public"."get_user_memberships"("auth"."uid"()) AS "get_user_memberships"))));



CREATE POLICY "Users can update own profile" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can update their own profile" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



ALTER TABLE "public"."courses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."group_members" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."holes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."round_players" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rounds" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."scores" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."skins_groups" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tee_boxes" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."claim_guest_profile"("p_guest_id" "uuid", "p_real_id" "uuid", "p_group_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."claim_guest_profile"("p_guest_id" "uuid", "p_real_id" "uuid", "p_group_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."claim_guest_profile"("p_guest_id" "uuid", "p_real_id" "uuid", "p_group_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."claim_phone_invite"("p_membership_id" "uuid", "p_phone" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."claim_phone_invite"("p_membership_id" "uuid", "p_phone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."claim_phone_invite"("p_membership_id" "uuid", "p_phone" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."convert_quick_game_to_group"("p_group_id" "uuid", "p_group_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."convert_quick_game_to_group"("p_group_id" "uuid", "p_group_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."convert_quick_game_to_group"("p_group_id" "uuid", "p_group_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_guest_profiles"("p_names" "text"[], "p_initials" "text"[], "p_handicaps" double precision[], "p_colors" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."create_guest_profiles"("p_names" "text"[], "p_initials" "text"[], "p_handicaps" double precision[], "p_colors" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_guest_profiles"("p_names" "text"[], "p_initials" "text"[], "p_handicaps" double precision[], "p_colors" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_guest_profiles"("p_names" "text"[], "p_initials" "text"[], "p_handicaps" double precision[], "p_colors" "text"[], "p_creator_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."create_guest_profiles"("p_names" "text"[], "p_initials" "text"[], "p_handicaps" double precision[], "p_colors" "text"[], "p_creator_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_guest_profiles"("p_names" "text"[], "p_initials" "text"[], "p_handicaps" double precision[], "p_colors" "text"[], "p_creator_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_group"("gid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_group"("gid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_group"("gid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_quick_game_guests"("p_round_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_quick_game_guests"("p_round_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_quick_game_guests"("p_round_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_user_account"() TO "anon";
GRANT ALL ON FUNCTION "public"."delete_user_account"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_user_account"() TO "service_role";



GRANT ALL ON FUNCTION "public"."find_pending_invites_by_phone"("p_phone" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."find_pending_invites_by_phone"("p_phone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."find_pending_invites_by_phone"("p_phone" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_active_group_ids"("uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_active_group_ids"("uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_active_group_ids"("uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_created_group_ids"("uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_created_group_ids"("uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_created_group_ids"("uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_created_round_ids"("uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_created_round_ids"("uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_created_round_ids"("uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_group_ids"("user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_group_ids"("user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_group_ids"("user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_invited_group_ids"("uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_invited_group_ids"("uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_invited_group_ids"("uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_member_group_ids"("uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_member_group_ids"("uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_member_group_ids"("uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_memberships"("uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_memberships"("uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_memberships"("uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_round_ids"("uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_round_ids"("uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_round_ids"("uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_group_creator"("gid" "uuid", "uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_group_creator"("gid" "uuid", "uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_group_creator"("gid" "uuid", "uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_round_creator"("rid" "uuid", "uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_round_creator"("rid" "uuid", "uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_round_creator"("rid" "uuid", "uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_round_participant"("rid" "uuid", "uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_round_participant"("rid" "uuid", "uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_round_participant"("rid" "uuid", "uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_username_available"("uname" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_username_available"("uname" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_username_available"("uname" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_push"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_push"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_push"() TO "service_role";



GRANT ALL ON FUNCTION "public"."reconcile_phone_invite_at_insert"() TO "anon";
GRANT ALL ON FUNCTION "public"."reconcile_phone_invite_at_insert"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."reconcile_phone_invite_at_insert"() TO "service_role";



GRANT ALL ON FUNCTION "public"."reconcile_phone_invites_for_profile"() TO "anon";
GRANT ALL ON FUNCTION "public"."reconcile_phone_invites_for_profile"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."reconcile_phone_invites_for_profile"() TO "service_role";



GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";



GRANT ALL ON FUNCTION "public"."send_handicap_reminders"() TO "anon";
GRANT ALL ON FUNCTION "public"."send_handicap_reminders"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_handicap_reminders"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_profiles_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_profiles_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_profiles_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_skins_groups_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_skins_groups_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_skins_groups_updated_at"() TO "service_role";



GRANT ALL ON TABLE "public"."courses" TO "anon";
GRANT ALL ON TABLE "public"."courses" TO "authenticated";
GRANT ALL ON TABLE "public"."courses" TO "service_role";



GRANT ALL ON TABLE "public"."group_members" TO "anon";
GRANT ALL ON TABLE "public"."group_members" TO "authenticated";
GRANT ALL ON TABLE "public"."group_members" TO "service_role";



GRANT ALL ON TABLE "public"."holes" TO "anon";
GRANT ALL ON TABLE "public"."holes" TO "authenticated";
GRANT ALL ON TABLE "public"."holes" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."round_players" TO "anon";
GRANT ALL ON TABLE "public"."round_players" TO "authenticated";
GRANT ALL ON TABLE "public"."round_players" TO "service_role";



GRANT ALL ON TABLE "public"."rounds" TO "anon";
GRANT ALL ON TABLE "public"."rounds" TO "authenticated";
GRANT ALL ON TABLE "public"."rounds" TO "service_role";



GRANT ALL ON TABLE "public"."scores" TO "anon";
GRANT ALL ON TABLE "public"."scores" TO "authenticated";
GRANT ALL ON TABLE "public"."scores" TO "service_role";



GRANT ALL ON TABLE "public"."skins_groups" TO "anon";
GRANT ALL ON TABLE "public"."skins_groups" TO "authenticated";
GRANT ALL ON TABLE "public"."skins_groups" TO "service_role";



GRANT ALL ON TABLE "public"."tee_boxes" TO "anon";
GRANT ALL ON TABLE "public"."tee_boxes" TO "authenticated";
GRANT ALL ON TABLE "public"."tee_boxes" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";








-- ====================================================================
-- Auth-schema trigger we own (originally from 20260322000000_complete_base_schema.sql)
-- ====================================================================
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
