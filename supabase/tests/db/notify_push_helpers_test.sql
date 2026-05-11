-- ============================================================================
-- Server-side tests: push-trigger auth helpers
-- ============================================================================
-- Covers the helpers introduced in 20260509000000_notify_push_use_vault.sql:
--   - public._vault_secret_or_default(p_name, p_default)
--   - public._push_notification_url()
--   - public._push_notification_anon_key()
--
-- USAGE:
--   Paste this whole file into Supabase Studio → SQL Editor and run.
--   The whole script wraps in BEGIN…ROLLBACK so any test fixtures we insert
--   (Vault secrets) are reverted at the end — production secrets are NOT
--   touched. No CREATE TABLE — uses UNION ALL CTE so the Studio RLS-warning
--   dialog does not fire.
--
-- Run on both dev (gbhljwtbobbxervekxkg) and prod (seeitehizboxjbnccnyd) —
-- expect identical results since the function bodies are identical.
-- ============================================================================

BEGIN;

-- ─── Fixtures (rolled back at end) ─────────────────────────────────────────
-- Two scratch secrets the helper tests rely on. Names prefixed `pgtest_` so
-- they cannot collide with production keys.
SELECT vault.create_secret('test_value_alpha', 'pgtest_helper_secret_a');
SELECT vault.create_secret('', 'pgtest_helper_secret_empty');

