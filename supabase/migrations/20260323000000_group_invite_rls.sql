-- ============================================================
-- Migration: Group invite RLS policies
-- Allows invited users to see their own invites and the groups
-- they're invited to
-- ============================================================

-- 1. Allow invited users to see their own group_members rows
--    Current policy only lets active members read group_members.
--    We need invited users to see their own row.
CREATE POLICY "Users can see own membership rows"
  ON group_members FOR SELECT
  USING (player_id = auth.uid());

-- 2. Allow invited users to see the group they're invited to
--    Current policy on skins_groups only shows groups where user is active.
CREATE POLICY "Invited users can see invited groups"
  ON skins_groups FOR SELECT
  USING (
    id IN (
      SELECT group_id FROM group_members
      WHERE player_id = auth.uid() AND status = 'invited'
    )
    OR created_by = auth.uid()
  );

-- 3. Add index for invited member lookups
CREATE INDEX IF NOT EXISTS idx_group_members_invited
  ON group_members(player_id) WHERE status = 'invited';
