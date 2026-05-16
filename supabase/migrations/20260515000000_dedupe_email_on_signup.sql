-- ============================================================================
-- 20260515000000_dedupe_email_on_signup.sql
-- ============================================================================
-- Auth-v2 quarantine gate #2: prevent duplicate auth.users rows for the same
-- human email across providers (Apple / Google / Email-password).
--
-- The 2026-05-01 prod incident root cause: signing in with Google when an
-- Apple-linked profile already existed for the same email created a SECOND
-- auth.users row (and a second profiles row), splitting the user's identity
-- across two accounts. Memory: feedback_auth_v2_quarantine.md +
-- auth_v2_uuid_mismatch_finding.md.
--
-- Structural fix: BEFORE INSERT trigger on auth.users that rejects any new
-- row whose email collides with an existing user's email. The iOS client
-- catches the exception and tells the user which provider they originally
-- signed up with.
--
-- What this trigger does NOT cover (by design):
-- - Account LINKING. linkIdentity() inserts into auth.identities, not
--   auth.users — no trigger fires. The linking path has its own collision
--   protection in Supabase (returns "identity already linked to another
--   user"), surfaced as LinkError.alreadyLinkedToOtherUser on iOS.
-- - Apple private-relay emails. If a user signs up with Apple (which gives
--   xyz@privaterelay.appleid.com) and later with Google (which gives their
--   real foo@example.com), the strings don't match, so no collision is
--   detected. Apple's relay design makes this fundamentally undetectable
--   server-side; accepted as a known limitation.
-- - Case sensitivity. We lowercase both sides for the comparison.
-- - Returning the existing user's auth row. We block + tell the user which
--   provider to use; we never auto-link without consent (see
--   docs/architecture/account-linking.md §"Linking wrong account orphans
--   data").
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_email_dedup_on_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    incoming_email text;
    existing_user_id uuid;
    existing_providers text[];
    primary_provider text;
BEGIN
    -- Pull the incoming email. Some providers populate auth.users.email
    -- directly (email-password); some put it in raw_user_meta_data.email
    -- (OAuth providers via signInWithIdToken). Check both.
    incoming_email := lower(trim(COALESCE(NEW.email, NEW.raw_user_meta_data->>'email', '')));

    -- No email -> phone-only auth or some edge case; let it through.
    IF incoming_email = '' THEN
        RETURN NEW;
    END IF;

    -- Look for any OTHER auth.users row with the same email.
    -- The id != NEW.id guard makes the trigger idempotent if Supabase's
    -- internal flow somehow re-inserts the same row (defensive).
    SELECT u.id INTO existing_user_id
    FROM auth.users u
    WHERE u.id != NEW.id
      AND lower(trim(COALESCE(u.email, u.raw_user_meta_data->>'email', ''))) = incoming_email
    LIMIT 1;

    -- No collision -> let the insert proceed normally.
    IF existing_user_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Collision found. Gather the existing user's providers so the client
    -- can tell the user "sign in with X instead."
    SELECT array_agg(DISTINCT provider ORDER BY provider) INTO existing_providers
    FROM auth.identities
    WHERE user_id = existing_user_id;

    -- Prefer apple > google > email for the user-facing message when the
    -- existing account has multiple linked identities. Apple Sign-In is the
    -- "default" provider on Carry today; if linked, prefer it.
    primary_provider := CASE
        WHEN 'apple' = ANY(existing_providers) THEN 'apple'
        WHEN 'google' = ANY(existing_providers) THEN 'google'
        WHEN 'email' = ANY(existing_providers) THEN 'email'
        ELSE COALESCE(existing_providers[1], 'unknown')
    END;

    -- RAISE EXCEPTION rolls back the transaction. The message format is
    -- "EMAIL_ALREADY_REGISTERED: <provider>" — iOS pattern-matches this
    -- string to surface the right UI. SQLSTATE 23505 (unique_violation)
    -- is what Supabase forwards cleanly to clients with the message
    -- preserved in the error body.
    RAISE EXCEPTION 'EMAIL_ALREADY_REGISTERED: %', primary_provider
        USING ERRCODE = 'unique_violation';
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_email_dedup_on_signup() TO postgres, anon, authenticated, service_role;

-- Drop any prior version so this migration is re-runnable.
DROP TRIGGER IF EXISTS check_email_dedup_before_insert ON auth.users;

CREATE TRIGGER check_email_dedup_before_insert
    BEFORE INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.check_email_dedup_on_signup();

-- ============================================================================
-- Verification queries (run manually after `db push`):
--
--   -- Check the trigger is installed:
--   SELECT tgname, tgrelid::regclass, tgenabled
--   FROM pg_trigger
--   WHERE tgname = 'check_email_dedup_before_insert';
--   -- Expect: 1 row, tgenabled = 'O' (enabled).
--
--   -- Check current prod state for any pre-existing duplicates (these
--   -- would NOT be caught by the trigger since the trigger only protects
--   -- future inserts):
--   SELECT lower(COALESCE(email, raw_user_meta_data->>'email')) AS norm_email,
--          count(*) AS row_count,
--          array_agg(id ORDER BY created_at) AS user_ids
--   FROM auth.users
--   WHERE COALESCE(email, raw_user_meta_data->>'email') IS NOT NULL
--   GROUP BY 1
--   HAVING count(*) > 1
--   ORDER BY 2 DESC;
--   -- Expect: 0 rows on a clean DB. If rows come back, those are pre-trigger
--   -- duplicates (e.g. the dsigvardsson@gmail.com case from 2026-05-01) that
--   -- need manual cleanup before/after the trigger ships.
-- ============================================================================

NOTIFY pgrst, 'reload schema';