-- ─── Run all assertions in one CTE, emit one row per test ──────────────────
WITH results AS (
    -- ─── _vault_secret_or_default ───────────────────────────────────────
    SELECT 1 AS test_id,
           '_vault_secret_or_default returns default when secret name unknown' AS name,
           CASE WHEN public._vault_secret_or_default('pgtest_nonexistent_key_42', 'fallback_xyz') = 'fallback_xyz'
                THEN 'PASS' ELSE 'FAIL' END AS result,
           public._vault_secret_or_default('pgtest_nonexistent_key_42', 'fallback_xyz')::text AS actual
    UNION ALL
    SELECT 2,
           '_vault_secret_or_default returns Vault value when secret exists',
           CASE WHEN public._vault_secret_or_default('pgtest_helper_secret_a', 'should_not_be_used') = 'test_value_alpha'
                THEN 'PASS' ELSE 'FAIL' END,
           public._vault_secret_or_default('pgtest_helper_secret_a', 'should_not_be_used')::text
    UNION ALL
    SELECT 3,
           '_vault_secret_or_default falls through when secret is empty string',
           CASE WHEN public._vault_secret_or_default('pgtest_helper_secret_empty', 'default_for_empty') = 'default_for_empty'
                THEN 'PASS' ELSE 'FAIL' END,
           public._vault_secret_or_default('pgtest_helper_secret_empty', 'default_for_empty')::text
    -- ─── _push_notification_url ─────────────────────────────────────────
    UNION ALL
    SELECT 4,
           '_push_notification_url returns a non-empty value',
           CASE WHEN length(public._push_notification_url()) > 0 THEN 'PASS' ELSE 'FAIL' END,
           ('len=' || length(public._push_notification_url())::text)
    UNION ALL
    SELECT 5,
           '_push_notification_url ends with /functions/v1/send-push-notification',
           CASE WHEN public._push_notification_url() LIKE '%/functions/v1/send-push-notification'
                THEN 'PASS' ELSE 'FAIL' END,
           public._push_notification_url()::text
    UNION ALL
    SELECT 6,
           '_push_notification_url uses HTTPS',
           CASE WHEN public._push_notification_url() LIKE 'https://%' THEN 'PASS' ELSE 'FAIL' END,
           public._push_notification_url()::text
    -- ─── _push_notification_anon_key ────────────────────────────────────
    UNION ALL
    SELECT 7,
           '_push_notification_anon_key returns a JWT-shaped string',
           CASE WHEN public._push_notification_anon_key() LIKE 'eyJ%'
                  AND length(public._push_notification_anon_key()) > 100
                THEN 'PASS' ELSE 'FAIL' END,
           ('len=' || length(public._push_notification_anon_key())::text
              || ', prefix=' || substring(public._push_notification_anon_key(), 1, 4))
    UNION ALL
    SELECT 8,
           '_push_notification_anon_key contains the current project ref in JWT payload',
           CASE WHEN encode(
                       decode(
                           translate(split_part(public._push_notification_anon_key(), '.', 2), '-_', '+/')
                             || repeat('=', (4 - length(split_part(public._push_notification_anon_key(), '.', 2)) % 4) % 4),
                           'base64'
                       ),
                       'escape'
                   ) ~ '"ref":"(seeitehizboxjbnccnyd|gbhljwtbobbxervekxkg)"'
                THEN 'PASS' ELSE 'FAIL' END,
           'JWT payload should contain "ref":"<project-ref>"'
    -- ─── helper-wiring regression on the 4 push-firing functions ────────
    UNION ALL
    SELECT 9,
           'notify_push uses _push_notification_url helper',
           CASE WHEN pg_get_functiondef('public.notify_push'::regproc) ~ '_push_notification_url\(\)' THEN 'PASS' ELSE 'FAIL' END,
           NULL::text
    UNION ALL
    SELECT 10,
           'notify_push uses _push_notification_anon_key helper',
           CASE WHEN pg_get_functiondef('public.notify_push'::regproc) ~ '_push_notification_anon_key\(\)' THEN 'PASS' ELSE 'FAIL' END,
           NULL::text
    UNION ALL
    SELECT 11,
           'send_handicap_reminders uses _push_notification_url helper',
           CASE WHEN pg_get_functiondef('public.send_handicap_reminders'::regproc) ~ '_push_notification_url\(\)' THEN 'PASS' ELSE 'FAIL' END,
           NULL::text
    UNION ALL
    SELECT 12,
           'send_handicap_reminders uses _push_notification_anon_key helper',
           CASE WHEN pg_get_functiondef('public.send_handicap_reminders'::regproc) ~ '_push_notification_anon_key\(\)' THEN 'PASS' ELSE 'FAIL' END,
           NULL::text
    UNION ALL
    SELECT 13,
           'reconcile_phone_invites_for_profile uses _push_notification_url helper',
           CASE WHEN pg_get_functiondef('public.reconcile_phone_invites_for_profile'::regproc) ~ '_push_notification_url\(\)' THEN 'PASS' ELSE 'FAIL' END,
           NULL::text
    UNION ALL
    SELECT 14,
           'reconcile_phone_invites_for_profile uses _push_notification_anon_key helper',
           CASE WHEN pg_get_functiondef('public.reconcile_phone_invites_for_profile'::regproc) ~ '_push_notification_anon_key\(\)' THEN 'PASS' ELSE 'FAIL' END,
           NULL::text
    UNION ALL
    SELECT 15,
           'reconcile_phone_invite_at_insert uses _push_notification_url helper',
           CASE WHEN pg_get_functiondef('public.reconcile_phone_invite_at_insert'::regproc) ~ '_push_notification_url\(\)' THEN 'PASS' ELSE 'FAIL' END,
           NULL::text
    UNION ALL
    SELECT 16,
           'reconcile_phone_invite_at_insert uses _push_notification_anon_key helper',
           CASE WHEN pg_get_functiondef('public.reconcile_phone_invite_at_insert'::regproc) ~ '_push_notification_anon_key\(\)' THEN 'PASS' ELSE 'FAIL' END,
           NULL::text
    -- ─── all 4 push-firing functions exist + are SECURITY DEFINER ───────
    UNION ALL
    SELECT 17,
           'all 4 push-firing functions exist and are SECURITY DEFINER',
           CASE WHEN (
                SELECT COUNT(*) FROM pg_proc
                WHERE proname IN (
                    'notify_push',
                    'send_handicap_reminders',
                    'reconcile_phone_invites_for_profile',
                    'reconcile_phone_invite_at_insert'
                )
                  AND prosecdef = true
                  AND pronamespace = 'public'::regnamespace
           ) = 4 THEN 'PASS' ELSE 'FAIL' END,
           ('count=' || (
                SELECT COUNT(*)::text FROM pg_proc
                WHERE proname IN (
                    'notify_push',
                    'send_handicap_reminders',
                    'reconcile_phone_invites_for_profile',
                    'reconcile_phone_invite_at_insert'
                )
                  AND prosecdef = true
                  AND pronamespace = 'public'::regnamespace
           ))
)
-- Show all results, FAIL rows on top
SELECT
    test_id,
    result,
    name,
    actual
