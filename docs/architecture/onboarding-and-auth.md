# Onboarding + Authentication

**TL;DR:** Three-state launch gate (`isLoading` → `!isAuthenticated` → `!isOnboarded` → main). Apple Sign In is only prod path. Auth-v2 (Google + email + linking) on `feature/auth-v2`, quarantined. Profile creation: server `handle_new_user` trigger (primary) + AuthService PGRST116 fallback (catch-all).

## Launch routing

[CarryApp.swift:148-149](../../Carry/CarryApp.swift:148): `@main struct CarryApp` with `@StateObject private var authService = AuthService()`.

Root view gated at [CarryApp.swift:276-306](../../Carry/CarryApp.swift:276):

| State | Render |
|---|---|
| `authService.isLoading` | Splash: `Color.white` + `GolfBallLoader(size: 60)` ([:278-282](../../Carry/CarryApp.swift:278)) |
| `!isAuthenticated` | `AuthView()` |
| `!isOnboarded` | `OnboardingView()` |
| else | `MainTabView()` |

`isLoading = true` during initial `checkSession()` ([AuthService.swift:55, :85-128](../../Carry/Services/AuthService.swift:55)).

## Three flags driving the gate

| Flag | Source | Set by |
|---|---|---|
| `isAuthenticated` | `@Published` on AuthService | `checkSession()` if `client.auth.session` returns; `signInWithApple` on success; `signOut()` clears |
| `isOnboarded` | `@Published` on AuthService | `loadProfile(userId:)` if `hasValidProfile`; OnboardingView's `completeOnboarding(...)` flip |
| `hasCompletedOnboarding` | UserDefaults `onboardingCompleted` ([AuthService.swift:61-62](../../Carry/Services/AuthService.swift:61)) | Set true at [AuthService.swift:301](../../Carry/Services/AuthService.swift:301) post profile save; cleared in `deleteAccount()` |
| `hasValidProfile` | Computed: `displayName != "" && (homeClubId != nil || homeClub != "")` ([AuthService.swift:70-83](../../Carry/Services/AuthService.swift:70)) | Read in `loadProfile`; if true, sets UserDefaults flag opportunistically |

`hasCompletedOnboarding` is historical. `hasValidProfile` is the resilience check (uninstall+reinstall with valid server profile skips onboarding). Two flags converge: first valid-profile load sets UserDefaults flag retroactively.

## Apple Sign In (current prod path)

[AuthView.swift:70-80](../../Carry/Views/AuthView.swift:70) — `SignInWithAppleButton(.signIn)` requesting `.fullName` + `.email`. On success → `handleSignIn(result:)`.

[AuthService.swift:132-143](../../Carry/Services/AuthService.swift:132) `signInWithApple(credential:)`:

| # | Action |
|---|---|
| 1 | Extract `identityToken` from `ASAuthorizationAppleIDCredential` |
| 2 | `client.auth.signInWithIdToken(provider: .apple, idToken: tokenString)` (Supabase SDK validates nonce + signature) |
| 3 | Success → `loadProfile(userId:)` runs; profile created via trigger OR fallback |

[AuthService.swift:145-173](../../Carry/Services/AuthService.swift:145) — Apple-specific enrichment: stores `firstName` / `lastName` / `email` from credential. **Apple returns name + email on FIRST sign-in only.** Subsequent sign-ins return only the user identifier.

Routing post-signin ([AuthService.swift:191-198](../../Carry/Services/AuthService.swift:191)):

| Condition | Branch |
|---|---|
| `!hasValidProfile` (first-timer) | `isNewUser = true`, route to OnboardingView |
| `hasValidProfile` (returner) | `isOnboarded = true`, route to MainTabView; immediately `NotificationService.shared.requestPermissionAndRegister()` |

## Onboarding flow

[OnboardingView.swift:5-174](../../Carry/Views/OnboardingView.swift:5) — 4-or-5-step flow.

| Apple returned name? | Steps |
|---|---|
| Yes (`hasAppleName = true`) | 4: golfProfile → phone → notification → disclaimer |
| No | 5: name → golfProfile → phone → notification → disclaimer |

`onAppear` at [OnboardingView.swift:131-154](../../Carry/Views/OnboardingView.swift:131) checks `authService.currentUser.firstName` / `displayName` and adapts `totalSteps`.

### Phone step

| Property | Value |
|---|---|
| Position | `isPhoneStep` index 1 (with Apple name) or 2 (without) at [OnboardingView.swift:42-46](../../Carry/Views/OnboardingView.swift:42) |
| Validation | digits-only, 10+ chars at [:325-328](../../Carry/Views/OnboardingView.swift:325) |
| Persistence | `completeOnboarding(phone:)` at [:347](../../Carry/Views/OnboardingView.swift:347) |

### Completion + reconciliation

