-- prod-release-smoke-check.sql
--
-- PRE-RELEASE GATE — run against the LIVE Supabase project in the Studio SQL
-- editor BEFORE submitting / releasing any build that changed a migration or
-- an RPC call. Catches the failure class from the 1.1.2 create_guest_profiles
-- incident: dev passed, prod silently broke because prod's function signature
-- differed from what the shipping app calls (PostgREST resolves RPCs by exact
-- argument signature; a missing/extra/ambiguous overload → runtime failure for
-- live users, invisible until someone hits it on the course).
--
-- HOW TO USE:
--   1. Supabase Studio → select the LIVE project (ref: seeitehizboxjbnccnyd —
--      Carry/Ohio). NOT the dev project (gbhljwtbobbxervekxkg).
--   2. SQL editor → paste this whole file → Run.
--   3. Read the `verdict` column. EVERY row must say PASS.
--      Any FAIL row spells out the problem + the fix. Do not release on a FAIL.
--
-- WHY MANUAL (not an automated script): migrations here are applied by hand in
-- Studio (db push is blocked by squash drift), and no prod service-role key
-- exists locally — by design (a service-role key bypasses RLS; keeping it off
-- the dev machine is a security win). So the check lives where the work already
-- happens. It is SELF-VERDICTING (returns the literal word PASS/FAIL) so there's
-- nothing to misread — that "eyeball the catalog rows" step is exactly how the
-- 1.1.2 incident slipped.
--
-- MAINTENANCE: when a migration adds/changes an RPC the app calls by name, add
-- a row here. The full set the app calls (grep '\.rpc("' in Carry/):
--   clear_current_user_password, convert_quick_game_to_group, create_guest_profiles,
--   create_phone_invite, current_user_has_password, delete_group, delete_user_account,
--   is_username_available, update_guest_profile

-- ─────────────────────────────────────────────────────────────────────────
-- CHECK 1: Every app-called RPC exists exactly once (no missing, no ambiguous
-- overload). An RPC present 0 times = app call 404s. Present 2+ times with
-- compatible signatures = "function is not unique" (SQLSTATE 42725) — the exact
-- 1.1.2 break. We assert each name resolves to a usable set.
-- ─────────────────────────────────────────────────────────────────────────
WITH expected(name) AS (
  VALUES
    ('clear_current_user_password'),
    ('convert_quick_game_to_group'),
    ('create_guest_profiles'),
    ('create_phone_invite'),
    ('current_user_has_password'),
    ('delete_group'),
    ('delete_user_account'),
    ('is_username_available'),
    ('update_guest_profile')
),
counts AS (
  SELECT e.name,
         (SELECT count(*) FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE p.proname = e.name AND n.nspname = 'public') AS n
  FROM expected e
)
SELECT
  name AS check_item,
  n    AS overload_count,
  CASE
    WHEN n = 0 THEN 'FAIL: RPC missing in prod — app calls will 404. Apply the migration that creates it.'
    WHEN n = 1 THEN 'PASS'
    ELSE 'FAIL: ' || n || ' overloads — app call may hit "function is not unique" (42725). DROP the stale signature(s); keep the one the app calls.'
  END AS verdict
FROM counts
ORDER BY (n <> 1) DESC, name;  -- FAILs float to the top

-- ─────────────────────────────────────────────────────────────────────────
-- CHECK 2: create_guest_profiles accepts the p_ids arg the SHIPPING app sends.
-- The 1.1.2 binary ALWAYS passes p_ids (stable-UUID architecture). If prod's
-- function lacks p_ids, guest creation breaks for every 1.1.2 user.
-- ─────────────────────────────────────────────────────────────────────────
SELECT
  'create_guest_profiles accepts p_ids' AS check_item,
  COALESCE((
    SELECT string_agg(pg_get_function_arguments(p.oid), ' || ')
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'create_guest_profiles' AND n.nspname = 'public'
  ), '(none)') AS signature,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'create_guest_profiles' AND n.nspname = 'public'
      AND pg_get_function_arguments(p.oid) LIKE '%p_ids%'
  ) THEN 'PASS' ELSE 'FAIL: prod create_guest_profiles has no p_ids arg — the shipping app passes it. Apply 20260530000000_guest_profiles_client_supplied_uuid.sql.' END AS verdict;

-- ─────────────────────────────────────────────────────────────────────────
-- CHECK 3 (LIVE RESOLUTION): actually call create_guest_profiles the way the
-- OLD binary does (5 args, no p_ids) inside a rolled-back transaction. If the
-- overloads are ambiguous, THIS is what throws 42725 in production. ROLLBACK
-- means nothing is written. Run this block on its own if your editor won't run
-- multi-statement scripts:
--
--   BEGIN;
--   SELECT create_guest_profiles(
--     p_names      := ARRAY['__smoke']::text[],
--     p_initials   := ARRAY['SM']::text[],
--     p_handicaps  := ARRAY[0.0]::double precision[],
--     p_colors     := ARRAY['#000000']::text[],
--     p_creator_id := NULL::uuid
--   );   -- expect: a {uuid} array, NOT "function ... is not unique"
--   ROLLBACK;
--
-- (Left as a comment so the main script stays pure SELECTs and never writes.
-- Run it manually as the final confidence step.)
