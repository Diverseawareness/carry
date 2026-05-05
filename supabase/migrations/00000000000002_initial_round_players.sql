-- ============================================================
-- Migration: Initial round_players table
-- Existed before migration tracking began.
-- IDEMPOTENT — safe to run on a fresh database.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.round_players (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    round_id    uuid NOT NULL REFERENCES public.rounds(id) ON DELETE CASCADE,
    player_id   uuid NOT NULL REFERENCES public.profiles(id),
    group_num   int NOT NULL DEFAULT 0,
    status      text NOT NULL DEFAULT 'accepted',
    invited_by  uuid REFERENCES auth.users(id),
    UNIQUE (round_id, player_id)
);

ALTER TABLE public.round_players ENABLE ROW LEVEL SECURITY;
