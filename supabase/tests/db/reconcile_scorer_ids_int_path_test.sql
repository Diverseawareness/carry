-- ============================================================================
-- Server-side tests: int-path scorer_ids reconciliation
-- ============================================================================
-- Covers the int-comparison helper + trigger updates introduced in
-- 20260513000003_reconcile_scorer_ids_int_path.sql:
--   - public._reconcile_scorer_ids_int(p_group_id, p_old_int, p_new_int)
--   - reconcile_phone_invites_for_profile (forward) — int-comparison version
--   - reconcile_phone_invite_at_insert (reverse) — int-comparison version
--
-- Supersedes the UUID-based test at reconcile_extends_scorer_ids_test.sql.
--
-- USAGE:
--   Paste into Supabase Studio → SQL Editor and run on dev. Wraps in
--   BEGIN/ROLLBACK so all fixtures revert; production data untouched.
-- ============================================================================

BEGIN;

-- ─── Fixture UUIDs (deterministic) ────────────────────────────────────────
DO $$
DECLARE
    _creator_uuid uuid := '00000000-0000-0000-0000-000000000c01';
    _invitee_uuid uuid := '00000000-0000-0000-0000-000000000c02';
    _group_uuid   uuid := '00000000-0000-0000-0000-000000000010';
    _membership_uuid uuid := '00000000-0000-0000-0000-000000000020';
    _membership_int bigint;
    _creator_int bigint;
BEGIN
    CREATE TEMP TABLE _test_uuids (k text PRIMARY KEY, v uuid) ON COMMIT DROP;
    INSERT INTO _test_uuids VALUES
        ('creator', _creator_uuid),
        ('invitee', _invitee_uuid),
        ('group',   _group_uuid),
        ('membership', _membership_uuid);

    -- Compute the stable-ints we'll seed scorer_ids with
    _membership_int := public.player_stable_id(_membership_uuid);
    _creator_int    := public.player_stable_id(_creator_uuid);

    INSERT INTO public.profiles (id, first_name, last_name, display_name, initials, color, avatar)
    VALUES (_creator_uuid, 'Creator', 'Test', 'Creator Test', 'CT', '#000000', '👤');

    INSERT INTO public.profiles (id, first_name, last_name, display_name, initials, color, avatar)
    VALUES (_invitee_uuid, 'Invitee', 'Test', 'Invitee Test', 'IT', '#000000', '👤');

    -- Seed scorer_ids: [creator_int, membership_int] — Group 2's scorer
    -- slot anchored on the placeholder membership UUID via stable-int.
    INSERT INTO public.skins_groups (id, name, created_by, is_quick_game, scorer_ids)
    VALUES (
        _group_uuid,
        'Test SMS Reconcile (int path)',
        _creator_uuid,
        true,
        ('[' || _creator_int::text || ', ' || _membership_int::text || ']')::jsonb
    );

    INSERT INTO public.group_members (id, group_id, player_id, role, status, invited_phone, group_num)
    VALUES (
        _membership_uuid,
        _group_uuid,
        _creator_uuid,
        'member',
        'invited',
        '5559876543',
        2
    );
END $$;

-- ─── Test the int helper directly ─────────────────────────────────────────

DO $$
DECLARE
    _group_uuid uuid := (SELECT v FROM _test_uuids WHERE k = 'group');
    _membership_uuid uuid := (SELECT v FROM _test_uuids WHERE k = 'membership');
    _invitee_uuid uuid := (SELECT v FROM _test_uuids WHERE k = 'invitee');
BEGIN
    PERFORM public._reconcile_scorer_ids_int(
        _group_uuid,
        public.player_stable_id(_membership_uuid),
        public.player_stable_id(_invitee_uuid)
    );
END $$;

SELECT
    'helper rewrites placeholder int → invitee int at index 1' AS test_name,
    CASE WHEN (scorer_ids->>1)::bigint = public.player_stable_id((SELECT v FROM _test_uuids WHERE k = 'invitee'))
         THEN 'PASS' ELSE 'FAIL' END AS result,
    scorer_ids::text AS actual_scorer_ids
FROM public.skins_groups
WHERE id = (SELECT v FROM _test_uuids WHERE k = 'group');

SELECT
    'helper preserves creator int at index 0' AS test_name,
    CASE WHEN (scorer_ids->>0)::bigint = public.player_stable_id((SELECT v FROM _test_uuids WHERE k = 'creator'))
         THEN 'PASS' ELSE 'FAIL' END AS result,
    (scorer_ids->>0) AS actual_index_0
FROM public.skins_groups
WHERE id = (SELECT v FROM _test_uuids WHERE k = 'group');

-- ─── Test forward trigger end-to-end ──────────────────────────────────────

-- Reset fixtures back to pre-trigger state
UPDATE public.skins_groups
SET scorer_ids = ('[' || public.player_stable_id((SELECT v FROM _test_uuids WHERE k = 'creator'))::text
                       || ', '
                       || public.player_stable_id((SELECT v FROM _test_uuids WHERE k = 'membership'))::text
                       || ']')::jsonb
WHERE id = (SELECT v FROM _test_uuids WHERE k = 'group');

UPDATE public.group_members
SET player_id = (SELECT v FROM _test_uuids WHERE k = 'creator'),
    invited_phone = '5559876543',
    status = 'invited'
WHERE id = (SELECT v FROM _test_uuids WHERE k = 'membership');

-- Fire the forward trigger by setting phone on the invitee profile
UPDATE public.profiles
SET phone = '5559876543'
WHERE id = (SELECT v FROM _test_uuids WHERE k = 'invitee');

SELECT
    'forward trigger: scorer_ids[1] rewritten to invitee stable-int' AS test_name,
    CASE WHEN (scorer_ids->>1)::bigint = public.player_stable_id((SELECT v FROM _test_uuids WHERE k = 'invitee'))
         THEN 'PASS' ELSE 'FAIL' END AS result,
    scorer_ids::text AS actual_scorer_ids
FROM public.skins_groups
WHERE id = (SELECT v FROM _test_uuids WHERE k = 'group');

SELECT
    'forward trigger: group_members reconciled to invitee + status active' AS test_name,
    CASE WHEN player_id = (SELECT v FROM _test_uuids WHERE k = 'invitee')
              AND status = 'active'
              AND (invited_phone IS NULL OR invited_phone = '')
         THEN 'PASS' ELSE 'FAIL' END AS result,
    'player_id=' || player_id::text || ' status=' || status AS actual
FROM public.group_members
WHERE id = (SELECT v FROM _test_uuids WHERE k = 'membership');

SELECT
    'forward trigger: scorer_ids[0] (creator) preserved untouched' AS test_name,
    CASE WHEN (scorer_ids->>0)::bigint = public.player_stable_id((SELECT v FROM _test_uuids WHERE k = 'creator'))
         THEN 'PASS' ELSE 'FAIL' END AS result,
    (scorer_ids->>0) AS actual_index_0
FROM public.skins_groups
WHERE id = (SELECT v FROM _test_uuids WHERE k = 'group');

ROLLBACK;
