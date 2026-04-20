# Carry Design System

## About This Document

Single source of truth for visual design in the Carry iOS app. Every color, font, spacing value, component spec, and interaction pattern needed to build consistent screens is defined here.

**How to use this document:**
- When building a new view, screen, or component, reference this document for all styling decisions
- Never hardcode colors, fonts, or token-able values — always reference `Color.xxx`, `Font.carry.xxx`, etc.
- When in doubt, refer to the principles at the end
- If you need a value that isn't defined, add it to the relevant source file (`CarryColors.swift`, `TypeRamp.swift`) and update this doc

**Target user profile:**
- Golfers aged 25–65, playing recreational skins games with friends
- Uses the app **during a round** — one-handed, on the course, outdoor glare
- Primary user role is **scorer** (entering scores for their group) — they are the most engaged, price-sensitive user
- Values speed, readability, low friction. Not interested in gamification.

---

## Design Principles

1. **Scorecard first.** The live scoring surface is the core product. Every other screen should feel lighter by comparison — never denser.
2. **Reading free, writing Premium.** Locked controls must be **visible + dimmed + gold crown badge** — never hidden.
3. **Gold = Premium signal.** Reserved for Premium cues (crown, upgrade CTAs) and winnings amounts. Not a generic accent.
4. **Monochrome + one accent.** Most screens are grayscale + gold (or grayscale + deep navy). Avoid rainbow.
5. **Rounded, not sharp.** Default corner radii 12–16pt. Hard corners only on small pills or grid lines.
6. **Generous whitespace.** Rows have 12–15pt vertical padding. Dense lists feel spreadsheet-y.
7. **Motion as confirmation.** Spring for interactions, ease-out for state. No elastic flourish.

---

## Responsive Design (All iPhone Sizes)

Build views that work across all iPhone sizes (SE 375pt → Pro Max 430pt):

- **Never hardcode widths** — use `.frame(maxWidth: .infinity)` instead of fixed widths
- **Use stack spacing parameters** — `VStack(spacing: 12)` instead of `Spacer().frame(height: 12)`
- **Never hardcode line breaks** — `VStack { Text("A"); Text("B") }` instead of `Text("A\nB")`
- **Let text wrap** — use `.multilineTextAlignment()` + `.lineLimit()`, don't force breaks
- **Minimum-scale fallback for constrained text** — `.minimumScaleFactor(0.85)` on buttons and labels that can't wrap
- **Respect safe areas** — `.padding()` respects safe area by default; use `.ignoresSafeArea()` intentionally

```swift
// GOOD
VStack(spacing: 12) {
    Text("Carry is a Scorekeeper")
        .font(.carry.sheetTitle)
    Text("Dollar amounts are for tracking only")
        .font(.carry.bodySM)
        .multilineTextAlignment(.leading)
}
.padding(.horizontal, 24)
.frame(maxWidth: .infinity)

// BAD
VStack {
    Text("Carry is a Scorekeeper")
    Spacer().frame(height: 16)              // hardcoded
    Text("Dollar amounts\nare for tracking") // hardcoded break
}
.frame(width: 350)                           // fixed width breaks on SE
```

### Device targets

| Aspect | Value |
|---|---|
| Min deployment | iOS 17.0 |
| Narrowest device | iPhone SE 3rd gen (375pt wide) |
| Tallest device | iPhone 15 Pro Max (932pt tall) |
| Oldest supported chip | A12 (iPhone XS, iPhone XR, 4GB RAM) |
| iPad | **Not supported** — iPhone-only layouts |
| Orientation | Portrait only |

Test every new screen on iPhone SE 3rd gen or SE 2nd gen — if it breaks there, it breaks.

---

## Color System

All colors live in `carry/Carry/CarryColors.swift` as `Color` extensions. Reference by semantic token name — never raw hex in views.

### Text

| Token | Hex | RGB | Usage |
|---|---|---|---|
| `textPrimary` | `#1A1A1A` | 26, 26, 26 | Headlines, primary content |
| `textSecondary` | `#999999` | 153, 153, 153 | Sub-labels, metadata |
| `textTertiary` | `#6E6E73` | 110, 110, 115 | Descriptions, helper text |
| `textDisabled` | `#AEAEB2` | 174, 174, 178 | Disabled controls, negative money |
| `textDark` | `#404142` | 64, 65, 66 | Occasional darker emphasis |
| `textMid` | `#888888` | 136, 136, 136 | Mid-gray variation |
| `textSubtle` | `#7B7F86` | 123, 127, 134 | Quiet inline text |

### Backgrounds

