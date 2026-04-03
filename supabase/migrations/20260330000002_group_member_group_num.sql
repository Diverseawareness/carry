-- Add group_num column to group_members for multi-group Quick Games
-- Stores which foursome group (1, 2, 3...) each member belongs to
ALTER TABLE public.group_members ADD COLUMN IF NOT EXISTS group_num int NOT NULL DEFAULT 1;

NOTIFY pgrst, 'reload schema';
