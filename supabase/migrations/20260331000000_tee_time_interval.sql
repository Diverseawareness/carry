-- Add tee_time_interval column for consecutive tee times (minutes between groups)
ALTER TABLE public.skins_groups ADD COLUMN IF NOT EXISTS tee_time_interval int;

NOTIFY pgrst, 'reload schema';
