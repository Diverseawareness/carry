-- ============================================================================
-- Phase 6 — Cleanup the broken 2026-05-01 12:20 Quick Game
-- Run AFTER:
--   * Phase 1 trigger fix is live and validated
--   * Phase 5 legacy guest purge has run (otherwise the 7 guest profiles
--     in this group will already be cleaned up by Phase 5 anyway — this
--     becomes a no-op for those rows, just deletes the skins_groups +
--     group_members shells)
--
-- Context (from active_quick_game_round_400_investigation.md):
--   On 2026-05-01 ~12:20 PT, Daniel created a Quick Game in TF 60 that hit
--   the notify_push() 42703 bug — POST /rest/v1/rounds returned 400 five
--   times. No `rounds` row materialized, but the `skins_groups` shell + 12
--   `group_members` rows DID get inserted. After the trigger fix landed,
--   that group is just dead data — no round, can't be played, takes up
--   space on the creator's Games tab.
--
-- This deletes it.
-- ============================================================================

BEGIN;

-- Sanity check: confirm we're targeting the right row.
SELECT id, name, created_by, created_at, is_quick_game
FROM public.skins_groups
WHERE id = '370df640-481a-4ea9-be06-69495b4db483';
-- Expect: 1 row, name='Fri, May 1', created_by='339fb48e-1d55-423e-ab5e-abdca6c8cf16'
-- (the Google test account leak — see auth-v2 quarantine notes).

-- Confirm no round_players reference this group's (non-existent) round.
-- (round_players cascades on rounds delete, so should always be empty here.)
SELECT count(*) AS rps_to_clean
FROM public.round_players rp
WHERE rp.round_id IN (
    SELECT id FROM public.rounds WHERE group_id = '370df640-481a-4ea9-be06-69495b4db483'
);
-- Expect: 0

DELETE FROM public.group_members
WHERE group_id = '370df640-481a-4ea9-be06-69495b4db483';

DELETE FROM public.skins_groups
WHERE id = '370df640-481a-4ea9-be06-69495b4db483';

-- Verify clean.
SELECT count(*) FROM public.skins_groups
WHERE id = '370df640-481a-4ea9-be06-69495b4db483';
-- Expect: 0

-- COMMIT;
-- ROLLBACK;
--
-- Read the counts above first.
