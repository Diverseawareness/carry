-- ============================================================================
-- 20260518000001_clear_current_user_password.sql
-- ============================================================================
-- Auth-v2 Email disconnect: clears `encrypted_password` on auth.users for the
-- calling user, so the SIGN-IN METHODS Email row's Disconnect action has
-- something to actually do.
--
-- Why an RPC: `auth.users.encrypted_password` is not writable from the client
-- role. Supabase exposes `client.auth.unlinkIdentity(...)` for OAuth
-- providers (apple/google), but not for the password field — because for
-- normal email-signup users the password is the only auth method, so unlink
-- would be a foot-gun. We bypass that with a SECURITY DEFINER function and
-- guard against the foot-gun explicitly: refuse to clear the password if no
-- OAuth identity rows exist (i.e., the user would be left with zero
-- sign-in methods).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.clear_current_user_password()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    caller_id uuid;
    oauth_count int;
BEGIN
    caller_id := auth.uid();
    IF caller_id IS NULL THEN
        RAISE EXCEPTION 'not_authenticated';
    END IF;

    -- Foot-gun guard: refuse if the user has no OAuth identities, because
    -- clearing the password would strand them with zero sign-in methods.
    SELECT count(*) INTO oauth_count
    FROM auth.identities
    WHERE user_id = caller_id;

    IF oauth_count = 0 THEN
        RAISE EXCEPTION 'last_sign_in_method'
            USING HINT = 'Connect Apple or Google sign-in before disconnecting your password.';
    END IF;

    UPDATE auth.users
    SET encrypted_password = NULL
    WHERE id = caller_id;

    RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.clear_current_user_password() TO authenticated;

COMMENT ON FUNCTION public.clear_current_user_password() IS
'Clears auth.users.encrypted_password for the calling user. Guards against leaving the user with zero sign-in methods. Used by the iOS Email row Disconnect action.';
