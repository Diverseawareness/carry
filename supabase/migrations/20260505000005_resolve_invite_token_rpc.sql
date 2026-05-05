-- Migration: resolve_invite_token RPC
--
-- Public RPC that takes an invite_token and returns the minimal info the
-- invitee onboarding flow needs BEFORE the user has authenticated:
--
--   - group name + creation date
--   - inviter (commissioner) display name + avatar
--   - invitee pre-fill: invited_name, invited_handicap, invited_phone
--   - next scheduled round date/tee_time (if any)
--
-- Scope is intentionally narrow: nothing about other members, no scores,
-- no financial details. Just enough for screens 01–03 of the invitee
-- onboarding flow.
--
-- SECURITY DEFINER because the caller is unauthenticated (anon role).

CREATE OR REPLACE FUNCTION public.resolve_invite_token(_token uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _result jsonb;
BEGIN
    SELECT jsonb_build_object(
        'group_id', sg.id,
        'group_name', sg.name,
        'inviter_name', inviter.display_name,
        'inviter_avatar_url', inviter.avatar_url,
        'invited_name', gm.invited_name,
        'invited_handicap', gm.invited_handicap,
        'invited_phone', gm.invited_phone,
        'status', gm.status,
        -- Earliest future tee time pulled from tee_times_json (a JSON array
        -- of ISO-8601 timestamp strings). NULL if no tee times scheduled.
        'next_tee_time', (
            SELECT MIN(tt::timestamptz)
            FROM jsonb_array_elements_text(
                COALESCE(sg.tee_times_json::jsonb, '[]'::jsonb)
            ) AS tt
            WHERE tt::timestamptz >= now()
        )
    )
    INTO _result
    FROM public.group_members gm
    JOIN public.skins_groups sg ON sg.id = gm.group_id
    LEFT JOIN public.profiles inviter ON inviter.id = sg.created_by
    WHERE gm.invite_token = _token
      AND gm.status = 'invited';

    RETURN _result;  -- nil if token not found or already accepted
END;
$$;

-- Allow anonymous (pre-auth) invokes — invitee hasn't signed in yet.
GRANT EXECUTE ON FUNCTION public.resolve_invite_token(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.resolve_invite_token(uuid) TO authenticated;

COMMENT ON FUNCTION public.resolve_invite_token IS
    'Public RPC: resolve invite_token to minimal group + pre-fill payload for invitee onboarding screens. Returns NULL if token not found or invite already accepted.';
