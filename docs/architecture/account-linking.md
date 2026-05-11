# Account Linking (auth-v2 — NOT IN PROD)

**TL;DR:** Single Carry user with multiple sign-in identities (Apple + Google + Email). Currently scaffolded on `feature/auth-v2` but **not built**. Doc captures present state, missing pieces, and design constraints. **Status: incomplete, untested. Do NOT merge to `main` or `release/*`.** See [onboarding-and-auth.md](onboarding-and-auth.md) §Auth-v2 quarantine.

## What linking is

Supabase Auth supports multiple identities per `auth.users` row. Each identity = one provider (Apple, Google, Email/password). Profile (`profiles` row keyed by `auth.uid()`) is shared across all identities.

| Operation | Definition |
|---|---|
| Link | Add a second identity to an existing `auth.users` row. Same `auth.uid()`, same profile, same data |
| Merge | Combine two existing `auth.users` rows into one. Reassign profiles + FKs. NOT in scope (see below) |

User signs up with Apple, later signs in with Google → ends up at same `auth.uid()`, same profile/groups/rounds/scores.

## Current state on `feature/auth-v2`

| Component | File | Status |
|---|---|---|
| Apple Sign In path (active in prod) | `AuthService.swift` | Solid; provider-agnostic finish via `finishProviderSignIn(userId:providerLabel:)` |
| Google Sign In service | `GoogleSignInService.swift` | Wraps GoogleSignIn-iOS SDK |
| Google in AuthService | `AuthService.swift` (auth-v2 ~L209) | `signInWithGoogle(idToken:accessToken:)` calls `signInWithIdToken(provider: .google, ...)` |
| Email / password | `EmailAuthSheet.swift` + `AuthService.swift` (~L234-244) | `signUpWithEmail`, `signInWithEmail`, `sendPasswordReset` |
| AuthView multi-button | `AuthView.swift` (auth-v2 ~L55-90) | Apple + Google + Email buttons. **No feature flag** |
| **Linking UI** | `ProfileSheetView.swift` (auth-v2, 1888 lines) | Stub or incomplete; no "Connected Accounts" row clearly visible |
| **Linking handlers** | `AuthService.swift` (auth-v2) | **No `linkIdentity` or `unlinkIdentity` methods detected** |

Sign-in for all three providers is built. Linking-as-an-action is not. Today, signing in with Google after Apple would create a NEW `auth.users` row, not link.

## Design constraints

### 1. Profile must follow linked identity

When user A (Apple) signs in via Google for the first time, Supabase needs:

| # | Action |
|---|---|
| 1 | Verify Google identity belongs to user A (linking, not new account) |
| 2 | Add Google identity to existing `auth.users` row |
| 3 | Return same JWT / `auth.uid()` |
| 4 | NOT create duplicate `profiles` row |

Supabase `linkIdentity()` API handles 1-3. Step 4 happens automatically — `handle_new_user` trigger fires only on INSERT to `auth.users`; linking doesn't INSERT.

### 2. Linking requires authenticated session

Can't link two anonymous identities. User must be signed in with Identity A first; link adds Identity B.

UI implication: "Connect Google" button in ProfileSheetView (Settings), NOT AuthView. Linking from pre-signin requires a different flow (claim/merge).

### 3. Linking wrong account orphans data

If user A (Apple, with 5 groups + history) accidentally links a Google identity that's already on another `auth.users` row → either link fails OR one set of data is orphaned.

The 2026-05-03 UUID mismatch finding (MEMORY.md `auth_v2_uuid_mismatch_finding.md`): keeper profile UUID didn't match Apple-linked auth row UUID. Linking in this state would orphan data. Investigate before resuming.

### 4. Unlinking must preserve a way back in

If user A has Apple + Google + Email linked, unlinking Apple must leave at least one working sign-in. Supabase enforces server-side. UI must reflect: "unlink" disabled if it would leave user with no sign-in path.

### 5. Email/password is most fragile

Apple + Google identities validated by provider. Email/password requires:

