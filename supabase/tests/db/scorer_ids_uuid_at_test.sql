-- ============================================================================
-- Server-side tests: scorer_ids_uuid_at helper
-- ============================================================================
-- Covers the helper introduced in 20260513000000_scorer_ids_uuid_format.sql:
--   - public.scorer_ids_uuid_at(jsonb, int) -> uuid
--
-- USAGE:
--   Paste this whole file into Supabase Studio → SQL Editor and run.
--   No fixtures inserted (function is IMMUTABLE and pure). Run on both
--   dev (gbhljwtbobbxervekxkg) and prod (seeitehizboxjbnccnyd) — expect
--   identical results since the function body is identical.
-- ============================================================================

WITH results AS (
    -- Returns UUID for valid uuid-string entry at index 0
    SELECT 1 AS test_id,
           'returns UUID for valid uuid-string entry at index 0' AS name,
           CASE WHEN public.scorer_ids_uuid_at(
                  '["11111111-1111-1111-1111-111111111111"]'::jsonb, 0)
                  = '11111111-1111-1111-1111-111111111111'::uuid
                THEN 'PASS' ELSE 'FAIL' END AS result
    UNION ALL
    SELECT 2,
           'returns UUID at non-zero index when array has multiple uuids',
           CASE WHEN public.scorer_ids_uuid_at(
                  '["11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"]'::jsonb, 1)
                  = '22222222-2222-2222-2222-222222222222'::uuid
                THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 3,
           'returns NULL for legacy integer entry',
           CASE WHEN public.scorer_ids_uuid_at('[42]'::jsonb, 0) IS NULL
                THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 4,
           'returns NULL for explicit null jsonb element',
           CASE WHEN public.scorer_ids_uuid_at('[null]'::jsonb, 0) IS NULL
                THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 5,
           'returns NULL when input ids is null',
           CASE WHEN public.scorer_ids_uuid_at(NULL::jsonb, 0) IS NULL
                THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 6,
           'returns NULL when input is not an array',
           CASE WHEN public.scorer_ids_uuid_at('"not-an-array"'::jsonb, 0) IS NULL
                THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 7,
           'returns NULL for index out of bounds (positive)',
           CASE WHEN public.scorer_ids_uuid_at(
                  '["11111111-1111-1111-1111-111111111111"]'::jsonb, 5) IS NULL
                THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 8,
           'returns NULL for invalid uuid string',
           CASE WHEN public.scorer_ids_uuid_at('["not-a-uuid"]'::jsonb, 0) IS NULL
                THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 9,
           'mixed array — int at 0 returns NULL, uuid at 1 returns the uuid',
           CASE WHEN public.scorer_ids_uuid_at(
                  '[42, "33333333-3333-3333-3333-333333333333"]'::jsonb, 0) IS NULL
                 AND public.scorer_ids_uuid_at(
                  '[42, "33333333-3333-3333-3333-333333333333"]'::jsonb, 1)
                       = '33333333-3333-3333-3333-333333333333'::uuid
                THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 10,
           'returns NULL for empty array',
           CASE WHEN public.scorer_ids_uuid_at('[]'::jsonb, 0) IS NULL
                THEN 'PASS' ELSE 'FAIL' END
)
SELECT test_id, name, result FROM results ORDER BY test_id;
