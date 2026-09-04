-- Scope onboarding forms to the director's parent or teacher view.

CREATE OR REPLACE FUNCTION public.upsert_google_form_connection(
    input_school_id UUID,
    input_form_role TEXT,
    input_form_key TEXT,
    input_form_id TEXT,
    input_form_url TEXT,
    input_form_title TEXT DEFAULT NULL,
    input_google_account_email TEXT DEFAULT NULL,
    input_credential_secret_ref TEXT DEFAULT NULL,
    input_is_required BOOLEAN DEFAULT TRUE,
    input_display_order INTEGER DEFAULT 0
)
RETURNS SETOF public.google_form_connections
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE actor UUID := auth.uid(); saved public.google_form_connections%ROWTYPE;
BEGIN
    IF actor IS NULL OR NOT public.has_school_role(input_school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can connect an onboarding Google Form';
    END IF;
    IF input_form_role NOT IN ('parent', 'teacher') THEN
        RAISE EXCEPTION 'A valid onboarding view is required';
    END IF;
    IF NULLIF(btrim(input_form_id), '') IS NULL OR input_form_url !~* '^https://docs\.google\.com/forms/' THEN
        RAISE EXCEPTION 'A valid Google Forms URL and form ID are required';
    END IF;
    INSERT INTO public.google_form_connections (
        school_id, form_role, form_key, form_id, form_url, form_title,
        google_account_email, credential_secret_ref, created_by, status,
        is_required, display_order, updated_at
    ) VALUES (
        input_school_id, input_form_role, COALESCE(NULLIF(btrim(input_form_key), ''), input_form_id),
        btrim(input_form_id), btrim(input_form_url), NULLIF(btrim(input_form_title), ''),
        NULLIF(lower(btrim(input_google_account_email)), ''), NULLIF(btrim(input_credential_secret_ref), ''),
        actor, 'connected', COALESCE(input_is_required, TRUE), COALESCE(input_display_order, 0), NOW()
    )
    ON CONFLICT (school_id, form_role, form_key) DO UPDATE SET
        form_id = EXCLUDED.form_id, form_url = EXCLUDED.form_url, form_title = EXCLUDED.form_title,
        google_account_email = EXCLUDED.google_account_email,
        credential_secret_ref = COALESCE(EXCLUDED.credential_secret_ref, google_form_connections.credential_secret_ref),
        status = 'connected', is_required = EXCLUDED.is_required, display_order = EXCLUDED.display_order,
        last_error = NULL, updated_at = NOW()
    RETURNING * INTO saved;
    RETURN NEXT saved;
END;
$$;

CREATE OR REPLACE FUNCTION public.disconnect_google_form_connection(input_connection_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE school UUID;
BEGIN
    SELECT school_id INTO school FROM public.google_form_connections WHERE id = input_connection_id;
    IF school IS NULL OR NOT public.has_school_role(school, auth.uid(), ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can disconnect this form';
    END IF;
    UPDATE public.google_form_connections
    SET status = 'disconnected', credential_secret_ref = NULL, updated_at = NOW()
    WHERE id = input_connection_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_google_form_connection(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.disconnect_google_form_connection(UUID) TO authenticated;
