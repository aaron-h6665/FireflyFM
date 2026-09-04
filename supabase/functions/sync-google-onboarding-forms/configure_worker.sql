-- Run once in the hosted Supabase SQL editor after deploying
-- sync-google-onboarding-forms. Create Vault secrets named
-- firefly_project_url and firefly_google_forms_worker_secret first.

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = 'firefly_project_url')
       OR NOT EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = 'firefly_google_forms_worker_secret') THEN
        RAISE EXCEPTION 'Create firefly_project_url and firefly_google_forms_worker_secret in Vault first';
    END IF;
END;
$$;

DO $$
DECLARE existing_job BIGINT;
BEGIN
    SELECT jobid INTO existing_job FROM cron.job
    WHERE jobname = 'firefly-google-forms-onboarding-sync';
    IF existing_job IS NOT NULL THEN PERFORM cron.unschedule(existing_job); END IF;
END;
$$;

SELECT cron.schedule(
    'firefly-google-forms-onboarding-sync',
    '*/5 * * * *',
    $$
    SELECT net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'firefly_project_url')
            || '/functions/v1/sync-google-onboarding-forms',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-google-forms-worker-secret',
            (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'firefly_google_forms_worker_secret')
        ),
        body := jsonb_build_object('source', 'scheduled_google_forms_sync', 'invoked_at', NOW())
    );
    $$
);
