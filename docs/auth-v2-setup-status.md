# Auth-v2 setup — status

**Last updated:** 2026-05-19 (mid-session 5 — in-app recovery verified, §C.1 paused mid-test)
**Branch:** `feature/auth-v2` (local-only, NOT pushed to origin)
**Target release:** 1.1.0 (1.0.7 live on App Store, 1.0.8 / 1.0.9 in hotfix flight)

## Session 5 status (2026-05-19, partway through)

**Headline:** In-app password recovery verified end-to-end ✅. Unit-test scaffolding for pure auth logic landed. §C.1 Ask-to-merge stalled because the obvious dev-side collision target (`dsigvardsson@gmail.com`) isn't a real Google account Daniel can sign in with — the Google picker fell through to his main `daniel@diverseawareness.com` (already Apple+Google linked, no trigger fires). Mid-pivot to a destructive-but-safe variant.

### What landed today

- **PasswordRecoverySheet `.fullScreenCover` fix.** Initial `.sheet` presentation conflicted with EmailAuthSheet in the modal stack ("Currently, only presenting a single sheet is supported"). Switched to `fullScreenCover` AND added `onChange(of: authService.isInPasswordRecovery)` in AuthView that dismisses `showEmailSheet` when recovery flips true. SwiftUI then queues the cover for after the sheet animates out. Verified end-to-end: tap reset email → app opens → cover slides up → set new password → signed out → sign back in with new password works.
- **`flow_state_expired` learning.** PKCE flow states have a short server-side TTL (~5 min), much shorter than the 1-hour email link expiry. The test plan needs a "tap within 2 min of request" note. Documented inline in `beginPasswordRecovery` once we confirmed it was the cause.
- **`recoveryEmail` published on AuthService + hidden `.username` field** in PasswordRecoverySheet and EmailLinkSheet so iCloud Keychain offers to save the new credentials. EmailAuthSheet already had the email field next to password so it was fine.
- **`AuthLogicTests.swift`** — 20 tests in `CarryTests/`. Covers `mapAuthSignupError` parsing (all 3 providers, passthrough, punctuation, empty tail), `AuthError.errorDescription` copy, `AuthNonce.randomString` (length, base62, randomness), `AuthNonce.sha256Hex` (known vector, deterministic, empty, length=64), `PendingProviderLink` struct round-trip, `LinkError.errorDescription` for all 3 cases. NOT YET added to the Xcode CarryTests target (right-click in navigator → Add Files → check CarryTests target box).
- **Stripped the `beginPasswordRecovery` AUTHDEBUG logs** after recovery flow was confirmed working. Other `‼️AUTHDEBUG` lines (in `mapAuthSignupError` + `CarryApp.swift ~L370`) still pending strip — task #6.

### Confidence audit (2026-05-19 session, written before §C.1 pause)

For each unverified flow, ranked from highest to lowest ship-readiness:

