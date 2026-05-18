# Test plan — 1.1.0 auth (Google + Email + linking)

Validates the full auth-v2 surface before App Store submission. Every test must pass on **DEV** (Carry-Dev scheme, dev Supabase `gbhljwtbobbxervekxkg`) before any TestFlight cut, and the §F regression suite must pass on **TestFlight** before App Store submission.

## What's shipping

- Google Sign-In (OIDC nonce flow via `AuthNonce` + `GoogleSignInService` → Supabase `signInWithIdToken(...nonce:)`)
- Email/password sign-up + sign-in + forgot-password (web reset page at `carryapp.site/reset`)
- Account linking: link/unlink Apple, Google, Email under a single `auth.users` row (`ProfileSheetView` → SIGN-IN METHODS)
- Cross-provider email-collision dedupe (server trigger `20260515000000_dedupe_email_on_signup.sql` + iOS `AuthError.emailAlreadyRegistered`)
- "Ask to merge" UX: collision → alert → sign in with existing provider → auto-link new provider

Server migration **MUST be applied to prod** before TestFlight cut. Apple sign-in path is unchanged.

---

## Pre-conditions

- `release/1.1.0` branched from `hotfix/1.0.9` tip, `feature/auth-v2` merged in
- Dev Supabase: dedupe trigger applied (verified via `pg_trigger` query in §A), Email provider enabled, Google provider configured with Web + iOS Client IDs
- Prod Supabase: dedupe trigger applied via Studio SQL Editor before TF cut
- iOS Info.plist has `GIDClientID` + reversed URL scheme (already shipping)
- AASA at `site/.well-known/apple-app-site-association` covers `/auth/*` (already deployed)
- `site/reset/index.html` deployed to carryapp.site (already deployed)
- 2 test devices (or 1 device + 1 simulator); 1 Apple ID, 1 Google account, 1 throwaway email address you control

---

## A. Server-side verification (no app build needed)

**A.1 Dedupe trigger present + enabled**
```sql
SELECT tgname, tgenabled, tgrelid::regclass
FROM pg_trigger
WHERE tgname = 'on_auth_user_email_dedupe';
```
Expect: one row, `tgenabled = 'O'`, `tgrelid = auth.users`.

**A.2 Trigger raises typed exception on direct INSERT collision**
```sql
DO $$
DECLARE
    fake_id uuid := gen_random_uuid();
BEGIN
    INSERT INTO auth.users (id, email, instance_id, aud, role)
    VALUES (fake_id, 'collision-test@example.com', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
    INSERT INTO auth.identities (id, user_id, provider_id, provider, identity_data, created_at, updated_at)
    VALUES (gen_random_uuid(), fake_id, 'fake-apple-' || fake_id::text, 'apple',
            jsonb_build_object('sub', 'fake-apple-' || fake_id::text, 'email', 'collision-test@example.com'),
            now(), now());
END $$;

-- Now try a second user with the same email + a 'google' identity
DO $$
DECLARE
    fake_id uuid := gen_random_uuid();
BEGIN
    INSERT INTO auth.users (id, email, instance_id, aud, role)
    VALUES (fake_id, 'collision-test@example.com', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
END $$;
```
Expect: second block raises `EMAIL_ALREADY_REGISTERED: apple` (SQLSTATE 23505).
Cleanup: `DELETE FROM auth.users WHERE email = 'collision-test@example.com';`

**A.3 No pre-existing duplicates on prod**
```sql
SELECT email, COUNT(*) FROM auth.users WHERE email IS NOT NULL GROUP BY email HAVING COUNT(*) > 1;
```
Expect: zero rows. If non-zero, halt — manual cleanup required before flipping the auth flow on.

---

## B. Sign-in flows

**B.1 Apple sign-in (regression)**
- Fresh install. Tap Sign in with Apple → real Apple ID → onboarding completes.
- Expect: profile created, lands on Home with Demo Round card visible.
- Sign out via ProfileSheetView. Sign back in with same Apple ID.
- Expect: lands on Home with existing data, no onboarding re-prompt.

**B.2 Google sign-in (new user)**
- Sign out from B.1. Tap Sign in with Google → pick a Google account that has NEVER been used with Carry → onboarding completes.
- Expect: `auth.users` row created with provider = `google`, profile backfilled from Google metadata (`full_name`, `picture` if available).
- Verify in Supabase Auth → Users: one row, identities = `[google]`.