| Token | Hex | Usage |
|---|---|---|
| `bgPrimary` | `#F0F0F0` | App canvas — default background (NOT pure white) |
| `bgSecondary` | `#F5F5F5` | Tinted strips, banners, section headers |
| `bgCard` | `#FAFAFA` | Light card background |
| `Color.white` | `#FFFFFF` | True white — use for premium emphasis (Round Stats card body) |

### Borders & dividers

| Token | Hex | Usage |
|---|---|---|
| `borderLight` | `#D1D1D6` | Input field strokes |
| `borderMedium` | `#CCCCCC` | Disabled button backgrounds |
| `gridLine` | `#D0D0D0` | Scorecard grid lines |
| `borderSubtle` | `#E5E5EA` | Quiet separators |
| `borderFaint` | `#E5E5E5` | Row dividers inside cards |
| `borderSoft` | `#BBBBBB` | $0 money color |
| `dividerLight` | `#D9D9D9` | Section dividers |
| `dividerMuted` | `#AAAAAA` | Stronger section breaks |
| `bgLight` | `#E0E0E0` | Divider alt, border alt |

### Brand — Gold (Premium signal)

| Token | Hex | Usage |
|---|---|---|
| `gold` | `#D4A017` | "You" tag color, primary gold |
| `goldMuted` | `#C4A450` | Positive winnings amount, muted gold variant |
| `goldDark` | `#C5A44E` | Paywall legal link color |
| `goldAccent` | `#CAA23E` | Crown icons, Upgrade CTAs, premium badges |
| `goldStandard` | `#FFD700` | Bright gold — reserve for celebration moments only |

### Brand — Other

| Token | Hex | Usage |
|---|---|---|
| `deepNavy` | `#181D27` | Primary CTA button background (Start Round, Save), score input box |
| `venmoBlue` | `#008CFF` | Venmo-branded elements (currently unused) |
| `debugOrange` | `#C0713B` | "Pending" / "Invited" labels, debug menu accents |

### Scores

| Token | Hex | Usage |
|---|---|---|
| `birdieGreen` | `#2ECC71` | Birdie score indicator |
| `bogeyRed` | `#E05555` | Bogey+ indicator |
| `successGreen` | `#064102` | Dark success text |

### Status

| Token | Hex | Usage |
|---|---|---|
| `concludedGreen` | `#BCF0B5` | Disclaimer bullets, concluded round tint |
| `successBgLight` | `#D9F7D2` | Skins Group picker card background |
| `mintLight` | `#B5EEB0` | Avatar fallback circle fill |
| `mintBright` | `#A9E3A5` | Avatar fallback circle stroke |
| `greenDark` | `#215B1D` | Avatar fallback initials |
| `systemRedColor` | `#FF3B30` | Destructive actions (Delete Account, Cancel Round) |

### Pending player (invited, not yet accepted)

| Token | Hex | Usage |
|---|---|---|
| `pendingBg` | `#FFE9D0` | Pending player row background |
| `pendingFill` | `#CB895D` | Pending avatar border + label color |
| `pendingBorder` | `#F8D6C4` | Pending row border |

### Color rules

- Never use raw hex in view code — always reference `Color.xxx`
- Adding a new color = add a token to `CarryColors.swift`, not inline
- Gold family = Premium/winnings/celebration only; no generic accents
- Dark mode: **not currently supported**. Palette is light-mode only. Post-launch feature.

### Semantic shortcuts (not yet tokenized, but consistent)

These patterns aren't in the Color extension but are used consistently:

| Pattern | Color |
|---|---|
| Positive money | `goldMuted` |
| Negative money | `textDisabled` |
| Zero money | `borderSoft` |
| "You" tag background | `gold.opacity(0.10)` |
| Pressed button overlay | `opacity(0.9)` |
| Disabled button overlay | `opacity(0.5)` |

---

## Typography

Type ramp in `carry/Carry/TypeRamp.swift`. Reference via `.font(.carry.xxx)`. All system font (SF Pro), no custom fonts (one fallback `ANDONESI-Regular` used ONLY for avatar fallback initials).

### Display (score entry, celebration)

| Token | Size | Weight | Usage |
|---|---|---|---|
| `displayXL` | 52pt | Bold | Full-screen score input numbers |
| `displayLG` | 40pt | Bold | Score sheet display |
| `displayMD` | 36pt | Bold | Winner money amount |
| `displaySM` | 32pt | Semibold | Skins count, large emphasis |

### Titles

| Token | Size | Weight | Usage |
|---|---|---|---|
| `pageTitle` | 28pt | Semibold | Top-level screens (Rounds, onboarding) |
| `sheetTitle` | 26pt | Semibold | Modal/sheet titles (Add Players) |
| `sectionTitle` | 20pt | Semibold | Section headers |

### Headlines

