-- Adds `self_initiated` flag to push-notification trigger payload so the edge
-- function can suppress the "You're Invited!" push when the user just scanned
-- their own way in (their device fired the INSERT, then iOS would show them a
-- push telling them they were invited to a group they actively joined).

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
    _self_initiated boolean;
BEGIN
    _url := rtrim(current_setting('app.settings.supabase_url', true), '/')
             || '/functions/v1/send-push-notification';

    IF _url IS NULL OR _url = '' OR _url = '/functions/v1/send-push-notification' THEN
        _url := 'https://seeitehizboxjbnccnyd.supabase.co/functions/v1/send-push-notification';
    END IF;

    _anon_key := current_setting('app.settings.supabase_anon_key', true);
    IF _anon_key IS NULL OR _anon_key = '' THEN
        _anon_key := coalesce(current_setting('supabase.anon_key', true), '');
    END IF;

    _self_initiated := (
        TG_TABLE_NAME = 'group_members'
        AND auth.uid() IS NOT NULL
        AND NEW.player_id = auth.uid()
    );

    _payload := jsonb_build_object(
        'type', TG_OP,
        'table', TG_TABLE_NAME,
        'record', to_jsonb(NEW),
        'old_record', CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END,
        'self_initiated', _self_initiated
    );

    IF TG_TABLE_NAME = 'group_members' AND NEW.status = 'invited' THEN
        PERFORM 1 FROM profiles
        WHERE id = NEW.player_id AND is_guest = true;
        IF FOUND THEN
            RETURN NEW;
        END IF;
    END IF;

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

NOTIFY pgrst, 'reload schema';
