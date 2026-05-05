-- Helper function to reload PostgREST schema cache.
-- Called via REST API when dev branch PostgREST restarts with a stale cache.
CREATE OR REPLACE FUNCTION public.reload_pgrst_schema()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    NOTIFY pgrst, 'reload schema';
END;
$$;

GRANT EXECUTE ON FUNCTION public.reload_pgrst_schema() TO service_role;