| Token | Size | Weight | Usage |
|---|---|---|---|
| `headline` | 17pt | Semibold | Card titles, primary actions, scorecard header |
| `headlineBold` | 17pt | Bold | Emphasis variant |
| `label` | 18pt | Medium | Sticky player labels (base) |
| `labelBold` | 18pt | Bold | Sticky "you" label |

### Body

| Token | Size | Weight | Usage |
|---|---|---|---|
| `bodyLG` | 16pt | Medium | Large body, taglines |
| `bodyLGSemibold` | 16pt | Semibold | Large body emphasis |
| `bodyLGBold` | 16pt | Bold | Money pill amounts |
| `body` | 15pt | Medium | Standard list items |
| `bodySemibold` | 15pt | Semibold | Secondary buttons, tab labels |
| `bodySM` | 14pt | Medium | Tertiary body, descriptions |
| `bodySMSemibold` | 14pt | Semibold | Small emphasis |
| `bodySMBold` | 14pt | Bold | Small bold labels |

### Captions

| Token | Size | Weight | Usage |
|---|---|---|---|
| `captionLG` | 13pt | Medium | Helper text |
| `captionLGSemibold` | 13pt | Semibold | Caption emphasis |
| `caption` | 12pt | Medium | Metadata |
| `captionSemibold` | 12pt | Semibold | Tab labels |
| `captionBold` | 12pt | Bold | Bold caption |

### Micro

| Token | Size | Weight | Usage |
|---|---|---|---|
| `micro` | 11pt | Semibold | Pill badges, tab bar labels |
| `microBold` | 11pt | Bold | Bold micro |
| `microSM` | 10pt | Semibold | Subscripts ("STROKES") |
| `microXS` | 8pt | Bold | Tiny badges |

### Letter spacing (tracking)

```swift
CarryTracking.tight   // -0.4  — tighten headlines for impact
CarryTracking.wide    // 1.0   — uppercase labels (ACCOUNT, SUBSCRIPTION)
CarryTracking.wider   // 1.5   — pill/badge labels
```

### Typography rules

- **Never** use `.font(.system(size:weight:))` directly — always a ramp token
- If a new size/weight is truly needed, add to `TypeRamp.swift`
- No custom fonts (system font only)
- **Dynamic Type is a known TODO** — 299 hardcoded font sizes exist; full migration is a large refactor

---

## Spacing

Carry does NOT currently have a formal spacing token system. Values are used inline but consistently. Below are the conventions — consider these de facto tokens until formalized.

### Standard spacing values used

| Context | Value | Common usage |
|---|---|---|
| Inline tight | 4pt | `HStack(spacing: 4)` between interpunct + text |
| Inline standard | 5–6pt | Between inline icon + label, inline pill + text |
| Stack small | 8pt | Between vertically stacked mini elements |
| Stack standard | 10–12pt | Avatar ↔ text spacing, row internal gap |
| Stack medium | 14–16pt | Between cards, between form fields |
| Stack large | 20–24pt | Between major sections |
| Section break | 32–40pt | Between screen-level sections |

### Standard padding values

| Context | Value |
|---|---|
| Horizontal screen edge | 20–24pt (24 default, 20 for denser screens) |
| Row horizontal padding (inside cards) | 16–18pt |
| Row vertical padding | 12–15pt (Round Stats uses 15, most lists 12) |
| Card internal padding | 14–16pt |
| Card top padding | 16pt |
| Card bottom padding | 12–18pt |
| Sheet top padding (below handle) | 24pt |
| Sheet horizontal padding | 20pt |

### Component-specific spacing

| Component | Value |
|---|---|
| Between tabs | 16pt |
| Between form fields | 20pt |
| Between buttons (stacked) | 12pt |
| Icon to text (inline) | 5–8pt |
| Pill badge padding | 5pt horizontal, 1pt vertical |
| Avatar to name (row) | 10–12pt (38pt avatar uses 12, 34pt avatar uses 10) |

### Spacing debt (tracked for cleanup)

- No formal `Spacing` enum — mixed inline values
- 299 hardcoded font/size/padding values across codebase
- Proposal: introduce `Spacing.xxs/xs/sm/md/base/lg/xl/xxl/xxxl` enum mirroring Sonia's pattern in future refactor

---

## Border Radius

No formal `BorderRadius` token system. Values used consistently:

| Value | Common usage |
|---|---|
| 4–6pt | Tiny badges, mini stroke elements |
| 8–10pt | HandicapPickerSheet buttons, small badges |
| 12pt | Cards (default), input fields, standard buttons |
| 14pt | ScorerAssignmentView row, HandicapPicker main card |
| 16pt | Large cards (Round Stats, Upgrade button), input fields alt |
| 18pt | Auth "Sign in with Apple" button |
| 19pt | Score input box, Done button |
| 20pt | ScoreInputSheet container, score pills |
| `Capsule()` | Pills, tabs, tags, "You" badge |

