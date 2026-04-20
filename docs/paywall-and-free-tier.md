# Carry — Paywall, Trial, and Free-Tier Strategy

**Purpose:** Complete context for anyone working on monetization strategy for Carry. Describes the products, the trial, what free users can and can't do, every point where the paywall fires, and the reasoning behind the current design. Written so a non-engineer can make informed strategic decisions.

**Last updated:** 2026-04-19 (Free Tier v2 implemented on `feature/free-tier-v2` branch, not yet merged to release).

---

## 1. Executive summary — how Carry makes money

Carry uses a **freemium subscription model**:

- Users download the app free.
- A free tier lets them **join and play** in rounds that others set up, and view their history.
- To **create, score, or manage** rounds themselves, they must subscribe.
- New users get a **30-day free trial** to experience all Premium features.
- After the trial, if they don't subscribe, they drop to the free tier but keep access to all their historical data (groups, rounds, leaderboards).

**Two subscription products:**
- Monthly
- Annual (better per-month value)

Both are auto-renewing subscriptions sold through Apple's App Store (StoreKit). Apple takes 15-30% of each sale.

**The economic thesis:**
> The scorer is the person doing real work and getting real value. Price by that role. Non-scoring players participate for free. This converts 2–5× better than gating by "creator" alone, because multi-tee-time groups (10+ players) need multiple scorers — each of whom needs their own subscription.

---

## 2. Products and pricing

### Subscription products
Configured in App Store Connect, sold through Apple's in-app purchase system.

| Product ID | Type | Duration | Introductory Offer |
|---|---|---|---|
| `com.diverseawareness.carry.premium.monthly` | Auto-renewing | 1 month | 30-day free trial |
| `com.diverseawareness.carry.premium.annual` | Auto-renewing | 1 year | 30-day free trial |

Actual prices are set in App Store Connect and can be changed without a code release. Current prices are whatever was most recently set there — the app pulls them dynamically via StoreKit.

### How to change prices
1. App Store Connect → Apps → Carry → Monetization → Subscriptions
2. Select the subscription group → select the product
3. Set a new price (Apple has pre-defined price tiers; you pick one)
4. Users on existing subscriptions get the old price; new subscribers pay the new price
5. Price changes can take 24h to propagate

### How to change the trial length
1. Same path — select the product → **Subscription Information** → **Introductory Offer**
2. Change "Free Trial" duration (currently 30 days, previously 7 days)
3. Submit the change — applies to new subscribers immediately, takes effect within minutes

Important: Apple limits trial eligibility. **A single Apple ID gets ONE free trial per subscription group, ever.** If someone subscribes, cancels, and tries again later, they don't get another free trial. This is Apple's rule, not ours.

---

## 3. The 30-day free trial

### What happens when a user starts the trial
- They tap "Start Free Trial" on the paywall (or equivalent) → Apple's system purchase sheet appears
- They confirm with Face ID / Touch ID / password
- They're charged $0 immediately
- They get a receipt showing the trial started + the date they'll be charged (30 days out)
- Premium is unlocked instantly — the app detects the active subscription via StoreKit and flips `isPremium = true`
- They have full feature access for 30 days

### During the trial
- Full Premium access
- Can cancel any time from **Settings → Apple ID → Subscriptions → Carry**
- If they cancel before the renewal date, they keep Premium until the end of the trial, then drop to free
- If they don't cancel, they're charged the full subscription price on day 30 and stay on Premium

### After the trial ends (no cancellation)
- User is charged the subscription price (monthly or annual)
- Nothing changes in their experience — they just keep Premium

### After the trial ends (they cancelled or payment failed)
- `isPremium` flips to `false`
- They're on the post-trial free tier (see §5)
- Their data is preserved — nothing is deleted
- They can re-subscribe any time, but **cannot use the trial again** (Apple rule)

### Why 30 days (not 7)?
The trial length was bumped from 7 days to 30 days for these reasons:

