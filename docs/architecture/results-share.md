# Results / Share / Post-Round

**TL;DR:** RoundCompleteView is post-round bottom sheet. ResultsShareCard renders fixed-width 390pt card → ShareCardRenderer (`ImageRenderer` 2.0x) → PNG → ShareLink. Venmo deep links with proportional split. Inline RoundStatsView shows skins/holes/money + score line + birdies/bogeys.

## RoundCompleteView

[RoundCompleteView.swift:68-972](../../Carry/Views/RoundCompleteView.swift:68) — bottom sheet shown when round transitions to `concluded`.

### Animation

Pre-results: checkmark pulse + gold flash 0.3–1.6s, crossfade to leaderboard. Splash flags managed similar to RoundCoordinatorView's `.starting` phase (see [phase-transitions.md](phase-transitions.md)).

### Action buttons

[RoundCompleteView.swift:656-754](../../Carry/Views/RoundCompleteView.swift:656):

| Button | Visible to | Action |
|---|---|---|
| "Save Round Results" | Creator | `updateRoundStatus(roundId, "completed")` + `advanceScheduledDateIfRecurring` (recurring only) + QG conversion prompt (gated, see [game-types.md](game-types.md)) |
| "Done — Waiting on others" | Anyone | Dismiss; round stays `concluded` until all groups finish |
| "Done" | Members | Dismiss without status change |
| Venmo charge | All players when winnings exist | Opens `venmo://` deep link |

## ResultsShareCard

[ResultsShareCard.swift:83-310](../../Carry/Views/ResultsShareCard.swift:83). Fixed width 390pt for consistent social-share dimensions. Theme via `ShareCardTheme` enum (dark/light).

| Section | Content |
|---|---|
| Header | Course name + date + theme accent |
| Leaderboard rows | Avatar + name + skins + money (`+$X` / `-$X` / `$0`) |
| Pot total | Bottom card |
| App Store badge | Footer with carryapp.site link |

### Money format

[ResultsShareCard.swift:215](../../Carry/Views/ResultsShareCard.swift:215) inline `moneyText(_:)`:
```swift
amount > 0 → "+$\(amount)"
amount < 0 → "-$\(abs(amount))"
amount == 0 → "$0"
```

Duplicated at [RoundCompleteView.swift:882](../../Carry/Views/RoundCompleteView.swift:882) and [:1194](../../Carry/Views/RoundCompleteView.swift:1194). Refactor backlog: extract to free function.

## ShareCardRenderer

[ShareCardRenderer.swift:1-12](../../Carry/Services/ShareCardRenderer.swift:1):
```swift
static func render(data: ResultsShareData, theme: ShareCardTheme) -> UIImage? {
    let renderer = ImageRenderer(content: ResultsShareCard(data: data, theme: theme))
    renderer.scale = 2.0
    return renderer.uiImage
}
```

`ImageRenderer` (iOS 16+) requires view body hydratable off-screen. Avatar URLs MUST be pre-fetched — `ImageRenderer` doesn't run async tasks.

## Avatar prefetch

[RoundCompleteView.swift:510](../../Carry/Views/RoundCompleteView.swift:510) — parallel `TaskGroup` downloads avatars before `render()`:
```swift
await withTaskGroup(of: (Int, UIImage?).self) { group in
    for player in players {
        group.addTask { (player.id, await downloadImage(url: player.avatarURL)) }
    }
    // collect → attach to ResultsShareData
}
let card = ShareCardRenderer.render(data: data, theme: theme)
```

Without prefetch: `ImageRenderer` captures placeholder state.

## Native share

[RoundCompleteView.swift:143-149](../../Carry/Views/RoundCompleteView.swift:143):
```swift
ShareSheet(activityItems: [
    cardImage,
    "Check out our skins game results! Get Carry: https://carryapp.site"
])
```

`UIActivityViewController` wrapped in SwiftUI `ShareSheet`. Image is primary; text is secondary (Messages includes both; some apps drop text).

## Venmo deep link

[RoundCompleteView.swift:889-950](../../Carry/Views/RoundCompleteView.swift:889) `VenmoSettlement`:
```
venmo://paycharge?
  txn={pay|charge}
  &recipients={username}
  &amount={cents}
  &note=Carry Skins – {course}
```

Built from leaderboard winners (charge) + losers (pay). Proportional split via cross-multiplication when totals don't match exactly. Falls through to App Store if Venmo not installed (Universal Links for `venmo.com/u/`).

## RoundStatsView (inline stats block)

[RoundCompleteView.swift:982-1199](../../Carry/Views/RoundCompleteView.swift:982) — embedded at [:406-416](../../Carry/Views/RoundCompleteView.swift:406). Per-player rows show:

| Field | Notes |
|---|---|
| Skins won + holes won | Cell pills |
| Money | `moneyText` |
| Handicap index | — |
| Pops | Via `RoundViewModel.playingHandicap` |
| Score line | `"38 · 38 76, 3 Birdies, 1 Bogey"` (front · back total + non-par counts) |

[RoundCompleteView.swift:8-63](../../Carry/Views/RoundCompleteView.swift:8) — `RoundStatsLine` enum with `make(playerScores:parsByHole:)` (testable). Omits pars; surfaces eagles, birdies, bogeys, doubles+ (eagle-or-better is `..<(-1)`).

## Convert-to-Skins-Group Phase 2

Post Save Round Results on a Quick Game, convert sheet Phase 2 fires (segmented control "Share Invite | Scan QR"). See [game-types.md](game-types.md) §Conversion. Share tab uses ResultsShareCard + invite link via ShareLink. Scan tab renders QR of invite URL.

## Render invocation sites

| Caller | Trigger |
|---|---|
| RoundCompleteView "Share Results" | Creator post-round |
| ResultsSheet (spectator final results) | Group card tap when round concluded |
| Convert-to-Skins-Group Phase 2 | Auto on conversion |

## Common bugs / gotchas

| Bug | Notes |
|---|---|
| Avatars missing from rendered card | `ImageRenderer` captured state before async load. Always prefetch into `[Int: UIImage]` dict first |
| Card image looks pixelated | Verify `renderer.scale = 2.0`. iOS uses 1.0 by default |
| Venmo URL doesn't open | Verify `note` URL-encoded. Current pattern uses `\u{2013}` (en-dash) — verify percent-encoder runs on full querystring |
| `+$X` vs `$X` inconsistency | 8 sites with this format. Audit before changing |
| Share text varies by app | Messages includes; LinkedIn drops; Twitter truncates. Don't put critical info in text — put in image |

## Last verified

2026-05-10 — converted to machine-readable format.
