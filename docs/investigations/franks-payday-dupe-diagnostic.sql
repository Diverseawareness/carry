-- ============================================================================
-- Frank's Payday — duplicate-guest diagnostic  (100% READ-ONLY)
-- Run in PROD Supabase Studio → SQL Editor
--   Project: seeitehizboxjbnccnyd  (Carry, East US Ohio = the LIVE app's DB)
-- Purpose: distinguish the two possible root-cause shapes for the dupes.
-- ============================================================================

-- ── Query A: the group row + its between-round snapshot ─────────────────────
select id, name, is_quick_game, created_at, guest_roster_json
from skins_groups
where name = 'Frank''s Payday'
order by created_at desc;

-- ── Query B: every round for the group (newest first) ──────────────────────
select id, status, created_at
from rounds
where group_id = (select id from skins_groups
                  where name = 'Frank''s Payday'
                  order by created_at desc limit 1)
order by created_at desc;

-- ── Query C: round_players of the MOST RECENT round, joined to profiles ────
-- THE decisive query. If the same human appears on >1 row with DIFFERENT
-- player_id ⇒ server-side duplicate guest profiles (identity minted twice).
-- If each human appears once here ⇒ the dupe is client-side (roster merge).
select rp.player_id,
       rp.group_num,
       coalesce(p.display_name, rp.guest_display_name) as name,
       coalesce(p.handicap,    rp.guest_handicap)     as handicap,
       coalesce(p.is_guest, true)                     as is_guest,
       (p.id is null)                                 as profile_wiped
from round_players rp
left join profiles p on p.id = rp.player_id
where rp.round_id = (
  select id from rounds
  where group_id = (select id from skins_groups
                    where name = 'Frank''s Payday'
                    order by created_at desc limit 1)
  order by created_at desc limit 1
)
order by name, rp.player_id;

-- ── Query D: dupe summary — names that occur more than once in that round ───
select coalesce(p.display_name, rp.guest_display_name) as name,
       count(*)                          as rows,
       count(distinct rp.player_id)      as distinct_player_ids
from round_players rp
left join profiles p on p.id = rp.player_id
where rp.round_id = (
  select id from rounds
  where group_id = (select id from skins_groups
                    where name = 'Frank''s Payday'
                    order by created_at desc limit 1)
  order by created_at desc limit 1
)
group by 1
having count(*) > 1
order by rows desc;