**B.3 Email sign-up (new user)**
- Sign out. Tap Sign in / Sign Up with Email → segmented control → Sign Up tab.
- Enter throwaway email + password ≥ 6 chars → Sign Up.
- Expect: "Check your email" confirmation state in-sheet.
- Open Gmail (or whatever) → tap confirmation link → lands on `carryapp.site/auth/confirm` → tap "Open Carry" → app deep-links back, session restored, onboarding completes.
- Verify Supabase Auth → Users: identities = `[email]`.

**B.4 Email sign-in (existing user, no email confirmation needed)**
- Sign out from B.3. Sign In tab → same email + password → Sign In.
- Expect: lands on Home with B.3's profile + data.

**B.5 Forgot password (web reset round-trip)**
- Sign out. Sign In tab → tap "Forgot password?".
- Enter B.3's email → Send Reset Link.
- Expect: green toast in-sheet ("Check your email…").
- Open email → tap reset link → lands on `carryapp.site/reset` → 4-state page renders the form state (not bad-token).
- Enter new password ≥ 6 chars → Update Password → success state.
- Close browser. Return to app → Sign In with email + NEW password.
- Expect: success.
- Negative: tap the SAME reset link a second time → bad-token state (single-use enforced by `persistSession: false`).

---

## C. Cross-provider Ask-to-merge (THE LOAD-BEARING FLOW)

The 2026-05-01 prod incident hinged on this. Every variant must pass.

**C.1 Google attempt on existing-Apple email**
- Pre-condition: Apple user exists (from B.1) with email `daniel@example.com`.
- Sign out. Tap Sign in with Google → pick a Google account with email `daniel@example.com`.
- Expect:
  - Server trigger blocks the implicit INSERT (raises `EMAIL_ALREADY_REGISTERED: apple`)
  - iOS catches it via `mapAuthSignupError` → `AuthError.emailAlreadyRegistered(provider: .apple)`
  - `AuthView` shows alert: "Found your Carry account" with copy referencing Apple + buttons [Sign in with Apple] [Cancel]
  - `pendingProviderLink` is populated with Google tokens
- Tap Sign in with Apple → real Apple flow → success
- Expect:
  - `consumePendingLink()` auto-runs `linkGoogleIdentity` with the stashed Google tokens
  - Green toast: "Google added to your account"
  - ProfileSheetView → SIGN-IN METHODS now shows Apple ✓ + Google ✓

**C.2 Google attempt on existing-Email user**
- Pre-condition: Email user exists (from B.3) with `throwaway@example.com`.
- Sign out. Sign in with Google using `throwaway@example.com`.
- Expect: alert "Found your Carry account" referencing Email + button [Sign in with Email] → opens EmailAuthSheet pre-filled with the email.
- Sign in with email password → `consumePendingLink` auto-links Google.
- Expect: SIGN-IN METHODS shows Email ✓ + Google ✓.

**C.3 Email sign-up attempt on existing-Apple user**
- Pre-condition: Apple user exists with `daniel@example.com`.
- Sign out. Email → Sign Up → `daniel@example.com` + password.
- Expect: same Ask alert pattern (server trigger fires on the auth.users INSERT).

**C.4 Tap Cancel on the Ask alert**
- Repeat C.1 but tap Cancel on the alert.
- Expect: `pendingProviderLink` is cleared, no link happens, returned to AuthView. Re-tapping Google starts the flow over.

**C.5 Trigger does NOT fire on legitimate same-provider re-sign-in**
- Apple user signs in with Apple again (same Apple ID) → smooth, no alert. (Trigger guards on cross-provider only.)
- Same for Google → Google, Email → Email.

---

## D. Linking & unlinking (ProfileSheetView)

**D.1 Connect Google to Apple-only account**
- Signed in as Apple-only user. Open Profile → SIGN-IN METHODS.
- Expect: Apple row shows ✓ Connected; Google row shows "Connect"; Email row shows "Connect".
- Tap Connect on Google → confirmation dialog → confirm → Google OAuth → success toast.
- Expect: Google row now ✓ Connected. Sign out + sign back in with Google → lands on same profile/data.

**D.2 Connect Email to Apple-only account**
- Profile → SIGN-IN METHODS → tap Connect on Email → EmailLinkSheet opens.
- Enter password ≥ 6 chars → submit → success toast.
- Expect: Email row ✓ Connected.
- Sign out + sign in with email + the password just set → lands on same profile.

