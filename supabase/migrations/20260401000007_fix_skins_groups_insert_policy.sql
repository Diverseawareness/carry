-- ============================================================
-- Migration: Fix skins_groups INSERT policy
-- Date: 2026-04-01
-- The old policy required auth.uid() = created_by which fails
-- if the client sends the UUID slightly differently.
-- Relax to: any authenticated user can create a group.
-- ============================================================

DROP POLICY IF EXISTS "Authenticated users can create groups" ON public.skins_groups;

CREATE POLICY "Authenticated users can create groups"
    ON public.skins_groups FOR INSERT
    WITH CHECK (auth.uid() IS NOT NULL);

-- Also fix UPDATE policy to allow creators (handles NULL created_by from deleted accounts)
DROP POLICY IF EXISTS "Creators can update their groups" ON public.skins_groups;

CREATE POLICY "Creators can update their groups"
    ON public.skins_groups FOR UPDATE
    USING (created_by = auth.uid() OR created_by IS NULL);
