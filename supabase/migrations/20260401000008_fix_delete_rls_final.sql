-- ============================================================
-- Migration: Final fix for delete_user_account
-- Date: 2026-04-01
-- Add DELETE policies for profiles and scores tables,
-- and ensure the function owner can bypass RLS.
-- ============================================================

-- Allow users to delete their own profile
DO $$ BEGIN
    CREATE POLICY "Users can delete their own profile"
        ON public.profiles FOR DELETE
        USING (auth.uid() = id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Allow users to delete their own scores
DO $$ BEGIN
    CREATE POLICY "Users can delete their own scores"
        ON public.scores FOR DELETE
        USING (player_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Allow users to delete guest profiles they created
DO $$ BEGIN
    CREATE POLICY "Users can delete guest profiles they created"
        ON public.profiles FOR DELETE
        USING (created_by = auth.uid() AND is_guest = true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
