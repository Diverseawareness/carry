# Carry — App Features Overview

Self-contained context for understanding Carry's main features. Shareable to a fresh agent with no prior knowledge of the codebase.

## What Carry is

iOS golf skins-tracking app. Users play live rounds with friends, score hole-by-hole on a phone scorecard, and the app calculates skins payouts, leaderboards, and stats. SwiftUI + Supabase backend. iOS 17+, US-only launch.

- Bundle ID: `com.diverseawareness.carry`
- App Store: live since 2026-04-27 (v1.0.1)
- Pricing: free download, $4.99/mo or $29.99/yr with 30-day trial
- Target users: recreational golf groups (foursomes, weekly skins games)

## Two ways to play

### 1. Quick Game (one-off)
- Create a one-shot game without forming a persistent group
- Add players by typing names + handicaps inline (no account needed)
- Players are **guests** — ephemeral, never saved as Carry users
- After the round: results sheet, optional convert-to-Group flow
- Used for casual outings, vacations, anyone who doesn't play regularly together

### 2. Skins Group (persistent)
- A named group with persistent membership (you, friends, recurring crew)
- All members are **Carry users** with accounts (Carry-only, no guests)
- Reusable across rounds — schedule a round, set tee times, play
- Tracks all-time leaderboard + stats across every round the group has played
- Used for league play, regular weekly games, ongoing rivalries

The split is load-bearing: Skins Groups never contain guests, Quick Games never persist guests.

## Round flow (both modes)

1. **Setup**: pick course (USGA-style course DB via `GolfCourseService`), pick tees, pick game type
2. **Roster**: assign players to tee times (max 5 groups, 4 players per group, 20 total)
3. **Game options**: buy-in ($0–500 step 5), HC strokes on/off, optional carry-overs, etc.
4. **Live round**: hole-by-hole `ScorecardView`; everyone scores in v1 (no designated scorer)
5. **Skins calc**: live skin assignment per hole, push notifications + Live Activity updates
6. **Results**: `ResultsSheet` / `RoundCompleteView` — final standings, money won, share card

## Scoring model

- **v1 = "everyone-scores"**: every player can input scores for any player. No locked scorer role. Free drag between groups, full-group rejection, swipe-deselect is non-destructive.
- The `scoringMode` enum exists in code but the toggle is hidden — can be re-enabled later without a DB migration.
- **Scorecard tap-to-score**: tap a cell → `ScoreInputSheet` opens with quick buttons + finer entry. Coachmark on first use.

## Auth

**Currently shipped (prod):**
- Apple Sign-In only (single provider)
- Phone number on profile (added 1.0.3, mandatory onboarding step)

**In progress on `feature/auth-v2` (dev branch only — quarantined):**
- Email sign-in (`EmailAuthSheet`)
- Google Sign-In (`GoogleSignInService`)
- Account linking — link/unlink Apple+Google in Settings (built, untested)
- 🔒 **Quarantine rule**: never merges to main/release until linking is fully tested AND prod has been validated against a separate dev DB. Violating this caused the 2026-05-01 prod incident.

## Premium / Free Tier

`StoreService` (StoreKit 2) gates premium features.

**Premium-required:**
- Creating a Skins Group
- Creating a Quick Game
- Joining a game via invite link
- Starting a round in any group

**Free-tier behavior:**
- Existing groups become read-only (gated empty state, "Subscription ended" + Upgrade CTA)
- Tee Times section + Start Round CTA hidden
- Leaderboards / stats still visible; meta info dimmed 50%
- Members can leave; creators can delete

**Trial logic:**
- 30-day intro offer (Apple-authoritative — `syncHadPremiumWithAppleIntroEligibility`)
- Trial ended users see "Premium Trial Ended" hero + "Keep your:" feature list (retention framing) instead of "Try It Free"
- TestFlight: `grantPremiumInTestFlight` flag (must be `false` for App Store builds)

Full details: `docs/paywall-and-free-tier.md`.

## Sharing & invites

- **Share invite link**: `ResultsShareCard` + native `ShareLink` — sends preview card image + invite URL via iMessage/etc.
- **QR code**: 262pt QR card in convert-to-group sheet (segmented control: Share Invite | Scan QR)
- **Universal links**: `carryapp.site` hosts `apple-app-site-association` for deep linking
- **Accept invite**: `HomeView` invite card; Premium gate enforced via `pendingInviteAfterPaywall`
- Invites section on Home is currently visible but flagged for removal (TODO)

