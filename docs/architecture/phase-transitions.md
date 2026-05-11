# Phase Transitions — `RoundCoordinatorView` State Machine

**TL;DR:** `phase: Phase` controls child view rendering. Four states. Order-of-state-mutations rule: change `phase` first, defer cleanup.

## Phase enum

[RoundCoordinatorView.swift:35-40](../../Carry/Views/RoundCoordinatorView.swift:35):
```swift
enum Phase: Equatable {
    case courseSelection
    case setup
    case starting
    case active
}
```

## Initial value

[RoundCoordinatorView.swift:105-145](../../Carry/Views/RoundCoordinatorView.swift:105):

| Condition | Phase |
|---|---|
| `initialRoundConfig != nil` | `.active` (joining existing round) |
| `startInActiveMode` | `.active` (scorecard-only mode) |
| `skipCourseSelection` (effective) | `.setup` (Quick Game / existing-group path) |
| else | `.courseSelection` |

## Wiring invariant — existing-group entry MUST skip course selection

🔒 Locked 2026-05-10. The constructor is preconditioned: when `groupId != nil`, the caller MUST pass at least one of `skipCourseSelection: true`, `startInActiveMode: true`, or `initialRoundConfig`. Otherwise the coordinator launches into `.courseSelection` — a full-screen course-search view the user can only escape via the X button — even though the existing group already has all the context it needs.

The constructor enforces this via `effectiveSkipCourseSelection`:

| Caller intent | Required props | Resulting phase |
|---|---|---|
| Brand-new round (no group) | none | `.courseSelection` |
| Existing group, setup view | `groupId` + `skipCourseSelection: true` | `.setup` |
| Existing group, live round | `groupId` + (`startInActiveMode: true` OR `initialRoundConfig`) | `.active` |

If a caller passes `groupId` but forgets the other props, the constructor:
- DEBUG: `assertionFailure` traps the wiring bug at the call site
- Production: forces `skipCourseSelection = true` (logs a warning) so users never hit the trap

Production callers:

| Site | Wiring |
|---|---|
| [GroupsListView.swift:809](../../Carry/Views/GroupsListView.swift:809) | Always passes `groupId` + `skipCourseSelection: !isLive` (correct) |
| [HomeView.swift:617](../../Carry/Views/HomeView.swift:617) | Passes `groupId` + `skipCourseSelection: true` (fixed 2026-05-10 — was missing) |
| [CarryApp.swift:423,436](../../Carry/CarryApp.swift:423) | Debug scenarios; pass `skipCourseSelection: true` |

## Back-from-setup invariant — never navigate to `.courseSelection`

🔒 Locked 2026-05-10. The setup view's Back button only ever transitions to `.active` (when a round is in flight) or calls `onExit` (otherwise). It NEVER mutates `phase = .courseSelection`. If a user wants to change the course mid-setup, the in-setup sheet at [GroupManagerView.swift:5157](../../Carry/Views/GroupManagerView.swift:5157) handles that without a phase transition.

The previous fall-through-to-courseSelection branch was dead code in well-formed callers but became a TRAP whenever any caller's prop wiring drifted (HomeView regression, 2026-05-10). Removing it eliminates the entire bug class.

See [bug-archive 2026-05-10 "Home-tab Quick Game entry: Restart Round breaks drag + back navigation"](bug-archive.md).

## Per-phase rendering

| Phase | View | Notes |
|---|---|---|
| `.courseSelection` | `CourseSelectionView` | Stateless. Course pick → `phase = .setup` |
| `.setup` | `GroupManagerView` | `allMembers: postCancelMembers ?? initialMembers` ([:167](../../Carry/Views/RoundCoordinatorView.swift:167)) |
| `.starting` | `roundStartedSplash` | Splash animation, staggered reveals |
| `.active` | `ScorecardView` OR loading fallback | Conditional on `roundConfig` + holes ([:269](../../Carry/Views/RoundCoordinatorView.swift:269)) |

### `.active` branch detail

```swift
case .active:
    if let baseConfig = roundConfig, !((baseConfig.holes ?? baseConfig.teeBox?.holes ?? []).isEmpty) {
        ScorecardView(config: activeConfig, ...)
    } else {
        // Loading fallback — schedules 10s offline-timeout
    }
```

