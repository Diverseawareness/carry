-- ============================================================================
-- Migration: Phone-invite finder + claim RPCs
-- Date:      2026-05-02
-- ============================================================================
-- Supports the post-onboarding "Did someone invite you?" modal in HomeView.
-- The user enters their phone number; iOS calls find_pending_invites_by_phone()
-- which returns any pending `group_members` rows where invited_phone matches.
-- If matches exist, the user confirms and iOS calls claim_phone_invite() per
-- match to reconcile the placeholder row to the real authenticated user.
--
-- Why two RPCs (not one query):
--   * find_pending_invites_by_phone is a SECURITY DEFINER lookup that bypasses
--     RLS. It returns ONLY the matched rows + minimal group metadata — never
--     leaks rows for OTHER phone numbers.
--   * claim_phone_invite verifies the caller's authenticated user_id and the
--     phone-match before mutating. Anti-impersonation: a user can't claim a
--     row they don't have the matching phone for, even if they know the row's
--     UUID.
--
-- Both functions are SECURITY DEFINER (run as the function owner — typically
-- `postgres` — and bypass RLS) but enforce their own checks via auth.uid().
-- ============================================================================

-- ─── 1. Lookup function ─────────────────────────────────────────────────────
-- Returns one row per pending phone invite for the given phone number. Each
-- row carries enough for the modal to render: membership id, group id, group
-- name, inviter name, when they were invited.
--
-- Returns ALL matches across ALL groups — a phone can be invited to multiple
-- groups by different creators. iOS shows them as a list and the user picks
-- which to claim (or claims all).

CREATE OR REPLACE FUNCTION public.find_pending_invites_by_phone(p_phone text)
RETURNS TABLE (
    membership_id uuid,
    group_id uuid,
    group_name text,
    invited_by_id uuid,
    invited_by_name text,
    is_quick_game boolean,
    invited_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _normalized_phone text;
BEGIN
    -- Caller must be authenticated. Anonymous lookups would let anyone fish
    -- for invites by phone number, which leaks group membership info.
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required to look up invites by phone';
    END IF;

    -- Normalize: strip everything that isn't a digit. iOS may send formatted
    -- like "(415) 555-1212" but the DB stores raw digits ("4155551212").
    _normalized_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');

    -- Reject suspiciously short numbers (less than 10 digits = not a real US
    -- phone). Avoids matching empty-string or partial inputs that would
    -- spuriously match other empty rows in the DB.
    IF length(_normalized_phone) < 10 THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        gm.id AS membership_id,
        sg.id AS group_id,
        sg.name AS group_name,
        sg.created_by AS invited_by_id,
        coalesce(p.display_name, 'A friend') AS invited_by_name,
        sg.is_quick_game,
        gm.joined_at AS invited_at
    FROM public.group_members gm
    JOIN public.skins_groups sg ON sg.id = gm.group_id
    LEFT JOIN public.profiles p ON p.id = sg.created_by
    WHERE gm.invited_phone = _normalized_phone
      AND gm.status = 'invited'
    ORDER BY gm.joined_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.find_pending_invites_by_phone(text) TO authenticated;

-- ─── 2. Claim function ──────────────────────────────────────────────────────
-- Reconciles a single pending invite to the authenticated user. Verifies
-- (a) the row exists, (b) it's still in 'invited' status, (c) the provided
-- phone matches what's on the row (anti-impersonation), then updates:
--   player_id     → auth.uid()
--   invited_phone → ''   (cleared so future searches don't re-match)
--   status        → 'active'
-- This mirrors the existing `inviteMemberByPhone` reconciliation logic in
-- GroupService.swift (line ~370) but driven by the invitee instead of by the
-- inviter's later add-member action.

CREATE OR REPLACE FUNCTION public.claim_phone_invite(p_membership_id uuid, p_phone text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _user_id uuid;
    _normalized_phone text;
    _row_phone text;
    _row_status text;
    _group_id uuid;
BEGIN
    _user_id := auth.uid();
    IF _user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required to claim an invite';
    END IF;

    _normalized_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
    IF length(_normalized_phone) < 10 THEN
        RAISE EXCEPTION 'Invalid phone number';
    END IF;

    -- Lock the row + verify match.
    SELECT invited_phone, status, group_id
      INTO _row_phone, _row_status, _group_id
    FROM public.group_members
    WHERE id = p_membership_id
    FOR UPDATE;

    IF _row_phone IS NULL THEN
        RAISE EXCEPTION 'Invite not found or already claimed';
    END IF;

    IF _row_status <> 'invited' THEN
        RAISE EXCEPTION 'Invite is no longer pending (status: %)', _row_status;
    END IF;

    IF _row_phone <> _normalized_phone THEN
        RAISE EXCEPTION 'Phone does not match this invite';
    END IF;

    -- Reconcile. Mirrors GroupService.inviteMemberByPhone post-claim logic.
    UPDATE public.group_members
    SET player_id = _user_id,
        invited_phone = '',
        status = 'active'
    WHERE id = p_membership_id;

    RETURN _group_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_phone_invite(uuid, text) TO authenticated;

-- ─── 3. Reload PostgREST schema cache ──────────────────────────────────────
NOTIFY pgrst, 'reload schema';
