-- ============================================================================
-- Server-side tests: player_stable_id helper
-- ============================================================================
-- Covers public.player_stable_id(uuid) introduced in
-- 20260513000002_player_stable_id_sql.sql.
--
-- IMPORTANT: the expected values below were computed by hand from the
-- Swift formula (Carry/Models/Player.swift:89-94). Any change to the
-- iOS Player.stableId(from:) implementation MUST be mirrored here AND
-- in the SQL function. The reconciliation triggers depend on iOS and
-- SQL producing identical ints for the same UUID.
--
-- USAGE: paste into Supabase Studio → SQL Editor and run. No fixtures
-- (function is IMMUTABLE / pure). Run on dev (gbhljwtbobbxervekxkg).
-- ============================================================================

WITH results AS (
    -- All-zero UUID → bytes a..h all 0 → raw = 0 → abs(0) = 0
    SELECT 1 AS test_id,
           'all-zero UUID returns 0' AS name,
           CASE WHEN public.player_stable_id('00000000-0000-0000-0000-000000000000'::uuid) = 0
                THEN 'PASS' ELSE 'FAIL' END AS result,
           public.player_stable_id('00000000-0000-0000-0000-000000000000'::uuid)::text AS actual

    UNION ALL
    -- UUID 01020304-0506-0708-... → bytes a=1,b=2,c=3,d=4,e=5,f=6,g=7,h=8
    -- a<<24 = 0x01000000 = 16777216
    -- b<<16 = 0x00020000 = 131072
    -- c<<8  = 0x00000300 = 768
    -- d     = 0x00000004 = 4
    -- e<<20 = 0x00500000 = 5242880
    -- f<<12 = 0x00006000 = 24576
    -- g<<4  = 0x00000070 = 112
    -- h     = 0x00000008 = 8
    -- No overlapping bits → OR = sum = 0x0152637C = 22176636
    SELECT 2,
           'UUID 01020304-0506-0708-... returns 22176636',
           CASE WHEN public.player_stable_id('01020304-0506-0708-0000-000000000000'::uuid) = 22176636
                THEN 'PASS' ELSE 'FAIL' END,
           public.player_stable_id('01020304-0506-0708-0000-000000000000'::uuid)::text

    UNION ALL
    -- All-0xff first 8 bytes → OR all → 0xFFFFFFFF = 4294967295
    SELECT 3,
           'UUID with first 8 bytes all 0xff returns 4294967295',
           CASE WHEN public.player_stable_id('ffffffff-ffff-ffff-0000-000000000000'::uuid) = 4294967295
                THEN 'PASS' ELSE 'FAIL' END,
           public.player_stable_id('ffffffff-ffff-ffff-0000-000000000000'::uuid)::text

    UNION ALL
    -- Bytes beyond byte 7 are ignored — verify two UUIDs differing only
    -- in bytes 8+ produce the SAME stable id.
    SELECT 4,
           'bytes beyond index 7 are ignored',
           CASE WHEN public.player_stable_id('01020304-0506-0708-aaaa-aaaaaaaaaaaa'::uuid)
                  = public.player_stable_id('01020304-0506-0708-bbbb-bbbbbbbbbbbb'::uuid)
                THEN 'PASS' ELSE 'FAIL' END,
           public.player_stable_id('01020304-0506-0708-aaaa-aaaaaaaaaaaa'::uuid)::text
              || ' vs ' ||
           public.player_stable_id('01020304-0506-0708-bbbb-bbbbbbbbbbbb'::uuid)::text

    UNION ALL
    -- Determinism: same UUID twice → same int.
    SELECT 5,
           'same UUID returns same int across calls (determinism)',
           CASE WHEN public.player_stable_id('11111111-1111-1111-1111-111111111111'::uuid)
                  = public.player_stable_id('11111111-1111-1111-1111-111111111111'::uuid)
                THEN 'PASS' ELSE 'FAIL' END,
           public.player_stable_id('11111111-1111-1111-1111-111111111111'::uuid)::text

    UNION ALL
    -- Different UUIDs differing in byte 0 → different stable ids
    -- (collision still possible due to OR-overlap, but trivial cases shouldn't).
    SELECT 6,
           'distinct UUIDs differing in byte 0 produce distinct ids',
           CASE WHEN public.player_stable_id('01000000-0000-0000-0000-000000000000'::uuid)
                  != public.player_stable_id('02000000-0000-0000-0000-000000000000'::uuid)
                THEN 'PASS' ELSE 'FAIL' END,
           public.player_stable_id('01000000-0000-0000-0000-000000000000'::uuid)::text
              || ' vs ' ||
           public.player_stable_id('02000000-0000-0000-0000-000000000000'::uuid)::text

    UNION ALL
    -- NULL input → NULL
    SELECT 7,
           'NULL UUID returns NULL',
           CASE WHEN public.player_stable_id(NULL) IS NULL
                THEN 'PASS' ELSE 'FAIL' END,
           coalesce(public.player_stable_id(NULL)::text, 'NULL')
)
SELECT test_id, name, result, actual FROM results ORDER BY test_id;