1. **Golfers play weekly, not daily.** A 7-day trial gives them one round. They don't have time to form a habit.
2. **Habit formation research:** ~21–66 days to cement a new routine (Lally, UCL 2010). 7 days isn't even the minimum.
3. **Network effects need time to spread.** Creator starts trial → invites friends → friends try → pod forms the "check Carry after every round" habit. 7 days barely starts this chain.
4. **Seasonal bias.** April–September is peak golf in most US markets. A month-long trial landing in April means Premium is paid-for by June. Short trials waste early-season momentum.
5. **Industry benchmarks.** SaaS products requiring behavioral change generally convert better on 14–30 day trials than on 7. Daily-use tools (meditation, language learning) convert on 7 because "daily" creates urgency. Golf doesn't.

### Strategic lever: trial length
Trial length is a live variable. If conversion data suggests 30 days is too long (users forget, cancel more), reduce it to 21 or 14. If conversion is weak because people need more time, extend to 45 or 60.

**To change:** ASC → Introductory Offer → Duration.

---

## 4. Free tier — what non-paying users get

### Can do (free forever)
- Sign up, create a Carry account, set their handicap and home club
- Receive invites from Premium users and join their groups
- View rounds they're part of (scorecard in view mode)
- View every leaderboard: **Last Round** AND **All Time**
- View round history / Recent Games cards
- See per-round stats (who won, holes won, final money)
- Edit their own profile (photo, name, home club, handicap index)
- Receive push notifications (group invites, round started, round ended)
- Play up to **3 Quick Games per calendar month** (resets at month rollover)
- Delete or leave groups they're in
- Share results cards (view-only)

### Cannot do (requires Premium)
- Create a **Skins Group** (recurring group with leaderboards)
- Create a **4th Quick Game** in the same calendar month
- **Start a new round** (even in an existing group)
- **Score a round** (tap scores, enter strokes)
- Edit group settings (name, course, buy-in, handicap %, winnings display, carries, scoring mode, tee times, schedule)
- Manage members (add via search, invite via SMS/QR, remove, rearrange across tee times)
- Rearrange tee times / player groups
- Invite via QR code

### Why this split?
The free tier is designed around **reading vs. writing**:
- Reading (passive participation, history, stats) = free.
- Writing (creating, scoring, modifying) = Premium.

This aligns with Apple's guidelines (can't hold user data hostage behind a paywall) and with the economic thesis (scorers do the work, scorers pay).

---

## 5. Post-trial free tier (sticky `hadPremium` state)

If a user *had* Premium (e.g., was on trial) and is now on the free tier, the app treats them slightly differently:

### What's remembered
When a user's `isPremium` flag is ever `true`, the app writes `hadPremium = true` to device storage. This flag is **sticky** — it never flips back to false, even if they cancel, get refunded, or uninstall and reinstall (uninstall clears it, but re-subscribing flips it again).

### How `hadPremium` changes their experience
- **Paywall framing changes.** Instead of a cold "Go Premium" pitch, the paywall's hero title becomes **"Your Premium trial ended"** — reassuring framing acknowledging they used to have it.
- This happens every time they tap a gated action (see §6) — not just once. There's no separate "welcome back" sheet. The paywall itself IS the trial-ended sheet for returning users.

### Why this design?
Post-trial users have different emotional context than first-time users. They know what Premium feels like, they lost it, they might be annoyed. Showing them a first-time pitch is cold and misses the opportunity to acknowledge their history. "Your Premium trial ended" frames re-subscription as *getting back* something, not *buying* something new.

---

## 6. The paywall — every trigger point

The paywall is **one sheet**, used across all gated moments. It shows:
1. A **hero title** — either "Go Premium" (first-time) or "Your Premium trial ended" (returning users).
2. A **contextual subtitle** — explains which action triggered the paywall. E.g., "Starting rounds is a Premium feature."
3. **Feature list** — what Premium unlocks.
4. **Plan cards** — Annual and Monthly options, with introductory trial copy.
5. **Terms of Service + Privacy Policy** links.
6. **Dismiss X** — always bypassable. No paywall is ever unskippable.

