# Carry — Next Steps After v57

Captured 2026-04-26 at the close of the v54–v57 push-notification + tee-sheet sweep. Everything below is **post-launch** unless explicitly tagged otherwise. Build 57 is what's about to ship.

---

## Recently shipped (v52 → v57)

For context — what was fixed in this final pre-launch sweep, so the next session knows what's already done.

| Build | Fix |
|---|---|
| v52 | `registerForRemoteNotifications` on every app launch (handles entitlement env transitions and restore-from-backup) |
| v53 | Tab bar `Binding<Bool>` race fixed via SwiftUI `PreferenceKey` (eliminates first-launch missing tab bar) |
| v54 | Session-restore push permission gate dropped `disclaimerAccepted` requirement (delete+reinstall existing users now get push permission prompted) + onboarding registers for remote notifications immediately after grant (new users no longer miss first-session pushes) |
| v55–v56 | `refreshGroupData` unions newly-active members into `selectedIDs` (pull-to-refresh now picks up new joiners) + SMS share message no longer duplicates subject + empty tee-time group cards no longer rendered |
| v57 | All-Time leaderboard filters out former Quick Game guests not carried over to the converted group |

---

## Open issues observed during testing — verify after launch, fix if real

These were noticed during the v54–v57 testing cycle but not blocking. Worth confirming on broader devices before deciding to fix.

### Round-started push not landing on iPhone 12 (Ziggy)
- Daniel started a round → Emese got "Round Started" iOS push → Ziggy did not
- Both UI buttons updated correctly to "Join Round" — so the in-app surface is fine
- Root cause unverified. Could be:
  - iPhone 12 specific (unlikely — model is well-supported)
  - Function not iterating Ziggy in the recipient list (`handleRoundStarted` filtering bug)
  - Ziggy's device token was stale when this fired (would've been cleaned up by APNs 410)
- **Diagnostic path**: Supabase function logs. Look at `[apns]` entries from when the round started; count `token_prefix` values. If only Emese's prefix appears, function is filtering Ziggy. If two prefixes, problem is at his device.
- Decision so far: park as iPhone 12 quirk; revisit if a non-iPhone-12 user reports the same.

### Pull-to-refresh stale state (iPhone 12 reproduce)
- Ziggy's iPhone 12 had a pull-to-refresh that didn't reload Emese's roster row even with v55's `selectedIDs` union fix
- Navigate-away-and-back fixed it
- v55 fix likely addresses the *member-not-in-roster* case but there may be a *separate* timing/race issue specific to iPhone 12 (slower CPU, async fetch race window)
- **Investigate later** if it keeps recurring on slower devices.

### Skin-won local notification inconsistency
- Local notification `NotificationService.shared.notifySkinWon` only fires on the device whose `RoundViewModel` polling cycle detects the skin event
- Different devices may or may not receive it depending on whether they're actively in the scorecard view at that moment
- Decision: leave as-is. Users can disable via Profile → Notifications → Live Scoring toggle. The in-app skin celebration animation carries the moment; lock-screen ping is supplemental.

---

## Cleanup / polish for v58+

Small things to fold into the next sprint. None of these are user-blocking.

### Toast copy stale post-auto-add
- "Alice joined — tap Manage to add" toast still fires when someone accepts an invite
- Post-v55, members are *automatically* added to the tee sheet — the "tap Manage to add" instruction is now misleading
- Update copy to something like "Alice joined the group" (no action required)

### Diagnostic logging in send-push-notification edge function
- v54 added `[dispatch]`, `[branch]`, `[apns]` console.log entries on every invocation for debugging
- Useful for ongoing visibility but verbose for steady-state production
- Keep for now (small Supabase project, log quota is generous). Trim later if log volume becomes a concern.

### Stray `TeeTimePickerSheet.swift` at repo root
- Duplicate of `Carry/Views/TeeTimePickerSheet.swift` — both are tracked in git, both are referenced by `Carry.xcodeproj/project.pbxproj`
- Original Build 49 archive failed when the root copy was deleted; restored to keep Xcode happy
- Real cleanup: remove the root copy from the .pbxproj reference, delete the file, verify build

### Dead `disclaimerAccepted` `@AppStorage` declaration
- `CarryApp.swift:154` declares `@AppStorage("disclaimerAccepted") private var disclaimerAccepted = false` but the variable is never read in CarryApp
- The only reader was the AuthService gate I removed in v54
- Delete the declaration

