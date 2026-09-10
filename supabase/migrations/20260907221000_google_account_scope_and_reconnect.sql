-- Finish account-scoped Google credential management without rewriting the
-- already-applied connection-management migration.

ALTER TABLE public.google_oauth_credentials
    DROP CONSTRAINT IF EXISTS google_oauth_credentials_school_id_google_account_email_key;
ALTER TABLE public.google_oauth_credentials
    DROP CONSTRAINT IF EXISTS google_oauth_credentials_school_director_account_key;
ALTER TABLE public.google_oauth_credentials
    ADD CONSTRAINT google_oauth_credentials_school_director_account_key
    UNIQUE (school_id, director_id, google_account_email);

CREATE OR REPLACE FUNCTION public.activate_google_oauth_credential(input_credential_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    credential_record public.google_oauth_credentials%ROWTYPE;
    resumed_count INTEGER := 0;
    was_revoked BOOLEAN := FALSE;
BEGIN
    SELECT * INTO credential_record
    FROM public.google_oauth_credentials
    WHERE id = input_credential_id;

    IF actor IS NULL
       OR credential_record.id IS NULL
       OR credential_record.director_id <> actor
       OR credential_record.status NOT IN ('connected', 'revoked')
       OR credential_record.refresh_token_ciphertext IS NULL
       OR credential_record.refresh_token_iv IS NULL
       OR NOT public.has_school_role(credential_record.school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only the connected school director can activate this Google account';
    END IF;

    was_revoked := credential_record.status = 'revoked';

    UPDATE public.google_oauth_credentials
    SET is_selected = FALSE
    WHERE school_id = credential_record.school_id
      AND director_id = actor
      AND id <> credential_record.id
      AND is_selected;
    UPDATE public.google_oauth_credentials
    SET status = 'connected', is_selected = TRUE, last_error = NULL, updated_at = NOW()
    WHERE id = credential_record.id;

    UPDATE public.google_form_connections
    SET status = 'connected', last_error = NULL, updated_at = NOW()
    WHERE credential_id = credential_record.id
      AND status = 'paused'
      AND last_error = 'Google account disconnected. Reconnect it to resume syncing.';
    GET DIAGNOSTICS resumed_count = ROW_COUNT;

    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id, metadata
    ) VALUES (
        credential_record.school_id, actor,
        CASE WHEN was_revoked THEN 'google_account_reconnected' ELSE 'google_account_connected' END,
        'google_oauth_credential', credential_record.id,
        jsonb_build_object('resumed_form_count', resumed_count)
    );
    RETURN resumed_count;
END;
$$;

REVOKE ALL ON FUNCTION public.activate_google_oauth_credential(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.activate_google_oauth_credential(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260907221000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
