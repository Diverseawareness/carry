-- 20260530000000_guest_profiles_client_supplied_uuid.sql
--
-- Stable-UUID architecture for Quick Game guests (1.1.2)
-- ======================================================
-- Adds an OPTIONAL `p_ids uuid[]` parameter to `create_guest_profiles`.
-- When supplied, the server uses THOSE UUIDs in the INSERT instead of
-- minting fresh ones via gen_random_uuid().
--
-- WHY: a guest's UUID was previously chosen by the server on every call.
-- Combined with the ephemeral-guest rule (delete_quick_game_guests wipes
-- profiles on round termination AND on deleteRound — see RoundService),
-- every restart re-minted guest UUIDs. iOS Player.profileId in local state
-- still held the OLD UUID, so the next refresh saw the SAME human with two
-- different UUIDs → duplicate guest pills + "vanishing guest" scorecard
-- regressions in 1.1.x. By letting the CLIENT supply the UUID, the same
-- guest reuses the same UUID across re-creation → identity stays stable.
--
-- BACK-COMPAT: existing callers that don't pass p_ids fall through to the
-- gen_random_uuid() path. No change to any current behavior.
--
-- ON CONFLICT (id) DO NOTHING: defense against the race where two iOS calls
-- supply the SAME UUID concurrently (or a prior wipe hasn't replicated). The
-- profile already exists with the right id → we just return it. Order
-- preserved via the `ordinality` join so the returned array matches the
-- caller's input order even when some rows already existed.
--
-- Lifecycle invariants untouched:
--   - is_guest = true still set
--   - created_by still set
--   - delete_quick_game_guests still wipes by round_id (unchanged)
--   - ephemeral-guest rule still applies (locked migration 20260501000001)
--
-- Apply order: dev first, prod later (per Daniel — 2026-05-30).

CREATE OR REPLACE FUNCTION create_guest_profiles(
  p_names text[],
  p_initials text[],
  p_handicaps double precision[],
  p_colors text[],
  p_creator_id uuid DEFAULT NULL,
  p_ids uuid[] DEFAULT NULL    -- 1.1.2: optional client-supplied UUIDs
) RETURNS uuid[] LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  result uuid[] := '{}';
  new_id uuid;
  use_id uuid;
  i int;
BEGIN
  -- Loop preserves caller-input order (the iOS side aligns names[i] with the
  -- returned UUIDs[i]). Using `array_length` instead of `unnest` because each
  -- iteration may resolve to a different id source (supplied vs minted).
  FOR i IN 1..array_length(p_names, 1) LOOP
    -- Pick the id: supplied if present, else mint fresh.
    IF p_ids IS NOT NULL AND array_length(p_ids, 1) >= i AND p_ids[i] IS NOT NULL THEN
      use_id := p_ids[i];
    ELSE
      use_id := gen_random_uuid();
    END IF;

    -- ON CONFLICT (id) DO NOTHING handles the race where the SAME client UUID
    -- arrives twice (concurrent calls during a restart-then-create cycle).
    -- The pre-existing row is the right one; we just want to return its id.
    -- We capture the id via RETURNING; if the INSERT was skipped (conflict),
    -- new_id is NULL and we use use_id directly (it's the id of the existing
    -- row by construction).
    INSERT INTO profiles (
      id, display_name, initials, color, avatar,
      handicap, is_guest, created_by, created_at, updated_at
    )
    VALUES (
      use_id,
      p_names[i],
      p_initials[i],
      p_colors[i],
      '🏌️',
      coalesce(p_handicaps[i], 0.0),
      true,
      p_creator_id,
      now(),
      now()
    )
    ON CONFLICT (id) DO NOTHING
    RETURNING id INTO new_id;

    -- new_id is NULL when the row already existed; the caller's intended id
    -- still applies. Either way append the resolved id to the result array.
    result := result || coalesce(new_id, use_id);
  END LOOP;

  RETURN result;
END; $$;

NOTIFY pgrst, 'reload schema';
