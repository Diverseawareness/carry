-- ============================================================
-- Migration: Add scores trigger for "all groups active" push
-- Date: 2026-04-02
-- When a score is inserted, fire the push notification edge
-- function. The edge function checks if all groups now have
-- at least one score and pushes to the creator if so.
-- ============================================================

-- Trigger on scores: fires on INSERT (new score entered)
DROP TRIGGER IF EXISTS on_score_insert ON public.scores;
CREATE TRIGGER on_score_insert
    AFTER INSERT ON public.scores
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_push();

NOTIFY pgrst, 'reload schema';
