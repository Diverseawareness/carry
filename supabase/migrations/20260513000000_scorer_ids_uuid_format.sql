-- ============================================================================
-- 20260513000000_scorer_ids_uuid_format.sql
-- ============================================================================
-- Forward-compat helper for the SMS-invite-as-scorer reconciliation fix.
--
-- Today, skins_groups.scorer_ids stores a jsonb array of integers (the iOS
-- client-side Player.id stable hashes). That format has an identity-collision
-- bug for SMS-invited scorers: the slot writes a hash derived from a
-- transient slot UUID, while the server-built phone-invite Player gets a
-- hash derived from group_members.id — they never match, and the scorer
-- slot wipes on first refresh.
--
-- The fix anchors all SMS-invite-as-scorer slots on group_members.id (UUID)
-- and stores that UUID as a string element in scorer_ids alongside legacy
-- integers. This migration adds the read-side helper for the new format —
-- the reconciliation trigger update (next migration) and client refactor
-- (next branch increment) both depend on it.
--
-- No data rewrite. Existing [Int] rows remain valid; the helper returns NULL
-- for non-UUID elements so consumers fall back to the existing int-based
-- path.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.scorer_ids_uuid_at(ids jsonb, idx int)
RETURNS uuid
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    elem jsonb;
    s text;
BEGIN
    IF ids IS NULL OR jsonb_typeof(ids) != 'array' THEN
        RETURN NULL;
    END IF;
    elem := ids -> idx;
    IF elem IS NULL OR jsonb_typeof(elem) != 'string' THEN
        RETURN NULL;
    END IF;
    s := elem #>> '{}';
    BEGIN
        RETURN s::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
        RETURN NULL;
    END;
END;
$$;

COMMENT ON FUNCTION public.scorer_ids_uuid_at(jsonb, int) IS
    'Returns the UUID at scorer_ids[idx] for new UUID-shaped entries; NULL for legacy int entries, non-uuid strings, out-of-bounds indexes, null elements, or non-array input. Used by reconcile_phone_invites_for_profile to rewrite scorer_ids on signup, and by future SQL consumers that need to resolve placeholder/profile UUIDs.';
