-- Add scorer_ids JSON column to skins_groups for per-group scorer assignments
-- Stores array of player Int IDs, one per group: [creatorId, scorer2Id, ...]
ALTER TABLE public.skins_groups ADD COLUMN IF NOT EXISTS scorer_ids jsonb;

NOTIFY pgrst, 'reload schema';
