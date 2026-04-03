-- ============================================================
-- Migration: skins_groups + group_members
-- Adds persistent skins game groups with membership tracking
-- ============================================================

-- 1. skins_groups — top-level group entity
create table skins_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid references profiles(id) not null,
  buy_in numeric default 0,
  last_course_name text,
  last_course_club_name text,
  scheduled_date timestamptz,
  recurrence jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table skins_groups enable row level security;

-- 2. group_members — junction between groups and profiles
create table group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid references skins_groups(id) on delete cascade not null,
  player_id uuid references profiles(id) not null,
  role text not null default 'member',       -- 'creator' | 'member'
  status text not null default 'active',     -- 'active' | 'invited' | 'removed'
  joined_at timestamptz default now(),
  unique(group_id, player_id)
);

alter table group_members enable row level security;

-- Index for fast "my groups" lookup
create index idx_group_members_player on group_members(player_id) where status = 'active';

-- ============================================================
-- RLS Policies: skins_groups
-- ============================================================

-- Members can read groups they belong to
create policy "Members can read their groups"
  on skins_groups for select
  using (
    id in (
      select group_id from group_members
      where player_id = auth.uid() and status = 'active'
    )
  );

-- Authenticated users can create groups (must be the creator)
create policy "Authenticated users can create groups"
  on skins_groups for insert
  with check (auth.uid() = created_by);

-- Creators can update their groups
create policy "Creators can update their groups"
  on skins_groups for update
  using (created_by = auth.uid());

-- Creators can delete their groups
create policy "Creators can delete their groups"
  on skins_groups for delete
  using (created_by = auth.uid());

-- ============================================================
-- RLS Policies: group_members
-- ============================================================

-- Members can see other members in their groups
create policy "Members can read group members"
  on group_members for select
  using (
    group_id in (
      select group_id from group_members gm
      where gm.player_id = auth.uid() and gm.status = 'active'
    )
  );

-- Group creators can add members
create policy "Creators can insert members"
  on group_members for insert
  with check (
    group_id in (
      select id from skins_groups where created_by = auth.uid()
    )
    or player_id = auth.uid()  -- users can add themselves (join)
  );

-- Group creators can update members (change role/status)
create policy "Creators can update members"
  on group_members for update
  using (
    group_id in (
      select id from skins_groups where created_by = auth.uid()
    )
    or player_id = auth.uid()  -- members can update their own status
  );

-- Group creators can remove members
create policy "Creators can delete members"
  on group_members for delete
  using (
    group_id in (
      select id from skins_groups where created_by = auth.uid()
    )
    or player_id = auth.uid()  -- members can leave
  );

-- ============================================================
-- Auto-update updated_at on skins_groups
-- ============================================================

create or replace function update_skins_groups_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger skins_groups_updated_at
  before update on skins_groups
  for each row
  execute function update_skins_groups_updated_at();
