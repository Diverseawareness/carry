-- ============================================================================
-- Migration: Fix notify_push() cross-table NEW-column binding (42703)
-- Date:      2026-05-01
-- ============================================================================
-- Root cause
-- ----------
-- `notify_push()` is a generic trigger function wired to `group_members`,
-- `rounds`, and (originally) `scores`. The 2026-04-29 self_initiated_invite_flag
-- migration introduced this line OUTSIDE any TG_TABLE_NAME guard:
--
--   _self_initiated := (
--       TG_TABLE_NAME = 'group_members'
--       AND auth.uid() IS NOT NULL
--       AND NEW.player_id = auth.uid()
--   );
--
-- PL/pgSQL must bind every NEW.<col> reference against the actual rowtype of
-- the firing trigger. AND-chains in a SQL boolean expression are NOT
-- guaranteed to short-circuit at plan time — the planner may evaluate any
-- conjunct first. So when this trigger fires on a `rounds` INSERT, PL/pgSQL
-- tries to resolve `NEW.player_id` against the `rounds` rowtype, which has
-- no `player_id` column, and raises:
--
--   ERROR  42703  column "player_id" of relation "rounds" does not exist
--
-- The error fires inside the AFTER INSERT trigger transaction, rolling back
-- the rounds row. PostgREST surfaces it as a 400 with `error=42703`.
-- This is exactly the symptom Daniel hit on 2026-05-01: every Quick Game and
-- Group round-start failed silently in TestFlight build 60.
--
-- Same bug class hit `scores` even before the 2026-04-29 migration. The IF
-- guard `IF TG_TABLE_NAME = 'group_members' AND NEW.status = 'invited' THEN`
-- references NEW.status; `scores` has no `status` column, so the same plan-
-- time binding failure rolled back every score INSERT. The 2026-04-26
-- cleanup migration dropped `on_score_insert` as a workaround and left a
-- TODO ("Root cause inside notify_push() when invoked from the `scores`
-- table is still TBD — investigate post-launch"). This migration closes
-- that loop too.
--
-- Fix
-- ---
-- Restructure notify_push() with TG_TABLE_NAME as an OUTER DISPATCHER so
-- every NEW.<col> reference lives inside an `IF TG_TABLE_NAME = 'X' THEN`
-- block whose condition only touches the built-in TG_TABLE_NAME variable
-- (no rowtype binding). The dispatcher is extensible — adding the function
-- to a new table = add a new IF block (or none, if no special handling
-- needed). The generic payload (`to_jsonb(NEW)`, TG_OP, OLD record) works
-- for any rowtype unchanged.
--
-- Behavior preserved (verified against send-push-notification/index.ts):
--   * group_members INSERT/UPDATE → invite, member-joined, member-declined,
--     self_initiated suppression for QR/link self-joins, guest-invite skip.
--   * rounds INSERT/UPDATE → round-started, round-ended, scorer-changed,
--     game-deleted (status→cancelled), game-force-ended (force_completed +
--     status→concluded).
--   * scores INSERT → all-groups-active creator push (restored after the
--     2026-04-26 drop).
--
-- The edge function dispatches by RECORD SHAPE (not by `table` field), so
-- the trigger's only responsibilities are: build payload, decide self_initiated,
-- decide guest-invite skip, POST. All three are now safely scoped.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _url text;
    _payload jsonb;
    _anon_key text;
    _self_initiated boolean := false;
BEGIN
    -- ─── Resolve edge function URL ────────────────────────────────────────
    _url := rtrim(current_setting('app.settings.supabase_url', true), '/')
             || '/functions/v1/send-push-notification';

    IF _url IS NULL OR _url = '' OR _url = '/functions/v1/send-push-notification' THEN
        _url := 'https://seeitehizboxjbnccnyd.supabase.co/functions/v1/send-push-notification';
    END IF;

    -- ─── Resolve anon key ─────────────────────────────────────────────────
    _anon_key := current_setting('app.settings.supabase_anon_key', true);
    IF _anon_key IS NULL OR _anon_key = '' THEN
        _anon_key := coalesce(current_setting('supabase.anon_key', true), '');
    END IF;

    -- ─── Per-table dispatch ───────────────────────────────────────────────
    -- All NEW.<col> references MUST live inside one of these IF blocks.
    -- The IF condition itself only touches TG_TABLE_NAME (a built-in trigger
    -- variable, no rowtype binding) so the planner cannot fail to bind it
    -- when the trigger fires on a different table.
    --
    -- DO NOT add NEW.<col> refs at the top level of this function or in any
    -- expression that runs unconditionally — that's how the 42703 bug
    -- (fixed by this migration) was originally introduced.

    IF TG_TABLE_NAME = 'group_members' THEN
        -- self_initiated: user QR/link-joined themselves. iOS immediately
        -- promotes the row 'invited' → 'active'; without this flag the edge
        -- function would push "You're Invited!" to the user about a group
        -- they actively joined. Set to true so handleGroupInvite skips.
        IF auth.uid() IS NOT NULL AND NEW.player_id = auth.uid() THEN
            _self_initiated := true;
        END IF;

        -- Guest invite skip: guest profiles have no device_token, so the
        -- edge-function call would no-op anyway. Skip the HTTP round-trip.
        IF NEW.status = 'invited' THEN
            PERFORM 1 FROM profiles
            WHERE id = NEW.player_id AND is_guest = true;
            IF FOUND THEN
                RETURN NEW;
            END IF;
        END IF;
    END IF;

    -- rounds and scores branches: payload is built generically below from
    -- to_jsonb(NEW); no table-specific NEW.<col> references needed here.

    -- ─── Build payload ────────────────────────────────────────────────────
    _payload := jsonb_build_object(
        'type',           TG_OP,
        'table',          TG_TABLE_NAME,
        'record',         to_jsonb(NEW),
        'old_record',     CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END,
        'self_initiated', _self_initiated
    );

    -- ─── Fire and forget ──────────────────────────────────────────────────
    PERFORM net.http_post(
        url := _url,
        body := _payload,
        headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'Authorization', 'Bearer ' || _anon_key
        )
    );

    RETURN NEW;
END;
$$;

-- ─── Restore the score-insert trigger ────────────────────────────────────
-- Dropped on 2026-04-26 because the buggy notify_push() rolled back score
-- INSERTs (see migration 20260426000001). The fixed function above is safe
-- on `scores` (no NEW.status / NEW.player_id refs reachable from a scores
-- INSERT under the new dispatcher). Re-create so the "all groups are live"
-- creator push fires again — that regression has been live since launch eve.

DROP TRIGGER IF EXISTS on_score_insert ON public.scores;
CREATE TRIGGER on_score_insert
    AFTER INSERT ON public.scores
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_push();

-- Reload PostgREST schema cache so the function definition update is
-- visible to API clients immediately.
NOTIFY pgrst, 'reload schema';
