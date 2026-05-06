# Migration runbook — 2026-05-01

Run these in order in the Supabase SQL Editor (https://supabase.com/dashboard/project/seeitehizboxjbnccnyd/sql/new). Each block is a complete, self-contained migration. Wait for `Success. No rows returned.` between them.

---

## 1. Trigger fix (already applied 2026-05-01 evening)

Source: [supabase/migrations/20260501000000_fix_notify_push_per_table_dispatch.sql](../supabase/migrations/20260501000000_fix_notify_push_per_table_dispatch.sql)

This is already live in prod. Skip if you're just resuming.

---

## 2. Ephemeral guests + history denormalization

Source: [supabase/migrations/20260501000001_ephemeral_quick_game_guests.sql](../supabase/migrations/20260501000001_ephemeral_quick_game_guests.sql)

Adds `guest_display_name` + `guest_handicap` to `round_players` and `scores`. Drops the FK from `round_players.player_id` and `scores.player_id` to `profiles.id` so guest profiles can be hard-deleted while keeping the UUID join key intact. Changes `group_members.player_id` FK to `ON DELETE CASCADE`. Creates `delete_quick_game_guests(p_round_id uuid)` RPC.

> **Pre-flight on prod 2026-05-01:** the original migration (without the orphan cleanup) FAILED with `23503: insert or update on table "group_members" violates foreign key constraint`. There were 39 orphaned `group_members` rows in prod from March–April test data — `player_id` UUIDs whose profiles had already been deleted manually. The new CASCADE FK couldn't be added against that data. The block below now includes the cleanup pre-step. Re-runnable on any environment.

```sql
ALTER TABLE public.round_players
    ADD COLUMN IF NOT EXISTS guest_display_name text,
    ADD COLUMN IF NOT EXISTS guest_handicap double precision;

ALTER TABLE public.scores
    ADD COLUMN IF NOT EXISTS guest_display_name text,
    ADD COLUMN IF NOT EXISTS guest_handicap double precision;

ALTER TABLE public.round_players DROP CONSTRAINT IF EXISTS round_players_player_id_fkey;

ALTER TABLE public.scores DROP CONSTRAINT IF EXISTS scores_player_id_fkey;

-- Pre-flight: remove orphaned group_members rows (player_id has no matching
-- profile). On prod 2026-05-01 this returned 39 rows from old test data.
SELECT count(*) AS orphaned_count
FROM public.group_members gm
WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = gm.player_id);

DELETE FROM public.group_members gm
WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = gm.player_id);

ALTER TABLE public.group_members DROP CONSTRAINT IF EXISTS group_members_player_id_fkey;
ALTER TABLE public.group_members
    ADD CONSTRAINT group_members_player_id_fkey
    FOREIGN KEY (player_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

CREATE OR REPLACE FUNCTION public.delete_quick_game_guests(p_round_id uuid)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    deleted_count int;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM rounds
        WHERE id = p_round_id AND created_by = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Not authorized — only the round creator can delete guests for round %', p_round_id;
    END IF;

    UPDATE round_players rp
    SET guest_display_name = p.display_name,
        guest_handicap = p.handicap
    FROM profiles p
    WHERE rp.player_id = p.id
      AND p.is_guest = true
      AND p.id IN (
          SELECT DISTINCT player_id FROM round_players
          WHERE round_id = p_round_id AND player_id IS NOT NULL
      );

    UPDATE scores s
    SET guest_display_name = p.display_name,
        guest_handicap = p.handicap
    FROM profiles p
    WHERE s.player_id = p.id
      AND p.is_guest = true
      AND p.id IN (
          SELECT DISTINCT player_id FROM round_players
          WHERE round_id = p_round_id AND player_id IS NOT NULL
      );

    DELETE FROM profiles
    WHERE is_guest = true
      AND id IN (
          SELECT DISTINCT player_id FROM round_players
          WHERE round_id = p_round_id AND player_id IS NOT NULL
      );

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_quick_game_guests(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
```

### Verify

```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('round_players', 'scores')
  AND column_name IN ('player_id', 'guest_display_name', 'guest_handicap')
ORDER BY table_name, column_name;
```
Expect: 6 rows total. `player_id` stays `uuid NOT NULL`. `guest_display_name` `text YES`. `guest_handicap` `double precision YES`.

```sql
SELECT tc.table_name, tc.constraint_name, rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.referential_constraints rc USING (constraint_schema, constraint_name)
WHERE tc.constraint_schema = 'public'
  AND tc.constraint_name IN (
      'round_players_player_id_fkey',
      'scores_player_id_fkey',
      'group_members_player_id_fkey'
  );
```
Expect: 1 row only — `group_members_player_id_fkey` → `CASCADE`. The other two constraint names should be GONE entirely (dropped, not re-created).

---

## 3. Convert RPC: Carry-only + auto-accept

Source: [supabase/migrations/20260501000002_convert_quick_game_carry_only_auto_accept.sql](../supabase/migrations/20260501000002_convert_quick_game_carry_only_auto_accept.sql)

Rewrites `convert_quick_game_to_group`:
- Wipes guest profiles for the round (via `delete_quick_game_guests`)
- KEEPS Carry users at `status='active'` (no demotion to `'invited'`, no invite UX)
- Flips `is_quick_game = false` and renames the group

```sql
CREATE OR REPLACE FUNCTION public.convert_quick_game_to_group(
    p_group_id uuid,
    p_group_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _round_id uuid;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM skins_groups
        WHERE id = p_group_id AND created_by = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Not authorized — only the group creator can convert group %', p_group_id;
    END IF;

    SELECT id INTO _round_id
    FROM rounds
    WHERE group_id = p_group_id
    ORDER BY created_at DESC
    LIMIT 1;

    IF _round_id IS NOT NULL THEN
        PERFORM public.delete_quick_game_guests(_round_id);
    END IF;

    UPDATE skins_groups
    SET is_quick_game = false,
        name = COALESCE(p_group_name, name)
    WHERE id = p_group_id;
END;
$$;

NOTIFY pgrst, 'reload schema';
```

### Verify

```sql
SELECT proname, prosecdef AS security_definer
FROM pg_proc
WHERE proname IN ('delete_quick_game_guests', 'convert_quick_game_to_group')
  AND pronamespace = 'public'::regnamespace;
```
Expect: 2 rows, both `security_definer = true`.

---

## 4. Phase 5 — One-time legacy guest purge

Source: [docs/phase-5-legacy-guest-purge.sql](phase-5-legacy-guest-purge.sql).

### State as of 2026-05-01 evening

✅ **Backfill + delete RAN.** Counts:
- 236 legacy `is_guest=true` profiles wiped.
- 140 orphaned `scores` rows still have `guest_display_name = NULL` after backfill — these reference profiles that were deleted manually in earlier testing (BEFORE today). The backfill couldn't reach them. Need a separate "Removed Guest" placeholder backfill.
- All 140 orphaned scores are tied to rounds that still exist (`orphaned_scores_in_orphaned_rounds = 0`), so they're real history records — we want to keep them visible.

### SQL run

```sql
UPDATE public.round_players rp
SET guest_display_name = p.display_name,
    guest_handicap = p.handicap
FROM public.profiles p
WHERE rp.player_id = p.id
  AND p.is_guest = true
  AND rp.guest_display_name IS NULL;

UPDATE public.scores s
SET guest_display_name = p.display_name,
    guest_handicap = p.handicap
FROM public.profiles p
WHERE s.player_id = p.id
  AND p.is_guest = true
  AND s.guest_display_name IS NULL;

DELETE FROM public.profiles WHERE is_guest = true;
```

### Pending: placeholder backfill for the pre-existing orphans

For score + round_players rows whose `player_id` references a profile that was deleted **before** today's wipe ran, set a sensible placeholder so Round History stays readable.

```sql
-- Will write the actual placeholder backfill SQL after deciding the placeholder
-- name with the user. Default candidate: "Removed Guest" + handicap=0.
```

---

## 5. Phase 6 — Cleanup the broken 12:20 group

Source: [docs/phase-6-cleanup-broken-1220-group.sql](phase-6-cleanup-broken-1220-group.sql).

Same approach — `BEGIN`/`COMMIT` with sanity SELECTs.

---

## State as of 2026-05-01 evening

| Step | State |
|------|-------|
| 1 — trigger fix | ✅ Applied + validated |
| 2 — ephemeral guests | 🔄 Running now |
| 3 — convert RPC | ⏸ Next |
| 4 — legacy purge | ⏸ After end-to-end retest |
| 5 — broken 12:20 cleanup | ⏸ Last |