### Every place the paywall can appear

| Trigger | When it fires | Contextual subtitle |
|---|---|---|
| **Start Round** | Creator taps "Start Round" button on group detail | "Starting rounds is a Premium feature" |
| **Score Round** | Non-premium scorer taps a score selector on the scorecard | "Scoring rounds is a Premium feature" |
| **Create Skins Group** | Free user taps the "Skins Group" card in New Game picker | "Recurring Skins Groups are Premium" |
| **Manage Group** | Creator taps QR Invite, "Invite & Manage", or Save in group settings / player groups | "Managing groups is a Premium feature" |
| **Quick Game Limit** | Free user tries to start their 4th Quick Game in one calendar month | "You've used all 3 free Quick Games this month" |
| **All Time Leaderboard** | (Currently free — was gated; removed in Free Tier v2) | — |
| **General** | Fallback for generic Upgrade buttons (Profile tab, etc.) | (no subtitle) |

### Visual treatment for gated controls
Rather than hide premium features from free users, we **show them as "visible but locked"**:
- Button or tappable element stays in place, normally-positioned.
- Opacity drops to ~50% so it looks dimmed.
- A small **gold crown icon** (👑) overlays the corner or sits inline as a suffix.
- Tapping opens the paywall (instead of invoking the action).
- Accessibility label is "Requires Premium subscription".

**Why "show dimmed" instead of "hide"?**
1. Discoverability — users learn what Premium unlocks by seeing it locked.
2. Conversion — a visible locked control is a quiet upsell every time they look at it.
3. Consistency — users don't get confused by a button "moving" when they subscribe.

---

## 7. How the gate logic works (mental model)

For each gated action, the app checks **two things**:
1. Is this action gated? (If yes, this feature requires Premium.)
2. Is the user Premium? (`isPremium == true`)

If the action is gated AND the user is not Premium, the paywall sheet opens with the right trigger. Otherwise the action runs normally.

**Creator vs. scorer vs. general user:**
- Some gates require being the group's **creator** (creators edit groups)
- Some gates require being the round's **scorer** (scorers enter scores)
- Some gates apply to everyone (anyone trying to create a group, anyone on the 4th Quick Game)

A free user who is NOT a creator or scorer in any group isn't affected by most gates — they just see the "You need Premium to do X" message only when they try to do something Premium.

---

## 8. Key strategic decisions (and the reasoning)

### Decision 1: Gate scoring, not just creating
**The tradeoff:** If we only gate round creation, one Premium creator can serve a whole group of free players. That's "1 sub per group."

If we also gate scoring, every scorer needs their own subscription. In a group with 2–5 tee times (common for larger leagues), that's 2–5× the revenue.

**The risk:** If a group's scorers won't subscribe, the group can't function — people might go back to paper scorecards.

**The mitigation:** The people willing to score are by definition the most engaged users, and they get a 30-day trial to decide. Peer pressure within the group ("don't be the one who breaks Saturday skins") works in our favor.

**Decision: Gate both.** The economic uplift outweighs the churn risk.

### Decision 2: Never hold historical data hostage
Users can always **view** their past rounds, leaderboards, and history — regardless of subscription state. Only **new writes** require Premium.

**Why:**
- Apple's App Store guidelines frown on apps that lock user-generated content behind a paywall after granting access.
- Emotionally, "pay to see your own data" is punitive. "Pay to create more" is a value proposition.
- Competitors (Evernote, Notion, etc.) have had public backlash for hostage-style pricing.

### Decision 3: No separate "trial ended" welcome sheet
Originally we considered a one-time "Hi, your trial ended, here's what you can still do" modal on first launch after expiry. We dropped it.

**Why:**
- The paywall itself handles the framing via `hadPremium` — hero title becomes "Your Premium trial ended".
- Fires at the moment of intent (tapping a gated action) — well-timed, not intrusive.
- Simpler to build and maintain.

