-- ============================================================
-- Migration: Holistic RLS dedup — fix recursion, cascade, and drift
-- Date: 2026-04-22
--
-- Problem:
-- ------
-- Several RLS policies reference RLS-protected tables inside inline
-- subqueries. Two of them (on `group_members` and `round_players`) are
-- *self-referential* — they query the same table they're protecting. Under
-- concurrent writes Postgres's RLS recursion short-circuit can return 0
-- rows from the inner subquery, causing the outer policy to deny reads.
-- Symptom: a member of a live round briefly sees only their own row and
-- none of the other players', so scorers vanish, scores stop sync'ing,
-- and "you were removed" alerts misfire on the client.
--
-- Migration 20260406 already fixed this pattern on `skins_groups` by
-- wrapping the offending subquery in a SECURITY DEFINER helper
-- (`get_user_invited_group_ids`). The *exact same class of bug* remained on
-- `group_members` and `round_players`, and every cross-table policy that
-- queries those two tables cascades through the gap.
--
-- Fix:
-- ---
-- 1. Introduce SECURITY DEFINER helpers for every "what can this user see"
--    lookup. SECURITY DEFINER means the inner query runs with the function
--    owner's privileges, bypassing RLS entirely. No recursion possible.
-- 2. Rewrite every SELECT/INSERT/UPDATE/DELETE policy that referenced an
--    RLS-protected table inline to instead call a helper. Semantics are
--    preserved exactly — no new access is granted, no access is removed.
-- 3. Consolidate the pattern so future policy changes have a single,
--    consistent API and can't reintroduce the recursion.
--
-- All DROP / CREATE pairs are idempotent (`IF EXISTS` / `OR REPLACE`) so
-- rerunning this migration is safe.
-- ============================================================

-- ---------------- HELPERS ----------------

-- Groups where the caller is currently an active member.
CREATE OR REPLACE FUNCTION get_user_active_group_ids(uid uuid)
RETURNS SETOF uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT group_id FROM group_members
  WHERE player_id = uid AND status = 'active';
$$;

-- Groups where the caller is a member in ANY non-removed state
-- (active or invited). Used for reads that should include pending invitees.
CREATE OR REPLACE FUNCTION get_user_member_group_ids(uid uuid)
RETURNS SETOF uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT group_id FROM group_members
  WHERE player_id = uid AND status IN ('active', 'invited');
$$;

-- Note: get_user_invited_group_ids(uuid) already exists from 20260406; reused as-is.

-- Groups the caller created. Cached on skins_groups.created_by, no
-- cross-table join. Helper exists for consistency + future-proofing.
CREATE OR REPLACE FUNCTION get_user_created_group_ids(uid uuid)
RETURNS SETOF uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM skins_groups WHERE created_by = uid;
$$;

-- Rounds where the caller is a player (from round_players).
CREATE OR REPLACE FUNCTION get_user_round_ids(uid uuid)
RETURNS SETOF uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT round_id FROM round_players WHERE player_id = uid;
$$;

-- Rounds the caller created.
CREATE OR REPLACE FUNCTION get_user_created_round_ids(uid uuid)
RETURNS SETOF uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM rounds WHERE created_by = uid;
$$;


-- ---------------- skins_groups ----------------

-- Was: queried group_members inline (works today but relies on
-- group_members RLS being healthy; swap for helper so the two tables'
-- policies are independent).
DROP POLICY IF EXISTS "Members can read their groups" ON skins_groups;

CREATE POLICY "Members can read their groups"
  ON skins_groups FOR SELECT
  USING (id IN (SELECT get_user_active_group_ids(auth.uid())));


-- ---------------- group_members ----------------

-- THE BUG. Self-referential subquery replaced with helper.
DROP POLICY IF EXISTS "Members can read group members" ON group_members;

CREATE POLICY "Members can read group members"
  ON group_members FOR SELECT
  USING (group_id IN (SELECT get_user_active_group_ids(auth.uid())));

-- INSERT/UPDATE/DELETE creator-gates: swap the inline skins_groups
-- subquery for the helper. Same semantics, no cross-table RLS dependency.
DROP POLICY IF EXISTS "Creators can insert members" ON group_members;

CREATE POLICY "Creators can insert members"
  ON group_members FOR INSERT
  WITH CHECK (group_id IN (SELECT get_user_created_group_ids(auth.uid())));

DROP POLICY IF EXISTS "Creators can update members" ON group_members;

CREATE POLICY "Creators can update members"
  ON group_members FOR UPDATE
  USING (group_id IN (SELECT get_user_created_group_ids(auth.uid())));

DROP POLICY IF EXISTS "Creators can delete members" ON group_members;

CREATE POLICY "Creators can delete members"
  ON group_members FOR DELETE
  USING (group_id IN (SELECT get_user_created_group_ids(auth.uid())));


-- ---------------- rounds ----------------

-- Was: inline round_players and group_members subqueries. Swap both.
DROP POLICY IF EXISTS "Round participants can read rounds" ON rounds;

CREATE POLICY "Round participants can read rounds"
  ON rounds FOR SELECT
  USING (
    created_by = auth.uid()
    OR id IN (SELECT get_user_round_ids(auth.uid()))
    OR (group_id IS NOT NULL AND group_id IN (SELECT get_user_active_group_ids(auth.uid())))
  );

DROP POLICY IF EXISTS "Users can delete their rounds" ON rounds;

CREATE POLICY "Users can delete their rounds"
  ON rounds FOR DELETE
  USING (
    created_by = auth.uid()
    OR id IN (SELECT get_user_round_ids(auth.uid()))
  );


-- ---------------- round_players ----------------

-- Self-referential subquery in the SELECT policy — same bug class as
-- group_members. Replace with helper.
DROP POLICY IF EXISTS "Players can view their own round_players rows" ON round_players;

CREATE POLICY "Players can view their own round_players rows"
  ON round_players FOR SELECT
  USING (
    player_id = auth.uid()
    OR round_id IN (SELECT get_user_round_ids(auth.uid()))
  );

-- INSERT uses an EXISTS over rounds — rounds has its own RLS now rewritten
-- above to use helpers, so this is safe. Still, swap to the helper for
-- uniformity.
DROP POLICY IF EXISTS "Round creators can invite players" ON round_players;

CREATE POLICY "Round creators can invite players"
  ON round_players FOR INSERT
  WITH CHECK (
    round_id IN (SELECT get_user_created_round_ids(auth.uid()))
    OR player_id = auth.uid()
  );


-- ---------------- scores ----------------

-- Reads/writes gated on round participation or round ownership.
DROP POLICY IF EXISTS "Round participants can read scores" ON scores;

CREATE POLICY "Round participants can read scores"
  ON scores FOR SELECT
  USING (
    round_id IN (SELECT get_user_round_ids(auth.uid()))
    OR round_id IN (SELECT get_user_created_round_ids(auth.uid()))
  );

DROP POLICY IF EXISTS "Round participants can insert scores" ON scores;

CREATE POLICY "Round participants can insert scores"
  ON scores FOR INSERT
  WITH CHECK (
    round_id IN (SELECT get_user_round_ids(auth.uid()))
    OR round_id IN (SELECT get_user_created_round_ids(auth.uid()))
  );

DROP POLICY IF EXISTS "Round participants can update scores" ON scores;

CREATE POLICY "Round participants can update scores"
  ON scores FOR UPDATE
  USING (
    round_id IN (SELECT get_user_round_ids(auth.uid()))
    OR round_id IN (SELECT get_user_created_round_ids(auth.uid()))
  );