**D.3 Unlink Google (with Apple + Email also linked)**
- Profile → SIGN-IN METHODS → tap Disconnect on Google → confirmation dialog → confirm.
- Expect: success toast, Google row reverts to "Connect", `identities` array no longer includes google.

**D.4 Last-identity guard blocks unlinking the only remaining provider**
- Pre-condition: user has only Apple linked (or only Google, or only Email).
- Profile → SIGN-IN METHODS → tap Disconnect on the only provider.
- Expect: server rejects with `LinkError.lastIdentity` → iOS shows error toast / disabled state. User stays signed in. Provider still ✓ Connected.

**D.5 Cross-account collision on link**
- User A signed in with Apple. Tap Connect Google → pick a Google account that's already linked to a DIFFERENT Carry user (User B).
- Expect: server rejects → `LinkError.alreadyLinkedToOtherUser` → iOS error toast: "That Google account is already linked to another Carry user". No data crossover.

---

## E. Edge cases & failure modes

**E.1 OIDC nonce mismatch (regression — was the 2026-05-15 blocker)**
- Sign in with Google. Watch Supabase Auth logs.
- Expect: no `"Passed nonce and nonce in id_token should either both exist or not"` error. (Raw nonce reaches `signInWithIdToken`.)

**E.2 Deep-link without app installed**
- On a device without Carry installed: open the email confirmation link.
- Expect: `carryapp.site/auth/confirm` renders the email-confirmed page with "Get Carry" App Store CTA, NOT a broken handler.

**E.3 Deep-link with fragment preserved**
- On a device with Carry installed but Universal Links not yet indexed: open email confirmation link in Safari → tap "Open Carry" button on the page.
- Expect: deep-link includes the URL fragment (`#access_token=…&type=signup&refresh_token=…`). App's `handleAuthCallback` restores the session (no error toast).

**E.4 Keychain leak across sign-out**
- Sign in as User A. Sign out. Sign in as User B (different provider, different email).
- Expect: app loads User B's profile/data. No User A bleed-through.

**E.5 App relaunch after sign-in keeps session**
- Sign in. Force-quit app. Relaunch.
- Expect: lands on Home, no AuthView. `identities` array still populated in Profile.

**E.6 Network failure during sign-in**
- Toggle Airplane Mode mid-Google-OAuth.
- Expect: error toast, AuthView still interactive, no half-state.

**E.7 Wrong password on email sign-in**
- Sign In → email + wrong password.
- Expect: inline error in sheet ("Invalid email or password"), no toast spam.

---

## F. Regression suite (must pass on TestFlight before App Store submit)

These confirm 1.1.0 didn't break anything that 1.0.9 ships.

- **F.1** Apple sign-in for an EXISTING App Store user → loads their profile, groups, history.
- **F.2** Onboarding new Apple user → completes through Disclaimer step, lands on Home.
- **F.3** Demo Round card on Home for new users (`isNewUser` → `.home` route).
- **F.4** Active Round card behavior unchanged on Home for users with a live round.
- **F.5** Push notifications still deliver (auth changes don't touch the push trigger chain, but verify post-build).
- **F.6** Phone-on-profile onboarding step still works for new users.

---

## Operational footguns (from 2026-05-15 session)

- **iOS Keychain survives app deletion.** Deleting a user from Supabase Studio while the iOS app has an active JWT for that user → app hangs on green splash on next launch. **Always sign out of the app first, then delete the Studio user.**
- **`supabase db push` is blocked by squash drift on dev.** Apply migrations to dev via Studio SQL Editor. Squash reconciliation is a separate task.
- **Remove `‼️AUTHDEBUG` NSLog lines** in `AuthService.mapAuthSignupError` ([Carry/Services/AuthService.swift:957-961](../Carry/Services/AuthService.swift:957)) and `CarryApp.swift:370` after this test plan passes once on dev. Small cleanup commit before TF cut.

---

## Acceptance criteria for App Store submit

- §A — all pass on prod (dedupe trigger live, no pre-existing duplicates)
- §B — all pass on TestFlight (release/1.1.0 build)
- §C — all 5 variants pass on TestFlight
- §D — all 5 cases pass on TestFlight
- §E.1, E.3, E.4 — explicitly verified (rest can be exercised in normal use)
- §F — full regression pass on TestFlight
- TEMP DEBUG NSLog lines removed from binary (verify via `strings` on the .ipa or by re-grepping the source before archive)
