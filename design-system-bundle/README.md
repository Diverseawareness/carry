# Carry Design System — Upload Bundle

Drag-and-drop ready for **claude.ai/design** (or any other tool that accepts a design system as source material).

## What's here

| File / folder | What it is | Priority |
|---|---|---|
| `design-system.md` | Full 1,000-line design spec (tokens, components, patterns, rules) | **Required** |
| `design-system-preview.html` | Visual rendering of the spec — open in a browser to see every token and component | Reference |
| `code-tokens/CarryColors.swift` | Authoritative color extensions (source of truth) | **Required** |
| `code-tokens/TypeRamp.swift` | Authoritative typography ramp (source of truth) | **Required** |
| `logos/` | Brand assets (carry-logo, carry-glyph, carry-logo-tag, premium-crown) — PNG inside each `.imageset` | **Required** |
| `screenshots/` | Drop 3–4 of your most on-brand screens here before uploading | Recommended |

## Upload order (claude.ai/design)

1. Open claude.ai/design → bottom-left → select/create org → start the "set up design system" flow.
2. Upload in this order:
   - `design-system.md`
   - `code-tokens/CarryColors.swift` + `code-tokens/TypeRamp.swift`
   - PNGs from `logos/*/*.png` (extract from each `.imageset` — use the 2x or 3x)
   - PNGs from `screenshots/` (after you've dropped some in)
3. Review the auto-generated UI kit. Compare to `design-system-preview.html` for delta.
4. Create a test project ("Tee Times screen") and verify it matches Carry's look.
5. Toggle **Published** to make it the default for all future projects under this org.

## Recommended screenshots to add

Before uploading, drop these into `screenshots/`:
- Paywall — trial-ended variant
- Scorecard (mid-round)
- Home — active round card + Recent Games
- Round Stats card (showing money formatting + X Skins line)
- Leaderboard — Last Round tab

Higher-fidelity screenshots = better inherited system.

## Updating later

Keep `design-system.md` in sync with `carry/docs/design-system.md` — it's the same file. Re-upload when tokens change significantly.
