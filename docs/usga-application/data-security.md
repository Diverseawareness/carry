# Carry — Data Security Documentation

**Applicant:** Diverse Awareness Inc.
**Product:** Carry — Golf Skins Tracker (iOS)
**Prepared for:** USGA Golfer Product Access (GPA) Program
**Last updated:** April 2026

## 1. Architecture Overview

Carry is a native iOS application with a cloud backend hosted on Supabase. There are no other data processors or service providers that receive GHIN-related personal data.

```
iOS Client ── HTTPS/TLS 1.3 ──▶ Supabase Edge Functions ── OAuth ──▶ GHIN API
                │                        │
                │                        ▼
                │                 Postgres (RLS)
                │
                └── Apple Push Notification service (device token only)
```

- **Client:** iOS 17.0+, Swift/SwiftUI
- **Backend:** Supabase (managed Postgres + edge functions, hosted in the United States)
- **Identity:** Apple Sign-In (OAuth 2.0)
- **Payments:** Apple StoreKit (handled entirely by Apple; no payment data touches Carry)

## 2. Authentication

- Users sign in exclusively via **Sign in with Apple**. Carry does not handle passwords.
- Apple returns a signed identity token that Supabase verifies against Apple's public keys.
- Supabase issues a session JWT scoped to the user; all subsequent API calls must present this JWT.
- JWTs expire on a rolling basis (1-hour access token, refresh token rotated on each refresh).
- GHIN API credentials (client ID / secret) are held exclusively in the Supabase edge function environment, never exposed to the client.

## 3. Data In Transit

- All client ↔ server traffic uses **HTTPS with TLS 1.3** (TLS 1.2 minimum; App Transport Security enforced).
- All server ↔ GHIN traffic uses HTTPS with certificate validation.
- All server ↔ APNs traffic uses HTTP/2 with token-based auth (p8 key, not certificate-based).
- Carry does not pin certificates beyond what iOS provides by default; we rely on the system certificate store.

## 4. Data At Rest

- **Supabase Postgres** uses AES-256 encryption at rest managed by the hosting provider.
- **Avatar photos** stored in Supabase Storage, encrypted at rest.
- **iOS local cache** stored in the app's sandboxed container. Sensitive values (auth tokens) are stored in the iOS Keychain with `kSecAttrAccessibleAfterFirstUnlock` access control. Scores and group state are stored in app-container files and are not exposed outside the app's sandbox.

## 5. Access Controls

### 5.1 Row-Level Security (RLS)

All tables in the Supabase database have **row-level security (RLS) enforced**. Access policies ensure:

- A user can read and write only their own `profiles` row.
- A user can access `skins_groups` rows only if they are an active or invited member.
- A user can access `rounds`, `round_players`, and `scores` only for rounds in groups they belong to.
- Public/unauthenticated access is denied on every table.

RLS policies are defined in version-controlled SQL migrations and tested before deployment. The most recent policy audit (April 2026) closed an edge-case recursion issue in group membership lookups via a `SECURITY DEFINER` helper function.

### 5.2 Edge Function Access

- GHIN API calls are gated behind an authenticated edge function. A user must present a valid Supabase JWT to trigger a GHIN lookup, and they can only look up data associated with their own authenticated identity.
- Service role keys and GHIN OAuth credentials are stored in Supabase secret environment variables, not in source control.

### 5.3 Administrative Access

- Backend administrative access is limited to the Diverse Awareness Inc. founder (one person at time of writing).
- Access to the Supabase dashboard requires a password and 2FA.
- There is no customer support team with database access.

## 6. Data Minimization

Carry collects only the data required to operate the product:

| Data | Source | Purpose |
|------|--------|---------|
| Name, email | Apple Sign-In (per user's Apple privacy choice) | Account identification |
| GHIN number | User-entered | GHIN API lookup key |
| Handicap Index | GHIN API or manual entry | Net score calculation |
| Home golf club | User-entered | Profile display, course preselection |
| Scores, round metadata | User-entered during play | Scorekeeping, leaderboards |
| Avatar photo | User-selected (optional) | Profile display |
| Device push token | APNs (on permission grant) | Game event notifications |

We do **not** collect: precise location, contacts, phone numbers (SMS is native-only), financial data, browsing activity, advertising identifiers, or third-party cross-app tracking identifiers.

## 7. GHIN-Specific Data Handling

When Carry fetches GHIN data for a user:

- **Handicap Index** is stored in the `profiles.handicap` column. It is cached locally for offline use during a round and refreshed from GHIN on next online session.
- **GHIN number** is stored in `profiles.ghin_number`, only after the user explicitly provides it. It is never displayed to other users.
- **Course/slope data** returned from GHIN is cached transiently; no golfer-specific data is retained from a course lookup.
- **Golfer name lookups** (for verification) are not stored — the result of the match is kept as a boolean flag.

Data derived from GHIN is treated at the same security level as data the user provided directly.

## 8. Data Retention and Deletion

- **Account data** is retained for the lifetime of the account.
- **Account deletion** is available in-app (Profile → Account → Delete Account). Upon request:
  - Personal data is removed from active database within 30 days
  - Encrypted backups are rotated out within 90 days
  - The user's GHIN number and cached Handicap Index are deleted with the account
- The in-app deletion is implemented via a database function (`delete_user_account`) that cascades across all owned rows.

## 9. Logging and Monitoring

- **Edge function logs** are retained 30 days in Supabase's managed logging. Logs record request metadata (user ID, endpoint, timestamp, response status) but not request/response bodies.
- **Client-side crash reports** are captured via PLCrashReporter and uploaded anonymously (no user identifiers tied to the crash).
- **Product analytics** are captured via PostHog in anonymized form; user IDs are hashed, and no Handicap Index, GHIN number, or scores are sent to PostHog.

## 10. Third-Party Processors

| Processor | Data Handled | Location | Purpose |
|-----------|--------------|----------|---------|
| Supabase Inc. | All user data | United States | Database, auth, edge functions |
| Apple Inc. | Name, email (hashed relay optional), device token | Worldwide | Identity, push |
| PostHog | Anonymized usage events | United States | Product analytics |

None of these processors receive data from GHIN. GHIN data stays within Carry's Supabase environment and the iOS client.

## 11. Incident Response

In the event of a suspected data breach:

1. Affected systems are taken offline or tokens revoked immediately
2. Scope is determined via audit logs
3. Affected users notified within 72 hours via email and in-app banner
4. USGA notified per GPA Program requirements if GHIN data is implicated
5. Post-incident review and corrective measures documented

Contact for security incidents: daniel@diverseawareness.com

## 12. Compliance Posture

- **COPPA:** Carry is not directed at children under 13. Apple Sign-In enforces minimum age requirements and our Terms of Service require users to be 13+.
- **GDPR / UK-GDPR:** Users in the EEA/UK have access to data subject rights (access, rectification, erasure, portability, objection) as described in our published Privacy Policy, Section 11.
- **CCPA:** California residents have access to data subject rights as described in our published Privacy Policy, Section 10.
- **Apple Developer Program License Agreement:** Carry operates in compliance with current Apple policies including App Tracking Transparency (no tracking) and Privacy Manifest requirements.

## 13. References

- Carry Privacy Policy: https://carryapp.site/privacy.html
- Carry Terms of Service: https://carryapp.site/terms.html
- Supabase Security: https://supabase.com/security
- Apple Platform Security: https://www.apple.com/platform-security/

## 14. Contact

Diverse Awareness Inc.
Attn: Daniel Sigvardsson
daniel@diverseawareness.com
https://carryapp.site
