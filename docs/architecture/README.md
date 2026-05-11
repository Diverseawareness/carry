# Architecture — Reference Cards

This is the blueprint for game-setup logic. Each topic doc is a compact reference card covering rules, dependencies, invariants, and known gotchas. The goal: pinpoint any state, flag, or transition without re-reading the whole codebase.

**Start here: [playbook.md](playbook.md)** — the entry point. It tells you which docs to read in what order before touching code, plus the pre-flight and post-change checklists. Always consult the playbook first.

**When to consult these:**
- Before adding a new feature that touches groups, rounds, scoring, or pushes
- Before changing a flag, status field, or invariant
- When a bug repro is unclear — find the topic doc, check the decision matrix
- During code review of changes to `GroupManagerView`, `PlayerGroupsSheet`, `RoundCoordinatorView`, `ScorecardView`, or any migration

**Convention:** every claim cites `file:line`. If a citation is wrong, the doc is wrong — fix the doc.

## Topic docs

| Doc | What it covers |
|---|---|
| [game-types.md](game-types.md) | Quick Game vs Skins Group — flag checks, lifecycle, conversion, member rules, UI differences |
| [guest-lifecycle.md](guest-lifecycle.md) | The 2026-05-01 ephemeral-guests rule, where guests live (round_players only), UserDefaults snapshot, conversion-clears, cleanup paths |
| [scorer-rules.md](scorer-rules.md) | `canScore` predicate, `scorerIDs` lifecycle, `syncScorerIDs` invariants, creator-locked rule, scoringMode (`.single` vs `.everyone`), the Quick Game scorer wedge |
| [player-flags.md](player-flags.md) | Decision matrix for `profileId`, `isGuest`, `isPendingInvite`, `isPendingAccept` — how they combine, who sets them, who reads them |
| [phase-transitions.md](phase-transitions.md) | `RoundCoordinatorView` state machine, transition triggers, the order-of-state-mutations rule that bit us 2026-05-09 |
| [refresh-race-guards.md](refresh-race-guards.md) | The 8-second `lastSavedAt` pattern — three instances, why they exist, how to add a new one without breaking |
| [push-trigger-chain.md](push-trigger-chain.md) | The four push-firing Postgres functions, shared Vault helpers, edge function dispatch, per-handler recipients + preference gating |
| [db-schema-rules.md](db-schema-rules.md) | Core tables, RLS policies, FK cascade rules, architectural invariants (Carry-only group_members, ephemeral round_players guests) |
| [onboarding-and-auth.md](onboarding-and-auth.md) | Three-state launch gate, Apple Sign In path, OnboardingView 4/5-step flow, profile creation (trigger + fallback), phone reconciliation, APNs registration, **auth-v2 extension points + quarantine rule** |
| [skins-math.md](skins-math.md) | USGA course-handicap formula, percentage allowance, stroke allocation (regular + plus-HC give-back), per-hole skins determination, carries on/off, pot split + money distribution, the 70% recalc canonical example |
| [score-pipeline.md](score-pipeline.md) | Tap → @State → ScoreStorage UserDefaults → Supabase upsert → realtime + 15s poll. Score dispute / proposal flow. Cancellation cleanup |
| [round-lifecycle.md](round-lifecycle.md) | The four `rounds.status` values, transition triggers, `force_completed` semantics, `archiveConcludedRound`, `isConcludedQuickGame` visibility, push fan-out |
| [tee-time-sovereignty.md](tee-time-sovereignty.md) | The 1.0.6 single-writer rule, recompute fallback, duplicate-time auto-bump, `tee_times_json` persistence |
| [recurring-rounds.md](recurring-rounds.md) | `GameRecurrence` enum, `advanceScheduledDateIfRecurring`, "Schedule Next Round" CTA, day-of-week mapping |
| [manage-members.md](manage-members.md) | Add/remove flow, pending section, the SwiftUI sheet state-propagation race (locked 2026-05-02), atomicity, dedup |
| [group-invitation-flow.md](group-invitation-flow.md) | Three invite paths, forward + reverse phone reconciliation triggers, 30-day staleness guard, auto-accept rule |
| [results-share.md](results-share.md) | RoundCompleteView post-round sheet, ResultsShareCard + ImageRenderer, Venmo deep link, RoundStatsView, avatar prefetch |
| [deep-link-routing.md](deep-link-routing.md) | `carry://` + Universal Links, AppRouter state, cold-start vs warm-start handlers, auth gate, lazy-load semantics |
| [account-linking.md](account-linking.md) | Forward-looking spec for auth-v2: link/unlink semantics, edge cases, the implementation checklist before merging to main |
| [bug-archive.md](bug-archive.md) | Every prod regression: symptom → root cause → fix → blueprint that should have prevented it. Use during retros + when a new bug looks familiar |

## Living rules quick-reference

- **Carry-only `group_members`** (locked 2026-05-01) — guests never have a row here
- **Ephemeral guests** (locked 2026-05-01) — guest profiles only in `round_players` for active rounds; survive wipe via denormalized `guest_display_name` + `guest_handicap`
- **Creator-locked-as-scorer** — wherever the creator sits in the tee sheet, that group's scorer must be the creator (PlayerGroupsSheet binding setter + `syncScorerIDs`)
- **Creator immutability** — `skins_groups.created_by` never changes after INSERT
- **Phase transitions** — change `phase` first, defer cleanup; never mutate `roundConfig` in the same closure as a phase change
- **8-second race guard** — every user-editable field guarded by `<field>LastSavedAt` to prevent refresh stomps
- **Verify JWT for push triggers** — back ON post-2026-05-09 Vault migration; URL no longer publicly callable

## How to update these docs

When you change source code that affects any of these topics:
1. Find the relevant topic doc.
2. Update the citation (file:line) and any rule statements that changed.
3. If a new rule emerged or a new flag was added, add it to the decision matrix.
4. Cross-link from related docs if dependencies changed.
5. Bump the "Last verified" date at the bottom of the topic doc.

If you discover a citation is stale during a bug hunt, fix the doc as part of the same PR. Stale docs are worse than no docs.