### Component-specific radii

| Component | Radius |
|---|---|
| Primary button (Start Round) | 12pt |
| Secondary / outlined button | 12–16pt |
| Apple Sign In button | 18pt |
| Text input (standard) | 12pt |
| Text input (picker card) | 14pt |
| Player search row | 14pt |
| Card (Round Stats, generic) | 16pt |
| Score input box | 19–20pt |
| Chat-like message | 20pt |
| Modal/Sheet | 16pt (system provides), corners fully rounded |
| Avatar | `Circle()` |
| Badge / pill | `Capsule()` |
| Crown badge overlay | `Circle()` on white bg |

### Border radius debt

- Slight inconsistency: 18 vs 19 vs 20 for similar-size elements
- Proposal: consolidate to 4 / 8 / 12 / 16 / 20 / Capsule — each with a named token

---

## Shadows & Elevation

Carry mostly uses **flat surfaces with borders** rather than shadows. When shadows are used, they're subtle.

| Context | Value | Usage |
|---|---|---|
| No shadow | default | 95% of surfaces |
| Subtle lift | `.shadow(color: .black.opacity(0.06), radius: 6, y: 2)` | CashGamesBar at rest |
| Celebratory lift | `.shadow(color: .black.opacity(0.12), radius: 8, y: 2)` | CashGamesBar during celebration |
| Share card stack | `.shadow(color: .black.opacity(0.03), radius: 6, y: 4)` | Behind share card preview |
| Share card emphasis | `.shadow(color: .black.opacity(0.08), radius: 16, y: 12)` | In front of share card preview |

### Shadow rules

- Default is NO shadow. Prefer borders (`strokeBorder(borderFaint)`).
- If you need elevation, use the "subtle lift" recipe — don't invent new values.
- Shadow color is always `.black.opacity(x)` — no tinted shadows.

---

## Animation

No formal `Animation` token enum. Conventions below.

### Duration (approximate, by role)

| Role | Value | Usage |
|---|---|---|
| Micro-interaction | 150–200ms | Tap feedback, toggle switches |
| Standard transition | 200–250ms (ease-out) | Sheet appear/dismiss, tab switch |
| Page-level | 300–400ms (spring) | Screen pushes, major state changes |
| Celebratory | 500ms+ (spring) | Skin-won confetti, score reveal |

### Easing recipes used

```swift
.easeOut(duration: 0.2)                                           // quick state flip (tab selection)
.easeOut(duration: 0.25)                                          // sheet content show/hide
.easeInOut(duration: 0.2)                                         // collapse/expand chevrons
.spring(response: 0.3, dampingFraction: 0.85)                     // row insertions
.spring(response: 0.38, dampingFraction: 0.82)                    // major state change (round complete)
.spring(response: 0.4, dampingFraction: 0.8)                      // score input reveal/dismiss
```

### Animation rules

- Always attach animation to **state**, not `.onAppear` (except screen-entry animations)
- Spring for user-initiated interactions (feels tactile)
- Ease-out for system transitions (predictable)
- No elastic flourishes (dampingFraction < 0.7) — feels cheap
- **Reduce Motion support is a TODO** — currently not honored. Plan: wrap springs in `@Environment(\.accessibilityReduceMotion)` check, fallback to `.linear(duration: 0.01)`

---

## Components

### Buttons

Primary action surfaces. Three shapes: **pill (`Capsule()`)**, **rounded rect (12pt)**, **outlined**.

#### Button types

| Type | Background | Text | Border | Usage |
|---|---|---|---|---|
| **Primary (Navy)** | `textPrimary` / `deepNavy` | white | — | Main CTA (Start Round, Save, I Understand) |
| **Primary (Gold)** | `goldAccent` | white | — | Upgrade CTA, Premium purchase |
| **Secondary** | transparent | `textPrimary` | 1.5pt `deepNavy` | Alternative actions |
| **Tertiary** | `bgPrimary` | `textPrimary` | — | Tab backgrounds, quiet actions |
| **Destructive** | `systemRedColor` or inline red text | white / `systemRedColor` | — | Delete Account, Cancel Round |
| **Ghost** | transparent | `textSecondary` | — | Cancel, "Maybe Later" |
| **Premium-Gated** | (parent type, dimmed 50%) | parent | parent + gold crown badge | Non-premium attempt on gated control |

#### Button sizes

| Size | Height | Font | Common usage |
|---|---|---|---|
| Large | 56pt | `.carry.body` semibold | Upgrade to Premium, screen-bottom CTAs |
| Standard | 51pt | `.carry.bodyLGSemibold` | Start Round, Apple Sign In |
| Medium | 48pt | `.carry.bodySemibold` | Standard buttons in sheets |
| Small (pill) | 36pt | `.carry.bodySMBold` | "+ Add Group", tab pills |
| Tiny (inline pill) | ~28pt | `.carry.captionLG` or `micro` | Upgrade pill in banners, badges |

