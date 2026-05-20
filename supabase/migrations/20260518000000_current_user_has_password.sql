-- ============================================================================
-- 20260518000000_current_user_has_password.sql
-- ============================================================================
-- Auth-v2 UI signal: tell the iOS client whether the currently-authenticated
-- user has a password set on their auth.users row.
--
-- Why: Supabase's auth.update(password:nonce:) DOES persist
-- encrypted_password on an OAuth-only user, but does NOT add an `email` row
-- to auth.identities retroactively. So `client.auth.userIdentities()` keeps
-- returning ["apple", "google"] even after a successful email-link, and the
-- iOS Email row in SIGN-IN METHODS never flips to "Connected ✓".
--
-- The structural fix is to drive the Email row's connected state off
-- `encrypted_password IS NOT NULL`, not off the identities array. That field
-- lives in auth.users which is not readable from the client role, so we
-- expose it via a SECURITY DEFINER RPC that returns just the boolean for the
-- calling user.
--
-- The RPC returns false (not an error) when called without an authenticated
-- session, so the client can call it unconditionally on startup.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.current_user_has_password()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    caller_id uuid;
    has_pw boolean;
BEGIN
    caller_id := auth.uid();
    IF caller_id IS NULL THEN
        RETURN false;
    END IF;

    SELECT (encrypted_password IS NOT NULL AND encrypted_password <> '')
    INTO has_pw
    FROM auth.users
    WHERE id = caller_id;

    RETURN COALESCE(has_pw, false);
END;
$$;

GRANT EXECUTE ON FUNCTION public.current_user_has_password() TO authenticated;

COMMENT ON FUNCTION public.current_user_has_password() IS
'Returns true if the calling auth user has encrypted_password set. Used by the iOS Email row in SIGN-IN METHODS since Supabase does not add an email identity row retroactively for OAuth-linked passwords.';