FROM results
ORDER BY (result = 'PASS'), test_id;

-- Summary in a separate row at the end (Studio shows one result tab; the
-- final SELECT below appears as a second tab).
WITH results AS (
    SELECT CASE WHEN public._vault_secret_or_default('pgtest_nonexistent_key_42', 'fallback_xyz') = 'fallback_xyz' THEN 1 ELSE 0 END +
           CASE WHEN public._vault_secret_or_default('pgtest_helper_secret_a', 'should_not_be_used') = 'test_value_alpha' THEN 1 ELSE 0 END +
           CASE WHEN public._vault_secret_or_default('pgtest_helper_secret_empty', 'default_for_empty') = 'default_for_empty' THEN 1 ELSE 0 END +
           CASE WHEN length(public._push_notification_url()) > 0 THEN 1 ELSE 0 END +
           CASE WHEN public._push_notification_url() LIKE '%/functions/v1/send-push-notification' THEN 1 ELSE 0 END +
           CASE WHEN public._push_notification_url() LIKE 'https://%' THEN 1 ELSE 0 END +
           CASE WHEN public._push_notification_anon_key() LIKE 'eyJ%' AND length(public._push_notification_anon_key()) > 100 THEN 1 ELSE 0 END +
           CASE WHEN encode(decode(translate(split_part(public._push_notification_anon_key(), '.', 2), '-_', '+/') || repeat('=', (4 - length(split_part(public._push_notification_anon_key(), '.', 2)) % 4) % 4), 'base64'), 'escape') ~ '"ref":"(seeitehizboxjbnccnyd|gbhljwtbobbxervekxkg)"' THEN 1 ELSE 0 END +
           CASE WHEN pg_get_functiondef('public.notify_push'::regproc) ~ '_push_notification_url\(\)' THEN 1 ELSE 0 END +
           CASE WHEN pg_get_functiondef('public.notify_push'::regproc) ~ '_push_notification_anon_key\(\)' THEN 1 ELSE 0 END +
           CASE WHEN pg_get_functiondef('public.send_handicap_reminders'::regproc) ~ '_push_notification_url\(\)' THEN 1 ELSE 0 END +
           CASE WHEN pg_get_functiondef('public.send_handicap_reminders'::regproc) ~ '_push_notification_anon_key\(\)' THEN 1 ELSE 0 END +
           CASE WHEN pg_get_functiondef('public.reconcile_phone_invites_for_profile'::regproc) ~ '_push_notification_url\(\)' THEN 1 ELSE 0 END +
           CASE WHEN pg_get_functiondef('public.reconcile_phone_invites_for_profile'::regproc) ~ '_push_notification_anon_key\(\)' THEN 1 ELSE 0 END +
           CASE WHEN pg_get_functiondef('public.reconcile_phone_invite_at_insert'::regproc) ~ '_push_notification_url\(\)' THEN 1 ELSE 0 END +
           CASE WHEN pg_get_functiondef('public.reconcile_phone_invite_at_insert'::regproc) ~ '_push_notification_anon_key\(\)' THEN 1 ELSE 0 END +
           CASE WHEN (SELECT COUNT(*) FROM pg_proc WHERE proname IN ('notify_push','send_handicap_reminders','reconcile_phone_invites_for_profile','reconcile_phone_invite_at_insert') AND prosecdef = true AND pronamespace = 'public'::regnamespace) = 4 THEN 1 ELSE 0 END
           AS passing
)
SELECT
    passing,
    17 - passing AS failing,
    17 AS total,
    CASE WHEN passing = 17 THEN 'ALL PASS' ELSE 'FAILURES — see results above' END AS status
FROM results;

ROLLBACK;