#### Button states

| State | Opacity | Additional |
|---|---|---|
| Default | 100% | — |
| Pressed | 90% | Optional scale 0.98 |
| Disabled | 50% | `.disabled(true)` — no interaction |
| Loading | 100% | Swap text for `ProgressView()` |
| Locked (Premium) | 50% | Gold crown badge overlay, tap → paywall |

#### Implementation — Primary Navy (51pt standard)

```swift
Button { action() } label: {
    Text("Start Round")
        .font(.carry.bodyLGSemibold)
        .foregroundColor(buttonEnabled ? .white : Color.textSecondary)
        .frame(width: 322, height: 51)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(buttonEnabled ? Color.textPrimary : Color.borderMedium)
        )
}
.disabled(!buttonEnabled)
```

#### Implementation — Secondary Outlined (56pt)

```swift
Button { action() } label: {
    Text("Upgrade to Premium")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(Color.deepNavy)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.deepNavy, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
}
.buttonStyle(.plain)
```

---

### Text inputs

| Property | Value |
|---|---|
| Default height | 50–52pt (single line) |
| Horizontal padding | 14–16pt |
| Vertical padding | 12–14pt |
| Border radius | 12pt (default), 14pt (picker card) |
| Border | 1pt `borderLight` |
| Background | `.white` |
| Focused border | Darker stroke (via `.carryInput(focused:)` modifier) |
| Font | `.carry.bodyLG` (16pt medium) |
| Placeholder color | `textSecondary` |

#### Input states

| State | Border | Background |
|---|---|---|
| Default | 1pt `borderLight` | `.white` |
| Focused | Auto-darkening stroke (`.carryInput(focused:)`) | `.white` |
| Error | 1pt `systemRedColor` | `.white` |
| Disabled | 1pt `borderSubtle` | `bgPrimary` |

Use `CarryTextField` component or `.carryInput(focused:)` modifier — don't style from scratch.

---

### Cards

| Property | Value |
|---|---|
| Background | `.white` or `bgCard` |
| Border | 1pt `borderFaint` (optional) |
| Border radius | 16pt (default), 14pt (search row), 12pt (inline) |
| Padding | 14–18pt internal |
| Shadow | None (default), subtle (`0.06 opacity`) only when lifted |

#### Card types

**Standard card** — white bg, faint border, 16pt radius. Round Stats, results summary.

**Tinted card** — `bgSecondary` bg, no border, 12pt radius. Upgrade banners, section containers.

**Accent card** — `successBgLight` or similar tinted bg, no border, 32pt radius. New Game picker cards (Skins Group, Quick Game).

**Two-tone card** — `bgSecondary` header strip + `.white` body, 16pt outer radius with `borderFaint` stroke. Round Stats.

---

### Navigation

#### Tab Bar

Currently custom-built (not system `TabView`). Three tabs:

| Tab | Icon | Label |
|---|---|---|
| Home | `house.fill` (SF Symbol) + custom assets | "Home" |
| Skins Games | `trophy.fill` or custom | "Skins Games" |
| Profile | `person.crop.circle.fill` or custom | "Profile" |

| Property | Value |
|---|---|
| Height | ~58pt + safe area |
| Background | `.white` with top border |
| Icon size | 20–22pt |
| Label font | `.carry.micro` |
| Active color | `textPrimary` |
| Inactive color | `textSecondary` |

#### Navigation "header"

Screens don't use UINavigationBar — instead custom top headers:

| Property | Value |
|---|---|
| Top inset | Safe area + ~16pt |
| Title font | `.carry.pageTitle` (28pt semibold) or `.carry.sheetTitle` (26pt) |
| Back / Close button | 40×40pt tappable, icon 16pt, optional circle background |
| Horizontal padding | 20–24pt |

---

### Sheets & Modals

#### Bottom sheet (system `.sheet`)

| Property | Value |
|---|---|
| Background | `.white` or `presentationBackground(.white)` |
| Top corners | Apple system (rounded) |
| Drag indicator | `.presentationDragIndicator(.visible)` |
| Detents | `.medium` / `.large` / `.height(x)` |
| Title padding | 24pt top, 20pt horizontal, 20pt bottom |
| Content horizontal padding | 20–24pt |

#### Full-screen cover

Used for Auth, Onboarding, Course Selector, Debug Menu:

| Property | Value |
|---|---|
| Background | `Color.white.ignoresSafeArea()` |
| Close button | Top right, 40×40pt, X icon |
| Padding | Screen margins |

---

### Lists / Rows

#### Standard settings row (`plainRow`)