Fallback view's `.onAppear` ([:359](../../Carry/Views/RoundCoordinatorView.swift:359)) schedules a 10s timeout that fires `"Couldn't connect — starting offline"` if `roundConfig` stays nil. **Misfires if you mutate `roundConfig = nil` while phase is still `.active`.**

## Transition triggers

| From | To | Trigger | Closure |
|---|---|---|---|
| `.courseSelection` | `.setup` | Course selected | `onCourseSelected` ([:157-162](../../Carry/Views/RoundCoordinatorView.swift:157)) |
| `.setup` | `.active` (creator) | "Start Round" tapped | `onConfirm` ([:185-261](../../Carry/Views/RoundCoordinatorView.swift:185)). Sets `roundConfig`, `hasStartedRound = true`, animates to `.starting` for creator OR directly to `.active` for non-creator |
| `.setup` | `.active` | "Back" mid-round | `onBack` ([:171-175](../../Carry/Views/RoundCoordinatorView.swift:171)). Only if `hasStartedRound` |
| `.setup` | exit (Games tab) | "Back" — existing group OR came from Games tab | `onBack` ([:176-186](../../Carry/Views/RoundCoordinatorView.swift:176)). Fires when `!hasStartedRound && (skipCourseSelection || groupId != nil)` |
| `.setup` | `.courseSelection` | "Back" — brand-new round flow only | `onBack` ([:188-191](../../Carry/Views/RoundCoordinatorView.swift:188)). Fires when `!hasStartedRound && !skipCourseSelection && groupId == nil` |
| `.starting` | `.active` | "Go to Scorecard" | [:596](../../Carry/Views/RoundCoordinatorView.swift:596) |
| `.active` | `.setup` | "Edit Players" mid-round | `onEditPlayers` ([:290-299](../../Carry/Views/RoundCoordinatorView.swift:290)). Phase only, no roundConfig touch |
| `.active` | `.setup` | "Restart Round" | `onCancelToSetup` ([:310-345](../../Carry/Views/RoundCoordinatorView.swift:310)). Snapshot roster, phase first, defer cleanup |
| `.active` | (exit) | "Back" / round complete | `onBack?()` ([:286-289](../../Carry/Views/RoundCoordinatorView.swift:286)) |

## Order-of-state-mutations rule

**Rule:** when transitioning out of `.active`, change `phase` first inside `withAnimation`, defer all other cleanup to next runloop via `DispatchQueue.main.async`.

State mutations within a single closure batch — body re-renders ONCE with all new values. If you set `roundConfig = nil` and `phase = .setup` synchronously, body may re-render with `phase = .active` + `roundConfig = nil` for one frame → `.active` branch evaluates → loading fallback view → its `.onAppear` schedules the 10s offline-timeout → user sees red toast 10s later on the setup screen.

### `onEditPlayers` — clean (phase only)

```swift
}, onEditPlayers: {
    showFlag = false
    showTitle = false
    showDetails = false
    showStats = false
    pulseFlag = false
    withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
        phase = .setup
    }
}
```

NEVER touches `roundConfig`. Round still exists; user just edits then comes back.

### `onCancelToSetup` — defers cleanup

[:310-345](../../Carry/Views/RoundCoordinatorView.swift:310):
```swift
}, onCancelToSetup: {
    // 1. Snapshot BEFORE any mutation
    if let players = roundConfig?.players {
        postCancelMembers = players
    }
    // 2. Phase first inside withAnimation
    withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
        phase = .setup
    }
    // 3. Defer all cleanup to next runloop tick
    DispatchQueue.main.async {
        hasStartedRound = false
        roundConfig = nil
        roundCreationTask?.cancel()
        roundCreationTask = nil
        showFlag = false; showTitle = false; showDetails = false
        showStats = false; pulseFlag = false
    }
}
```

By the time the deferred block runs, `.setup` branch has rendered and `.active` branch is no longer evaluated. Mutating `roundConfig = nil` is safe.

## `postCancelMembers` snapshot

[RoundCoordinatorView.swift:130](../../Carry/Views/RoundCoordinatorView.swift:130):
```swift
@State private var postCancelMembers: [Player]? = nil
```

| Property | Value |
|---|---|
| Purpose | Preserve just-played roster (incl. Quick Game guests added during setup) when `.active → .setup` via Restart Round |
| Why needed | `initialMembers` is static — captured at coordinator init — doesn't reflect mid-session guest additions |
| Set in | `onCancelToSetup`: `postCancelMembers = roundConfig?.players` |
| Read in | `.setup` case: `allMembers: postCancelMembers ?? initialMembers` ([:167](../../Carry/Views/RoundCoordinatorView.swift:167)) |
| Lifecycle | Set in `onCancelToSetup`, never reset, persists for coordinator's lifetime |

