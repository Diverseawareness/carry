# Auth-v2 setup — status

**Last updated:** 2026-05-15 (mid-session)
**Branch:** `feature/auth-v2` (local-only, NOT pushed to origin)
**Target release:** 1.1.0 (App Store ships 1.0.9 today)

## TL;DR

`feature/auth-v2` is rebased on `hotfix/1.0.9` and contains:
- The Google + Email sign-in scaffold (April 30 work)
- Account-linking code restored from `stash@{3}` (was uncommitted since May 2)
- Password-recovery web page at `carryapp.site/reset`
- Cross-provider email-collision dedupe (server trigger + iOS error mapping)
- Toast-overlay fix so `ForgotPasswordView`'s confirmation toast renders inside `EmailAuthSheet`

Dedupe trigger is **live on the dev Supabase branch** (`gbhljwtbobbxervekxkg`).
Google provider is **enabled on the dev branch**.
**Not yet smoke-tested.** Not yet pushed to origin. Not yet applied to prod.

## What was decided this session

1. **Dropped `feature/dev-push-setup` work** from the auth-v2 rebase (Carry-dev.entitlements, widgets scheme, " · DEV" suffix in ProfileSheetView). Per Daniel: "don't bring back anything except the auth stuff." The dev-push-setup branch still exists for later if real-device push testing on dev becomes a need.
2. **Dropped `09409fd` infra commit** (`supabase/config.toml` + reload tooling). Same "auth only" rule.
3. **Reset and cherry-picked** instead of straight-rebasing. The straight rebase tried to replay the `46bd922` hotfix/1.0.3 bundle commit (already in hotfix/1.0.9 under a different SHA) and conflicted on dozens of files. Cleaner: reset auth-v2 to hotfix/1.0.9 + cherry-pick only the 4 auth-original commits, then re-apply the linking stash on top.
4. **Web-only password reset page** (`site/reset/index.html`), not a native deep-link intercept. The redirect URL Daniel chose in April was a web URL; the web page works everywhere (browser, desktop, no-app-installed). Native intercept can be added later if desired.
5. **Server-side dedupe trigger** (not iOS-side pre-check). Pre-check has a TOCTOU race and is bypassable by other clients; server trigger is the structural fix per the playbook's "no patches" rule.
6. **Migration applied to dev via Studio SQL Editor**, not `supabase db push`. The squash drift from May still blocks `db push` (DB has the baseline tracking row, local tree has 58 individual migration files). Squash reconciliation is its own task — out of scope for this session.

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
- `AuthService.signInWithGoogle` — token exchange + profile backfill from Google metadata + provider-agnostic post-auth wrap. Wrapped in `mapAuthSignupError` to translate the dedupe trigger's exception.
- `AuthService.signUpWithEmail` — same wrap; throws `AuthError.emailConfirmationPending` when Supabase requires email confirmation
- `AuthService.signInWithEmail` — no wrap (sign-in doesn't insert rows, trigger doesn't fire)
- `AuthService.sendPasswordReset` — redirects to `https://carryapp.site/reset`
- `AuthService.handleAuthCallback(url:)` — exchanges the Universal Link callback URL for a session, backfills profile from user_metadata
- `AuthService.linkAppleIdentity / linkGoogleIdentity / unlinkProvider` — with `LinkError` (last-identity guard, alreadyLinked, alreadyLinkedToOtherUser, underlying)
- `AuthService.refreshIdentities` — populates `@Published var identities: [UserIdentity]`, auto-called from `checkSession` and `finishProviderSignIn`
- `AuthView` — Email + Google + Apple button stack; Google handler catches `AuthError`
- `EmailAuthSheet` — segmented Sign In / Sign Up, check-email confirmation state, forgot-password navigationDestination, `.carryToastOverlay()` so toasts render inside the sheet
- `ForgotPasswordView` — Figma 1370:3502 layout, fires `ToastManager.shared.success / .error`
- `ProfileSheetView` — SIGN-IN METHODS section above DATA with Apple + Google rows, Connect/Disconnect confirmation dialog
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
- **iOS smoke test on dev** — Apple sign-in (with Share My Email) → sign out → try Google with same email → expect "use Apple instead" copy + no new user row
- **Pre-existing duplicate cleanup on prod** — the May 1 `dsigvardsson@gmail.com` double-row needs manual reconciliation before the trigger ships. Verification query is in the migration footer.
- **UUID-mismatch resolution** — quarantine gate; SQL ready in `memory/auth_v2_uuid_mismatch_finding.md`, not yet run. Result determines whether smoke testing on Daniel's own account is reliable.
- **Apply migration to prod** — held until smoke test passes. (Safe technically; held for clean audit trail.)

### Deferred design decisions
- **Email row in SIGN-IN METHODS section** — left out of ProfileSheetView when linking was first built (Apple + Google only). Decision: stub "Email — coming soon" or build set-password + verify flow? Not blocking 1.1.0 if shipped Apple+Google only initially.
- **Native deep-link intercept for password reset** — current path is pure web. Could add `/reset*` to AASA + an in-app "set new password" sheet for the iOS-with-app-installed case. Web is fallback for browser/desktop/no-app users. Not blocking.
- **Squash drift reconciliation** — out of scope for this session. The dev Supabase has the `20260101000000` baseline tracking row but local tree has 58 individual files. `supabase db push` is blocked; Studio SQL Editor is the workaround. Needs a dedicated session.

### Operational
- **Push `feature/auth-v2` to origin** — held. Branch is local-only until Daniel approves.
- **Delete `feature/auth-v2-backup-2026-05-15`** — kept as safety net until Xcode build on dev scheme is verified clean.
- **Drop `stash@{3}`** — kept until same point. (Stash content is already committed as `92d61de`.)
- **Email provider on dev Supabase** — not enabled yet. Need it before testing the Email/password flow end-to-end.

## How to resume

1. **Run the iOS smoke test** (see "Blocking 1.1.0 ship" above)
2. If smoke green, **run the UUID-mismatch SQL** from `memory/auth_v2_uuid_mismatch_finding.md`
3. If smoke red, paste the result + we adjust `mapAuthSignupError` parsing or the trigger
4. Then **prod cleanup** for pre-existing dups
5. Then **enable Email provider** on dev + repeat smoke test for email signup
6. Once everything's green, **push to origin** + start cutting `release/1.1.0` from current `hotfix/1.0.9` tip + merge auth-v2 in

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