| Property | Value |
|---|---|
| Min height | 44pt (Apple minimum tap target) |
| Horizontal padding | 16pt |
| Vertical padding | 14pt |
| Title font | `.carry.bodyLG` (16pt medium) |
| Value font | `.carry.bodyLG` (16pt medium), `textSecondary` |
| Trailing icon | `chevron.right` (11pt, `textSecondary`) |
| Divider | 1pt `borderFaint`, inset 16pt from left |

#### Player / scorer row (58pt — `ScorerAssignmentView` spec)

| Property | Value |
|---|---|
| Height | 58pt |
| Avatar size | 34pt |
| Avatar-to-text | 12pt |
| Name font | `.carry.bodySemibold` |
| Subtitle font | `.carry.bodySM` (`homeClub · HC`) |
| Horizontal padding | 12pt |
| Background | `.white` |
| Border | 1pt `borderLight`, radius 14pt |

#### Leaderboard row (different — 38pt avatar)

| Property | Value |
|---|---|
| Avatar | 38pt |
| Avatar-to-text | 12pt |
| Name font | 17pt semibold |
| Subtitle (HC) font | 12pt semibold, `borderMedium` |
| Row horizontal | 24pt |
| Row vertical | 10pt |

---

### Selection controls

#### Toggle / Switch

Uses system `Toggle` with default iOS styling. No custom overrides except inline labels.

#### Picker (Wheel — HandicapPickerSheet pattern)

| Property | Value |
|---|---|
| Height | 260pt |
| Selection highlight | `RoundedRectangle(cornerRadius: 8)` |
| Value cell padding | Standard Apple wheel |
| HC/+HC toggle | Pill group, 36pt height, `Capsule()` |

---

### Avatars

| Size | Usage |
|---|---|
| 34pt | Compact search rows, inline player references |
| 38pt | **Leaderboard rows, round stats (standard)** |
| 44pt | Teaser cards, intermediate |
| 58pt | Sticky player labels during scoring |
| 86pt | Profile header |

#### Avatar states

| State | Treatment |
|---|---|
| Active (confirmed) | Full opacity, green/user color fill |
| Pending | 50% opacity + orange border (`pendingFill`) |
| Fallback (no photo) | Mint-green circle + initials in `greenDark`, font `ANDONESI-Regular` 35pt |

---

### Feedback & Status

#### Toast

Top-anchored, transient.

| Type | Accent | Usage |
|---|---|---|
| `.success` | Green | Scorer accepted, member joined |
| `.error` | Red/orange | Save failed, network issue |
| `.info` | Neutral gray | Informational nudges |

| Property | Value |
|---|---|
| Background | `.white` with shadow |
| Border radius | 12pt |
| Padding | 16pt |
| Auto-dismiss | ~3s |
| Position | Top, below safe area |

#### Loading states

- **Full screen:** `GolfBallLoader(size: 60)` centered on `.white` background
- **Inline:** `ProgressView()` with `.tint(textSecondary)`
- No skeleton screens — prefer quick transitions

#### Empty states

- Centered illustration or SF Symbol (64pt)
- Title: `.carry.sectionTitle`
- Description: `.carry.body`, `textSecondary`
- Optional CTA button

---

### Premium / Gated Controls

Pattern: **visible + dimmed + gold crown**. Tap opens paywall with contextual trigger.

| Property | Value |
|---|---|
| Opacity on label | 50% |
| Crown icon | `Image("premium-crown")` + `.renderingMode(.template)` + `foregroundColor(Color.goldAccent)` |
| Crown size | 10–16pt (inline) or 14pt (corner badge) |
| Crown position | Either inline suffix (5pt after text) OR top-right corner overlay (circle on white bg, 6pt inset) |
| Tap action | Open paywall sheet with `PaywallTrigger` |

#### Implementation — Inline Crown Suffix

```swift
HStack(spacing: 5) {
    Text("Invite & Manage")
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(Color.textPrimary)
    if !storeService.isPremium {
        Image("premium-crown")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: 11, height: 11)
            .foregroundColor(Color.goldAccent)
    }
}
.padding(.horizontal, 10)
.padding(.vertical, 4)
.background(Capsule().strokeBorder(Color.textPrimary, lineWidth: 1))
.opacity(storeService.isPremium ? 1.0 : 0.6)
```

#### Implementation — Corner Crown Badge (icon buttons)

```swift
ZStack(alignment: .topTrailing) {
    Image(systemName: "qrcode")
        .font(.system(size: 16, weight: .bold))
        .frame(width: 40, height: 40)
        .background(Circle().fill(.white))
        .opacity(storeService.isPremium ? 1.0 : 0.5)

    if !storeService.isPremium {
        Image("premium-crown")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: 10, height: 10)
            .foregroundColor(Color.goldAccent)
            .padding(3)
            .background(Circle().fill(Color.white))
            .offset(x: 2, y: -2)
    }
}
```

