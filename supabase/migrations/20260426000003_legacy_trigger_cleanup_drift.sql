-- Placeholder for prod migration applied via the Supabase dashboard on
-- 2026-04-26. The original SQL was the legacy-trigger cleanup that fixed
-- duplicate push notifications (see MEMORY: prod_db_drift_legacy_triggers.md).
-- The actual statements are not recoverable — this file exists only so
-- `supabase migration list` reconciles, and prod can be re-checked with
-- `SELECT tgname FROM pg_trigger WHERE tgrelid IN (...);` if push behavior
-- regresses.
SELECT 1;
