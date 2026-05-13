-- ============================================================================
-- Server-side tests: scorer_ids reconciliation extension
-- ============================================================================
-- Covers the helper + trigger extensions introduced in
-- 20260513000001_reconcile_extends_scorer_ids.sql:
--   - public._reconcile_scorer_ids(p_group_id, p_old_id, p_new_id)
--   - reconcile_phone_invites_for_profile (forward) — extended
--   - reconcile_phone_invite_at_insert (reverse) — extended
--
-- USAGE:
--   Paste this whole file into Supabase Studio → SQL Editor and run.
--   Whole script wraps in BEGIN…ROLLBACK so test fixtures (a temporary
--   skins_groups row + its members + a temporary auth.users / profile)
--   are reverted at the end. Production data is NOT touched.
--
--   Run on dev (gbhljwtbobbxervekxkg) — prod has zero SMS-invite usage
--   per the 2026-05-12 audit, so trigger extensions can't regress
--   anything on prod, but tests on dev confirm the rewrites work.
-- ============================================================================

BEGIN;

-- ─── Fixture UUIDs (deterministic so assertions can compare) ──────────────
DO $$
DECLARE
    _creator_uuid uuid := '00000000-0000-0000-0000-000000000c01';
    _invitee_uuid uuid := '00000000-0000-0000-0000-000000000c02';
    _group_uuid   uuid := '00000000-0000-0000-0000-000000000010';
    _membership_uuid uuid := '00000000-0000-0000-0000-000000000020';
    _existing_member_uuid uuid := '00000000-0000-0000-0000-000000000030';
BEGIN
    -- Stash for later steps via temp table
    CREATE TEMP TABLE _test_uuids (k text PRIMARY KEY, v uuid) ON COMMIT DROP;
    INSERT INTO _test_uuids VALUES
        ('creator', _creator_uuid),
        ('invitee', _invitee_uuid),
        ('group',   _group_uuid),
        ('membership', _membership_uuid),
        ('existing_member', _existing_member_uuid);

    -- Fixture: creator profile (the inviter; placeholder member.player_id)
    INSERT INTO public.profiles (id, first_name, last_name, display_name, color, avatar)
    VALUES (_creator_uuid, 'Creator', 'Test', 'Creator Test', '#000000', '👤');

    -- Fixture: invitee profile (will be the reconciled scorer). Phone NOT
    -- yet set — we'll set it later to fire the forward trigger.
    INSERT INTO public.profiles (id, first_name, last_name, display_name, color, avatar)
    VALUES (_invitee_uuid, 'Invitee', 'Test', 'Invitee Test', '#000000', '👤');

    -- Fixture: skins_groups row with scorer_ids containing the placeholder
    -- membership UUID at index 1 (Group 2 scorer slot).
    INSERT INTO public.skins_groups (id, name, created_by, is_quick_game, scorer_ids)
    VALUES (
        _group_uuid,
        'Test SMS Reconcile',
        _creator_uuid,
        true,
        ('[42, "' || _membership_uuid::text || '"]')::jsonb
    );

    -- Fixture: existing pending phone-invite row at the placeholder id.
    INSERT INTO public.group_members (id, group_id, player_id, role, status, invited_phone, group_num)
    VALUES (
        _membership_uuid,
        _group_uuid,
        _creator_uuid,    -- placeholder until reconciliation
        'member',
        'invited',
        '5551234567',
        2
    );
END $$;

-- ─── Test the helper directly ─────────────────────────────────────────────

WITH _u AS (SELECT v FROM _test_uuids WHERE k = 'group'),
     _m AS (SELECT v FROM _test_uuids WHERE k = 'membership'),
     _i AS (SELECT v FROM _test_uuids WHERE k = 'invitee'),
     _do AS (
        SELECT public._reconcile_scorer_ids((SELECT v FROM _u), (SELECT v FROM _m), (SELECT v FROM _i))
     ),
     _after AS (
        SELECT scorer_ids FROM public.skins_groups WHERE id = (SELECT v FROM _u)
     )
SELECT
    'helper rewrites placeholder UUID to invitee UUID at index 1' AS test_name,
    CASE WHEN public.scorer_ids_uuid_at((SELECT scorer_ids FROM _after), 1) = (SELECT v FROM _i)
         THEN 'PASS' ELSE 'FAIL' END AS result,
    (SELECT scorer_ids::text FROM _after) AS actual_scorer_ids;

-- ─── Test legacy [Int] preservation (index 0 was 42) ──────────────────────

SELECT
    'helper preserves legacy int entry at index 0 (still 42)' AS test_name,
    CASE WHEN (scorer_ids->0)::text = '42' THEN 'PASS' ELSE 'FAIL' END AS result,
    (scorer_ids->0)::text AS actual_index_0
FROM public.skins_groups
WHERE id = (SELECT v FROM _test_uuids WHERE k = 'group');

-- ─── Test forward trigger end-to-end ──────────────────────────────────────
-- Reset scorer_ids back to the placeholder, then fire the trigger by
-- setting the invitee's phone. The trigger should rewrite scorer_ids
-- automatically.

UPDATE public.skins_groups
SET scorer_ids = ('[42, "' || (SELECT v FROM _test_uuids WHERE k = 'membership')::text || '"]')::jsonb
WHERE id = (SELECT v FROM _test_uuids WHERE k = 'group');

-- Reset the membership row back to invited+phone in case the previous
-- helper test or other state altered it.
UPDATE public.group_members
SET player_id = (SELECT v FROM _test_uuids WHERE k = 'creator'),
    invited_phone = '5551234567',
    status = 'invited'
WHERE id = (SELECT v FROM _test_uuids WHERE k = 'membership');

-- Fire the forward trigger by setting phone on the invitee profile.
UPDATE public.profiles
SET phone = '5551234567'
WHERE id = (SELECT v FROM _test_uuids WHERE k = 'invitee');

SELECT
    'forward trigger: scorer_ids index 1 rewritten to invitee profile UUID' AS test_name,
    CASE WHEN public.scorer_ids_uuid_at(scorer_ids, 1) = (SELECT v FROM _test_uuids WHERE k = 'invitee')
         THEN 'PASS' ELSE 'FAIL' END AS result,
    scorer_ids::text AS actual_scorer_ids
FROM public.skins_groups
WHERE id = (SELECT v FROM _test_uuids WHERE k = 'group');

SELECT
    'forward trigger: group_members.player_id updated to invitee + status active' AS test_name,
    CASE WHEN player_id = (SELECT v FROM _test_uuids WHERE k = 'invitee')
              AND status = 'active'
              AND (invited_phone IS NULL OR invited_phone = '')
         THEN 'PASS' ELSE 'FAIL' END AS result,
    'player_id=' || player_id::text || ' status=' || status AS actual
FROM public.group_members
WHERE id = (SELECT v FROM _test_uuids WHERE k = 'membership');

-- ─── Cleanup ──────────────────────────────────────────────────────────────

ROLLBACK;