Use `PremiumGatedButton` component (`Views/Components/PremiumGatedButton.swift`) where possible — wraps the pattern in a reusable view.

---

## Patterns

### "You" tag (current-user identifier)

Small gold capsule next to the current user's name:

```
[Avatar]  Daniel  [You]
          6.5 · 6 pops
```

| Property | Value |
|---|---|
| Font | `.carry.micro` (11pt semibold) |
| Text color | `Color.gold` |
| Background | `Color.gold.opacity(0.10)` |
| Padding | 5pt horizontal, 1pt vertical |
| Shape | `Capsule()` |

### Money formatting

| Value | Format | Color |
|---|---|---|
| Positive | `$150` (no `+` prefix) | `goldMuted` |
| Negative | `-$50` | `textDisabled` |
| Zero | `$0` | `borderSoft` |

Always use `.monospacedDigit()` on money labels so column widths stay stable.

### "X Skins · Holes Y, Z" line

Per-player stats format:

```
3 Skins · Holes 1, 12, 16
```

| Element | Style |
|---|---|
| "3 Skins" | `.carry.bodySM`, `textSecondary` |
| "·" (interpunct) | `.carry.bodySM`, `textDisabled` |
| "Holes 1, 12, 16" | `.carry.bodySM`, `textTertiary` |

If 0 skins: show just `No Skins` in `textSecondary` (no detail after).

### Two-tone card (Round Stats)

```
┌──────────────────────────────────┐
│ Round Stats             [chevron]│  ← bgSecondary header strip
├──────────────────────────────────┤
│  [Avatar] Daniel         $150    │  ← white body rows
│           6.5 · 6 pops           │
│           3 Skins · Holes 1,12   │
│  ────────────────────────        │
│  [Avatar] Garreth        $100    │
│           ...                    │
└──────────────────────────────────┘
```

- Outer: `RoundedRectangle(cornerRadius: 16)` clip
- Border: 1pt `borderFaint` via `.overlay(RoundedRectangle().strokeBorder)`
- Header bg: `bgSecondary`
- Body bg: `.white`
- Chevron: system `chevron.down`, rotates 180° on expand

### Section headers (`capsHeader`)

Used in Profile, settings:

```
ACCOUNT                            ← uppercase, wide tracking, bodySMBold
┌──────────────────────────────┐
│ Edit Profile           ›     │   ← settingsGroup() container
│ ──────────                   │
│ Handicap Index    5.6   ‹›   │
└──────────────────────────────┘
```

| Property | Value |
|---|---|
| Header font | `.carry.bodySMBold` (14pt bold) |
| Header color | `textSecondary` |
| Header tracking | `CarryTracking.wide` (1.0) |
| Header case | UPPERCASE |
| Group bg | `.white` |
| Group radius | 12–16pt |
| Group horizontal padding | 20–24pt from screen edge |
| Row divider | 1pt `borderFaint`, inset 16pt |

### Pending state (invited but not accepted)

- Avatar opacity 50%
- Avatar border: `pendingFill` (`#CB895D`)
- Subtitle text: "Pending" or "Invited" in `debugOrange`
- Row background (optional): `pendingBg`

---

## Icons

### System icons (SF Symbols) — primary source

Common SF Symbols used:

| Function | SF Symbol |
|---|---|
| Chevron right | `chevron.right` |
| Chevron down | `chevron.down` (rotates for expand/collapse) |
| Chevron up/down | `chevron.up.chevron.down` |
| Close | `xmark` |
| Back | `chevron.left` |
| More | `ellipsis` |
| Share | `square.and.arrow.up` |
| Flag | `flag.fill` (Start Round icon) |
| Envelope | `envelope` |
| Trophy / leaderboard | `chart.bar.fill` |
| QR | `qrcode` |
| Wifi off | `wifi.slash` |
| Lock | `lock.fill` |
| Chart | `chart.bar.fill` |

### Icon sizes

| Token | Size | Usage |
|---|---|---|
| Inline small | 10–12pt | Inline with micro/caption text |
| Inline standard | 13–14pt | Chevrons, inline meta |
| Button icons | 16pt | Navigation buttons, action icons |
| Tab bar icons | 20–22pt | Tab bar |
| Feature icons | 24–28pt | Headers, empty state accents |
| Hero | 44pt | Paywall crown, feature highlights |

### Icon weight + color

- Weight: `.medium` or `.semibold` for most, `.bold` for emphasis
- Color: inherit from text context (`.foregroundColor(Color.textPrimary)` or similar)

### Custom assets

