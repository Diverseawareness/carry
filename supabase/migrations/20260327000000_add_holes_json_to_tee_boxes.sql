-- Migration: Add per-hole data (par, handicap) to tee_boxes
-- Date: 2026-03-27
-- Stores JSON array of 18 hole objects so real par/handicap data from the
-- Golf Course API persists across sessions and is available to all players.

alter table public.tee_boxes
    add column if not exists holes_json text;

comment on column public.tee_boxes.holes_json is 'JSON array of per-hole data [{id,num,par,hcp},...] for 18 holes from Golf Course API';

-- Notify PostgREST to reload schema cache
notify pgrst, 'reload schema';
