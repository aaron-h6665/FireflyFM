-- Make director-owned Google credentials manageable without exposing OAuth
-- material to the client. Disconnecting pauses linked Forms and preserves all
-- previously imported school records.

ALTER TABLE public.google_oauth_credentials
    ALTER COLUMN refresh_token_ciphertext DROP NOT NULL,
    ALTER COLUMN refresh_token_iv DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS is_selected BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.google_form_connections
    DROP CONSTRAINT IF EXISTS google_form_connections_status_check;
ALTER TABLE public.google_form_connections
    ADD CONSTRAINT google_form_connections_status_check
    CHECK (status IN ('connected', 'syncing', 'error', 'paused', 'disconnected'));

WITH ranked AS (
    SELECT id,
           row_number() OVER (
               PARTITION BY school_id, director_id
               ORDER BY updated_at DESC, created_at DESC, id
           ) AS position
    FROM public.google_oauth_credentials
    WHERE status = 'connected'
)
UPDATE public.google_oauth_credentials credential
SET is_selected = ranked.position = 1
FROM ranked
WHERE credential.id = ranked.id;

CREATE UNIQUE INDEX IF NOT EXISTS idx_google_oauth_credentials_selected
    ON public.google_oauth_credentials(school_id, director_id)
    WHERE is_selected;

CREATE OR REPLACE FUNCTION public.select_google_oauth_credential(input_credential_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    credential_record public.google_oauth_credentials%ROWTYPE;
BEGIN
    SELECT * INTO credential_record
    FROM public.google_oauth_credentials
    WHERE id = input_credential_id;

    IF actor IS NULL
       OR credential_record.id IS NULL
       OR credential_record.director_id <> actor
       OR NOT public.has_school_role(credential_record.school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only the connected school director can select this Google account';
    END IF;
    IF credential_record.status <> 'connected' THEN
        RAISE EXCEPTION 'Reconnect this Google account before selecting it';
    END IF;

    UPDATE public.google_oauth_credentials
    SET is_selected = FALSE
    WHERE school_id = credential_record.school_id
      AND director_id = actor
      AND is_selected;
    UPDATE public.google_oauth_credentials
    SET is_selected = TRUE, updated_at = NOW()
    WHERE id = input_credential_id;

    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id
    ) VALUES (
        credential_record.school_id, actor, 'google_account_selected',
        'google_oauth_credential', credential_record.id
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.activate_google_oauth_credential(input_credential_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    credential_record public.google_oauth_credentials%ROWTYPE;
    resumed_count INTEGER := 0;
BEGIN
    SELECT * INTO credential_record
    FROM public.google_oauth_credentials
    WHERE id = input_credential_id;

    IF actor IS NULL
       OR credential_record.id IS NULL
       OR credential_record.director_id <> actor
       OR credential_record.status <> 'connected'
       OR credential_record.refresh_token_ciphertext IS NULL
       OR credential_record.refresh_token_iv IS NULL
       OR NOT public.has_school_role(credential_record.school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only the connected school director can activate this Google account';
    END IF;

    UPDATE public.google_oauth_credentials
    SET is_selected = FALSE
    WHERE school_id = credential_record.school_id
      AND director_id = actor
      AND id <> credential_record.id
      AND is_selected;
    UPDATE public.google_oauth_credentials
    SET is_selected = TRUE, last_error = NULL, updated_at = NOW()
    WHERE id = credential_record.id;

    UPDATE public.google_form_connections
    SET status = 'connected', last_error = NULL, updated_at = NOW()
    WHERE credential_id = credential_record.id
      AND status = 'paused';
    GET DIAGNOSTICS resumed_count = ROW_COUNT;

    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id, metadata
    ) VALUES (
        credential_record.school_id, actor, 'google_account_connected',
        'google_oauth_credential', credential_record.id,
        jsonb_build_object('resumed_form_count', resumed_count)
    );
    RETURN resumed_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.disconnect_google_oauth_credential(input_credential_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    credential_record public.google_oauth_credentials%ROWTYPE;
    paused_count INTEGER := 0;
BEGIN
    SELECT * INTO credential_record
    FROM public.google_oauth_credentials
    WHERE id = input_credential_id;

    IF actor IS NULL
       OR credential_record.id IS NULL
       OR credential_record.director_id <> actor
       OR NOT public.has_school_role(credential_record.school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only the connected school director can disconnect this Google account';
    END IF;

    UPDATE public.google_form_connections
    SET status = 'paused',
        last_error = 'Google account disconnected. Reconnect it to resume syncing.',
        updated_at = NOW()
    WHERE credential_id = credential_record.id
      AND status IN ('connected', 'syncing', 'error');
    GET DIAGNOSTICS paused_count = ROW_COUNT;

    UPDATE public.google_oauth_credentials
    SET refresh_token_ciphertext = NULL,
        refresh_token_iv = NULL,
        status = 'revoked',
        is_selected = FALSE,
        last_error = NULL,
        updated_at = NOW()
    WHERE id = credential_record.id;

    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id, metadata
    ) VALUES (
        credential_record.school_id, actor, 'google_account_disconnected',
        'google_oauth_credential', credential_record.id,
        jsonb_build_object('paused_form_count', paused_count)
    );
    RETURN paused_count;
END;
$$;

REVOKE ALL ON FUNCTION public.select_google_oauth_credential(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.activate_google_oauth_credential(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.disconnect_google_oauth_credential(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.select_google_oauth_credential(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.activate_google_oauth_credential(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.disconnect_google_oauth_credential(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260907220000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
