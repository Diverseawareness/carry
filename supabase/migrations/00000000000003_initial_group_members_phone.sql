-- ============================================================
-- Migration: Add invited_phone to group_members
-- This column was added to prod manually before migration
-- 20260426000000 (unique_group_member_per_player) which
-- references it. Idempotent.
-- ============================================================

ALTER TABLE public.group_members
    ADD COLUMN IF NOT EXISTS invited_phone text;
