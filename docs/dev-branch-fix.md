# Dev branch — "Unhealthy / MIGRATIONS: FAILED" badge

Captured 2026-05-06. Self-contained explanation of why the Supabase dashboard's dev branch is showing the failure badge, why the obvious "just press Reset" path doesn't work, and what the actual fix is.

---

## TL;DR

The dev branch can't apply its pending migrations because main still has the 48 original migration files. The fix isn't a button-press — it's a consolidation merge that brings hotfix/1.0.3 + hotfix/1.0.4 + the squash baseline into main as one careful operation, then reconfigures dev to follow main.

**Current decision (2026-05-06): defer.** The badge is cosmetic; dev still functions. Plan the consolidation for after 1.0.5 ships.

---

## What the badge actually means

The Supabase dashboard shows two recent failed runs (visible in Workflow logs for dev): both `MIGRATIONS: FAILED` with `2 PENDING`. Those aren't stale UI — they're real failures from the dev branch trying (and failing) to apply pending migrations against a broken state.

The "2 PENDING" are likely the dev-only sync commits from `infra/squash-migrations-baseline`:
- `8e37e73` — chore(migrations): dev sync — rename duplicate timestamp + drift backfill
- `02db5c0` — infra: squash 48 migrations into single baseline

---

## Current state (verified via git, 2026-05-06)

| What | State |
|---|---|
| `main` HEAD | `be619ab` ("Bump MARKETING_VERSION to 1.0.2") — pre-1.0.3, pre-squash |
| `hotfix/1.0.3` | Multiple commits, shipped as build 67 to App Store |
| `hotfix/1.0.4` | Branched from 1.0.3, shipped as build 77 to App Store (LIVE) |
| `hotfix/1.0.5` | Branched from 1.0.4, work-in-progress (modal removal + finder cleanup) |
| `feature/auth-v2` | In-progress, never merged anywhere |
| `feature/notif-prefs-server-side` | In-progress |
| `feature/dev-push-setup` | Parked WIP (Carry-dev.entitlements + widgets scheme) |
| `infra/squash-migrations-baseline` | Pushed to remote at `02db5c0`. **NOT merged to main.** |

**Critical:** none of the hotfix work has been merged back to main. Main is ~3 weeks behind production.

---

## Why "just press Reset on the dashboard" doesn't work

The Reset action pulls migrations from `main` → applies them to dev. Sequence:

1. You press Reset.
2. Supabase pulls migrations from `main`.
3. Main has the original 48 broken pre-squash migration files.
4. Dev tries to apply those → **same failure as before** → badge stays red.

The fix only works once main has the squashed baseline.

---

## What the squash branch actually contains

`infra/squash-migrations-baseline` is **not** just a clean migration squash. Looking at its full delta from main:

```
20 commits ahead of main:
  ├─ 18 hotfix/1.0.3 + hotfix/1.0.4 commits (production code)
  ├─ chore(migrations): dev sync — timestamp rename + drift backfill
  └─ infra: squash 48 migrations → 1 baseline   ← the actual squash
```

So merging `infra/squash-migrations-baseline → main` brings:
- Three weeks of shipped hotfix code (1.0.3 + 1.0.4)
- The migration squash

…all in one go. That's a substantial merge with real regression surface — not a small infra fix.

---

## The proper fix path (consolidation merge — for later)

**Do this AFTER 1.0.5 ships and is stable.** Plan a dedicated session for it.

### Step 1 — Sync main with shipped state
Merge the latest hotfix branch into main first, so main reflects what's actually in production:

```bash
git checkout main
git merge hotfix/1.0.5  # or whatever the latest shipped hotfix is
git push origin main
```

This catches main up to production. Lots of code; deserves careful review.

### Step 2 — Land the squash baseline on top
Cherry-pick the squash commit onto main:

```bash
git cherry-pick 02db5c0
git push origin main
```

(The dev-sync commit `8e37e73` may or may not be needed depending on whether it's a no-op once main is current — judge at the time.)

### Step 3 — Configure dev's GitHub integration
Supabase dashboard → dev branch settings → set up GitHub integration → point at `main`. **Do not skip this step.** Reset without a configured GitHub source risks the platform marking versions "applied" without running the SQL (because it doesn't store migration content), leaving you with a green badge over an empty DB.

### Step 4 — Reset dev branch
Supabase dashboard → Reset dev → it pulls the new squashed baseline from `main` → applies cleanly → MIGRATIONS: SUCCEEDED → badge flips green.

### Step 5 — Rebase in-flight feature branches
`feature/auth-v2`, `feature/notif-prefs-server-side`, `feature/dev-push-setup` all branch from older points. Rebase each onto the new main, resolve conflicts, push. This is the painful part.

---

## The dirty alternative (`supabase migration repair`) — avoid

Run something like:
```bash
supabase migration repair --status applied <migration-version> --project-ref gbhljwtbobbxervekxkg
```

This marks the failed migrations as "applied" without actually running them. Badge goes green fast. **But:**

- Dev's actual schema state diverges from any source-of-truth baseline.
- Memory's auth-v2 quarantine rule **literally depends** on dev being clean (tested against an authoritative baseline). Repairing-without-syncing undermines that condition.
- The next time you need dev's schema to match prod (e.g., real auth-v2 testing against expected prod schema), the divergence bites silently.

This is a trap that sounds clean. Don't.

---

## Why "do nothing now" is the right call

1. **The badge doesn't block anything.** Dev still functions for testing — auth-v2, dev builds, everything works. The badge signals broken migration-audit history, not broken DB connectivity.
2. **The proper fix is bigger than the badge warrants.** Multi-hour consolidation operation with real regression surface, requiring rebases of three feature branches. Doing it solely to clear a dashboard badge is the tail wagging the dog.
3. **A natural moment is coming.** After 1.0.5 ships, you'll have stable production + no active hotfix track + time to plan the consolidation properly. That's the right moment, not now while mid-flight.

---

## Future Claude session — start here

If a future session is asked "fix the unhealthy dev badge":
1. Re-read this doc first.
2. Confirm `git log main` is at `be619ab` or thereabouts (still pre-squash) — if so, the consolidation merge hasn't happened yet.
3. Check whether 1.0.5 has shipped + stabilized.
4. If not stable yet → recommend continuing to defer.
5. If stable → walk through the consolidation merge above, carefully, branch-by-branch.

---

## References

- Squash branch: `origin/infra/squash-migrations-baseline`, HEAD `02db5c0`
- Dev project ref: `gbhljwtbobbxervekxkg`
- Prod project ref: `seeitehizboxjbnccnyd`
- Memory entry: `MEMORY.md` "🟡 TOMORROW (2026-05-07): Reset dev branch" — note: that entry's "tomorrow" framing is too aggressive; this doc supersedes it.