| Component | Notes |
|---|---|
| Email verification | Or Supabase magic link |
| Password reset | `sendPasswordReset` redirect to `carryapp.site/reset` |
| Password change | UX in Settings |

If Email is the ONLY identity (no Apple or Google), losing the password = losing the account. Email-as-primary should offer "set up a backup identity."

## Edge cases auth-v2 must handle

| Edge case | Required behavior |
|---|---|
| Apple-signed user taps Connect Google → Google identity exists on different `auth.users` | Block + "this Google account is already in use; sign out and try signing in with Google" |
| Apple-signed user taps Connect Email → email already on different `auth.users` | Same as above |
| User links Google then unlinks Apple → only Google remains | Allowed |
| User links Google then unlinks Google | Allowed |
| User with Apple + Google linked signs out, signs back in via Google | Returns to same profile via provider-agnostic finish |
| Apple credential returns nil name on second sign-in (post-linking) | Don't overwrite stored name |
| Sign in via Google for brand-new user (no Apple history) | Standard new-user: `handle_new_user` creates profile, OnboardingView starts |

## What "merge" means (NOT in scope)

Combine two existing `auth.users` rows. Required when user created Apple account, then signed in with Google BEFORE linking → ended up with two profiles.

Order of magnitude harder. Requires:

| Step | Notes |
|---|---|
| Reassign `profiles` rows | Multi-FK references (groups, rounds, scores) |
| Resolve identity conflicts | Whose name wins? |
| Re-key foreign keys | `group_members.player_id`, `rounds.created_by`, etc. |
| Push notifications | `device_token` on profiles |
| Rollback on failure | Postgres transaction across multiple tables |

**Not part of auth-v2 scope.** Duplicate accounts → manual support path (delete unwanted one). Build linking correctly first try; merge stays out of scope.

## Implementation checklist (when resuming)

Before merging linking to main, ALL of:

| # | Item |
|---|---|
| 1 | `linkIdentity(provider:)` on AuthService — calls Supabase `signInWithOAuth(...)` with `redirectTo` to capture link |
| 2 | `unlinkIdentity(identityId:)` calls Supabase `unlinkIdentity(...)` + refreshes session |
| 3 | "Connected Accounts" UI row in ProfileSheetView with unlink button per identity |
| 4 | Disable unlink for last remaining identity (server-side check + UI gate) |
| 5 | Email verification flow for newly-linked email |
| 6 | Smoke tests on dev DB: link Apple→Google→unlink Apple→sign in Google→same profile; link Apple→Email→set password→sign in Email→same profile; try link in-use Google→error toast; try unlink last→disabled |
| 7 | UUID mismatch investigation (2026-05-03) resolved |
| 8 | Push test: `device_token` preserved across linking |
| 9 | Telemetry: `account_linked` + `account_unlinked` PostHog events with `provider` field |

All checked → merge auth-v2 → main. Bump version, archive, ship.

## Quarantine invariant

🔒 Locked, project memory `feedback_auth_v2_quarantine.md`:

Google / Email / account-linking code never merges to `main` or `release/*` until ALL:

| # | Condition |
|---|---|
| 1 | Linking built AND tested end-to-end |
| 2 | Separate dev DB exists (Supabase Pro dev branch) — **satisfied 2026-05-05** |
| 3 | UUID mismatch finding resolved |

Missing this caused the 2026-05-01 prod incident.

## Common bugs / gotchas (anticipated)

| Bug | Notes |
|---|---|
| Two devices link simultaneously | Race between two `linkIdentity` calls. Supabase serializes; second fails with "already linked." UI must handle error + refresh linked-list display |
| Linking after token refresh | Stale JWT may fail. Re-call `client.auth.session` first |
| Email link to email already in `profiles.email` on another row | `linkIdentity` enforces identity uniqueness; `profiles.email` not unique by default. Link succeeds but leaves inconsistent denormalization. Consider server-side check |
| Sign-out clears in-memory state | `currentUser` linked-identities list must reload on next sign-in. Don't cache stale |

## Last verified

2026-05-10 — converted to machine-readable format. Auth-v2 branch state: linking code NOT present. Doc is spec for upcoming work.
