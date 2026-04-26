# Session Handoff — 2026-04-26 EOD

This is the pickup point for the next conversation. Read this top-to-bottom; it captures everything that was open at session close, plus what was just shipped so the new session doesn't re-investigate solved problems.

---

## Current state

- **Build 57** just uploaded to App Store Connect (TestFlight) at session close.
- Branch: `feature/free-tier-v2`. Latest commit: `3c525de` (`docs: next steps after the v54-v57 push-notification + tee-sheet sweep`).
- Working tree is clean except `aps-environment = production` in `Carry/Carry.entitlements` (uncommitted by design — flips back to `development` after archive verification).
- Two TestFlight test devices: Daniel (newer iPhone), Ziggy (iPhone 12), Emese (newer iPhone).
- Server-side push function `send-push-notification` is at v35+ on Supabase, deployed with `--no-verify-jwt` (correct config — DB trigger calls it).
- Migrations applied to prod through `20260422000001_fix_group_members_self_policies.sql`.

---

## ✅ Duplicate "You're Invited" pushes — RESOLVED in working tree

The dup-push bug (4× pushes per single invite action) was diagnosed and fixed in `supabase/functions/send-push-notification/index.ts`. Root cause: the DB trigger fires the function on **every** UPDATE of `group_members` rows, including writes that don't change status (e.g. iOS `saveGroupNums` reordering tee-time slots). Pre-fix the dispatch matched on `record.status === "invited"` regardless of whether status had just transitioned, so each subsequent UPDATE re-fired `handleGroupInvite`.

Fix applied: **transition guards** added to every status-driven dispatch branch:

```ts
} else if (record.status === "invited" && record.player_id && record.role
           && (type === "INSERT" || old_record?.status !== "invited")) {
  return await handleGroupInvite(...);
}
```

Same pattern added to `round started`, `round ended`, `member joined`, `member declined`, and `score dispute` branches. INSERT always counts as a transition (no `old_record`); UPDATE only counts if the relevant field changed.

**Function deploy state**: edit is in the working tree only. **Redeploy is required** for the fix to take effect:

```bash
supabase functions deploy send-push-notification --project-ref seeitehizboxjbnccnyd --no-verify-jwt
```

After redeploy: re-test by inviting a Carry user. Should produce **one** `[dispatch]` → `[branch] group invite` → `[apns] status:200` cycle, **one** push delivered.

Side benefit: the same transition guards likely fix the parked **"round-started push didn't land on Ziggy"** issue too — the previous code may have fired ghost "round started" pushes on irrelevant UPDATEs that exhausted some recipient state. Verify after redeploy.

---

## What was just shipped (v52–v57)

So the new session knows what's already done and doesn't reopen these:

| Build | Fix |
|---|---|
| **v52** | `UIApplication.shared.registerForRemoteNotifications()` on every `application(_:didFinishLaunchingWithOptions:)` — handles entitlement env transitions and restore-from-backup. No-op when not authorized, refreshes token when changed. |
| **v53** | Tab bar `Binding<Bool>` race fixed via SwiftUI `PreferenceKey`. Eliminates first-launch missing tab bar. Children publish `TabBarHiddenKey` via `.preference`; MainTabView mirrors via `.onPreferenceChange`. No more shared writable state. |
| **v54** | (1) Session-restore push permission gate dropped the `disclaimerAccepted` requirement. UserDefaults gets wiped on delete+reinstall; relying on it for an existing user (server `isOnboarded=true`) meant the iOS prompt never fired. Gate now checks server truth only. (2) `OnboardingView` now calls `registerForRemoteNotifications` immediately after the user grants permission — previously the token only registered on the *next* app launch via the v52 didFinishLaunching fix, so new users missed all first-session pushes. |
| **v55–v56** | (1) `GroupManagerView.refreshGroupData` now unions newly-active members into `selectedIDs` (drops members who left + adds new joiners + respects persisted swipe-offs in `deselectedIDs_<groupId>` UserDefaults). Pull-to-refresh now picks up new joiners on viewer devices. (2) SMS share message no longer duplicates the subject — `convertInviteCTA` was setting `message = "\(subject) — \(url)"` while ShareLink also passes subject separately, so iOS Messages was rendering both. (3) Empty tee-time group cards no longer rendered — the underlying `groups` array stays intact (so `groupIdx` keeps mapping correctly to scorerIDs/teeTimes/round_players), only the render filters out empty slots. |
| **v57** | All-Time leaderboard filters out former Quick Game guests not carried over to the converted Skins Group. Was including ghost players from the migrated QG round who were never invited to the new group. |

