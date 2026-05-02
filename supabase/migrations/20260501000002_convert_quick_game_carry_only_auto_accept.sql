-- ============================================================================
-- Migration: Quick Game → Group conversion = Carry-only + auto-accept
-- Date:      2026-05-01
-- ============================================================================
-- New architectural rules (locked 2026-05-01, see memory/quick_game_guest_lifecycle.md):
--
--   * Skins Groups are Carry-only. Guests never appear in a Skins Group's
--     group_members table. On conversion, guests get wiped (their profiles
--     deleted, history denormalized via the standard wipe RPC).
--
--   * Carry users who were `active` in the Quick Game stay `active` in the
--     new Skins Group. No demotion to `invited`. No invite UX. They were
--     already opted-in by playing — re-asking them for a separate "accept"
--     was the cold UX disconnect we're closing.
--
-- This migration updates `convert_quick_game_to_group` to enforce both rules.
-- The previous version (20260330000000) flipped EVERY non-creator member to
-- 'invited' — that's the behavior we're replacing.
--
-- Pre-req: 20260501000001 must already be applied (creates delete_quick_game_guests).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.convert_quick_game_to_group(
    p_group_id uuid,
    p_group_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _round_id uuid;
BEGIN
    -- Authorization: only the group creator can convert.
    IF NOT EXISTS (
        SELECT 1 FROM skins_groups
        WHERE id = p_group_id AND created_by = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Not authorized — only the group creator can convert group %', p_group_id;
    END IF;

    -- Find the most recent round in this group, whatever its status. The
    -- iOS Create-Group button flips status to 'completed' before invoking
    -- this RPC, so a status filter would miss it. The wipe RPC's own auth
    -- check (round.created_by = auth.uid()) keeps this from being a vector
    -- to wipe arbitrary other-creators' rounds.
    SELECT id INTO _round_id
    FROM rounds
    WHERE group_id = p_group_id
    ORDER BY created_at DESC
    LIMIT 1;

    -- Wipe guest profiles for this round before flipping the group. The wipe
    -- denormalizes display_name + handicap onto round_players + scores so
    -- Round History keeps showing each guest by name. Cascades clean the
    -- guest's group_members row entirely (Skins Groups are Carry-only by rule).
    --
    -- If there's no eligible round (edge case: convert called on a fresh
    -- group with no rounds), skip the wipe — nothing to do.
    IF _round_id IS NOT NULL THEN
        PERFORM public.delete_quick_game_guests(_round_id);
    END IF;

    -- Flip the group: not a Quick Game anymore, optionally rename.
    UPDATE skins_groups
    SET is_quick_game = false,
        name = COALESCE(p_group_name, name)
    WHERE id = p_group_id;

    -- Carry users who were `active` STAY active — no demotion. The previous
    -- migration (20260330000000) used `UPDATE group_members SET status='invited'`
    -- here; that was the cold "You're Invited!" disconnect. Removed entirely.
    --
    -- Note: any group_members rows that were 'invited' or 'declined' before
    -- conversion are intentionally left alone — those represent Carry users
    -- the creator invited but never accepted, separate from the conversion
    -- itself.
END;
$$;

NOTIFY pgrst, 'reload schema';