### Decision 4: No Home banner nagging post-trial users
We considered a persistent "Upgrade" banner at the top of the Home tab for trial-ended users. We dropped it.

**Why:**
- The paywall already fires when they try gated actions — natural prompt.
- Nagging a disengaged user correlates more with uninstall than conversion.
- The "Upgrade to Premium" button in Profile is always available for users who want to self-serve.

### Decision 5: Delete Group + Leave Group always free
Exit paths stay open regardless of subscription state. Per Apple guidelines and common sense — never make someone pay to leave.

### Decision 6: TestFlight override flag
`grantPremiumInTestFlight = true` grants all testers Premium for free on TestFlight builds. This lets internal/external testers experience paid features without real purchases. **Must be flipped to `false` before every App Store archive** or Apple reviewers get Premium for free too.

### Decision 7: 3 Quick Games per calendar month for free users
Free users get a small taste of actively creating games — 3 per month, resets on the 1st. Not server-tracked (stored on device), so uninstall/reinstall resets the counter. Known trade-off; acceptable for simplicity.

---

## 9. Apple App Store considerations

### Relevant guidelines
- **3.1.1** — In-app purchases must be used for unlocking features or functionality. We use auto-renewing subscriptions, compliant.
- **3.1.2(a) Subscriptions** — subscriptions must provide ongoing value, can't be used for one-time content. Ours provides ongoing access to creation and scoring features. Compliant.
- **3.1.2 / Spirit clause** — apps must not hold user-generated data hostage. Our free tier provides read access to historical data. Compliant.
- **5.1.1 (iv)** — apps must provide a way to delete account + data. We have that in Profile → Delete Account. Compliant.

### Review-risk areas to watch
- **Trial length changes** — don't reduce dramatically (e.g., 30 → 3 days) without reason; can draw reviewer attention.
- **Adding more gates** — if we add future gates (e.g., "view your own round history"), likely rejected. Keep gates on writes, not reads.
- **Paywall copy** — avoid misleading language ("free forever", "no catches", etc.) when there's a trial with auto-renewal.
- **Renewal disclosure** — required by Apple: must clearly show "Auto-renews at $X/mo unless cancelled 24h before" on the paywall. Already present in the Plan cards.

---

## 10. What to measure for strategy

### Top-line metrics
- **Trial starts / Install** — how many users opt into the trial vs. just browse
- **Trial-to-paid conversion** — % of trial users who become paying subscribers
- **Annual vs. monthly split** — most SaaS sees 20-40% annual; golf's seasonal nature might push higher annual
- **Churn** — % of paying users who cancel each month (steady state target: <5%)
- **LTV (Lifetime Value)** — average revenue per paying user over their lifetime

### Conversion funnel metrics
- **Paywall views by trigger** — which action drives the most paywall opens?
- **Paywall-to-subscribe rate by trigger** — some triggers convert better than others
  - Expected high converters: Score Round (high intent, in-flow), Quick Game Limit (value proof point)
  - Expected low converters: Create Group (first visit, cold)
- **Dismissal rate** — how often users close the paywall without buying

### Free-tier behavior
- **Quick Games played / free user / month** — are users hitting the 3-game limit? If most hit it, the limit is a conversion lever. If most play 1, the limit doesn't matter.
- **Group invitations accepted** — how many free users are in groups? Each is a potential scorer → potential conversion
- **Recent Games opened / free user** — are free users coming back to view history? Strong engagement signal

### Cohort metrics worth building
- **30-day retention by trial length** — compare 30-day trial cohort to historical 7-day cohort
- **Month-of-trial-start cohorts** — April starts vs. November starts (seasonality)
- **Scorer role conversion rate** — free users who receive a scorer invite → what % convert? This is the BIG lever

---

## 11. Open strategic questions

These are decisions that haven't been made yet or are actively under consideration:

### Pricing
- **What prices should annual and monthly be?** Current values are placeholder — need a pricing strategy. Common golf-app pricing: $49–79/yr, $7–10/mo. Options: match competitors, price below, price above on premium positioning.
- **Regional pricing?** Apple supports per-country pricing. Worth considering for UK, Australia, etc. where golf is popular but economics differ.
- **Lifetime purchase option?** One-time fee (e.g., $199) for lifetime access. Adds complexity but gives commitment-averse users an option.

### Trial
- **Still 30 days or adjust after launch data?** Track trial-to-paid conversion by week of trial. If dropout is concentrated in days 20–30, trial might be too long. If dropout is in days 1–5, trial might be too short.
- **Extended trial for specific users?** Invite-code-based longer trials for influencers / early adopters?

### Tier structure
- **Two-tier (current) vs. three-tier?** Premium vs. free is simple. A middle tier (e.g., "Solo" — for individuals who want to track their own rounds but not groups) could expand TAM.
- **One-time purchase for casual users?** E.g., "Pay $2.99 to run this one round" as an alternative to a full subscription. Apple allows "non-consumable IAPs" alongside subscriptions.

### Promotional strategy
- **Referral program?** "Invite a friend, get a month free." Would require server-side tracking.
- **Seasonal promotions?** Discounted annual during off-season (November–February) to lock in summer revenue.
- **Partnership deals?** Golf course partnerships for member discounts.

### Paywall UX experiments
- **Contextual copy variations** — test different wording per trigger. "Scoring requires Premium" vs. "Unlock scoring" vs. "Keep the live leaderboard going."
- **Plan card order** — Annual first (current) vs. Monthly first vs. auto-default based on heuristics.
- **Urgency mechanics** — "Join 10,000+ golfers" social proof, countdown on discount offers, etc.

### Retention levers
- **Win-back emails for lapsed Premium users?** Apple doesn't let you email IAP users directly — would need a side account system.
- **Push notifications celebrating round milestones** for free users (build habit → trial)?
- **Onboarding tweaks** — what % of new installs start the trial? Currently the trial prompt only fires when they try a gated action. Should there be an upfront offer?

---

## 12. Things to verify before strategic decisions

If you're making strategic calls, these are the facts you'd want to confirm because they drive the math:

1. **Current trial-to-paid conversion rate** — we don't have this yet because we haven't shipped Free Tier v2
2. **Current subscription prices in App Store Connect** — placeholder values, need setting
3. **Annual vs. monthly uptake** — need post-launch data
4. **Apple's take** — 30% year 1, 15% year 2+ for subscriptions (can factor into pricing)
5. **Competitor pricing** — survey 5–10 golf apps with subscriptions for a benchmark

---

## 13. Where to read more (in the repo)

For the engineers or anyone wanting code-level detail:
- Entitlement + paywall state: `carry/Carry/Services/StoreService.swift`
- The paywall sheet: `carry/Carry/Views/PaywallView.swift`
- Trigger enum + contextual copy: top of `PaywallView.swift`
- Paywall gating logic: `PremiumGatedButton.swift` + inline gates in `GroupManagerView.swift`, `ScorecardView.swift`, `PlayerGroupsSheet.swift`
- Free-tier 3 Quick Games/month counter: `GroupsListView.swift` (uses `@AppStorage`)

---

## 14. Summary for strategy sessions

The monetization model is:
- **Free** = passive participation, history, and 3 Quick Games/month. Joinable groups, viewable leaderboards.
- **Premium** ($price/mo or $price/yr) = active play: create groups, start rounds, score rounds, manage everything.
- **Trial** = 30 days of Premium, automatic, cancellable.
- **Gate triggers** = 6 distinct moments, each with contextual copy.
- **Post-trial** = data stays accessible, return to free tier.

The scorer-gating decision is the single biggest revenue lever in the current design. Every strategic conversation about pricing, trial, conversion, etc. should be grounded in **how the scorer role converts** — that's the economic engine.
