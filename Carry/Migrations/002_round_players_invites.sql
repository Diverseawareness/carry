-- Migration: Add invite support to round_players
-- Run this in the Supabase SQL Editor

-- Add status column: tracks whether a player accepted, is invited, or declined
ALTER TABLE round_players
ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'accepted';

-- Add invited_by column: references the user who sent the invite
ALTER TABLE round_players
ADD COLUMN IF NOT EXISTS invited_by uuid REFERENCES auth.users(id);

-- Index for fast lookup of pending invites per player
CREATE INDEX IF NOT EXISTS idx_round_players_status
ON round_players (player_id, status);

-- Update RLS: players can see invites directed at them
-- (Existing policies should already allow select on round_players
--  where player_id = auth.uid(). If not, add:)

-- Allow invited players to read their own invite rows
CREATE POLICY IF NOT EXISTS "Players can view their own round_players rows"
ON round_players FOR SELECT
USING (player_id = auth.uid());

-- Allow invited players to update their own status (accept/decline)
CREATE POLICY IF NOT EXISTS "Players can update their own invite status"
ON round_players FOR UPDATE
USING (player_id = auth.uid())
WITH CHECK (player_id = auth.uid());

-- Allow round creators to insert invites for others
CREATE POLICY IF NOT EXISTS "Round creators can invite players"
ON round_players FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM rounds
    WHERE rounds.id = round_players.round_id
    AND rounds.created_by = auth.uid()
  )
  OR player_id = auth.uid()
);