| Step | Code |
|---|---|
| Set onboardingCompleted | [AuthService.swift:301](../../Carry/Services/AuthService.swift:301) — `UserDefaults.standard.set(true, forKey: "onboardingCompleted")` |
| `claimPhoneInvitesIfNeeded()` | [CarryApp.swift:373-396](../../Carry/CarryApp.swift:373). Called post-onboarding ([:290](../../Carry/CarryApp.swift:290)) AND on every session restore ([:302](../../Carry/CarryApp.swift:302)) |
| Logic | `groupService.checkPhoneInvites(phone:)` returns pending → for each match, `claimPhoneInvite(membershipId:realPlayerId:)` flips invite to `active` |
| Modal popup | Deferred. Not popped on launch in 1.0.5+; manual entry preserved in Profile → Support |
| 30-day staleness guard | [20260502000002:98](../../supabase/migrations/20260502000002_phone_on_profile.sql:98) — only auto-claims invites <30 days |

## Profile creation — two paths

### Path A: server trigger (primary)

[20260322000000_complete_base_schema.sql:316-358](../../supabase/migrations/20260322000000_complete_base_schema.sql:316) — `handle_new_user()` trigger AFTER INSERT on `auth.users`:

- Creates `profiles` row with `first_name`, `last_name`, `display_name`, `initials`, `email`, `color`, `avatar`, `handicap = 0.0`
- Pulls metadata from Apple credential / Supabase `raw_user_meta_data`

### Path B: AuthService fallback (catch-all)

[AuthService.swift:401-441](../../Carry/Services/AuthService.swift:401) — `loadProfile(userId:)`:

- Selects `profiles` row by `id = auth.uid()`
- On `PGRST116` ("Cannot coerce single JSON object" → no row found): INSERT minimal fallback (`display_name = "Player"`, `initials = "P"`)
- Catches case where trigger silently fails. Observed on dev 2026-05-05 during first Apple sign-in

Both paths converge on same row shape. OnboardingView's `completeOnboarding` always UPDATEs (never INSERTs).

### `profiles` row shape

[20260322000000_complete_base_schema.sql:12-46](../../supabase/migrations/20260322000000_complete_base_schema.sql:12):
```
id (uuid, FK auth.users.id), first_name, last_name, display_name (default 'Player'),
initials, email, phone, handicap (default 0.0), home_club, home_club_id, is_club_member,
avatar, avatar_url, username, color, device_token, updated_at, is_guest
```

`is_guest = false` for Carry users; `true` for Quick Game ephemeral guests.

## Session lifecycle

| Operation | Code |
|---|---|
| Initial restore | `checkSession()` at [AuthService.swift:85-128](../../Carry/Services/AuthService.swift:85) |
| Token refresh | Supabase SDK internal; `client.auth.session` triggers refresh on read |
| Sign out | [AuthService.swift:366-374](../../Carry/Services/AuthService.swift:366) — clears `isAuthenticated`, `isOnboarded`, `currentUser`; `client.auth.signOut()` |
| Account deletion | [AuthService.swift:378-397](../../Carry/Services/AuthService.swift:378) — `client.rpc("delete_user_account")`, signs out, clears UserDefaults `onboardingCompleted` |

## APNs registration

| Step | Code |
|---|---|
| Device token received | [CarryApp.swift:59-68](../../Carry/CarryApp.swift:59) — `didRegisterForRemoteNotificationsWithDeviceToken` converts to hex |
| Persist | [NotificationService.swift:64-79](../../Carry/Services/NotificationService.swift:64) — UPDATEs `profiles.device_token` |
| Trigger | [AuthService.swift:120](../../Carry/Services/AuthService.swift:120) — returner/onboarded calls `NotificationService.shared.requestPermissionAndRegister()` post-signin |
| Stale token cleanup | Edge function on APNs 410 / BadDeviceToken — see [push-trigger-chain.md](push-trigger-chain.md) |

### Dev vs prod entitlement split (incomplete)

[Carry/Carry.entitlements:6](../../Carry/Carry.entitlements:6): `<aps-environment>production</aps-environment>`.

TODO: dev scheme needs `Carry-dev.entitlements` with `aps-environment = development`. Without it: dev builds with prod key get 400 BadDeviceToken from sandbox APNs. See MEMORY.md "Next session pickup" 2026-05-07.

Server-side: dev project secret `APNS_PRODUCTION` must be `false` for sandbox tokens.

## Telemetry

| Event | Source |
|---|---|
| `user_signed_in` | [AuthService.swift:185](../../Carry/Services/AuthService.swift:185) post Apple sign-in |
| `onboarding_completed` | [AnalyticsService.swift:61-62](../../Carry/Services/AnalyticsService.swift:61) |
| `welcome_email_sent` / `welcome_email_failed` | [AnalyticsService.swift:67-75](../../Carry/Services/AnalyticsService.swift:67) |

PostHog US cloud. See project memory `posthog_setup.md`.

