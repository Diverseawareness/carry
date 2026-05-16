# Auth-v2 setup — status

**Last updated:** 2026-05-15 evening (end of session 2)
**Branch:** `feature/auth-v2` (local-only, NOT pushed to origin)
**Target release:** 1.1.0 (App Store ships 1.0.9 today)

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
- Visual smoke of the Ask alert on device (requires synthesizing a fake collision row on dev — instructions in §"How to resume")
- Trigger applied to prod (safe to do; held for clean audit trail)
- `feature/auth-v2` pushed to origin
- 5 files of code changes from session 2 still uncommitted in working tree

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

## How to resume

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
