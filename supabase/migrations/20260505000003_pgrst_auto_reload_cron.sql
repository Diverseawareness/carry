-- Enable pg_cron and schedule automatic PostgREST schema reloads every minute.
-- Fixes the cold-start race condition on the dev Supabase branch where
-- PostgREST starts before its schema cache is warm.
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule(
    'reload-pgrst-schema',
    '* * * * *',
    $$ NOTIFY pgrst, 'reload schema' $$
);
