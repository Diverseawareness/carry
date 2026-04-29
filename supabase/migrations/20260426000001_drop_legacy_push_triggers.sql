-- Migration: Drop legacy push-notification triggers and their helper function.
--
-- Why: production logs showed every group invite firing two `[dispatch]`
-- entries in send-push-notification, two APNs sends, and (when timing
-- allowed) two banners on the device. Cause: `group_members`, `rounds`,
-- and `scores` each had two parallel sets of triggers, both calling the
-- same edge function with the same payload:
--
--   * `on_*_change` triggers from migration 20260330000001 (kept) →
--      `notify_push()`
--   * `push_on_*` triggers (dropped here) → `notify_webhook()`, an older
--      function that was never captured in a migration. It existed only
--      in the live DB, so the original migration had no DROP for it.
--
-- Both functions POST identical payloads to /functions/v1/send-push-notification,
-- so the legacy set produced exact duplicates of every invite, member-joined,
-- round-started, round-ended, scorer-change, and score-dispute push.
--
-- Safe to re-run: every step uses IF EXISTS.

DROP TRIGGER IF EXISTS push_on_group_member_insert ON public.group_members;
DROP TRIGGER IF EXISTS push_on_group_member_update ON public.group_members;
DROP TRIGGER IF EXISTS push_on_round_insert ON public.rounds;
DROP TRIGGER IF EXISTS push_on_round_update ON public.rounds;
DROP TRIGGER IF EXISTS push_on_scorer_change ON public.rounds;
DROP TRIGGER IF EXISTS push_on_score_dispute ON public.scores;

-- The helper function has no remaining references (verified via pg_trigger
-- sweep on 2026-04-26). Drop it so it can't be wired back up by accident.
DROP FUNCTION IF EXISTS public.notify_webhook();

-- Also drop on_score_insert. It was declared in 20260402000000 to fire the
-- "all groups active" creator push, but in prod the AFTER INSERT trigger
-- consistently rolls back the underlying score INSERT (every device's score
-- writes hung in the SyncQueue with the orange "pending" icon). Live triage
-- on launch eve confirmed: dropping the trigger restored scoring across all
-- devices within seconds. Root cause inside notify_push() when invoked from
-- the `scores` table is still TBD — investigate post-launch. Until then,
-- the all-groups-active creator push will not fire, which is a regression
-- vs the original spec but matches the prior (also broken) prod state we
-- inherited at the start of this session.
DROP TRIGGER IF EXISTS on_score_insert ON public.scores;

NOTIFY pgrst, 'reload schema';
