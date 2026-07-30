-- Run once in the hosted Supabase SQL editor after deploying the Edge Function.
-- Create Vault secrets named `firefly_project_url` and
-- `firefly_outbox_worker_secret` before running this file.

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = 'firefly_project_url')
       OR NOT EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = 'firefly_outbox_worker_secret') THEN
        RAISE EXCEPTION 'Create firefly_project_url and firefly_outbox_worker_secret in Vault first';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.invoke_notification_outbox_worker()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    project_url TEXT;
    worker_secret TEXT;
BEGIN
    SELECT decrypted_secret INTO project_url
    FROM vault.decrypted_secrets WHERE name = 'firefly_project_url';
    SELECT decrypted_secret INTO worker_secret
    FROM vault.decrypted_secrets WHERE name = 'firefly_outbox_worker_secret';

    PERFORM net.http_post(
        url := project_url || '/functions/v1/process-notification-outbox',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-outbox-worker-secret', worker_secret
        ),
        body := jsonb_build_object('source', 'notification_outbox', 'queued_at', NOW())
    );
    RETURN NULL;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Could not invoke notification outbox worker: %', SQLERRM;
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.invoke_notification_outbox_worker() FROM PUBLIC, authenticated;

DROP TRIGGER IF EXISTS invoke_notification_outbox_worker_trigger ON public.notification_outbox;
CREATE TRIGGER invoke_notification_outbox_worker_trigger
AFTER INSERT ON public.notification_outbox
FOR EACH STATEMENT EXECUTE FUNCTION public.invoke_notification_outbox_worker();

DO $$
DECLARE
    existing_job BIGINT;
BEGIN
    SELECT jobid INTO existing_job
    FROM cron.job
    WHERE jobname = 'firefly-notification-outbox-recovery';
    IF existing_job IS NOT NULL THEN PERFORM cron.unschedule(existing_job); END IF;
END;
$$;

SELECT cron.schedule(
    'firefly-notification-outbox-recovery',
    '* * * * *',
    $$
    SELECT net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'firefly_project_url')
            || '/functions/v1/process-notification-outbox',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-outbox-worker-secret',
            (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'firefly_outbox_worker_secret')
        ),
        body := jsonb_build_object('source', 'cron_recovery', 'invoked_at', NOW())
    );
    $$
);
