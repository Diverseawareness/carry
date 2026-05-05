-- Migration: invite pre-fill metadata
--
-- Lets the commissioner pre-fill name + handicap (and existing invited_phone)
-- when adding a member to a Skins Group, so the invitee's onboarding screens
-- can show "you're set up as Mike Chen / HC 12 — looks right?" instead of
-- asking them to type their own name.
--
-- New columns on group_members:
--   invited_name       — display name the commissioner entered
--   invited_handicap   — handicap the commissioner entered
--   invite_token       — random per-row UUID; embedded in the invite URL so
--                        the invitee app can look up THIS specific pending
--                        invite (not just the group) and pull pre-fill data
--
-- All three are optional/nullable — existing invite flows keep working
-- without the metadata. When an invitee signs up:
--   - invite_token in URL → server returns invited_name/_handicap/_phone
--   - app pre-fills onboarding screens 02 (phone) + 03 (profile)
--   - on profile creation, those values copy into profiles.display_name /
--     profiles.handicap if the user accepts (taps "Looks right")
--   - existing reverse_phone_invite_at_insert trigger then reconciles the
--     group_members row from invited_* placeholder to the new profile

ALTER TABLE public.group_members
    ADD COLUMN IF NOT EXISTS invited_name text,
    ADD COLUMN IF NOT EXISTS invited_handicap double precision,
    ADD COLUMN IF NOT EXISTS invite_token uuid DEFAULT gen_random_uuid();

-- Backfill tokens for existing invited rows so older pending invites can
-- still be linked. Only touches rows missing a token.
UPDATE public.group_members
SET invite_token = gen_random_uuid()
WHERE invite_token IS NULL;

-- Index for fast token lookup from the invitee onboarding flow.
CREATE UNIQUE INDEX IF NOT EXISTS idx_group_members_invite_token
    ON public.group_members(invite_token)
    WHERE invite_token IS NOT NULL;

COMMENT ON COLUMN public.group_members.invited_name IS
    'Display name the commissioner pre-filled. Copies into profiles.display_name on accept.';
COMMENT ON COLUMN public.group_members.invited_handicap IS
    'Handicap the commissioner pre-filled. Copies into profiles.handicap on accept.';
COMMENT ON COLUMN public.group_members.invite_token IS
    'Random per-row token embedded in invite URL; resolves to this specific pending invite.';
