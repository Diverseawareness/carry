-- Fix infinite recursion in group_members RLS policies (error 42P17)
--
-- Root cause: The "Invited users can see invited groups" policy on skins_groups
-- queried group_members directly via inline subquery. When DELETE on group_members
-- triggered evaluation of skins_groups RLS, that policy queried group_members again,
-- which re-triggered group_members RLS, causing infinite recursion.
--
-- Fix: wrap the subquery in a SECURITY DEFINER helper function so it bypasses RLS.

-- 1. Create SECURITY DEFINER helper for invited group IDs
CREATE OR REPLACE FUNCTION get_user_invited_group_ids(uid uuid)
RETURNS SETOF uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT group_id FROM group_members
  WHERE player_id = uid AND status = 'invited';
$$;

-- 2. Drop the recursive policy
DROP POLICY IF EXISTS "Invited users can see invited groups" ON skins_groups;

-- 3. Recreate using the SECURITY DEFINER function
CREATE POLICY "Invited users can see invited groups" ON skins_groups
FOR SELECT
USING (id IN (SELECT get_user_invited_group_ids(auth.uid())));
