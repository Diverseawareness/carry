-- Store per-hole par/handicap data directly on the group so it survives
-- refreshes and is available before a round is created.
ALTER TABLE skins_groups ADD COLUMN IF NOT EXISTS last_tee_box_holes_json text;

NOTIFY pgrst, 'reload schema';
