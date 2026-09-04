-- Parent onboarding form connection and import provenance.
-- OAuth tokens are intentionally not stored here; only a backend secret reference is kept.

ALTER TABLE IF EXISTS public.child_medical_profiles
    RENAME COLUMN sleep_habits TO medicine_requirements;

CREATE TABLE IF NOT EXISTS public.google_form_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    form_role TEXT NOT NULL DEFAULT 'parent' CHECK (form_role = 'parent'),
    form_id TEXT NOT NULL,
    form_url TEXT NOT NULL,
    form_title TEXT,
    google_account_email TEXT,
    credential_secret_ref TEXT,
    status TEXT NOT NULL DEFAULT 'connected'
        CHECK (status IN ('connected', 'syncing', 'error', 'disconnected')),
    last_synced_at TIMESTAMPTZ,
    next_sync_after TIMESTAMPTZ,
    last_error TEXT,
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (school_id, form_role)
);

CREATE TABLE IF NOT EXISTS public.google_form_question_mappings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id UUID NOT NULL REFERENCES public.google_form_connections(id) ON DELETE CASCADE,
    question_id TEXT NOT NULL,
    question_title TEXT NOT NULL,
    field_key TEXT NOT NULL,
    required BOOLEAN NOT NULL DEFAULT FALSE,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (connection_id, question_id),
    UNIQUE (connection_id, field_key)
);

CREATE TABLE IF NOT EXISTS public.google_form_imports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id UUID NOT NULL REFERENCES public.google_form_connections(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    google_response_id TEXT NOT NULL,
    response_created_at TIMESTAMPTZ,
    response_submitted_at TIMESTAMPTZ,
    respondent_email TEXT,
    child_id UUID REFERENCES public.children(id) ON DELETE RESTRICT,
    submitted_payload JSONB NOT NULL DEFAULT '{}'::JSONB CHECK (jsonb_typeof(submitted_payload) = 'object'),
    status TEXT NOT NULL DEFAULT 'pending_review'
        CHECK (status IN ('pending_review', 'approved', 'changes_requested', 'rejected', 'ambiguous', 'error')),
    review_note TEXT,
    reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (connection_id, google_response_id)
);

CREATE TABLE IF NOT EXISTS public.google_form_import_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    import_id UUID NOT NULL REFERENCES public.google_form_imports(id) ON DELETE CASCADE,
    question_id TEXT NOT NULL,
    google_file_id TEXT NOT NULL,
    file_name TEXT NOT NULL,
    content_type TEXT,
    private_file_path TEXT,
    document_type TEXT NOT NULL DEFAULT 'other',
    child_document_id UUID REFERENCES public.child_documents(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (import_id, google_file_id)
);

CREATE INDEX IF NOT EXISTS idx_google_form_imports_review
    ON public.google_form_imports(school_id, status, created_at DESC);

ALTER TABLE public.google_form_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.google_form_question_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.google_form_imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.google_form_import_attachments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Directors manage parent form connections" ON public.google_form_connections;
CREATE POLICY "Directors manage parent form connections"
    ON public.google_form_connections FOR ALL
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['school_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director']));

DROP POLICY IF EXISTS "Directors manage form mappings" ON public.google_form_question_mappings;
CREATE POLICY "Directors manage form mappings"
    ON public.google_form_question_mappings FOR ALL
    USING (EXISTS (
        SELECT 1 FROM public.google_form_connections c
        WHERE c.id = connection_id AND public.has_school_role(c.school_id, auth.uid(), ARRAY['school_director'])
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.google_form_connections c
        WHERE c.id = connection_id AND public.has_school_role(c.school_id, auth.uid(), ARRAY['school_director'])
    ));

DROP POLICY IF EXISTS "Authorized users view form imports" ON public.google_form_imports;
CREATE POLICY "Authorized users view form imports"
    ON public.google_form_imports FOR SELECT
    USING (
        public.has_school_role(school_id, auth.uid(), ARRAY['school_director'])
        OR (child_id IS NOT NULL AND public.can_access_child(child_id, auth.uid()))
    );

DROP POLICY IF EXISTS "Directors review form imports" ON public.google_form_imports;
CREATE POLICY "Directors review form imports"
    ON public.google_form_imports FOR UPDATE
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['school_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director']));

DROP POLICY IF EXISTS "Authorized users view form attachments" ON public.google_form_import_attachments;
CREATE POLICY "Authorized users view form attachments"
    ON public.google_form_import_attachments FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.google_form_imports i
        WHERE i.id = import_id
          AND (public.has_school_role(i.school_id, auth.uid(), ARRAY['school_director'])
               OR (i.child_id IS NOT NULL AND public.can_access_child(i.child_id, auth.uid())))
    ));

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
        school_id, form_id, form_url, form_title, google_account_email,
        credential_secret_ref, created_by, status, updated_at
    ) VALUES (
        input_school_id, btrim(input_form_id), btrim(input_form_url),
        NULLIF(btrim(input_form_title), ''), NULLIF(lower(btrim(input_google_account_email)), ''),
        NULLIF(btrim(input_credential_secret_ref), ''), actor, 'connected', NOW()
    )
    ON CONFLICT (school_id, form_role) DO UPDATE SET
        form_id = EXCLUDED.form_id, form_url = EXCLUDED.form_url,
        form_title = EXCLUDED.form_title, google_account_email = EXCLUDED.google_account_email,
        credential_secret_ref = COALESCE(EXCLUDED.credential_secret_ref, google_form_connections.credential_secret_ref),
        status = 'connected', last_error = NULL, updated_at = NOW()
    RETURNING * INTO saved;
    RETURN NEXT saved;
END;
$$;

CREATE OR REPLACE FUNCTION public.disconnect_parent_google_form(input_school_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT public.has_school_role(input_school_id, auth.uid(), ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can remove a parent Google Form';
    END IF;
    UPDATE public.google_form_connections
    SET status = 'disconnected', credential_secret_ref = NULL, updated_at = NOW()
    WHERE school_id = input_school_id AND form_role = 'parent';
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_parent_google_form_connection(UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.disconnect_parent_google_form(UUID) TO authenticated;
