-- Migration: Push notification triggers for group_members and rounds
-- Uses pg_net to call the send-push-notification edge function

-- Enable pg_net extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA net;

-- Trigger function: calls the edge function with the record as JSON payload
CREATE OR REPLACE FUNCTION public.notify_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _url text;
    _payload jsonb;
    _anon_key text;
BEGIN
    -- Build the edge function URL
    _url := rtrim(current_setting('app.settings.supabase_url', true), '/')
             || '/functions/v1/send-push-notification';

    -- Fallback: use environment variable if app.settings not set
    IF _url IS NULL OR _url = '' OR _url = '/functions/v1/send-push-notification' THEN
        _url := 'https://seeitehizboxjbnccnyd.supabase.co/functions/v1/send-push-notification';
    END IF;

    _anon_key := current_setting('app.settings.supabase_anon_key', true);
    IF _anon_key IS NULL OR _anon_key = '' THEN
        _anon_key := coalesce(current_setting('supabase.anon_key', true), '');
    END IF;

    _payload := jsonb_build_object(
        'type', TG_OP,
        'table', TG_TABLE_NAME,
        'record', to_jsonb(NEW),
        'old_record', CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END
    );

    -- Skip push for guest profiles (no device_token)
    -- The edge function handles this gracefully, but we can save the call
    IF TG_TABLE_NAME = 'group_members' AND NEW.status = 'invited' THEN
        -- Check if invited player is a guest (no device_token → skip)
        PERFORM 1 FROM profiles
        WHERE id = NEW.player_id AND is_guest = true;
        IF FOUND THEN
            RETURN NEW;
        END IF;
    END IF;

    -- Fire and forget via pg_net
    PERFORM net.http_post(
        url := _url,
        body := _payload,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || _anon_key
        )
    );

    RETURN NEW;
END;
$$;

-- Trigger on group_members: fires on INSERT (invite) and UPDATE (accept/decline/scorer change)
DROP TRIGGER IF EXISTS on_group_member_change ON public.group_members;
CREATE TRIGGER on_group_member_change
    AFTER INSERT OR UPDATE ON public.group_members
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_push();

-- Trigger on rounds: fires on INSERT (round started) and UPDATE (round completed, scorer changed)
DROP TRIGGER IF EXISTS on_round_change ON public.rounds;
CREATE TRIGGER on_round_change
    AFTER INSERT OR UPDATE ON public.rounds
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_push();

-- Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';
