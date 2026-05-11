# Recurring Rounds

**TL;DR:** `GameRecurrence` enum (weekly / biweekly / monthly) + `scheduledDate`. Recurring groups advance `scheduledDate` after Save Round Results — no cron. Members start next round manually via "Schedule Next Round."

## Recurrence enum

[GroupsListView.swift:2499](../../Carry/Views/GroupsListView.swift:2499):

| Case | Payload | Meaning |
|---|---|---|
| `.weekly(dayOfWeek: Int)` | 1=Sunday … 7=Saturday | Every week |
| `.biweekly(dayOfWeek: Int)` | same | Every 2 weeks |
| `.monthly(dayOfMonth: Int)` | 1–31 | Every month |

Stored on `skins_groups.recurrence` as JSON. Absent → one-off.

## Fields

| Field | Type | Source |
|---|---|---|
| `recurrence` | `GameRecurrence?` | [GroupsListView.swift:2687](../../Carry/Views/GroupsListView.swift:2687) |
| `scheduledDate` | `Date?` | [:2686](../../Carry/Views/GroupsListView.swift:2686) |

## Advance semantics

[GroupService.swift:1420](../../Carry/Services/GroupService.swift:1420) `advanceScheduledDateIfRecurring(groupId:)`:

| # | Action |
|---|---|
| 1 | Read current `scheduledDate` + `recurrence` from server |
| 2 | If recurrence is nil → no-op |
| 3 | Compute `recurrence.nextDate()` (line 1433) |
| 4 | UPDATE `skins_groups.scheduled_date = nextDate` |

Triggered from: [ScorecardView.swift:296](../../Carry/Views/ScorecardView.swift:296), [RoundCompleteView.swift:720](../../Carry/Views/RoundCompleteView.swift:720) (after Save Round Results).

No cron — new rounds NOT auto-inserted. Next round started manually via "Schedule Next Round" → `TeeTimePickerSheet` → user confirms → INSERT new `rounds` row.

## Recurrence picker UI

[TeeTimePickerSheet.swift:76-132](../../TeeTimePickerSheet.swift:76):

| Component | Lines |
|---|---|
| Date picker (base date/time) | [:63-74](../../TeeTimePickerSheet.swift:63) |
| Frequency buttons (Weekly / Biweekly / Monthly) | [:84](../../TeeTimePickerSheet.swift:84) |
| Day-of-week pills (W/BW only; Monthly uses day-of-month from date picker) | [:109-129](../../TeeTimePickerSheet.swift:109) |

## "Schedule Next Round" CTA

[GroupManagerView.swift:675](../../Carry/Views/GroupManagerView.swift:675) — `startButtonLabel` flips to "Schedule Next Round" when `needsNextSchedule` is true (last round completed + recurrence active + no future `scheduledDate`).

Tap → TeeTimePickerSheet → user confirms → `scheduledDate` UPDATE → card shows new label.

## `scheduledLabel` rendering

[GroupsListView.swift:2714-2727](../../Carry/Views/GroupsListView.swift:2714):

| Recurrence | Format |
|---|---|
| Set + `scheduledDate` | `"Every Friday · 8:00 AM"` |
| Single date | `"Sat, Mar 14 · 8:24 AM"` |
| Same-day | `"Today · 8:00 AM"` |

Cached `DateFormatter` instances at static level (avoid per-render allocation).

## Day-of-week mapping

[GroupsListView.swift:2585-2588](../../Carry/Views/GroupsListView.swift:2585) `pillIndex(fromWeekday:)`:

| Calendar weekday | Pill index | Label |
|---|---|---|
| 1 (Sunday) | 6 | Sun |
| 2 (Monday) | 0 | Mon |
| 3 (Tuesday) | 1 | Tue |
| ... | ... | ... |
| 7 (Saturday) | 5 | Sat |

Conversion: `w == 1 ? 6 : w - 2`. Sunday at END (Mon-first convention).

## Not yet implemented

| Feature | Notes |
|---|---|
| Per-player opt-out for specific recurring round | Members can be in group every round or leave entirely. MEMORY.md `member_self_availability_todo.md` |
| Auto-creation of rounds via cron | Pre-create next round 1 hour before tee time. Requires server cron + push-notify-on-create |
| Skip-this-week shortcut | Would call `advanceScheduledDateIfRecurring` without playing |

## Common bugs / gotchas

| Bug | Notes |
|---|---|
| Schedule advances even if cancelled? | Verify. `endGameDestructively` may not trigger `advanceScheduledDateIfRecurring`. Recurring groups keep same date until next Save. May be intentional |
| Day-of-week index off-by-one | Calendar.weekday is 1-indexed Sunday-first; pill UI is 0-indexed Monday-first. Always use `pillIndex(fromWeekday:)` |
| Monthly day 31 in 30-day month | `recurrence.nextDate()` should clamp; verify |
| Two members tap "Schedule Next Round" simultaneously | Both see picker; second write wins. Last-write-wins acceptable |

## Last verified

2026-05-10 — converted to machine-readable format. Recurrence + advancement intact, no auto-cron.
