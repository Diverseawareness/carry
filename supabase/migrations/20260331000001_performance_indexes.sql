-- Performance indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_group_members_group_status ON group_members(group_id, status);
CREATE INDEX IF NOT EXISTS idx_group_members_player_status ON group_members(player_id, status);
CREATE INDEX IF NOT EXISTS idx_round_players_round_status ON round_players(round_id, status);
CREATE INDEX IF NOT EXISTS idx_scores_round_player ON scores(round_id, player_id);
CREATE INDEX IF NOT EXISTS idx_rounds_group_status ON rounds(group_id, status);

NOTIFY pgrst, 'reload schema';
