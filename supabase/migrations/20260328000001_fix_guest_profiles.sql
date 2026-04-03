-- Fix: profiles.id has FK to auth.users(id), blocking guest profile creation.
-- Solution: Drop the FK constraint so guest profiles can exist without auth accounts.
-- Guest profiles are identified by is_guest=true and created_by UUID.

-- Find and drop the FK constraint on profiles.id → auth.users.id
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_id_fkey;

-- Recreate the RPC with the constraint removed (same function, no change needed)
-- The original create_guest_profiles function will now work since the FK is gone.

NOTIFY pgrst, 'reload schema';
