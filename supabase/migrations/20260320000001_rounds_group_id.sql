-- ============================================================
-- Migration: Add group_id to rounds
-- Links rounds to skins_groups for group-based round queries
-- ============================================================

ALTER TABLE rounds ADD COLUMN IF NOT EXISTS group_id uuid REFERENCES skins_groups(id);

-- Fast lookup for active rounds in a group
CREATE INDEX IF NOT EXISTS idx_rounds_group ON rounds(group_id) WHERE status = 'active';
