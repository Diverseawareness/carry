-- Add tee_times_json column to skins_groups so creators can save independent
-- (non-consecutive) per-group tee times. Stored as a JSON-encoded array of
-- ISO8601 strings with nullable entries — e.g. ["2026-04-18T09:00:00Z",
-- "2026-04-18T09:30:00Z", null]. When present, this overrides the derived
-- scheduled_date + tee_time_interval computation on read.

ALTER TABLE skins_groups
ADD COLUMN IF NOT EXISTS tee_times_json TEXT;

NOTIFY pgrst, 'reload schema';