## Auth-v2 — extension points (NOT in `main`)

`feature/auth-v2` branch contains uncommitted scaffolding for Google + email + linking. **Do not merge to `main` or any `release/*` branch.** See quarantine invariant.

| Component | File | Notes |
|---|---|---|
| Google sign-in service | `GoogleSignInService.swift` | Wraps GoogleSignIn-iOS SDK. `signIn(presenting:)` returns idToken + accessToken |
| Google in AuthService | `AuthService.swift` (auth-v2) ~L209 | `signInWithGoogle(idToken:accessToken:)` → `client.auth.signInWithIdToken(provider: .google, ...)` |
| Email auth sheet | `EmailAuthSheet.swift` | Sign In / Sign Up segmented picker; email + password |
| Email signup/signin | `AuthService.swift` (auth-v2) ~L234-243 | `signUpWithEmail`, `signInWithEmail` |
| Password reset | `AuthService.swift` (auth-v2) ~L244 | `sendPasswordReset(email:)` redirects to `carryapp.site/reset` |
| AuthView multi-button | `AuthView.swift` (auth-v2) ~L55-90 | Email + Google + Apple buttons. **No feature flag yet** |
| Account linking UI | `ProfileSheetView.swift` (auth-v2, 1888 lines) | Link/unlink Apple+Google. UNTESTED |

### Plug-in checklist for new auth providers

| # | Action |
|---|---|
| 1 | Add `AuthService` method mirroring `signInWithApple(credential:)` — call `client.auth.signInWithIdToken(provider:..., idToken:..., accessToken:...)` |
| 2 | Both `handle_new_user` (server) + AuthService PGRST116 fallback auto-create profile — no special-casing |
| 3 | Add button to `AuthView`. Route through `handleSignIn(result:)` style |
| 4 | Linking is different: it adds an identity to existing `auth.users` row (not new user). Supabase SDK exposes `linkIdentity(provider:)`. UI in `ProfileSheetView` (auth-v2) |
| 5 | Verify post-signin routing: returner with valid profile → main; first-timer → onboarding. `hasValidProfile` is provider-agnostic |
| 6 | PostHog events: pipe provider name through existing `user_signed_in` or add per-provider events |

### UUID mismatch (open finding 2026-05-03)

MEMORY.md `auth_v2_uuid_mismatch_finding.md` — keeper profile UUID may not match Apple-linked auth row UUID. Investigate before resuming linking smoke tests; mismatch on link orphans linked user's groups/rounds.

## Living invariants

### 🔒 Auth-v2 quarantine

Google / Email / account-linking code never merges to `main` or `release/*` until ALL of:

| # | Condition |
|---|---|
| 1 | Linking built AND tested end-to-end (link Apple → Google round-trip, unlink, sign back in via either) |
| 2 | Separate dev DB exists (Supabase Pro dev branch) — **satisfied 2026-05-05** |
| 3 | UUID mismatch finding resolved |

Source: project memory `feedback_auth_v2_quarantine.md`. Missing this caused the 2026-05-01 prod incident.

### 🔒 First-time vs returner routing

After any auth call succeeds, route by `hasValidProfile`. No provider-specific routing.

### 🔒 Phone is optional but stable

Phone step allows skip. Once entered, value flows through `reconcile_phone_invites_for_profile` trigger. Don't bypass that trigger from any client path.

### 🔒 Profile creation has two paths and must converge

Both `handle_new_user` and PGRST116 fallback must end with same post-condition: `profiles` row keyed by `auth.uid()` with `display_name` + `initials`. Drift = dev-only bugs.

## Common bugs / gotchas

| Bug | Notes |
|---|---|
| `handle_new_user` silently doesn't fire | Observed dev 2026-05-05. AuthService PGRST116 fallback catches. If "Cannot coerce single JSON object" in logs WITHOUT fallback INSERT, fallback itself broke. Check `pg_trigger` |
| Apple credential returns nil name on second sign-in | By design. Don't overwrite stored name with nil; update only if non-nil |
| Dev token + prod APNs key = 400 BadDeviceToken | Apple signing tier mismatch. Fix: per-environment entitlements + `APNS_PRODUCTION` secret |
| `hasValidProfile` evaluates after fallback | If trigger lags, fallback inserts minimal row first. `hasValidProfile` then false → routes to onboarding. Correct, but user briefly sees "Player" placeholder name in profile UI |
| Sign out doesn't clear all UserDefaults | `onboardingCompleted` survives. Different user signing in: if their profile is valid, skip onboarding; else show. Stale UserDefaults can drop returning user at wrong step |
| Account deletion DOES clear `onboardingCompleted` | [AuthService.swift:378-397](../../Carry/Services/AuthService.swift:378). Correct — next account on device should onboard |

## Last verified

2026-05-10 — converted to machine-readable format. Apple-only path is only prod-active flow.
