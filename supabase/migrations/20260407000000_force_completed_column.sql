-- Add force_completed flag to rounds table.
--
-- Signals that the creator explicitly ended the game early (as opposed to the
-- round completing naturally after all 18 holes are scored).
--
-- Consumed by:
--   - Client polling: non-creator devices observe status + force_completed
--     to decide whether to auto-show RoundCompleteView or dismiss to home.
--   - send-push-notification Edge Function: routes to gameForceEnded /
--     gameDeleted push types based on status + force_completed.
--
-- Combined with status, the meaning is:
--   status = 'active'                               → in progress
--   status = 'concluded' + force_completed = false  → natural completion
--   status = 'concluded' + force_completed = true   → creator ended early w/ partial scores
--   status = 'cancelled' + force_completed = true   → creator destructively ended, scores deleted
--   status = 'completed'                            → user tapped Save Round Results

ALTER TABLE rounds
ADD COLUMN IF NOT EXISTS force_completed BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN rounds.force_completed IS
'True when the creator used End Game / End Game & Save Results to end the game early. Combined with status, disambiguates natural completion from forced end.';