## `hasStartedRound`

[RoundCoordinatorView.swift:140](../../Carry/Views/RoundCoordinatorView.swift:140) — distinguishes "fresh setup" vs "returning from active scorecard":

| Value | Back button → |
|---|---|
| `false` | `.courseSelection` (initial setup) |
| `true` | `.active` (return to scorecard) |

Set true in `onConfirm` at [:205](../../Carry/Views/RoundCoordinatorView.swift:205). Set false in deferred cleanup of `onCancelToSetup`.

## `roundCreationTask`

[RoundCoordinatorView.swift:124](../../Carry/Views/RoundCoordinatorView.swift:124) — async task for Supabase round creation.

| Step | Action |
|---|---|
| Spawn | `onConfirm` at [:218-219](../../Carry/Views/RoundCoordinatorView.swift:218) when round needs creating |
| During creation | `.active` branch shows loading fallback |
| Cancel | `onCancelToSetup` deferred block |

## Splash animation states (`.starting`)

[RoundCoordinatorView.swift:143-147](../../Carry/Views/RoundCoordinatorView.swift:143):

| Flag | Reveals at | What |
|---|---|---|
| `showFlag` | +0.15s | Icon + pulsing glow |
| `showTitle` | +0.5s | "Round Started" text |
| `showDetails` | +0.8s | Player count + group count |
| `showStats` | +1.2s | Player pills grid |
| `pulseFlag` | +1.5s | Repeating pulse on outer glow |

Animator: staggered `DispatchQueue.main.asyncAfter` writes ([:242-258](../../Carry/Views/RoundCoordinatorView.swift:242)) wrapped in `withAnimation` for visual sync.

Non-creators skip `.starting` ([:239](../../Carry/Views/RoundCoordinatorView.swift:239)) — direct `.setup → .active`.

## Animation conventions

| Transition | Animation |
|---|---|
| `.courseSelection ↔ .setup` | `easeInOut(0.3)` |
| `.setup → .starting → .active` | `spring(0.45, 0.9)` for active leg |
| `.active → .setup` (edit/restart) | `spring(0.45, 0.9)` |

Wrapping in `withAnimation` is critical: tells SwiftUI's render scheduler to apply animation, delaying branch evaluation to next render tick.

## The 2026-05-09 toast bug (canonical violation)

| Field | Value |
|---|---|
| Symptom | Restart Round → land on setup → red "Couldn't connect — starting offline" toast appears |
| Cause | `onCancelToSetup` cleared `roundConfig = nil` BEFORE `phase = .setup` (or in same `withAnimation` closure). One render tick: phase=.active + roundConfig=nil → loading fallback → onAppear → 10s timeout → fires after user is on setup screen |
| Fix | Moved `roundConfig = nil` (and other cleanup) into `DispatchQueue.main.async` block AFTER `withAnimation { phase = .setup }`. Committed 2026-05-09 |

`onEditPlayers` was already doing this correctly (never mutates `roundConfig`).

## Common bugs / gotchas

| Bug | Cause |
|---|---|
| `onAppear` fires for transitional views | SwiftUI may render branch for one frame during state transitions even if user never visually sees it. Loading-fallback `onAppear` scheduling timeouts is canonical |
| Batched state mutations in closures | Body re-renders once with all changes. Setting `roundConfig = nil` then `phase = .setup` both apply, but body still evaluates `.active` branch (with nil config) once before next state push |
| `postCancelMembers` is one-way | Once set, stays. Course changes don't clear it. By design — quick re-restart preserves roster |
| `roundConfig` may be nil at `.active` | Loading fallback handles it. 10s offline-timeout catches truly stuck state |
| Splash flags can leak | If `onEditPlayers` doesn't reset `showFlag` etc., `.setup` could render with half-rendered splash. Reset in `onEditPlayers` + deferred cleanup of `onCancelToSetup` both handle it |

## Last verified

2026-05-10 — "Back to Groups" splash button removed (half-wired UX trap). `.starting` now has only "Go to Scorecard" forward. To return to setup post-round-start, use scorecard `...` menu (`onEditPlayers` or `onCancelToSetup`).
