-- Allow round creators and participants to delete rounds
DO $$ BEGIN
    CREATE POLICY "Users can delete their rounds"
        ON public.rounds FOR DELETE
        USING (
            created_by = auth.uid()
            OR id IN (
                SELECT round_id FROM round_players WHERE player_id = auth.uid()
            )
        );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
