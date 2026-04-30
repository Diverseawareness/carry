# Google + Email Sign-In Setup

Code is in place for Google Sign-In and Email Sign-Up. Before the buttons work end-to-end, a handful of dashboard + Xcode steps need to happen. None of these affect the live App Store build (1.0.1) — they only kick in when the next build ships.

## 1. Google Cloud Console

1. Open https://console.cloud.google.com → create or pick a project
2. **APIs & Services → Credentials → Create Credentials → OAuth client ID**
3. Application type: **iOS**
4. Bundle ID: `com.diverseawareness.carry`
5. Save. Copy two values:
   - **iOS client ID** — looks like `123-abc.apps.googleusercontent.com`
   - **Reversed client ID (URL scheme)** — same value, components reversed: `com.googleusercontent.apps.123-abc`
6. Also create a **Web application** OAuth client in the same project. Copy its **client ID** and **client secret** — Supabase needs both for token verification.

## 2. Supabase Dashboard

Project: `seeitehizboxjbnccnyd`

### Authentication → Providers
- **Google**: enable. Paste the Web client ID and secret from step 1.6 above. Leave "Skip nonce check" off.
- **Email**: confirm enabled. Toggle **Confirm email** ON (we agreed required).

### Authentication → URL Configuration
Add to allowed redirect URLs:
- `carry://login-callback`
- `https://carryapp.site/reset`

### Authentication → Email Templates → Reset Password
The default template works. The reset link will land at `https://carryapp.site/reset?...` — that page needs to exist (see step 6).

### SMTP (optional, recommended later)
Supabase's default sender has rate limits and shows a `noreply@mail.app.supabase.io` from address. Fine for launch testing. For production volume, set up a custom SMTP provider (Resend, Postmark, etc.) under Authentication → Settings → SMTP.

## 3. Xcode — SPM Dependency

1. File → Add Package Dependencies
2. URL: `https://github.com/google/GoogleSignIn-iOS`
3. Add `GoogleSignIn` and `GoogleSignInSwift` products to the Carry target
4. Build — `GoogleSignInService.swift` will start using the real SDK (it's behind `#if canImport(GoogleSignIn)` until the package is added).

## 4. Info.plist

Two entries needed:

```xml
<key>GIDClientID</key>
<string>123-abc.apps.googleusercontent.com</string>

<key>CFBundleURLTypes</key>
<array>
  <!-- existing carry:// scheme stays -->
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.123-abc</string>
    </array>
  </dict>
</array>
```

Replace `123-abc` with your actual reversed client ID from step 1.5.

## 5. App Init — wire GoogleSignIn URL handling

In `CarryApp.swift`, add to the root view:

```swift
.onOpenURL { url in
    GIDSignIn.sharedInstance.handle(url)
}
```

(Wrap in `#if canImport(GoogleSignIn)` if you want to keep building without the SPM package added.)

## 6. Asset Catalog

Add a `google-logo` image set:
- Source: official Google G logo (https://developers.google.com/identity/branding-guidelines)
- PDF asset with **Preserve Vector Data** enabled, or 1x/2x/3x PNGs at 20pt
- Asset name must be exactly `google-logo` (matches `Image("google-logo")` in `AuthView.swift`)

## 7. carryapp.site/reset page

Supabase sends users to this URL after they click the password reset email. The page needs to:
1. Read the recovery token from the URL fragment
2. Show "set new password" form
3. Call Supabase's `updateUser({ password })` with the token
4. Show success → "Open Carry" button (deep link to `carry://`)

Easiest: copy the pattern from Supabase's auth UI examples (https://supabase.com/docs/guides/auth/passwords#password-resets). Static HTML + a few lines of JS.

## 8. Pre-archive additions

Add to the existing pre-archive checklist:
- [ ] Verify Google iOS client ID points at production bundle ID (not dev)
- [ ] Test Google Sign-In on a real device (simulator works, but verify once)
- [ ] Test email sign-up end-to-end: signup → email arrives → tap link → return to app → sign in
- [ ] Test password reset: tap "Forgot" → email arrives → tap link → set new password → sign in
- [ ] Update App Store privacy questionnaire — "Email" data type is now collected via the email provider
- [ ] Update site privacy policy if needed

## What's intentionally NOT done yet

- **Account linking in Settings** ("Connected Accounts" section). Approved but separate scope — needs `linkIdentity()` calls + a Settings UI section. Build after Google + Email are shipping.
- **Onboarding rename** of `hasAppleName` → `hasProviderName`. The current flag works correctly for Google (server trigger pre-fills name) and email (no name → 4-step path with Name input). Rename is cosmetic; defer.