Also removed in this session (already in v57 / earlier commits):
- `Profile → Upgrade to Premium` button removed for free users (paywall fires via gates everywhere else; redundant CTA was clutter)
- `[Single Game tapped]` debug toast in `GroupsListView`'s debug-only Create Group Card overlay

---

## 🟡 Open issues observed during testing — verify before deciding to fix

These were noticed but not blocking. Mention them up-front if the user starts a session by saying "what's left?"

### 1. Round-started push didn't land on Ziggy's iPhone 12
Daniel tapped Start Round → Emese got "Round Started" iOS push → Ziggy did not. Both UI buttons updated correctly. **Possibly resolved by the same transition-guard fix above** — the previous dispatch may have been firing `handleRoundStarted` on UPDATEs that didn't actually transition status to active, which could have caused recipient-state weirdness. **Re-verify after function redeploy.** If it still misses pushes only on iPhone 12, dig further (function log `[apns]` token_prefix counts).

### 2. Pull-to-refresh stale state on iPhone 12
Even with v55's `selectedIDs` union fix, Ziggy's iPhone 12 had a moment where pull-to-refresh didn't reload the roster but navigate-away-and-back did. Could be a slower-CPU race window unrelated to the v55 fix. Park unless it keeps recurring; revisit if a non-iPhone-12 user reports.

### 3. Skin-won local notification inconsistency
Local notification only fires on the device whose `RoundViewModel` polling cycle catches the skin event. Different devices receive different subsets depending on whether they're actively in the scorecard view. **Decision: leave as-is.** Users can disable via Profile → Notifications → Live Scoring toggle. The in-app skin celebration animation is the primary surface; lock-screen ping is supplemental.

---

## ⚪ Cleanup / polish for v58+ (none user-blocking)

- **Toast copy stale post-auto-add**: "Alice joined — tap Manage to add" no longer matches the auto-add behavior shipped in v55. Update to "Alice joined the group" or similar.
- **Diagnostic logging in send-push-notification edge function**: `[dispatch]`/`[branch]`/`[apns]` console.log entries are useful for visibility but verbose. Trim if log quota becomes a concern.
- **Stray `TeeTimePickerSheet.swift` at repo root**: byte-identical duplicate of `Carry/Views/TeeTimePickerSheet.swift`. Both tracked in git, both referenced in `project.pbxproj`. The original Build 49 archive failed when the root copy was deleted; restored to keep Xcode happy. Real cleanup: remove the root copy from .pbxproj reference, delete the file, verify build.
- **Dead `disclaimerAccepted` `@AppStorage` declaration** in `CarryApp.swift:154`. Variable declared but never read. Only reader was the AuthService gate removed in v54.
- **`AppStore.showManageSubscriptions(in:)`**: already used in `ProfileSheetView.swift:217`. Memory once flagged a stale `https://apps.apple.com/account/subscriptions` URL fallback elsewhere — verify cleared.

---

## 🔵 Deferred features (Build 50+ territory)

These have decisions made; just need a sprint to build:

