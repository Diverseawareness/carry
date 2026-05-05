-- Migration: Enforce one membership row per (group_id, player_id) for
-- non-phone invites.
--
-- Why: production logs from the send-push-notification edge function
-- show duplicate INSERT INTO group_members succeeding for the same
-- (group_id, player_id), causing 2-3× duplicate "You're Invited!"
-- pushes per single user-invite action. The original unique constraint
-- declared in 20260320000000_skins_groups.sql either never made it to
-- prod or was dropped manually. This migration is defensive: it dedupes
-- existing rows, drops any older non-partial constraint, and adds a
-- partial unique index that correctly tolerates phone-invite rows
-- (where player_id is intentionally the inviter's UUID and the real
-- identifier is invited_phone).
--
-- Safe to re-run: every step is idempotent.

-- 1. Dedupe existing rows on the non-phone-invite subset. For each
--    (group_id, player_id) we keep one row — preferring active >
--    invited > declined > removed, then oldest joined_at, then lowest
--    id (deterministic tiebreak). All other duplicates are deleted.
WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY group_id, player_id
           ORDER BY
             CASE status
               WHEN 'active'   THEN 1
               WHEN 'invited'  THEN 2
               WHEN 'declined' THEN 3
               WHEN 'removed'  THEN 4
               ELSE 5
             END,
             COALESCE(joined_at, NOW()) ASC,
             id::text ASC
         ) AS rn
  FROM public.group_members
  WHERE invited_phone IS NULL OR invited_phone = ''
)
DELETE FROM public.group_members
WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

-- 2. Drop the original full-table unique constraint if it survived in
--    prod. The partial index in step 3 supersedes it and is more
--    correct: phone invites can legitimately share (group_id, player_id)
--    when one inviter sends multiple SMS invites to different numbers
--    (player_id = inviter UUID for all such rows).
ALTER TABLE public.group_members
  DROP CONSTRAINT IF EXISTS group_members_group_id_player_id_key;

-- 3. Partial unique index: one row per (group_id, player_id) where the
--    row represents a real Carry-user membership (no phone placeholder).
CREATE UNIQUE INDEX IF NOT EXISTS group_members_unique_real_player
  ON public.group_members (group_id, player_id)
  WHERE invited_phone IS NULL OR invited_phone = '';

-- 4. Notify PostgREST so the schema cache picks up the new index.
NOTIFY pgrst, 'reload schema';
