# Skins / Handicap Math Engine

**TL;DR:** USGA course-handicap formula × 0–100% allowance. Stroke allocation by stroke index with plus-HC give-back. Per-hole skin = lowest net (or gross). Ties are squashed or carried. Pot ÷ (skins-with-winners + open holes) = per-skin value. Math in [`RoundViewModel`](../../Carry/ViewModels/RoundViewModel.swift) + [`TeeBox`](../../Carry/Models/TeeBox.swift).

## Course handicap formula

[TeeBox.swift:21-23](../../Carry/Models/TeeBox.swift:21) `courseHandicapRaw(forIndex:)`:
```
raw = index × (slope / 113) + (rating - par)
```

[TeeBox.swift:33-36](../../Carry/Models/TeeBox.swift:33) `playingHandicap(forIndex:percentage:)`:
```
playingHandicap = round(raw × percentage)
```

Swift `round()` is half-away-from-zero: `0.5 → 1`, `-0.5 → -1`.

| Input | Source |
|---|---|
| `index` | `Player.handicap` — onboarding, editable in Profile |
| `slope` | `TeeBox.slopeRating` ([TeeBox.swift:15](../../Carry/Models/TeeBox.swift:15)) |
| `rating` | `TeeBox.courseRating` ([:14](../../Carry/Models/TeeBox.swift:14)) |
| `par` | `TeeBox.par` ([:16](../../Carry/Models/TeeBox.swift:16)) |
| `percentage` | `SkinRules.handicapPercentage` ([RoundConfig.swift:18](../../Carry/Models/RoundConfig.swift:18)) — 0.0 to 1.0 |

## Percentage allowance

`SkinRules.handicapPercentage` per-game allowance (0–100%). Server: `skins_groups.handicap_percentage`.

| Value | Effect on raw HC of 14 |
|---|---|
| 1.0 (100%) | playingHandicap = 14 |
| 0.85 (85%) | round(11.9) = 12 |
| 0.70 (70%) | round(9.8) = 10 |
| 0.0 (0%) | 0 (gross) |

Race-guarded: see [refresh-race-guards.md](refresh-race-guards.md) §3.

## Stroke allocation per hole

[TeeBox.swift:41-58](../../Carry/Models/TeeBox.swift:41) `strokesOnHole(playingHandicap:holeHcp:)`. Holes ranked by stroke index (`Hole.hcp`, 1=hardest, 18=easiest).

### Regular handicap (positive)
```
base = floor(pops / 18)
remainder = pops % 18
strokes_on_hole = base + (1 if hcp ≤ remainder else 0)
```

| pops | Effect |
|---|---|
| 14 | 0 base; 14 hardest holes get 1 stroke |
| 22 | 1 base everywhere; 4 hardest holes get 2 |

### Plus handicap (negative — better than scratch)

[TeeBox.swift:50-57](../../Carry/Models/TeeBox.swift:50) — give-back:
```
absPops = abs(pops)
base = floor(absPops / 18)
remainder = absPops % 18
strokes_on_hole = -base - (1 if (19 - hcp) ≤ remainder else 0)
```

Plus-HC owes strokes; pays back on EASIEST holes first (hcp 18, 17, 16…).

## Per-hole skins

[RoundViewModel.swift:131-203](../../Carry/ViewModels/RoundViewModel.swift:131) `calculateSkins()`. Per hole:

| Step | Action |
|---|---|
| 1 | For each player: `net = gross - strokesOnHole` |
| 2 | Find `bestNet` (lowest net) |
| 3 | Count players tied at `bestNet` |

Outcomes:

| Tag | Condition | Effect |
|---|---|---|
| `.won(playerId, carry)` | Exactly 1 at bestNet | Player wins hole + any pending carry |
| `.carried` | 2+ tied, carries on | Pending carry rolls forward |
| `.squashed` | 2+ tied, carries off | Skin lost forever |
| `.pending` | Hole not scored | Excluded from final skin count, included in pot denominator while open |

`carriesEnabled` = `config.skinRules.carries` ([RoundViewModel.swift:133](../../Carry/ViewModels/RoundViewModel.swift:133)). Server: `skins_groups.carries_enabled`.

### Per-player skins count

[RoundViewModel.swift:261-271](../../Carry/ViewModels/RoundViewModel.swift:261) `skinsWonByPlayer()`:
- Iterate `cachedSkins`
- For each `.won(playerId, carryValue)`: add `1 + carryValue` to player's count
- Returns `[Int: Int]`

## Pot split + money distribution

[RoundViewModel.swift:208](../../Carry/ViewModels/RoundViewModel.swift:208): `pot = config.buyIn × allPlayers.count`.

[RoundViewModel.swift:210-258](../../Carry/ViewModels/RoundViewModel.swift:210) `moneyTotals()`:
```
totalSkinsAwarded = sum of skinsWonByPlayer().values
openCount = count of holes with .pending
skinValue = pot / (totalSkinsAwarded + openCount)
playerMoney[id] = skinsWon[id] × skinValue
```

Open holes dilute denominator while pending. `.carried` holes excluded ([:279-282](../../Carry/ViewModels/RoundViewModel.swift:279)) — carry will absorb into next `.won`.

### Net vs gross display

[RoundViewModel.swift:246](../../Carry/ViewModels/RoundViewModel.swift:246):
```swift
if displayMode == "net" {
    money = (skinsWon × skinValue) - buyIn
} else {
    money = skinsWon × skinValue
}
```