| Asset | Usage |
|---|---|
| `carry-glyph` | Carry "C" mark (splash, empty states) |
| `carry-logo` / `carry-logo-tag` | Full wordmark |
| `premium-crown` | Premium crown (gated controls, paywall) — always `.renderingMode(.template)` + tinted `goldAccent` |
| `usga-ghin` | USGA GHIN logo (onboarding teaser) |
| `picker-group` / `picker-quick` | New Game picker illustrations |
| `golfball` | Loading spinner |
| `premium-crown` | Gold crown for Premium gates |
| `welcome-bg` | Onboarding background |
| `avatar-*` (adi, aj, daniel, garret, tyson) | Demo/tester avatars |

---

## Accessibility

### Minimum requirements

1. **Touch targets:** 44×44pt minimum for all interactive elements (known TODO — several small controls below this).
2. **Contrast ratios:**
   - Normal text: 4.5:1 minimum
   - Large text (18pt+): 3:1 minimum
   - UI components: 3:1 minimum
3. **Dynamic Type:** Partial support today; full support is a TODO (~299 hardcoded sizes).
4. **VoiceOver:** All interactive elements must have `accessibilityLabel` + `accessibilityHint` where non-obvious.
5. **Reduce Motion:** Not currently honored (TODO).

### Conventions

- Decorative icons: `.accessibilityHidden(true)`
- Related element groups: `.accessibilityElement(children: .combine)`
- Tab / segment states: `.accessibilityAddTraits(.isSelected)`
- Dynamic accessibility hint on gated controls: "Requires Premium subscription"

### Color contrast notes

- Gold on white: use `goldMuted` or `goldDark` (not bright `gold` or `goldStandard`) for AA compliance
- Pending orange (`debugOrange`) on `pendingBg`: verified sufficient
- `textDisabled` on `bgPrimary`: borderline — check before using

### Accessibility TODOs

1. Dynamic Type support (large refactor — 299 sites)
2. Reduce Motion support (spring → linear fallback)
3. Tap targets <44pt audit
4. VoiceOver audit across all flows
5. Larger text color-contrast audit

---

## Design Debt

Tracked for future cleanup:

1. **No formal Spacing enum** — values are inline (4/8/12/16/20/24). Should formalize.
2. **No formal BorderRadius enum** — values inline (12/14/16/18/19/20). Slight inconsistency (18 vs 19 vs 20 for similar elements). Consolidate.
3. **No formal Shadow tokens** — we barely use shadows, but the few we do could be tokenized.
4. **Gold family has 5 variants** (`gold`, `goldMuted`, `goldDark`, `goldAccent`, `goldStandard`) — consolidate to 3.
5. **Border/divider tokens have 6 variants** — several are near-identical (`#E5E5EA` vs `#E5E5E5`). Consolidate.
6. **299 hardcoded font sizes** — migrate to ramp tokens.
7. **Pending player visuals** inconsistent across surfaces.
8. **Dynamic Type** not supported.
9. **Reduce Motion** not honored.
10. **Dark mode** not implemented.
11. **Tap targets <44pt** audit needed.
12. **Leaderboard sheet duplicated** (two files) — unification tracked in memory.

---

## Implementation Checklist

When building a new screen, verify:

- [ ] Uses only defined color tokens (`Color.xxx`)
- [ ] Uses only defined typography ramp (`.font(.carry.xxx)`)
- [ ] Spacing values match the conventions in §4
- [ ] Border radii match the conventions in §5
- [ ] Works at 375pt (iPhone SE) without horizontal scroll
- [ ] No hardcoded `.frame(width: X)` — use `maxWidth: .infinity`
- [ ] No `Text("A\nB")` hardcoded line breaks
- [ ] Touch targets ≥ 44×44pt (or note exception)
- [ ] Interactive elements have `accessibilityLabel`
- [ ] Decorative icons have `.accessibilityHidden(true)`
- [ ] Loading and empty states designed
- [ ] Error states handled gracefully
- [ ] Premium-gated controls use crown pattern (§ Components → Premium)
- [ ] Animations use spring or ease-out (not elastic / bouncy)
- [ ] Screen tested in Preview at smallest device width
- [ ] Dark mode not broken (even though not yet supported)

---

## References

- Color tokens source: `carry/Carry/CarryColors.swift`
- Type ramp source: `carry/Carry/TypeRamp.swift`
- Shared components: `carry/Carry/Views/Components/`
- Paywall strategy: `carry/docs/paywall-and-free-tier.md`
- Session history: memory files at `~/.claude/projects/.../memory/`

---

## Version History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-19 | Initial design system doc, sourced from live code. Formalizes existing conventions; flags debt items for future cleanup. To be reconciled with Figma library once imported. |

---

*This document is the single source of truth for visual design in Carry. When in doubt, refer here. When something isn't defined, add it here before implementing.*
