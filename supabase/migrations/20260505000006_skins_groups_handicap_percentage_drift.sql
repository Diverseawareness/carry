-- Migration: backfill skins_groups.handicap_percentage column on dev.
--
-- iOS writes `handicap_percentage` as part of both SkinsGroupInsert and
-- SkinsGroupUpdate (see SupabaseModels.swift). Prod's `skins_groups` table
-- has this column — added historically outside migration tracking — but
-- dev's clean migration history never created it, so Quick Game / Skins
-- Group creates against dev fail with PGRST204 "Could not find the
-- 'handicap_percentage' column of 'skins_groups'".
--
-- Backfill the column so dev matches prod. Default 1.0 (100%) matches the
-- iOS default in `SkinRules.default`.

ALTER TABLE public.skins_groups
    ADD COLUMN IF NOT EXISTS handicap_percentage double precision NOT NULL DEFAULT 1.0;

COMMENT ON COLUMN public.skins_groups.handicap_percentage IS
    'Default handicap percentage applied to rounds in this group (0.0-1.0, e.g. 0.7 = 70%). Drift-fix migration: column existed on prod outside migration tracking.';
