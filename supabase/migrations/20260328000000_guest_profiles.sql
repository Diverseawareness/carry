-- Guest profiles for Quick Game flow
-- Allows creating lightweight player profiles without auth accounts

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS is_guest BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES profiles(id);

CREATE INDEX IF NOT EXISTS idx_profiles_created_by ON profiles(created_by);
CREATE INDEX IF NOT EXISTS idx_profiles_is_guest ON profiles(is_guest) WHERE is_guest = true;

-- RPC function to batch-create guest profiles (SECURITY DEFINER bypasses RLS)
CREATE OR REPLACE FUNCTION create_guest_profiles(
  p_names text[],
  p_initials text[],
  p_handicaps double precision[],
  p_colors text[],
  p_creator_id uuid DEFAULT NULL
) RETURNS uuid[] LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  result uuid[] := '{}';
  new_id uuid;
  i int;
BEGIN
  FOR i IN 1..array_length(p_names, 1) LOOP
    new_id := gen_random_uuid();
    INSERT INTO profiles (id, display_name, initials, color, avatar,
      handicap, is_guest, created_by, created_at, updated_at)
    VALUES (
      new_id,
      p_names[i],
      p_initials[i],
      p_colors[i],
      '🏌️',
      coalesce(p_handicaps[i], 0.0),
      true,
      p_creator_id,
      now(),
      now()
    );
    result := result || new_id;
  END LOOP;
  RETURN result;
END; $$;

-- Allow guest profiles to be read by authenticated users
-- (existing RLS on profiles should already allow this, but ensure)

NOTIFY pgrst, 'reload schema';
