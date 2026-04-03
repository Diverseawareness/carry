-- ============================================================
-- Migration: Drop the ACTUAL FK constraints blocking deletion
-- Date: 2026-04-01
-- Found via pg_constraint query: rounds_scorer_id_fkey,
-- scores_proposed_by_fkey, profiles_created_by_fkey
-- ============================================================

ALTER TABLE public.rounds DROP CONSTRAINT IF EXISTS rounds_scorer_id_fkey;
ALTER TABLE public.scores DROP CONSTRAINT IF EXISTS scores_proposed_by_fkey;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_created_by_fkey;
