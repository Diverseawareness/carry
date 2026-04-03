-- Migration: Guest profile conversion RPCs
-- Supports Quick Game → Group conversion and guest profile claiming

-- RPC 1: Convert a Quick Game to a recurring group
-- Flips is_quick_game, sets group name, marks guest members as 'invited' (pending)
CREATE OR REPLACE FUNCTION public.convert_quick_game_to_group(
    p_group_id uuid,
    p_group_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Update the group
    UPDATE skins_groups
    SET is_quick_game = false,
        name = COALESCE(p_group_name, name)
    WHERE id = p_group_id;

    -- Mark all non-creator members as 'invited' so they show as pending
    -- This includes both guest profiles AND real Carry users who were scorers
    UPDATE group_members
    SET status = 'invited'
    WHERE group_id = p_group_id
      AND role != 'creator';
END;
$$;

-- RPC 2: Claim a guest profile (merge guest data into real user)
-- Migrates scores, round_players, and group membership from guest → real user
CREATE OR REPLACE FUNCTION public.claim_guest_profile(
    p_guest_id uuid,
    p_real_id uuid,
    p_group_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- 1. Migrate scores: update player_id from guest to real user
    --    Skip rows where real user already has a score for same (round_id, hole_num)
    UPDATE scores s
    SET player_id = p_real_id
    WHERE s.player_id = p_guest_id
      AND NOT EXISTS (
          SELECT 1 FROM scores s2
          WHERE s2.round_id = s.round_id
            AND s2.hole_num = s.hole_num
            AND s2.player_id = p_real_id
      );

    -- Delete any remaining guest score rows (duplicates that couldn't be migrated)
    DELETE FROM scores WHERE player_id = p_guest_id;

    -- 2. Migrate round_players: update player_id from guest to real user
    --    Skip rows where real user is already in that round
    UPDATE round_players rp
    SET player_id = p_real_id
    WHERE rp.player_id = p_guest_id
      AND NOT EXISTS (
          SELECT 1 FROM round_players rp2
          WHERE rp2.round_id = rp.round_id
            AND rp2.player_id = p_real_id
      );

    -- Delete any remaining guest round_player rows
    DELETE FROM round_players WHERE player_id = p_guest_id;

    -- 3. Group membership: delete guest row, activate real user's row
    DELETE FROM group_members
    WHERE group_id = p_group_id AND player_id = p_guest_id;

    -- If real user already has a membership row (from invite link), activate it
    UPDATE group_members
    SET status = 'active'
    WHERE group_id = p_group_id AND player_id = p_real_id;

    -- If real user has no membership row, create one
    INSERT INTO group_members (group_id, player_id, role, status)
    SELECT p_group_id, p_real_id, 'member', 'active'
    WHERE NOT EXISTS (
        SELECT 1 FROM group_members
        WHERE group_id = p_group_id AND player_id = p_real_id
    );

    -- 4. Mark guest profile as claimed
    UPDATE profiles
    SET is_guest = false, created_by = NULL
    WHERE id = p_guest_id;
END;
$$;