**High confidence (90%+):** §C.5 same-provider re-sign-in, §D.1 connect Google to Apple-only, §D.3 unlink Google, §E.1 OIDC nonce (unit-tested), §E.4 keychain, §E.5 relaunch, §E.6 network errors, §E.7 wrong password, §F regression (auth-v2 doesn't touch demo/groups/scoring/push), Apple/Google basic sign-in (unchanged code), prod migrations (dev/prod schema parity since baseline squash).

**Medium-high (70-85%):** §C.1 Ask-to-merge Google→Apple (trigger + parser unit-tested, alert/auto-link wiring untested), §C.3 email signup on Apple, Email Disconnect button (RPC ✅ server-side, SwiftUI dialog wiring untested), §E.3 fragment preservation.

**Medium (50-70%):** §C.2 Ask via email path (`consumePendingLink` in EmailAuthSheet signIn unverified), §C.4 Cancel on alert (state cleanup unexercised), §D.4 last-identity guard, §D.5 cross-account collision (both rely on fragile `.contains()` string matching in `mapLinkError`), iOS password save prompt (wired correctly but iOS sometimes silently skips), §E.2 deep-link with no app installed (web confirm page deployment unverified).

**Real risk concentrated in §C.1.** That's the 2026-05-01 incident flow — medium-high isn't good enough.

### Minimum must-runs before App Store ship (4 tests)

These are the deterministic-must-pass set. Skip anything else from §B-§E unless time allows.

1. **§C.1 Ask-to-merge Google→Apple** — see §"Resume from here" below for the exact SQL/click steps. Mid-execution.
2. **§D.1 Connect Google to Apple-only account** — sign in as `daniel+signuptest@diverseawareness.com` (email-only user from yesterday's §B.3) → Profile → SIGN-IN METHODS → tap Connect on Google → real Google flow → expect ✅ Connected.
3. **§D.4 Last-identity guard** — sign in as a user with only one provider → Profile → SIGN-IN METHODS → tap Disconnect on the only provider → expect error toast "You can't disconnect your only sign-in method", row stays connected.
4. **§F.1 Apple sign-in regression** — sign out → sign in with Daniel's real Apple ID → expect Home with all existing groups/data, no re-onboarding.

### Resume from here (session 6 — pick up exactly at §C.1)

The previous §C.1 attempt failed silently because `dsigvardsson@gmail.com` isn't a real Google account on Daniel's device. The Google picker offered his main `daniel@diverseawareness.com` instead, which is already Apple+Google linked — no trigger fires.

**Pivot:** unlink Google from `daniel@diverseawareness.com` temporarily so the same email becomes a fresh collision target. Then sign in with Google → trigger fires → Ask alert → re-link via the alert.

```sql
-- Step 1 — verify state
SELECT id, provider FROM auth.identities
WHERE user_id = 'c39f96d3-81a3-43b2-bba4-a777681bf484' AND provider = 'google';

-- Step 2 — remove the Google identity (Apple stays — Daniel can still sign in)
DELETE FROM auth.identities
WHERE user_id = 'c39f96d3-81a3-43b2-bba4-a777681bf484' AND provider = 'google';
```

Then in the app:
1. Sign out of Carry
2. Tap **Sign in with Google** → pick `daniel@diverseawareness.com`
3. **Expected:** alert "Found your Carry account, sign in with Apple to link"
4. Tap **Sign in with Apple** in the alert → real Apple flow → success → expect green toast "Google added to your account"

Verify after:
```sql
SELECT provider FROM auth.identities WHERE user_id = 'c39f96d3-81a3-43b2-bba4-a777681bf484';
-- expect: both 'apple' and 'google'
```

Failure modes to watch for at each step:
- Step 3 lands on Home directly → trigger didn't fire OR `mapAuthSignupError` didn't catch the typed error. Check Xcode console for `‼️AUTHDEBUG mapAuthSignupError` line.
- Step 3 shows error toast (no alert) → mapAuthSignupError caught but pendingProviderLink wasn't set / alert binding broken in AuthView.
- Step 4 succeeds but no toast → `consumePendingLink()` didn't fire. Check Xcode console.
- Step 4 succeeds but Google not re-linked → linkGoogleIdentity failed inside consumePendingLink. Check Xcode console for AUTHDEBUG.

### After §C.1 passes — sprint to ship

1. Run must-runs §D.1, §D.4, §F.1 (combined ~15 min).
2. Apply both 20260518 migrations to prod via Studio SQL Editor (`seeitehizboxjbnccnyd`). Confirm 20260515000000_dedupe_email_on_signup is already on prod.
3. Strip remaining `‼️AUTHDEBUG` NSLog lines (AuthService.mapAuthSignupError + CarryApp ~L370).
4. Add `Carry/Views/PasswordRecoverySheet.swift` to the Xcode Carry target (right-click Views → Add Files → check Carry target). Already added per yesterday's instruction; verify it's there.
5. Add `CarryTests/AuthLogicTests.swift` to the Xcode CarryTests target (different target than #4).
6. Cmd+U to run unit tests — expect 20 passes.
7. Commit `feature/auth-v2` as a clean set of commits (suggested: 3 commits — "auth(hasPassword)", "auth(recovery)", "auth(ui+tests)").
8. Push `feature/auth-v2` to origin.
9. Cut `release/1.1.0` from `hotfix/1.0.9`, merge feature/auth-v2, bump MARKETING_VERSION, archive, submit.
10. On TestFlight: run §F regression sweep (Apple sign-in for existing user, demo round, push delivery), then App Store submit.

### Code state (uncommitted on feature/auth-v2 at session-5 pause)

| File | Change |
|---|---|
| `Carry/Services/AuthService.swift` | Session 4 changes + session 5: `@Published var recoveryEmail`, store email in `beginPasswordRecovery`, clear in `complete`/`cancel`. `beginPasswordRecovery` AUTHDEBUG logs stripped. `sendPasswordReset` reverted to plain `redirectTo` (no `?env=dev` — abandoned). |
| `Carry/Views/ProfileSheetView.swift` | Email row drives off `hasPassword`, disconnect routes to `disconnectEmailPassword` |
| `Carry/Views/EmailAuthSheet.swift` | Keyboard Done removed; Forgot password? color → textPrimary |
| `Carry/Views/EmailLinkSheet.swift` | Keyboard Done removed; hidden `.username` field for iCloud Keychain |
| `Carry/Views/AuthView.swift` | Per-provider `SigningProvider` enum + `inFlightProvider` state; `onChange` dismisses EmailAuthSheet when `isInPasswordRecovery` flips true |
| `Carry/Views/PasswordRecoverySheet.swift` (NEW) | Full-screen cover sheet, takes new password, hidden `.username` field, signs out after save |
| `Carry/CarryApp.swift` | `handleIncomingURL` routes `/reset*` → `beginPasswordRecovery`; root view has `.fullScreenCover(isPresented: $authService.isInPasswordRecovery)` |
| `CarryTests/AuthLogicTests.swift` (NEW) | 20 tests, needs Xcode target wiring |
| `site/.well-known/apple-app-site-association` | paths now `["/invite*", "/auth/*", "/reset*"]`. DEPLOYED to carryapp.site as of yesterday |
| `site/reset/index.html` | Env-aware code from a now-abandoned branch — dead code for installed-app users since AASA intercepts `/reset`. Keep as "no app installed" fallback. Cleanup later. |
| `supabase/migrations/20260518000000_current_user_has_password.sql` (NEW) | Applied to dev only |
| `supabase/migrations/20260518000001_clear_current_user_password.sql` (NEW) | Applied to dev only |

### Tasks state at pause

- #4 — Apply migration to prod Supabase (pending; 2 migrations + verify dedupe is on prod)
- #5 — Commit hasPassword changes on feature/auth-v2 (pending)
- #6 — Strip ‼️AUTHDEBUG NSLog lines (pending; `beginPasswordRecovery` already done)
- #7 — Push feature/auth-v2 to origin (pending)
- #8 — Cut release/1.1.0 + archive + submit (pending)
- #9 — Test Email Disconnect end-to-end (in-progress; server-side RPC ✅, button UX untested)
- #13 — §C.1 Cross-provider Ask-to-merge (pending → IN-PROGRESS, resume per "Resume from here")
- #15 — Switch forgot-password to in-app recovery (in-progress; flow verified, sheet conflict resolved)
- #16 — Build auth unit test suite (in-progress; tests written, target wiring pending)

---

## Session 4 status (2026-05-18, evening)

**Headline:** Email-link Supabase quirk RESOLVED + most §B/D flows verified on dev. Forgot-password flow pivoted from web-page to in-app due to PKCE flow incompatibility. Code is written but NOT YET tested end-to-end.

### Email-link diagnosis (session 3 unblock)
- Cause: `auth.update(password:)` **does** persist `encrypted_password` server-side but Supabase does NOT add an `email` row to `auth.identities` retroactively for OAuth-linked users. So `identities.contains("email")` never flips → UI stayed on "Connect" forever.
- Structural fix: `current_user_has_password()` SECURITY DEFINER RPC reads `auth.users.encrypted_password IS NOT NULL` for the calling user. AuthService exposes `@Published var hasPassword`, refreshed alongside `identities`. ProfileSheetView Email row drives `isConnected` off `hasPassword`. Verified: `has_password=true` for `daniel@diverseawareness.com` (UUID `c39f96d3-…`) → Email row correctly shows Connected ✓.
- Session 3's mystery UUID `C39F96D3-…` was real — it's Daniel's dev user. Doc was wrong about "doesn't exist on either DB".
- The 2-step OTP flow in `stash@{0}` is no longer needed and was NOT applied. EmailLinkSheet stays as the simple single-password form on HEAD.

### Email Disconnect built
- `clear_current_user_password()` SECURITY DEFINER RPC clears `encrypted_password` with a foot-gun guard: refuses if user has zero OAuth identities (would strand them).
- `AuthService.disconnectEmailPassword()` calls the RPC + `refreshIdentities`.
- ProfileSheetView's `disconnect()` routes `provider == "email"` to the new path instead of `unlinkProvider` (which would silently no-op since there's no email identity row to unlink).
- `mapLinkError` maps `last_sign_in_method` exception → `LinkError.lastIdentity` so the existing alert UI works.
- NOT yet exercised end-to-end via the in-app Disconnect button (#9 task).

### Verified on dev today (§B, partial §D)
- Email row shows **Connected ✓** for existing users with passwords (§D.2 backbone)
- Email row flips Connected ✓ → Connect after `UPDATE auth.users SET encrypted_password = NULL ...` + sign-in refresh
- §B.4 Email sign-in works after password set (proved persistence end-to-end without 2-step OTP)
- §B.3 Email sign-up works: throwaway plus-alias → confirmation email → tap link → `carryapp.site/auth/confirm.html` → Open Carry → onboarding completes
- §A.1 + §A.2 dedupe trigger present + raises `EMAIL_ALREADY_REGISTERED: apple` on collision
- Daniel had to deploy `site/reset/index.html` (was 404 before; first deploy this session)

### Forgot-password root cause + pivot
- §B.5 attempts failed: every fresh email link landed on the in-app ForgotPasswordView instead of the web reset page.
- After ruling out AASA cache, allowlist gaps, and Mail-browser quirks, **root cause** is the iOS SDK uses **PKCE flow** (default in newer `supabase-swift`). PKCE recovery puts a `?code=` query in the redirect, and exchanging the code requires the **verifier** generated on the iOS side and stored in iOS Keychain. The web `site/reset/index.html` cannot complete the exchange because it doesn't have the verifier.
- Pivot (Daniel's call): **drop the web reset page; make recovery purely in-app.** Email link opens app via Universal Link, app exchanges the code using its own verifier, presents a sheet for the new password.

### Code written this session (NOT YET TESTED end-to-end)
- `supabase/migrations/20260518000000_current_user_has_password.sql` — applied to dev only
- `supabase/migrations/20260518000001_clear_current_user_password.sql` — applied to dev only
- `Carry/Services/AuthService.swift`:
  - `@Published var hasPassword: Bool`
  - `refreshHasPassword()` folded into `refreshIdentities()`
  - `linkEmailIdentity` alreadyLinked guard switched from `identities.contains("email")` to `hasPassword`
  - `disconnectEmailPassword()` calling `clear_current_user_password` RPC
  - `mapLinkError` adds `last_sign_in_method` → `.lastIdentity` mapping
  - `signOut()` resets `hasPassword = false`
  - `sendPasswordReset` reverted to plain `https://carryapp.site/reset` (the `?env=dev` experiment was abandoned after the PKCE realization)
  - NEW: `@Published var isInPasswordRecovery: Bool`
  - NEW: `beginPasswordRecovery(url:)` calls `client.auth.session(from:)` (the PKCE exchange) and flips the flag
  - NEW: `completePasswordRecovery(newPassword:)` calls `auth.update(password:)` + `signOut()` so user re-enters cleanly
  - NEW: `cancelPasswordRecovery()` dumps the recovery session
- `Carry/Views/ProfileSheetView.swift`:
  - Email row `isConnected` → `authService.hasPassword`
  - `disconnect()` helper routes `provider == "email"` to `disconnectEmailPassword`
- `Carry/Views/EmailAuthSheet.swift` — removed redundant keyboard-toolbar Done button
- `Carry/Views/EmailLinkSheet.swift` — removed redundant keyboard-toolbar Done button
- `Carry/Views/AuthView.swift` — replaced single `isSigningIn: Bool` with per-provider `enum SigningProvider; @State inFlightProvider: SigningProvider?`. Spinner now scoped: tapping Apple no longer spins the Google button. `isSigningIn` kept as a computed bool so opacity/disabled across all three buttons stays a single source.
- `Carry/Views/EmailAuthSheet.swift` — "Forgot password?" link recolored from `textTertiary` → `textPrimary` (Daniel's call for visibility)
- NEW: `Carry/Views/PasswordRecoverySheet.swift` — clone of EmailLinkSheet's form, calls `completePasswordRecovery`. NOT yet added to Xcode project file.
- `Carry/CarryApp.swift`:
  - `handleIncomingURL` adds `/reset` path branch calling `authService.beginPasswordRecovery`
  - Root view adds `.sheet(isPresented: $authService.isInPasswordRecovery) { PasswordRecoverySheet() }`
- `site/.well-known/apple-app-site-association` — paths now `["/invite*", "/auth/*", "/reset*"]`. NOT yet redeployed.
- `site/reset/index.html` — has env-aware code from an earlier branch of this session. Now effectively dead code for installed-app users since iOS will intercept `/reset` via the AASA. Worth keeping for "no Carry installed" fallback, but not on the critical path. Re-delete or simplify later.

### Open thread — what session 5 has to do FIRST
1. **Add `Carry/Views/PasswordRecoverySheet.swift` to the Xcode project** — right-click `Views` in the navigator → Add Files to "Carry" → select the file → Add. Without this Xcode won't compile it.
2. **Re-deploy `site/.well-known/apple-app-site-association`** to carryapp.site. Verify with `curl -s https://carryapp.site/.well-known/apple-app-site-association | grep reset` — must show `/reset*`.
3. **Clean build + uninstall + reinstall.** iOS caches AASA at install time. To force re-fetch: Product → Clean Build Folder → delete the app from device → Cmd+R.
4. **Smoke-test §B.5 end-to-end on dev:** Sign Out → Email → Sign In → Forgot password? → enter `daniel+signuptest@diverseawareness.com` → tap fresh email link → expect app to open with PasswordRecoverySheet → enter new password → Save → expect sign-out → sign back in with new password works.

### Then the remaining unfinished work
5. **§C.1 Cross-provider Ask-to-merge** — pending. Daniel's main dev user already has Apple + Google linked, so a Google sign-in won't trigger the dedupe trigger. Need a fresh email or planted-fake-row setup per the test plan §"Old how-to resume" #2.
6. **Test Email Disconnect button end-to-end** (#9 task). Sign in → ProfileSheet → SIGN-IN METHODS → tap Connected ✓ on Email → confirm → expect toast + row reverts + server `encrypted_password IS NULL`.
7. **Apply both new migrations to prod** (`20260518000000_current_user_has_password.sql`, `20260518000001_clear_current_user_password.sql`). And re-confirm `20260515000000_dedupe_email_on_signup.sql` is on prod.
8. **Strip `‼️AUTHDEBUG` NSLog lines** from AuthService.swift + CarryApp.swift.
9. **Commit all uncommitted work** on `feature/auth-v2` as a clean set of commits (suggest 3: "auth(hasPassword): expose RPC + UI signal + disconnect", "auth(recovery): in-app PKCE recovery sheet + AASA /reset*", "auth(ui): per-provider sign-in spinner + drop keyboard Done buttons").
10. **Push `feature/auth-v2` to origin**.
11. **Cut `release/1.1.0` from `hotfix/1.0.9`** + merge feature/auth-v2 + bump MARKETING_VERSION + archive + submit.

### Operational notes from this session
- The Site URL in dev Supabase is `https://carryapp.site` (bare root). If a `redirect_to` ever fails the allowlist match, that's where the user lands. Not the cause of any of today's symptoms; documenting for context.
- Removing the keyboard toolbar Done button from sheets is safe — `scrollDismissesKeyboard(.interactively)` + `.onTapGesture { focused = nil }` + Return-key submit cover keyboard dismissal.
- The reset page deployment turned up that nothing under `/auth/` is deployed on carryapp.site either — `/auth/confirm.html` returned 404 in earlier curl checks. Yet §B.3 worked end-to-end, meaning Supabase's verify endpoint deep-links straight into the app via AASA's `/auth/*` glob without ever needing the page to render. Worth keeping in mind: `site/auth/confirm.html` is unreachable from real flows; it's a fallback for "no app installed" scenarios.

### Cleanup that can land alongside or after 1.1.0
- Remove `https://carryapp.site/reset` + `https://carryapp.site/reset?env=dev` + `https://carryapp.site/reset/**` from both dev and prod Redirect URLs allowlists once in-app recovery is verified — the web page is no longer the redirect target.
- Decide whether to delete `site/reset/index.html` + the `/reset*` AASA path entry (currently both still useful for "app not installed" fallback).
- Drop the two duplicate plus-alias email users on dev (`daniel+confirm@...`, `daniel+testresend@...`) once they're confirmed dead.

---

## TL;DR

`feature/auth-v2` is rebased on `hotfix/1.0.9` and contains:
- The Google + Email sign-in scaffold (April 30 work)
- Account-linking code restored from `stash@{3}` (was uncommitted since May 2)
- Password-recovery web page at `carryapp.site/reset`
- Cross-provider email-collision dedupe (server trigger + iOS error mapping)
- OIDC nonce wiring for Google Sign-In (without it, Supabase rejects with "Passed nonce and nonce in id_token should either both exist or not")
- "Ask to merge" flow — collision detected → alert prompts existing-provider sign-in → auto-links Google to the now-authenticated user
- Toast-overlay fix so `ForgotPasswordView`'s confirmation toast renders inside `EmailAuthSheet`

**Verified end-to-end on dev as of 2026-05-15 evening:**
- Google Sign-In completes (`dsigvardsson@gmail.com` created a real auth.users row)
- Dedupe trigger fires correctly (`EMAIL_ALREADY_REGISTERED: apple` confirmed via direct SQL INSERT)
- No pre-existing duplicates on prod (clean slate before trigger ships)
- "UUID mismatch" 2026-05-03 finding was a red herring — `f1d8b8a4` and `951d4c86` are two legitimate separate Apple accounts (Daniel + Ziggy), not a split user

**Not yet:**
- Visual smoke of the Ask alert on device (attempted in session 3 — see §"Session 3" — couldn't reproduce on dev because the iOS app was unintentionally on the **prod** scheme and Daniel's prod Google identity is already linked to his account, so no fresh INSERT to trip the trigger)
- Trigger applied to prod (safe to do; held for clean audit trail)
- `feature/auth-v2` pushed to origin
- Email-link Supabase quirk unresolved — session 3 surfaced that `client.auth.update(password:nonce:)` succeeds client-side but persists nothing server-side, even after `reauthenticate()` and even with email field included. Theory: Supabase doesn't add an `email` row to `auth.identities` retroactively for OAuth users.

## Session 3 status (2026-05-18)

**3 commits landed locally on `feature/auth-v2`:**
- `f6597c8` auth(ask-flow): wire OIDC nonce + pendingProviderLink + Ask-to-link UX (the session-2 bundle that had been sitting uncommitted)
- `a7b049b` demo-round(route): land new users on Home so the Demo card is first (MainTabView isNewUser → .home; Demo Round shipped in 1.0.8)
- `a4f05ca` docs(auth): add 1.1.0 test plan (A–F + acceptance criteria) — `docs/test-plan-1.1.0-auth.md`

**Working tree (uncommitted):**
- `Carry/Services/AuthService.swift` — Email-link diagnostic refactor:
  - Added `requestEmailLinkCode()` calling `client.auth.reauthenticate()`
  - Changed `linkEmailIdentity(password:)` → `linkEmailIdentity(password:, nonce:)`
  - Latest experiment passes `UserAttributes(email: currentEmail, password: password, nonce: nonce)` — untested
  - 6 `‼️AUTHDEBUG` NSLog lines for diagnostics (session 3 additions, on TOP of the ones from session 2)
- `Carry/Views/EmailLinkSheet.swift` — Rewritten as 2-step flow (Send Code → enter code+password), `.toolbar` Done button removed

**Open thread blocking Email-link feature:**
The 2-step reauth flow still results in `has_password=false` and `identities=[apple, google]` (no email) on the server. AUTHDEBUG confirms the `auth.update` returns a User object with the same identities — server isn't persisting the email identity row.

Hypotheses to test next session:
1. **Supabase doesn't create email identity rows retroactively.** OAuth-only users can only have `auth.users.encrypted_password` set; the `auth.identities` table treats `email` as a signup-time provider, not a link-time one. If this is true, the "Connected ✓" row state needs a different signal (e.g., check `currentUser.hasPassword` if Supabase exposes it, or query `auth.identities` directly).
2. **`reauthentication_sent_at` wasn't actually set** on Daniel's user — we asked for the SQL result but the session got tangled on which DB the app was hitting. Re-verify with fresh AUTHDEBUG showing user ID + direct SQL on that exact user.
3. **Email confirmation needed.** Maybe Supabase requires `email_confirmed_at` to be set on the user row before allowing password updates. Apple OAuth users have it set; Daniel's user might not. Check.

**Operational learning (session 3):**
- Xcode scheme drift: the app was unintentionally on `Carry` (prod) scheme for much of the session. All `client.auth.*` calls hit prod auth API → `reauthenticate()` may have emailed real prod inbox. No prod SQL writes were made, and Daniel's real prod user `f1d8b8a4` shows `has_password=false` per the post-incident query, so no persistent damage. **Always verify scheme dropdown before any auth testing — add to test plan §Pre-conditions.**
- The mystery `C39F96D3-81A3-43B2-BBA4-A777681BF484` user ID returned by the SDK doesn't exist on either prod or dev when queried. Likely a stale Keychain session pointing at a deleted user, OR a UUID misread from screenshot. Not load-bearing; ignore on resume unless it surfaces again.

## What was decided this session

1. **Dropped `feature/dev-push-setup` work** from the auth-v2 rebase (Carry-dev.entitlements, widgets scheme, " · DEV" suffix in ProfileSheetView). Per Daniel: "don't bring back anything except the auth stuff." The dev-push-setup branch still exists for later if real-device push testing on dev becomes a need.
2. **Dropped `09409fd` infra commit** (`supabase/config.toml` + reload tooling). Same "auth only" rule.
3. **Reset and cherry-picked** instead of straight-rebasing. The straight rebase tried to replay the `46bd922` hotfix/1.0.3 bundle commit (already in hotfix/1.0.9 under a different SHA) and conflicted on dozens of files. Cleaner: reset auth-v2 to hotfix/1.0.9 + cherry-pick only the 4 auth-original commits, then re-apply the linking stash on top.
4. **Web-only password reset page** (`site/reset/index.html`), not a native deep-link intercept. The redirect URL Daniel chose in April was a web URL; the web page works everywhere (browser, desktop, no-app-installed). Native intercept can be added later if desired.
5. **Server-side dedupe trigger** (not iOS-side pre-check). Pre-check has a TOCTOU race and is bypassable by other clients; server trigger is the structural fix per the playbook's "no patches" rule.
6. **Migration applied to dev via Studio SQL Editor**, not `supabase db push`. The squash drift from May still blocks `db push` (DB has the baseline tracking row, local tree has 58 individual migration files). Squash reconciliation is its own task — out of scope for this session.

## Session 2 decisions (2026-05-15 evening)

7. **OIDC nonce wired properly (path B), not "Skip nonce check" toggle (path A)**. First Google sign-in attempt failed with "Passed nonce and nonce in id_token should either both exist or not" — GoogleSignIn-iOS embeds a nonce hash in the ID token by default, and we weren't passing the raw nonce to Supabase. Path A would have flipped Skip-nonce-check ON on the dev provider (10 sec fix, weakens replay protection, leaves a "remember to revert" footgun on prod). Path B added a CSPRNG + SHA256 utility (`AuthNonce.swift`), wired Google to receive the hashed nonce, returned raw nonce to AuthService, and passed raw nonce to Supabase's `signInWithIdToken(...nonce:)`. Done in both `signInWithGoogle` and `linkGoogleIdentity` (linking has the same OIDC contract).
8. **"Ask to merge" UX (flow C from the design fork)** picked over Block (A) or Auto-merge (B). Block is safe but bad UX; auto-merge is best UX but has a real security risk (attacker controls a Google for victim's email → walks into victim's data). Ask requires the user to authenticate as the existing provider before we link — preserves the security boundary, gives near-best UX. Built as: `AuthError.emailAlreadyRegistered(provider:)` from the trigger → AuthView stashes Google tokens on `AuthService.pendingProviderLink` → alert "Found your Carry account, sign in with Apple to link" → user taps Apple → `signInWithApple` succeeds → `consumePendingLink()` auto-runs `linkGoogleIdentity` with the stashed tokens → green toast "Google added to your account". Email-as-existing-provider case also wired (consumePendingLink hook in EmailAuthSheet's signIn success path).
9. **Temp `NSLog("‼️AUTHDEBUG ...")` in `mapAuthSignupError`** added during diagnosis when the typed error wasn't reaching iOS (turned out to be the nonce issue, not a mapping bug). Lines are tagged with the unique `‼️AUTHDEBUG` prefix so they're trivially grep-able. Marked as "TEMP DEBUG" in code comment — remove once the full Ask flow is exercised against a real collision in TestFlight.

## Commits on `feature/auth-v2`

Topmost first. All sit on top of `hotfix/1.0.9` (`b1eb1f8`).

| SHA | Subject |
|---|---|
| `2078440` | auth(dedupe): block cross-provider email collisions + fix Forgot toast |
| `cf159b0` | auth(reset): add carryapp.site/reset password-recovery page |
| `92d61de` | auth(linking): restore 2026-04-30 work from stash@{3} |
| `704d313` | docs: add dev/prod migration workflow to auth setup guide |
| `cf62b06` | AuthView: fix Image name to match googleIcon asset |
| `cca572d` | Auth scaffold: register Email/Google sources in Xcode + add googleIcon asset |
| `1806674` | Reapply "Auth: scaffold Google Sign-In and Email Sign-Up alongside existing Apple flow" |

## Code state — what's wired

### iOS
- `AuthService.signInWithApple` — unchanged (shipping in prod)
- `AuthService.signInWithGoogle(idToken:accessToken:nonce:)` — token exchange (now with OIDC nonce) + profile backfill from Google metadata + provider-agnostic post-auth wrap. Wrapped in `mapAuthSignupError` to translate the dedupe trigger's exception.
- `AuthService.signUpWithEmail` — same dedupe wrap; throws `AuthError.emailConfirmationPending` when Supabase requires email confirmation
- `AuthService.signInWithEmail` — no dedupe wrap (sign-in doesn't insert rows, trigger doesn't fire). Calls `consumePendingLink()` after success so a Google→email Ask flow auto-links.
- `AuthService.sendPasswordReset` — redirects to `https://carryapp.site/reset`
- `AuthService.handleAuthCallback(url:)` — exchanges the Universal Link callback URL for a session, backfills profile from user_metadata
- `AuthService.linkAppleIdentity / linkGoogleIdentity(...nonce:) / unlinkProvider` — with `LinkError` (last-identity guard, alreadyLinked, alreadyLinkedToOtherUser, underlying). `linkGoogleIdentity` now takes nonce (same OIDC contract as sign-in).
- `AuthService.refreshIdentities` — populates `@Published var identities: [UserIdentity]`, auto-called from `checkSession` and `finishProviderSignIn`
- `AuthService.pendingProviderLink` (new) — `@Published PendingProviderLink?` stash for Google tokens between a blocked sign-in attempt and the subsequent existing-provider sign-in
- `AuthService.consumePendingLink()` (new) — drained after successful Apple/email sign-in; auto-links the stashed provider to the now-authenticated user; toasts success / "add it in Settings" on failure
- `AuthNonce` (new file, `Carry/Services/AuthNonce.swift`) — CSPRNG `randomString()` + `sha256Hex()` utility for OIDC nonce flows
- `AuthView` — Email + Google + Apple button stack; Google handler catches `AuthError.emailAlreadyRegistered`, stashes tokens, shows the Ask alert; Apple success handler calls `consumePendingLink`
- `AuthView` (Ask alert) — `.alert("Found your Carry account", presenting: linkPromptExistingProvider)` — provider-aware copy + action buttons that route to Apple sign-in or open EmailAuthSheet
- `GoogleSignInService.signIn(presenting:)` — generates raw nonce + SHA256 hash, passes hash to `GIDSignIn.signIn(...nonce:)`, returns `Tokens(idToken, accessToken, rawNonce)`
- `EmailAuthSheet` — segmented Sign In / Sign Up, check-email confirmation, forgot-password navigationDestination, `.carryToastOverlay()` so toasts render inside the sheet. SignIn success calls `consumePendingLink`.
- `ForgotPasswordView` — Figma 1370:3502 layout, fires `ToastManager.shared.success / .error`
- `ProfileSheetView` — SIGN-IN METHODS section above DATA with Apple + Google rows, Connect/Disconnect confirmation dialog. `linkGoogleFlow` passes nonce through.
- `CarryApp.handleIncomingURL` — `carryapp.site/auth/*` branch routes to `authService.handleAuthCallback`; `GIDSignIn.sharedInstance.handle(url)` early-return for Google OAuth

### Server (Supabase — dev branch `gbhljwtbobbxervekxkg` only)
- Migration `20260515000000_dedupe_email_on_signup.sql` applied via Studio SQL Editor. Verified via `pg_trigger` query (`tgenabled = 'O'`).
- Google provider enabled with Web client + iOS client in the comma-separated Client IDs field

### External
- Google Cloud Console (project `powerful-anchor-401116`): both prod and dev callback URIs on the `Carry Supabase Auth` Web client
- Info.plist already had `GIDClientID` + reversed URL scheme (didn't need to add)
- AASA at `site/.well-known/apple-app-site-association` already covers `/auth/*` paths

### Web
- `site/reset/index.html` — 4-state page (loading, form, success, bad-token). Uses Supabase JS v2 ESM via jsdelivr CDN. `detectSessionInUrl: true` + `persistSession: false` so recovery is single-use and tab-bound.
- `site/auth/confirm.html` — existed in stash (email-confirmation landing)

### .gitignore additions
- `client_secret_*.json` — Google OAuth secrets must never commit (quarantine rule)
- `GoogleService-Info.plist` — same posture

## What's NOT done

### Blocking 1.1.0 ship
- **Commit the session-2 work in tree** — 6 modified files + 1 new file + 1 pbxproj entry. See "How to resume" §1.
- **Visual smoke of the Ask alert on dev** — requires synthesizing a fake collision (instructions in §"How to resume"). Trigger + iOS code are both proven to work; this is the last "saw it with my eyes" confirmation.
- **Apply migration to prod** — safe to do (no pre-existing duplicates, trigger only blocks future collisions). Held for clean audit trail until the iOS code is ready to ship.

### Deferred design decisions
- **Email row in SIGN-IN METHODS section** — left out of ProfileSheetView when linking was first built (Apple + Google only). Decision: stub "Email — coming soon" or build set-password + verify flow? Not blocking 1.1.0 if shipped Apple+Google only initially.
- **Native deep-link intercept for password reset** — current path is pure web. Could add `/reset*` to AASA + an in-app "set new password" sheet for the iOS-with-app-installed case. Web is fallback for browser/desktop/no-app users. Not blocking.
- **Squash drift reconciliation** — out of scope for this session. The dev Supabase has the `20260101000000` baseline tracking row but local tree has 58 individual files. `supabase db push` is blocked; Studio SQL Editor is the workaround. Needs a dedicated session.
- **Remove `‼️AUTHDEBUG` NSLog lines from `mapAuthSignupError`** — added 2026-05-15 evening during the nonce diagnosis. Tagged as "TEMP DEBUG" in code. Leave until the Ask flow is exercised once against a real collision; remove in a small cleanup commit after.

### Operational
- **Push `feature/auth-v2` to origin** — held. Branch is local-only until Daniel approves.
- **Delete `feature/auth-v2-backup-2026-05-15`** — kept as safety net until Xcode build on dev scheme is verified clean.
- **Drop `stash@{3}`** — kept until same point. (Stash content is already committed as `92d61de`.)
- **Email provider on dev Supabase** — not enabled yet. Need it before testing the Email/password flow end-to-end.

### Resolved during session 2
- ~~iOS smoke test on dev~~ — Google sign-in completes end-to-end (verified by creating `dsigvardsson@gmail.com` user from a real Google OAuth flow). Dedupe trigger fires correctly when there IS a collision (verified by direct SQL INSERT raising `EMAIL_ALREADY_REGISTERED: apple`).
- ~~Pre-existing duplicate cleanup on prod~~ — Q3 returned zero rows. No duplicates on prod. The May 1 incident's dups were apparently cleaned up at some point; nothing to do.
- ~~UUID-mismatch resolution~~ — The 2026-05-03 finding was a red herring. `f1d8b8a4` (daniel@diverseawareness.com) and `951d4c86` (hello@diverseawareness.com) are two separate, legitimate Apple-signed accounts owned by Daniel — not a split profile. Memory entry `memory/auth_v2_uuid_mismatch_finding.md` can be marked resolved.

## How to resume (session 4)

**Verify scheme FIRST before any auth testing.** Xcode dropdown must say **Carry-Dev**, not Carry. The session-3 confusion came from a stealth scheme drift.

### Pick up the Email-link debug

Working tree has:
- `Carry/Services/AuthService.swift` — `linkEmailIdentity(password:, nonce:)` currently sends `UserAttributes(email: currentEmail, password:, nonce:)`. Latest experiment — untested.
- `Carry/Views/EmailLinkSheet.swift` — 2-step Send Code → enter code+password flow.
- 6 fresh `‼️AUTHDEBUG` NSLog lines in AuthService (added session 3).

**Step 1.** Sign out of the app → delete from phone (Keychain flush) → confirm scheme is `Carry-Dev` → Cmd+R → sign in with Apple.

**Step 2.** Run the Email-link flow on Carry-Dev. Capture the new AUTHDEBUG line: `linkEmailIdentity: server response id=...`. **Note that exact user ID** — that's your real dev user.

**Step 3.** Query dev (`gbhljwtbobbxervekxkg`) for that exact ID:
```sql
SELECT id, email, encrypted_password IS NOT NULL AS has_password,
       reauthentication_sent_at, reauthentication_token IS NOT NULL AS has_reauth_token,
       email_confirmed_at, raw_user_meta_data
FROM auth.users WHERE id = '<paste-the-user-id-here>';
```

**Outcomes & next moves:**
- If `reauthentication_sent_at` is NULL → `reauthenticate()` didn't actually fire server-side. Investigate SMTP / project config.
- If `reauthentication_sent_at` is set but `encrypted_password` is still NULL → password update step is rejecting silently. Check Supabase Auth logs in Studio for the PUT /user request body + response.
- If `encrypted_password` is set but `auth.identities` doesn't include email → confirmed Supabase doesn't add email identity rows retroactively. Pivot: rework `signInMethodRow` to drive the Email row's "Connected ✓" state off `currentUser.email != nil && hasPassword`, not the identities array. Add a `hasPassword: Bool` @Published to AuthService, refreshed by querying `auth.users.encrypted_password` via an RPC or by reading the user metadata directly.

### Fallback if Email-link can't be cracked

Pivot to path A: hide the Email row from SIGN-IN METHODS for 1.1.0, ship Apple+Google linking only. The change is small:
- ProfileSheetView.swift L290-293: remove the `signInMethodRow(label: "Email", ...)` block
- Optionally keep the EmailLinkSheet code path dormant for 1.1.1 (don't delete)

The auth-v2 quarantine doesn't require email linking; Apple+Google linking + dedupe trigger is the load-bearing scope.

### Then ship-prep (independent of Email-link decision)

1. Remove ALL `‼️AUTHDEBUG` NSLog lines:
   - `Carry/Services/AuthService.swift` lines around `mapAuthSignupError` (session 2 additions)
   - `Carry/Services/AuthService.swift` `requestEmailLinkCode` + `linkEmailIdentity` (session 3 additions, 6 lines)
   - `Carry/CarryApp.swift` line ~370 (session 2 addition)
2. Apply migration `20260515000000_dedupe_email_on_signup.sql` to prod via Studio SQL Editor.
3. Visual smoke of the Ask alert on Carry-Dev. The fake-row SQL is in §"Old how-to resume" below. Note: needs a Google account whose email matches the fake row's email, AND the Google picker must let you actually select that account (i.e., the account must NOT already be linked to your real dev user — if it is, sign out of that Google in Safari first).
4. Push `feature/auth-v2` to origin (`git push -u origin feature/auth-v2`).
5. Cut `release/1.1.0` from current `hotfix/1.0.9` tip, merge `feature/auth-v2`, bump `MARKETING_VERSION` → 1.1.0 + build number forward. Archive, submit.

## Old how-to resume (session 2 — superseded by session 4 above)

1. **Commit the session-2 work in tree**:
   - `Carry/Services/AuthNonce.swift` (new)
   - `Carry/Services/GoogleSignInService.swift` (nonce wiring)
   - `Carry/Services/AuthService.swift` (nonce + `PendingProviderLink` + `consumePendingLink` + `AuthError.emailAlreadyRegistered` + `mapAuthSignupError`; plus temp `‼️AUTHDEBUG` NSLog lines)
   - `Carry/Views/AuthView.swift` (Ask flow alert + Google handler restructure + Apple success → consumePendingLink hook)
   - `Carry/Views/EmailAuthSheet.swift` (signIn success → consumePendingLink hook)
   - `Carry/Views/ProfileSheetView.swift` (nonce forwarding through `linkGoogleFlow`)
   - `Carry.xcodeproj/project.pbxproj` (registers `AuthNonce.swift` — IDs `B10101` / `B10102`)
2. **Visual smoke of the Ask alert on dev** (~3 min, optional but completes the "I saw it" loop):
   - In dev Studio SQL Editor, plant a fake colliding apple user:
     ```sql
     DO $$
     DECLARE
         fake_user_id uuid := gen_random_uuid();
     BEGIN
         INSERT INTO auth.users (id, email, instance_id, aud, role)
         VALUES (fake_user_id, 'dsigvardsson@gmail.com', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
         INSERT INTO auth.identities (id, user_id, provider_id, provider, identity_data, created_at, updated_at)
         VALUES (gen_random_uuid(), fake_user_id, 'fake-test-' || fake_user_id::text, 'apple',
                 jsonb_build_object('sub', 'fake-test-' || fake_user_id::text, 'email', 'dsigvardsson@gmail.com'),
                 now(), now());
     END $$;
     ```
   - Sign out of Carry dev. Tap Google → pick `dsigvardsson@gmail.com`. Expect alert "Found your Carry account — sign in with Apple…" with [Sign in with Apple] [Cancel].
   - **Tap Cancel** (do NOT tap Sign in with Apple — that would link Google to your real Apple user, not the fake row).
   - Clean up: dev Studio → Auth → Users → delete `dsigvardsson@gmail.com`.
3. **Enable Email provider on dev Supabase** if you want to smoke-test the email flow too.
4. **Remove the `‼️AUTHDEBUG` NSLog lines** in `mapAuthSignupError` (small cleanup commit).
5. **Apply migration `20260515000000_dedupe_email_on_signup.sql` to prod** via Studio SQL Editor (paste contents → Run). Re-run the trigger verify query on prod to confirm.
6. **Push `feature/auth-v2` to origin** (`git push -u origin feature/auth-v2`).
7. **Cut `release/1.1.0`** from current `hotfix/1.0.9` tip + merge `feature/auth-v2` in. Bump MARKETING_VERSION to 1.1.0 + CURRENT_PROJECT_VERSION. Archive, submit.

## Operational footguns observed this session

- **iOS Keychain survives app deletion.** Deleting users from Supabase Studio while the iOS app has an active session JWT for that user causes "stuck on green splash" on next launch. Recovery: stop in Xcode → delete the app from the device → reinstall via Cmd+R. **Prevention: sign OUT of the app first, then delete the Studio user.** Reverse order leaves orphaned Keychain sessions.
- **`db push` is blocked by squash drift on dev** (the `20260101000000` baseline row vs the 58 individual migration files in the tree). Workaround: paste migration SQL into Studio SQL Editor manually. The proper fix is the squash reconciliation, which is its own session.

## Project refs (for SQL Editor / `supabase link`)

| | |
|---|---|
| Dev Supabase | `gbhljwtbobbxervekxkg` — `https://gbhljwtbobbxervekxkg.supabase.co` |
| Prod Supabase | `seeitehizboxjbnccnyd` — `https://seeitehizboxjbnccnyd.supabase.co` |
| Google Cloud project | `powerful-anchor-401116` (project number `501439459788`) |
| Google iOS OAuth client | `501439459788-g9auqo5f8rn5nellkuqehugmqae396lc` |
| Google Web OAuth client | `501439459788-pc4dc3etr2ipqt58u9rr9kpd5oqnt907` |

## Related docs
- `docs/google-email-auth-setup.md` — original setup checklist (April work) + dev/prod migration workflow
- `docs/architecture/onboarding-and-auth.md` — onboarding flow + Apple sign-in details
- `docs/architecture/account-linking.md` — linking spec (was written when linking code was thought to be unbuilt; the spec is still accurate)
- `docs/dev-branch-fix.md` — squash drift background
- `memory/feedback_auth_v2_quarantine.md` — the 3 quarantine gates
- `memory/auth_v2_uuid_mismatch_finding.md` — open finding + investigation SQL
- `memory/auth_expansion_state.md` — the April 30 EOD snapshot that pointed us to `stash@{3}`