## Key features

- **Live Activities** (`LiveActivityService`) — Dynamic Island + Lock Screen score updates during round
- **Push notifications** — score updates, invites, "joined group" toasts (APNS via Supabase Edge Function)
- **Round stats** (`RoundStatsView`) — HC pops, skins/holes, money, birdies/bogeys per round
- **All-time leaderboard** (`GroupManagerView`) — money + skins + appearances across every group round
- **Cumulative stats per player** — cached aggregation, not re-computed in sort comparators
- **Pending members**: invited-but-not-accepted users sit in a "Pending" section in Manage Members; excluded from tee sheet by default
- **Recurring rounds**: rounds can advance to next scheduled date; "Schedule Next Round" CTA on group page
- **Round history**: every completed round archived per group, with full scorecard + results replayable

## Architecture

### Frontend (SwiftUI)
- **Tabs**: Home / Games (groups list) / Profile (`MainTabView`)
- **Home**: launches Quick Game, shows active rounds, invite cards
- **Games**: list of Skins Groups + Quick Games + concluded rounds
- **Group page** (`GroupManagerView`): roster, tee times, settings, leaderboard, round history
- ~50 view files, several large (HomeView, GroupManagerView, GroupsListView are 1000+ lines each)
- State: `@Published` view-model pattern, `AppRouter` for global navigation, `NotificationCenter` for cross-view events

### Backend (Supabase)
- **Postgres** with tables: `profiles`, `skins_groups`, `group_members`, `rounds`, `round_players`, `courses`, `tee_boxes`, `scores`, `holes`
- **RLS** on every user-facing table
- **Edge Functions** (Deno): push notification fan-out (`notify_push`), phone-OTP, etc.
- **Realtime subscriptions** for live round updates
- **pg_cron**: schema cache reload every minute on dev branch (PGRST205 mitigation)

### Dev/Prod split (new — 2026-05-05)
- **Prod**: `seeitehizboxjbnccnyd` — real users, only stable code touches it
- **Dev**: `gbhljwtbobbxervekxkg` — preview branch, where auth-v2 + breaking changes get tested
- Xcode `Carry dev` scheme switches via `-DDEV_SUPABASE` flag in `Config.swift`
- Migrations live in `supabase/migrations/`, pushed to either via `supabase db push --project-ref`

## Hard rules / invariants (do not break)

- Groups physically separated on course → **never** suggest "creator scores all groups"
- Max 4 players per tee time
- Max 5 tee times per game (20 players cap)
- Skins Groups are **Carry-only** (no guests, ever)
- Quick Game guests are **ephemeral** (never persisted as members of any future group)
- Auth-v2 stays on `feature/auth-v2` until linking is tested
- App Store builds: `grantPremiumInTestFlight = false`, `aps-environment = production`

## Active state (as of 2026-05-05)

- **Live build**: 1.0.1 on App Store, build 60-series in TestFlight
- **In flight**: `hotfix/1.0.3` (bug-fix bundle from 2026-05-01/02 + phone-on-profile) ready to archive
- **App Store rejection** 2026-05-05: phone-onboarding keyboard trap on iPhone 17 Pro Max — fixed in build 67, ready for re-archive
- **Auth-v2**: building clean on dev branch, ready for Email + Google provider testing

## Where to look in the code

- Round logic: `RoundCoordinatorView` + `RoundService` + `ScoreStorage`
- Group logic: `GroupService` + `GroupManagerView` + `GroupStorage`
- Skins math: `SkinResult.swift` + `RoundConfig.swift`
- Scoring UI: `ScorecardView` + `ScoreInputSheet`
- Auth: `AuthService` + `AuthView` + (dev only) `EmailAuthSheet` + `GoogleSignInService`
- Paywall: `PaywallView` + `StoreService`
- Push/Live Activity: `NotificationService` + `LiveActivityService`
- Edge functions: `supabase/functions/`

## Related docs

- `docs/paywall-and-free-tier.md` — full premium gating spec
- `docs/google-email-auth-setup.md` — auth-v2 setup + dev/prod migration workflow
- `docs/migration-runbook-2026-05-01.md` — how migrations get pushed
- `docs/test-plan-2026-05-01.md` — section-by-section regression test matrix
- `docs/session-handoff.md` — handoff notes from build 57
- `docs/design-system.md` — colors, fonts, spacing conventions