- **Guest-claim disambiguation sheet wiring** — sheet (`Carry/Views/GuestClaimView.swift`) is fully built and backend-wired. Production trigger never fires — multi-match and no-match cases silently skip in `HomeView.acceptInvite` (around line 1139). 3-line code change. Add round count + skins won next to each guest name so users can recognize themselves by stats.
- **Phone-anchored guest claim** — the architectural fix for nickname mismatches. Capture phone in onboarding (optional, with skip), match guest profiles by phone instead of name. Eliminates "T-Bone vs Tyson" recognition problem. Significant scope — privacy disclosure update (App Store labels, privacy manifest, privacy policy + site re-deploy). Privacy rationale for App Review: "we use your phone number to link you with games your friends invited you to".
- **Empty-group placeholder** — alternative to v57's hide-empty approach: render pending-only groups with a placeholder ("Waiting for Emese to accept"). More informative, design decision needed.
- **How-to videos linked from Home tab** — voiceover scripts exist in `docs/voiceover-scripts.md`. ScreenFlow / Screen Studio for capture, ElevenLabs (or own voice) for VO. Hosting: YouTube unlisted simplest.
- **Sweden / Localization** — parked entirely. Worktree-ready off `main` at `../carry-i18n/`. Code: ~1–2 days for currency formatting + buy-in slider scaling. ASC: enable territory + add SEK pricing tier.
- **Quick Game → Group conversion UX** — "demoted to invited" framing feels cold. See `memory/quick_game_conversion_ux.md`.
- **GroupManagerView pending-members indicator** — small badge/dot near Manage button showing pending count; user to design visual. See `memory/group_manager_pending_indicator.md`.
- **Guest pending-status semantics** — former QG guests show as "pending" in converted groups but no invite was actually sent; need visual distinction + per-row Invite flow. See `memory/guest_pending_status_semantics.md`.
- **Creator-can't-play scenario** — creator who organizes a Quick Game but doesn't want to play is currently blocked. See `memory/creator_cant_play_todo.md`.

Full list: `docs/next-steps.md`.

---

## Pre-archive runtime checks (mechanical — always do these)

For every App Store archive after this session:

1. `aps-environment` flipped to `production` in `Carry/Carry.entitlements` (uncommitted change)
2. `CURRENT_PROJECT_VERSION` bumped (App Store Connect rejects duplicate build numbers)
3. `grantPremiumInTestFlight = false` in `StoreService.swift:44` (already false; double-check)
4. ASC App Description matches site features
5. Site files deployed to `carryapp.site` (verify `https://carryapp.site/invite/` shows invite page)
6. `apple-app-site-association` accessible at `https://carryapp.site/.well-known/apple-app-site-association`
7. Clean Build Folder (`Cmd+Shift+K`) before Archive
8. After upload, flip `aps-environment` back to `development` for ongoing local dev

---

## Server-side state at session close

- **APNs secrets**: all 4 present (`APNS_KEY_ID`, `APNS_PRIVATE_KEY`, `APNS_TEAM_ID`, `APNS_PRODUCTION="true"`)
- **Function**: `send-push-notification` v35+ ACTIVE, deployed with `--no-verify-jwt`
- **Function code** has diagnostic `[dispatch]` / `[branch]` / `[apns]` console.log on every invocation (useful — keep until log quota becomes a concern)
- **DB triggers**: confirmed working (function fires for invites, accepts, round status changes, score events)

---

## How to start the next session

Open with: *"Carry pickup — read `docs/session-handoff.md` first. Function transition guards are in the working tree but not deployed; redeploy and verify the duplicate-push bug is gone. Build 57 already on TestFlight."*

The new session's first move should be:
1. Redeploy `send-push-notification` with `--no-verify-jwt`
2. Have Daniel send a fresh test invite to a Carry user
3. Confirm exactly one `[dispatch]` → `[branch] group invite` → `[apns] 200` cycle in function logs
4. Confirm recipient sees exactly one banner notification
5. If verified, commit the function file change with a tight message and push

If the dup-push bug persists post-deploy, fall back to the diagnostic table previously in this section (now in git history): inspect `[dispatch]` payloads to determine whether iOS is multi-firing `inviteMember`, the DB trigger is duplicated, or pg_net is retrying.

The new agent should not re-investigate problems already solved by v52–v57. Those are in the table above.

---

_Last updated: 2026-04-26 EOD_
