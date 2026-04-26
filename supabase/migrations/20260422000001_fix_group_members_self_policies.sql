-- ============================================================
-- Migration: Restore self-action branches on group_members policies
-- Date: 2026-04-22
--
-- Problem:
-- ------
-- 20260422000000_holistic_rls_dedup.sql rewrote the group_members
-- INSERT / UPDATE / DELETE policies to use SECURITY DEFINER helpers, but
-- inadvertently dropped the `OR player_id = auth.uid()` branch that the
-- original 20260320 policies carried. Those branches let a user act on
-- their OWN membership row — required for:
--   - INSERT: users can add themselves (e.g. QR-scan auto-join via
--     `inviteMember` / `joinGroupViaInvite`)
--   - UPDATE: users can update their own status (e.g. `acceptGroupInvite`
--     flipping 'invited' → 'active', declining an invite)
--   - DELETE: users can remove themselves (self-leave flow in GroupsListView)
--
-- Without these branches, every one of the above silently fails because
-- the calls are wrapped in `try?`. That's why QR scans "did nothing" —
-- the insert was blocked by RLS.
--
-- Fix:
-- ---
-- Re-add the self-branch to each policy. Semantics match the pre-dedup
-- 20260320 baseline exactly.
-- ============================================================

DROP POLICY IF EXISTS "Creators can insert members" ON group_members;

CREATE POLICY "Creators can insert members"
  ON group_members FOR INSERT
  WITH CHECK (
    group_id IN (SELECT get_user_created_group_ids(auth.uid()))
    OR player_id = auth.uid()
  );

DROP POLICY IF EXISTS "Creators can update members" ON group_members;

CREATE POLICY "Creators can update members"
  ON group_members FOR UPDATE
  USING (
    group_id IN (SELECT get_user_created_group_ids(auth.uid()))
    OR player_id = auth.uid()
  );

DROP POLICY IF EXISTS "Creators can delete members" ON group_members;

CREATE POLICY "Creators can delete members"
  ON group_members FOR DELETE
  USING (
    group_id IN (SELECT get_user_created_group_ids(auth.uid()))
    OR player_id = auth.uid()
  );
