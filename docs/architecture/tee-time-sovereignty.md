# Tee-Time Sovereignty

**TL;DR:** Only the per-group tee-time picker writes `teeTimes`. Game Options Save and date/recurrence picker do NOT. Server: `tee_times_json` on `skins_groups`. NULL → refresh recomputes from `scheduledDate + interval`. Race-guarded by `teeTimesLastSavedAt`. Default interval: 8 min.

## Single-writer rule (1.0.6 fix, commit `f70b6d6`) + Game-Options time propagation (1.0.9, commit `5e29368`)

Per-group tee-time picker ([TeeTimePickerSheet](../../TeeTimePickerSheet.swift)) is the primary writer of `teeTimes: [Date?]?`. As of 1.0.9, Game Options Save propagates a time change to `teeTimes[0]` (and shifts the staggered groups by the same interval) — see "Game Options propagation" below.

| UI | Writes `teeTimes` | Writes side-channel |
|---|---|---|
| TeeTimePickerSheet (per-group) | **Yes** — any index | — |
| Game Options sheet Save (round time) | **`teeTimes[0]` + staggered shift for `[1..N]`** (1.0.9) | `handicapPercentage`, `winningsDisplay`, etc. |
| Date / recurrence picker | No | `scheduledDate`, `recurrence` |

Pre-1.0.6: three UIs mutated `teeTimes` independently; saves stomped each other. 1.0.6 collapsed write authority to TeeTimePickerSheet alone.

### Game Options propagation (1.0.9, commit `5e29368`)

[GroupManagerView.swift:2221-2261](../../Carry/Views/GroupManagerView.swift:2221) — when GroupOptionsSheet's onSave returns a new `teeTime`:

| # | Action |
|---|---|
| 1 | `roundDate = t` (scheduled date) |
| 2 | Derive existing stagger interval: `(teeTimes[1] ?? t).timeIntervalSince(teeTimes[0] ?? t)` |
| 3 | `teeTimes[0] = t` |
| 4 | For each `i in 1..<teeTimes.count`: `teeTimes[i] = t.addingTimeInterval(Double(i) * interval)` |
| 5 | Stamp `teeTimesLastSavedAt = Date()` (refresh recompute branch defers for 8s) |
| 6 | `onTeeTimeChanged?(t)` |

**Why this is still single-writer per index:** Game Options writes the ROUND start time. The per-group picker is the only UI that writes a SPECIFIC group's tee time independent of the round start. Game Options shifting all groups by a fixed interval is "moving the round to 9 AM" not "editing group 3's individual tee time" — it doesn't conflict with the per-group picker.

**Pre-1.0.9:** Game Options changed `roundDate` only. The header clock icon reads `teeTimes.first`, which stayed at the old value because the refresh recompute fallback only fires when `tee_times_json` is NULL on the server (any previous edit blocks it). Net: user changed time in Game Options, headline time didn't update until a Quick Game create or first per-group edit.

## Array structure

| Property | Value |
|---|---|
| Type | `[Date?]?` — outer nil if never set; inner nil per-group = use schedule fallback |
| Indexing | `teeTimes[group_num - 1]` |
| Server field | `skins_groups.tee_times_json` ([SupabaseModels.swift:425](../../Carry/Models/SupabaseModels.swift:425)) — JSON `[String?]` ISO8601 |
| Sync method | [GroupManagerView.swift:4469](../../Carry/Views/GroupManagerView.swift:4469) `syncTeeTimesToSupabase()` → [GroupService.swift:699](../../Carry/Services/GroupService.swift:699) `saveTeeTimes(groupId:teeTimes:)` |

## Default interval

[GroupManagerView.swift:125](../../Carry/Views/GroupManagerView.swift:125):
```swift
private let teeTimeInterval: TimeInterval = 8 * 60  // 8 minutes between groups
```

Server: `skins_groups.tee_time_interval` (Int, minutes). Used by recompute fallback when `tee_times_json` is NULL.

## Duplicate-time conflict resolution

[GroupManagerView.swift:2903-2934](../../Carry/Views/GroupManagerView.swift:2903) — when picker time conflicts with another group:

| # | Action |
|---|---|
| 1 | Compare time-of-day only (hour:minute, ignoring calendar day) — line 2910 |
| 2 | While conflict, bump `resolvedPickerDate` by 8 min (line 2929) |
| 3 | Apply |

Example: groups at 8:00 + 8:08. User changes first to 8:08 → second auto-bumps to 8:16.

## Recompute fallback

[GroupManagerView.swift:1102-1134](../../Carry/Views/GroupManagerView.swift:1102):
```swift
if interval > 0 && groupCount > 1 {
    teeTimes = (0..<groupCount).map { i in
        date.addingTimeInterval(Double(i) * Double(interval) * 60)
    }
}
```

Fires only when:
| # | Condition |
|---|---|
| 1 | Server's `tee_times_json` is NULL (never edited) |
| 2 | `teeTimesLastSavedAt` is NOT recent (>8s since last edit) |

See [refresh-race-guards.md](refresh-race-guards.md) §2.

## Known gap

`createGroup` / `SkinsGroupInsert` don't accept `tee_times_json`. New groups have NULL server-side until first edit. Recompute-on-NULL fallback fills the gap. Audited 2026-05-08 — accepted.

## Persistence chain

| Action | Local | Server |
|---|---|---|
| User picks per-group time | `teeTimes[idx] = date` + stamp `teeTimesLastSavedAt` ([:2401](../../Carry/Views/GroupManagerView.swift:2401)) | After 0.8s debounce: `syncTeeTimesToSupabase` |
| Other device receives | `loadSingleGroup` returns updated `teeTimes` | Realtime / 30s poll |
| Game Options Save (round time change) | `teeTimes[0] = t`, shifts `[1..N]` by existing interval, stamps `teeTimesLastSavedAt` ([:2240-2257](../../Carry/Views/GroupManagerView.swift:2240)) | `handicapPercentage` etc. saved; tee-times sync via the standard `.onChange(of: teeTimes)` debounce path |
| Quick Game create | NULL server-side | `tee_times_json` NULL until first edit |

## Common bugs / gotchas

| Bug | Notes |
|---|---|
| Tee times shift on every edit | Fixed 1.0.6 via sovereignty rule + race guard. Don't add second writer to `teeTimes` |
| `teeTimes.count != groupCount` | Guard with `min(idx, count - 1)`. Adding a new group should append nil slot |
| Cross-device clock drift | ISO8601 UTC; render uses local timezone. Don't round-trip through `Date.timeIntervalSinceReferenceDate` |
| Recompute off by 8 min | Verify `interval` is minutes not seconds in `addingTimeInterval` |

## Last verified

2026-05-13 — patched for commit `5e29368`: Game Options time change now writes `teeTimes[0]` and shifts staggered `[1..N]` by the existing interval. Per-group picker is still the only writer of an individual group's tee time independent of round start. Race guard intact.
