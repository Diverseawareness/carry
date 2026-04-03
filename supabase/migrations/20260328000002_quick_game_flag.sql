-- Add is_quick_game flag to skins_groups so Quick Game UI persists across reloads
ALTER TABLE skins_groups ADD COLUMN IF NOT EXISTS is_quick_game BOOLEAN DEFAULT false;
NOTIFY pgrst, 'reload schema';