`displayMode` = `SavedGroup.winningsDisplay` (`"gross"` or `"net"`). Net subtracts buy-in for P&L view.

## Pop-computation outside a round

[RoundViewModel.swift:117-121](../../Carry/ViewModels/RoundViewModel.swift:117) — convenience helper for GroupManagerView pops display.

No-tee-box fallback: when `currentCourse?.teeBox == nil`, formula degrades to `round(index × percentage)` (no slope adjustment). Tested in [PopsComputationTests.swift:108-127](../../CarryTests/PopsComputationTests.swift:108).

## Test coverage

| Test file | Scenarios |
|---|---|
| [SkinsCalculationTests.swift](../../CarryTests/SkinsCalculationTests.swift) | Outright winners ([:70-91](../../CarryTests/SkinsCalculationTests.swift:70)), tied with carries on/off ([:93-142](../../CarryTests/SkinsCalculationTests.swift:93)), 70% allowance ([:246-297](../../CarryTests/SkinsCalculationTests.swift:246)), plus-HC give-back ([:303-341](../../CarryTests/SkinsCalculationTests.swift:303)), 0% allowance ([:345-361](../../CarryTests/SkinsCalculationTests.swift:345)), money totals + gross/net ([:170-211](../../CarryTests/SkinsCalculationTests.swift:170)) |
| [PopsComputationTests.swift](../../CarryTests/PopsComputationTests.swift) | Slope/rating ([:47-77](../../CarryTests/PopsComputationTests.swift:47)), % reduction ([:69-77](../../CarryTests/PopsComputationTests.swift:69)), plus-HC clamping ([:86-95](../../CarryTests/PopsComputationTests.swift:86)), no-tee-box fallback ([:108-127](../../CarryTests/PopsComputationTests.swift:108)), zero-slope guards ([:130-144](../../CarryTests/PopsComputationTests.swift:130)) |
| [PotCalculationTests.swift](../../CarryTests/PotCalculationTests.swift) | `pot = buyIn × count` ([:29-38](../../CarryTests/PotCalculationTests.swift:29)), denominator logic ([:43-82](../../CarryTests/PotCalculationTests.swift:43)), `.carried` excluded ([:64-82](../../CarryTests/PotCalculationTests.swift:64)), full pot allocation ([:87-114](../../CarryTests/PotCalculationTests.swift:87)) |

## Where invoked

| Caller | Trigger | Citation |
|---|---|---|
| ScorecardView | Score tap → `enterScore()` → `calculateSkins()` via `checkForNewSkinWins()` | [ScorecardView.swift:435](../../Carry/Views/ScorecardView.swift:435) |
| FinalResultsHero | Final round display | [FinalResultsComponents.swift:17-64](../../Carry/Views/FinalResultsComponents.swift:17) |
| FinalResultsWinnerRow | Per-player skins + money | [:68-124](../../Carry/Views/FinalResultsComponents.swift:68) |
| HomeView Active Round card | Display-only via precomputed `HomeRound.playerWinnings` | [HomeView.swift:13-89](../../Carry/Views/HomeView.swift:13) |
| GroupManagerView Pops display | Per-player pops in tee sheet, recomputed locally | `RoundViewModel.playingHandicap()` |

## 70% recalculation (2026-05-09) — canonical example

Round played 2026-05-08 ran at 100% by mistake. Recomputed offline at 70%:

| # | Action |
|---|---|
| 1 | Pull per-hole gross scores from `scores` via SQL |
| 2 | Per player: `playingHandicap = round(index × (slope/113) + (rating - par)) × 0.70)` |
| 3 | Allocate strokes by hcp |
| 4 | Per hole: `net = gross - strokes`, find min, count ties |
| 5 | Assign skin / carry / squash, aggregate |
| 6 | Money: `pot / (totalSkins + openHoles)`, distribute |

Result: 6 skins → 5 skins, $250 shifted. Math correct in both runs; difference solely the percentage. Logged in `yesterdays-round-fixes.md`.

When results feel wrong, check INPUTS first (allowance %, slope/rating/par, per-hole hcp, scoring mode). Engine is well-tested.

## Common bugs / gotchas

| Bug | Notes |
|---|---|
| Swift `round()` half-away-from-zero | Affects plus-HCs near 0. Test with idx 0.5 not 0.0 |
| Stale `holes_json` from API | GolfCourse API may not populate stroke indices. Fallback uses `Hole.allHoles` static defaults — wrong hcp ordering means every game on that course uses wrong allocation. Audit before reporting "skins math is wrong" |
| `handicapPercentage = 0.0 ≠ 1.0` | Visual test slider both ends. The 1.0.7 race-guard fix addressed slider snap-back to 1.0 mid-save |
| `buyIn = 0` → pot = 0 → division by zero | Guarded; `moneyTotals()` returns zeros when pot is 0. Re-verify after refactors |
| Carries-on with all 18 tied | Final carry disappears, no winner. Verify intended before edge-case-fixing |
| Mid-round `handicapPercentage` change | Slider applies on next score entry. Already-scored holes don't retroactively recalc — implicit because `calculateSkins()` reruns on every `enterScore()` |

## Last verified

2026-05-10 — converted to machine-readable format. Engine confirmed correct via 2026-05-09 70% recalc.
