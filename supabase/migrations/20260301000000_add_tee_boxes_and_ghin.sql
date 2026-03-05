-- Migration: Add tee boxes table, GHIN number, and handicap percentage
-- Date: 2026-03-01

-- Add GHIN number to profiles
alter table public.profiles
    add column if not exists ghin_number text;

-- Create tee_boxes table (each course has multiple tee boxes)
create table if not exists public.tee_boxes (
    id              uuid primary key default gen_random_uuid(),
    course_id       uuid not null references public.courses(id) on delete cascade,
    name            text not null,           -- e.g. "Blue", "White", "Gold"
    color           text not null default '#FFFFFF',  -- hex color for UI
    course_rating   double precision not null,  -- e.g. 71.5
    slope_rating    int not null,               -- e.g. 134 (range: 55-155)
    par             int not null,               -- total par from these tees
    created_at      timestamptz not null default now(),
    unique(course_id, name)
);

-- Add tee_box_id and handicap_percentage to rounds
alter table public.rounds
    add column if not exists tee_box_id uuid references public.tee_boxes(id),
    add column if not exists handicap_percentage double precision not null default 1.0;

-- RLS for tee_boxes
alter table public.tee_boxes enable row level security;

create policy "Tee boxes are viewable by everyone"
    on public.tee_boxes for select using (true);

create policy "Authenticated can create tee boxes"
    on public.tee_boxes for insert with check (auth.uid() is not null);

create policy "Course creator can update tee boxes"
    on public.tee_boxes for update using (
        exists (
            select 1 from public.courses c
            where c.id = course_id and c.created_by = auth.uid()
        )
    );

-- Comment for documentation
comment on column public.profiles.ghin_number is 'USGA GHIN number for handicap index lookup';
comment on column public.tee_boxes.course_rating is 'USGA Course Rating for this set of tees';
comment on column public.tee_boxes.slope_rating is 'USGA Slope Rating (55-155, standard 113)';
comment on column public.rounds.tee_box_id is 'Which tees are being played this round';
comment on column public.rounds.handicap_percentage is 'Handicap percentage (0.0-1.0), e.g. 0.7 for 70%';