### `AppStore.showManageSubscriptions(in:)` migration
- `ProfileSheetView.swift:217` already uses this for Manage Subscription
- An older comment in memory referenced a stale `https://apps.apple.com/account/subscriptions` URL — verify no other places still hit the URL fallback

---

## Deferred features — Build 50+ territory

Decisions already made; just need a sprint to build them.

### Guest-claim disambiguation sheet wiring
- The "Are you one of these players?" sheet (`Carry/Views/GuestClaimView.swift`) is fully built and wired backend-side
- Production trigger never fires — multi-match and no-match cases silently skip in `HomeView.acceptInvite` (line ~1139)
- Three-line code change to flip the trigger
- Add round count + skins won next to each guest name so users can recognize themselves by stats even if the nickname doesn't match
- See: `memory/next_steps_pending_users_in_group.md` and the deeper analysis in this session's transcript

### Phone-anchored guest claim (the architectural fix)
- Adds phone number capture to onboarding (optional, with explicit skip)
- Server-side: when an SMS-invite recipient signs up, match the invite-token's phone to find the guest profile, claim silently — no name comparison needed
- Eliminates the "T-Bone vs Tyson" recognition problem entirely
- Significant scope: privacy disclosure update (App Store labels, privacy manifest, privacy policy + site re-deploy)
- Privacy rationale: "we use your phone number to link you with games your friends invited you to — and to keep your past scores attached to your account"

### Empty-group UX (the alternative path)
- v57 hides empty tee-time groups entirely — clean but doesn't surface "waiting for X to accept"
- Alternative: render pending-only groups with a placeholder ("Waiting for Emese to accept")
- More informative, slightly more code; design decision

### "How-to" video tutorials linked from Home tab
- Voiceover scripts saved in `docs/voiceover-scripts.md`
- Production: ScreenFlow or Screen Studio for screen capture, ElevenLabs for VO (or own voice via mic)
- Hosting: YouTube unlisted (simplest), Mux, or Bunny.net
- New "How it works" card on Home tab opens Safari sheet or in-app WebView

### Sweden / Localization (parked entirely — post-launch)
- Worktree-ready setup planned at `/Users/danielsigvardsson/Documents/claude/carry-i18n/` (off `main`)
- Code work: ~1–2 days for currency formatting + buy-in slider scaling
- ASC: enable territory + add SEK pricing tier
- App Store listing: Swedish localization (~days for translation pipeline)
- Site: `carryapp.site` Swedish version

### Quick Game → Group conversion UX
- "Demoted to invited" framing feels cold for players who were already in the QG together
- See: `memory/quick_game_conversion_ux.md`

### GroupManagerView pending-members indicator
- Small badge/dot near Manage button showing pending count
- User to design the visual

### Guest pending-status semantics
- Former Quick Game guests show as "pending" in converted groups but no invite was actually sent
- Need visual distinction in the Manage Members list + per-row "Invite" flow
- See: `memory/guest_pending_status_semantics.md`

### Creator-can't-play scenario
- Creator who organizes a Quick Game but doesn't want to play is currently blocked
- Skins Group case is handled (swipe-deselect is non-destructive); Quick Game case forces delete
- See: `memory/creator_cant_play_todo.md`

---

## Pre-archive runtime checks (always do these)

Before every App Store submission archive, verify:

1. `aps-environment` flipped to `production` in `Carry/Carry.entitlements`
2. `CURRENT_PROJECT_VERSION` bumped (App Store Connect rejects duplicate build numbers)
3. `grantPremiumInTestFlight = false` in `StoreService.swift:44` (already false; double-check)
4. ASC App Description matches site features (last updated 2026-04-23 to add Leaderboards & Stats + Share Your Round)
5. Site files deployed to `carryapp.site` (privacy/terms/faq/about/index/invite — verify by visiting `https://carryapp.site/invite/`)
6. `apple-app-site-association` accessible at `https://carryapp.site/.well-known/apple-app-site-association`
7. Clean Build Folder (`Cmd+Shift+K`) before Archive
8. After upload succeeds, flip `aps-environment` back to `development` for ongoing local dev

---

## Post-launch v1 watch list

Things to monitor in the first 100 users:
- Push delivery rate (Supabase function logs — `[apns]` 200 vs 4xx ratio)
- Guest-claim auto-match success rate (single-name-match auto-claims should land for ~80% of typical golf crews)
- Subscription conversion (free trial → paid) at the 30-day mark
- Crash reports (PostHog + native iOS crash logs)
- Apple Review feedback if anything bounces

---

_Last updated: 2026-04-26_
