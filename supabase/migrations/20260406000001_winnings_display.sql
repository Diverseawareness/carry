-- Add winnings_display setting to skins_groups
-- 'gross' = show only what you've won (never negative)
-- 'net' = show winnings minus buy-in (true P&L, can be negative)

ALTER TABLE skins_groups
ADD COLUMN IF NOT EXISTS winnings_display TEXT NOT NULL DEFAULT 'gross'
CHECK (winnings_display IN ('gross', 'net'));

NOTIFY pgrst, 'reload schema';
