-- Grant missing table permissions for group_members and skins_groups.
-- These were never granted in any prior migration, causing PostgREST
-- schema cache issues on fresh database instances (e.g. dev branch).
GRANT SELECT, INSERT, UPDATE, DELETE ON public.skins_groups TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.group_members TO authenticated;
