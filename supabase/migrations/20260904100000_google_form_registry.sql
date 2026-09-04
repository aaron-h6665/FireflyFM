-- Make Google Form connections extensible without exposing a dense configuration UI.

ALTER TABLE public.google_form_connections
    ADD COLUMN IF NOT EXISTS form_key TEXT NOT NULL DEFAULT 'parent_intake',
    ADD COLUMN IF NOT EXISTS is_required BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS display_order INTEGER NOT NULL DEFAULT 0;

ALTER TABLE public.google_form_connections
    DROP CONSTRAINT IF EXISTS google_form_connections_form_role_check;

ALTER TABLE public.google_form_connections
    ADD CONSTRAINT google_form_connections_form_role_check
    CHECK (form_role IN ('parent', 'teacher'));

ALTER TABLE public.google_form_connections
    DROP CONSTRAINT IF EXISTS google_form_connections_school_id_form_role_key;

CREATE UNIQUE INDEX IF NOT EXISTS google_form_connections_school_role_key
    ON public.google_form_connections (school_id, form_role, form_key);

CREATE INDEX IF NOT EXISTS idx_google_form_connections_order
    ON public.google_form_connections (school_id, form_role, display_order);

CREATE OR REPLACE FUNCTION public.upsert_parent_google_form_connection(
    input_school_id UUID,
    input_form_id TEXT,
    input_form_url TEXT,
    input_form_title TEXT DEFAULT NULL,
    input_google_account_email TEXT DEFAULT NULL,
    input_credential_secret_ref TEXT DEFAULT NULL
)
RETURNS SETOF public.google_form_connections
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE actor UUID := auth.uid(); saved public.google_form_connections%ROWTYPE;
BEGIN
    IF actor IS NULL OR NOT public.has_school_role(input_school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can connect a parent Google Form';
    END IF;
    IF NULLIF(btrim(input_form_id), '') IS NULL OR input_form_url !~* '^https://docs\.google\.com/forms/' THEN
        RAISE EXCEPTION 'A valid Google Forms URL and form ID are required';
    END IF;
    INSERT INTO public.google_form_connections (
        school_id, form_role, form_key, form_id, form_url, form_title,
        google_account_email, credential_secret_ref, created_by, status, is_required, display_order, updated_at
    ) VALUES (
        input_school_id, 'parent', 'parent_intake', btrim(input_form_id), btrim(input_form_url),
        NULLIF(btrim(input_form_title), ''), NULLIF(lower(btrim(input_google_account_email)), ''),
        NULLIF(btrim(input_credential_secret_ref), ''), actor, 'connected', TRUE, 0, NOW()
    )
    ON CONFLICT (school_id, form_role, form_key) DO UPDATE SET
        form_id = EXCLUDED.form_id, form_url = EXCLUDED.form_url,
        form_title = EXCLUDED.form_title, google_account_email = EXCLUDED.google_account_email,
        credential_secret_ref = COALESCE(EXCLUDED.credential_secret_ref, google_form_connections.credential_secret_ref),
        status = 'connected', last_error = NULL, updated_at = NOW()
    RETURNING * INTO saved;
    RETURN NEXT saved;
END;
$$;
