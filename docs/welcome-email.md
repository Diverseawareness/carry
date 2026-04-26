# Welcome Email — How It Works

Plain-text welcome email sent automatically the first time a user finishes onboarding.

## Tech stack

| Layer | Service | Purpose |
|---|---|---|
| Sender | [Resend](https://resend.com) | Transactional email API (us-east-1 region) |
| Server | Supabase Edge Function (Deno) | Validates the user's session and calls Resend |
| Client | iOS app (Swift) | Fires the request after onboarding completes |
| DNS | Cloudflare | Hosts the `carryapp.site` zone (DKIM, SPF, MX, DMARC) |
| Domain registrar | Enom | Points `carryapp.site` nameservers to Cloudflare |

## End-to-end flow

```
iOS app                  Supabase Edge Function           Resend API           User inbox
   │                              │                          │                     │
   │ 1. completeOnboarding()      │                          │                     │
   │    succeeds                  │                          │                     │
   │                              │                          │                     │
   │ 2. POST /functions/v1/       │                          │                     │
   │    send-welcome-email        │                          │                     │
   │    Authorization: <JWT>      │                          │                     │
   │    body: { firstName }       │                          │                     │
   │ ───────────────────────────► │                          │                     │
   │                              │                          │                     │
   │                              │ 3. Verify JWT, look up   │                     │
   │                              │    auth.users → email    │                     │
   │                              │                          │                     │
   │                              │ 4. POST /emails          │                     │
   │                              │    from: daniel@         │                     │
   │                              │    carryapp.site         │                     │
   │                              │ ───────────────────────► │                     │
   │                              │                          │                     │
   │                              │                          │ 5. SPF/DKIM signed, │
   │                              │                          │    delivered        │
   │                              │                          │ ──────────────────► │
   │ ◄─────────────────────────── │                          │                     │
   │   { ok: true, id }           │                          │                     │
```

1. **Trigger** — `AuthService.completeOnboarding()` finishes saving the profile and sets `isOnboarded = true`. It then calls `sendWelcomeEmail(firstName:)` non-blocking — if it fails, we log but don't surface an error to the user (they're already onboarded).
2. **Auth** — the call sends the user's Supabase access token. The edge function uses that token to verify the session and look up the user's email from `auth.users`. We never trust an email passed from the client.
3. **Send** — the function calls Resend's `/emails` API with `from`, `to`, `subject`, `text`. Resend signs with DKIM and delivers via Amazon SES infrastructure.
4. **Result** — the user receives the email within seconds. The function returns `{ ok: true, id }` so we can debug specific sends in Resend's logs.

## Key files

| File | What it does |
|---|---|
| [`carry/supabase/functions/send-welcome-email/index.ts`](../supabase/functions/send-welcome-email/index.ts) | The edge function. Email subject + body lives here. |
| `carry/Carry/Services/AuthService.swift` | `completeOnboarding()` fires the call. Method `sendWelcomeEmail(firstName:)`. |
| `carry/Carry/Views/Debug/DebugMenuView.swift` | "Send Test Welcome Email" row in the AUTH section for manual testing. |

## Email copy (current)

**Subject:** `Welcome to Carry`

```
Hi {firstName},

Welcome to Carry — glad you're here.

Carry helps you and your crew track skins games without keeping paper scorecards or arguing over who owes who. Start a Quick Game with "+ New" on the Games tab the next time you're heading out.

If you hit any snags, just reply to this email — I read everything.

— Daniel
Carry
```

`{firstName}` falls back to `"there"` if missing.

## DNS records (Cloudflare)

Hosted on the `carryapp.site` zone. **All records must be set to "DNS only" (gray cloud) — never proxy email DNS.**

| Type | Name | Value | Purpose |
|---|---|---|---|
| TXT | `resend._domainkey` | `p=MIGfMA0GCSqG…` (long key from Resend) | DKIM — proves Resend is authorized to sign mail for our domain |
| TXT | `send` | `v=spf1 include:amazonses.com ~all` | SPF — authorizes Amazon SES (Resend's backend) to send for us |
| MX | `send` | `feedback-smtp.us-east-1.amazonses.com` (priority 10) | Lets SES deliver bounce / complaint feedback to Resend |
| TXT | `_dmarc` | `v=DMARC1; p=none;` | DMARC policy — currently report-only, no enforcement |

> **Why DNS lives at Cloudflare instead of Dreamhost:** Dreamhost can't host MX records on subdomains (like `send.carryapp.site`), and Resend requires that MX record. Moving the zone to Cloudflare unblocked verification.

## Configuration

Stored as Supabase Edge Function Secrets (project `seeitehizboxjbnccnyd`):

| Secret | Value | Notes |
|---|---|---|
| `RESEND_API_KEY` | (Resend account API key) | Generated in Resend dashboard. Rotate via Resend → API Keys, then update here. |
| `RESEND_FROM` | `Daniel <daniel@carryapp.site>` | If unset, the function falls back to Resend's sandbox `onboarding@resend.dev` (only delivers to the email that signed up for Resend — useful for early dev, not production). |

Edit at: https://supabase.com/dashboard/project/seeitehizboxjbnccnyd/functions/secrets

## How to edit the email copy

Edit the `subject` (~line 46) or `text` array (~lines 47–58) in [`index.ts`](../supabase/functions/send-welcome-email/index.ts), then redeploy:

```bash
supabase functions deploy send-welcome-email --project-ref seeitehizboxjbnccnyd
```

No app rebuild needed — the function is server-side. Changes are live immediately.

## How to test

**In the app:** Debug Menu → AUTH section → "Send Test Welcome Email". Goes to the email of whoever's signed in.

**Via curl:**
```bash
curl -X POST \
  https://seeitehizboxjbnccnyd.supabase.co/functions/v1/send-welcome-email \
  -H "Authorization: Bearer <user-access-token>" \
  -H "Content-Type: application/json" \
  -d '{"firstName":"Daniel"}'
```

## Observability

- **Resend dashboard** → Logs: every send, with delivery status, opens, bounces. https://resend.com/emails
- **Supabase dashboard** → Edge Functions → `send-welcome-email` → Logs: function-side errors and the `Welcome email sent: { id, to }` lines.
- **PostHog** → events captured client-side from [`AuthService.sendWelcomeEmail`](../Carry/Services/AuthService.swift):
  - `welcome_email_sent` — fires when Resend returns success
  - `welcome_email_failed` — fires on any error, with a `reason` property containing the error description

  Both are defined in [`AnalyticsService.swift`](../Carry/Services/AnalyticsService.swift). Use these to build an activation funnel: `onboarding_completed` → `welcome_email_sent` → `round_started`. Drop-off between steps tells you whether the email is actually pulling new users back into the app.

## Failure handling

The Swift call is **fire-and-forget** — if the function or Resend fails, the user is still onboarded successfully and lands in the app. We just lose the welcome email for that user. Trade-off: keeping onboarding fast and reliable matters more than guaranteeing the email lands.

The `!isAuthenticated` debug branch of `completeOnboarding` deliberately skips the call — there's no real Supabase session for the function to authenticate against in that flow.

## Cost

Resend free tier: 3,000 emails/month, 100/day. Comfortably above current signup volume. Upgrade kicks in only at scale.
