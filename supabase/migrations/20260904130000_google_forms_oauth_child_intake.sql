-- Director-owned Google Forms onboarding.  Google tokens and OAuth state are
-- backend-only; a Form response is evidence, never an active child record.

CREATE TABLE IF NOT EXISTS public.google_oauth_credentials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    director_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    google_account_email TEXT NOT NULL,
    refresh_token_ciphertext TEXT NOT NULL,
    refresh_token_iv TEXT NOT NULL,
    granted_scopes TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    status TEXT NOT NULL DEFAULT 'connected'
        CHECK (status IN ('connected', 'needs_reconnect', 'revoked')),
    last_error TEXT,
    last_used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (school_id, google_account_email)
);

CREATE TABLE IF NOT EXISTS public.google_oauth_operations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    director_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    state_hash TEXT NOT NULL UNIQUE,
    pkce_verifier_ciphertext TEXT NOT NULL,
    pkce_verifier_iv TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.google_oauth_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.google_oauth_operations ENABLE ROW LEVEL SECURITY;
-- Deliberately no policies: only Edge Functions using service_role may read
-- OAuth material or PKCE operations.

ALTER TABLE public.google_form_connections
    ADD COLUMN IF NOT EXISTS credential_id UUID REFERENCES public.google_oauth_credentials(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS form_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB;

ALTER TABLE public.google_form_question_mappings
    ADD COLUMN IF NOT EXISTS prefill_parameter TEXT;

ALTER TABLE public.google_form_imports
    ADD COLUMN IF NOT EXISTS submitted_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS membership_id UUID REFERENCES public.school_memberships(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS submission_session_id UUID,
    ADD COLUMN IF NOT EXISTS child_connection_request_id UUID,
    ADD COLUMN IF NOT EXISTS parent_import_id UUID REFERENCES public.google_form_imports(id) ON DELETE SET NULL;

ALTER TABLE public.child_connection_requests
    ADD COLUMN IF NOT EXISTS source_google_form_import_id UUID REFERENCES public.google_form_imports(id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_child_connection_request_google_import
    ON public.child_connection_requests(source_google_form_import_id)
    WHERE source_google_form_import_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.google_form_submission_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id UUID NOT NULL REFERENCES public.google_form_connections(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    membership_id UUID NOT NULL REFERENCES public.school_memberships(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    connection_snapshot JSONB NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    import_id UUID REFERENCES public.google_form_imports(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_google_form_submission_sessions_lookup
    ON public.google_form_submission_sessions(connection_id, user_id, expires_at DESC);

ALTER TABLE public.google_form_submission_sessions ENABLE ROW LEVEL SECURITY;
-- Sessions contain a one-time reference and mapping snapshot.  They are only
-- returned by the launch RPC, never selectable from the client.

ALTER TABLE public.google_form_imports
    ADD CONSTRAINT google_form_imports_submission_session_fk
    FOREIGN KEY (submission_session_id) REFERENCES public.google_form_submission_sessions(id) ON DELETE SET NULL;
ALTER TABLE public.google_form_imports
    ADD CONSTRAINT google_form_imports_connection_request_fk
    FOREIGN KEY (child_connection_request_id) REFERENCES public.child_connection_requests(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.google_form_requirement_bindings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id UUID NOT NULL REFERENCES public.google_form_connections(id) ON DELETE CASCADE,
    onboarding_template_requirement_id UUID NOT NULL REFERENCES public.onboarding_template_requirements(id) ON DELETE RESTRICT,
    published_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (connection_id)
);

CREATE TABLE IF NOT EXISTS public.google_form_requirement_evidence (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    import_id UUID NOT NULL REFERENCES public.google_form_imports(id) ON DELETE RESTRICT,
    requirement_instance_id UUID NOT NULL REFERENCES public.onboarding_requirement_instances(id) ON DELETE RESTRICT,
    approved_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    approved_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (import_id, requirement_instance_id),
    UNIQUE (requirement_instance_id)
);

ALTER TABLE public.google_form_requirement_bindings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.google_form_requirement_evidence ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Directors manage Google Form requirement bindings" ON public.google_form_requirement_bindings;
CREATE POLICY "Directors manage Google Form requirement bindings"
    ON public.google_form_requirement_bindings FOR ALL
    USING (EXISTS (
        SELECT 1 FROM public.google_form_connections connection
        WHERE connection.id = connection_id
          AND public.has_school_role(connection.school_id, auth.uid(), ARRAY['school_director'])
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.google_form_connections connection
        WHERE connection.id = connection_id
          AND public.has_school_role(connection.school_id, auth.uid(), ARRAY['school_director'])
    ));

DROP POLICY IF EXISTS "Users view own Google Form evidence" ON public.google_form_requirement_evidence;
CREATE POLICY "Users view own Google Form evidence"
    ON public.google_form_requirement_evidence FOR SELECT
    USING (EXISTS (
        SELECT 1
        FROM public.google_form_imports form_import
        WHERE form_import.id = import_id
          AND (form_import.submitted_by = auth.uid()
               OR public.has_school_role(form_import.school_id, auth.uid(), ARRAY['school_director']))
    ));

-- A parent can see only their own response while it is awaiting review.  The
-- old policy exposed a response only once it was attached to a child, which
-- made the awaiting-review state impossible to project safely.
DROP POLICY IF EXISTS "Authorized users view form imports" ON public.google_form_imports;
CREATE POLICY "Authorized users view form imports"
    ON public.google_form_imports FOR SELECT
    USING (
        public.has_school_role(school_id, auth.uid(), ARRAY['school_director'])
        OR submitted_by = auth.uid()
        OR (child_id IS NOT NULL AND public.can_access_child(child_id, auth.uid()))
    );

DROP POLICY IF EXISTS "Authorized users view form attachments" ON public.google_form_import_attachments;
CREATE POLICY "Authorized users view form attachments"
    ON public.google_form_import_attachments FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.google_form_imports form_import
        WHERE form_import.id = import_id
          AND (public.has_school_role(form_import.school_id, auth.uid(), ARRAY['school_director'])
               OR form_import.submitted_by = auth.uid()
               OR (form_import.child_id IS NOT NULL AND public.can_access_child(form_import.child_id, auth.uid())))
    ));

CREATE OR REPLACE FUNCTION public.google_form_scalar_answer(input_payload JSONB, input_question_id TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE value JSONB;
BEGIN
    value := input_payload -> input_question_id;
    IF jsonb_typeof(value) = 'string' THEN RETURN NULLIF(btrim(value #>> '{}'), ''); END IF;
    IF jsonb_typeof(value) = 'number' OR jsonb_typeof(value) = 'boolean' THEN RETURN value #>> '{}'; END IF;
    IF jsonb_typeof(value) = 'array' THEN RETURN NULLIF(btrim(value ->> 0), ''); END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_google_form_connection_v2(
    input_school_id UUID,
    input_credential_id UUID,
    input_form_role TEXT,
    input_form_key TEXT,
    input_form_id TEXT,
    input_form_url TEXT,
    input_form_title TEXT,
    input_google_account_email TEXT,
    input_is_required BOOLEAN,
    input_display_order INTEGER,
    input_form_snapshot JSONB,
    input_mappings JSONB,
    input_template_requirement_id UUID DEFAULT NULL
)
RETURNS SETOF public.google_form_connections
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    saved public.google_form_connections%ROWTYPE;
    mapping JSONB;
    required_field TEXT;
    credential_school UUID;
BEGIN
    IF actor IS NULL OR NOT public.has_school_role(input_school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can connect an onboarding Google Form';
    END IF;
    IF input_form_role NOT IN ('parent', 'teacher') OR NULLIF(btrim(input_form_id), '') IS NULL
       OR input_form_url !~* '^https://docs\\.google\\.com/forms/' THEN
        RAISE EXCEPTION 'A valid authorized Google Form is required';
    END IF;
    SELECT school_id INTO credential_school FROM public.google_oauth_credentials
    WHERE id = input_credential_id AND status = 'connected';
    IF credential_school IS DISTINCT FROM input_school_id THEN
        RAISE EXCEPTION 'The selected Google account is not connected to this school';
    END IF;
    IF jsonb_typeof(input_mappings) <> 'array' THEN RAISE EXCEPTION 'Form mappings are required'; END IF;

    IF input_form_role = 'parent' THEN
        FOREACH required_field IN ARRAY ARRAY[
            'child_first_name', 'child_last_name', 'child_birthdate', 'relationship',
            'respondent_email', 'submission_reference'
        ] LOOP
            IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(input_mappings) item
                           WHERE item ->> 'field_key' = required_field
                             AND COALESCE((item ->> 'active')::BOOLEAN, TRUE)) THEN
                RAISE EXCEPTION 'Parent intake must map %', replace(required_field, '_', ' ');
            END IF;
        END LOOP;
    END IF;

    INSERT INTO public.google_form_connections (
        school_id, credential_id, form_role, form_key, form_id, form_url, form_title,
        google_account_email, credential_secret_ref, created_by, status, is_required,
        display_order, form_snapshot, updated_at
    ) VALUES (
        input_school_id, input_credential_id, input_form_role,
        COALESCE(NULLIF(btrim(input_form_key), ''), input_form_id), btrim(input_form_id),
        btrim(input_form_url), NULLIF(btrim(input_form_title), ''),
        NULLIF(lower(btrim(input_google_account_email)), ''), NULL, actor, 'connected',
        COALESCE(input_is_required, TRUE), GREATEST(COALESCE(input_display_order, 0), 0),
        COALESCE(input_form_snapshot, '{}'::JSONB), NOW()
    ) ON CONFLICT (school_id, form_role, form_key) DO UPDATE SET
        credential_id = EXCLUDED.credential_id, form_id = EXCLUDED.form_id,
        form_url = EXCLUDED.form_url, form_title = EXCLUDED.form_title,
        google_account_email = EXCLUDED.google_account_email, credential_secret_ref = NULL,
        status = 'connected', is_required = EXCLUDED.is_required,
        display_order = EXCLUDED.display_order, form_snapshot = EXCLUDED.form_snapshot,
        last_error = NULL, updated_at = NOW()
    RETURNING * INTO saved;

    DELETE FROM public.google_form_question_mappings WHERE connection_id = saved.id;
    FOR mapping IN SELECT value FROM jsonb_array_elements(input_mappings) LOOP
        IF NULLIF(btrim(mapping ->> 'question_id'), '') IS NULL
           OR NULLIF(btrim(mapping ->> 'field_key'), '') IS NULL THEN
            RAISE EXCEPTION 'Each mapping needs a question and field key';
        END IF;
        INSERT INTO public.google_form_question_mappings (
            connection_id, question_id, question_title, field_key, required, active, prefill_parameter, updated_at
        ) VALUES (
            saved.id, btrim(mapping ->> 'question_id'), COALESCE(NULLIF(btrim(mapping ->> 'question_title'), ''), btrim(mapping ->> 'question_id')),
            btrim(mapping ->> 'field_key'), COALESCE((mapping ->> 'required')::BOOLEAN, FALSE),
            COALESCE((mapping ->> 'active')::BOOLEAN, TRUE), NULLIF(btrim(mapping ->> 'prefill_parameter'), ''), NOW()
        );
    END LOOP;

    IF input_template_requirement_id IS NULL THEN
        DELETE FROM public.google_form_requirement_bindings WHERE connection_id = saved.id;
    ELSE
        IF NOT EXISTS (
            SELECT 1 FROM public.onboarding_template_requirements requirement
            JOIN public.onboarding_templates template ON template.id = requirement.template_id
            WHERE requirement.id = input_template_requirement_id
              AND template.school_id = input_school_id AND template.target_role = input_form_role
        ) THEN RAISE EXCEPTION 'The selected onboarding requirement does not belong to this form role'; END IF;
        INSERT INTO public.google_form_requirement_bindings (
            connection_id, onboarding_template_requirement_id, published_snapshot, updated_at
        ) VALUES (saved.id, input_template_requirement_id,
                  jsonb_build_object('form', COALESCE(input_form_snapshot, '{}'::JSONB), 'mappings', input_mappings), NOW())
        ON CONFLICT (connection_id) DO UPDATE SET
            onboarding_template_requirement_id = EXCLUDED.onboarding_template_requirement_id,
            published_snapshot = EXCLUDED.published_snapshot, updated_at = NOW();
    END IF;
    RETURN NEXT saved;
END;
$$;

CREATE OR REPLACE FUNCTION public.fetch_my_google_form_steps(input_school_id UUID)
RETURNS TABLE (
    connection_id UUID, form_title TEXT, form_url TEXT, form_role TEXT, is_required BOOLEAN,
    display_order INTEGER, submission_status TEXT, review_note TEXT, submitted_at TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT connection.id, connection.form_title, connection.form_url, connection.form_role,
           connection.is_required, connection.display_order, form_import.status,
           form_import.review_note, form_import.response_submitted_at
    FROM public.school_memberships membership
    JOIN public.google_form_connections connection
      ON connection.school_id = membership.school_id
     AND connection.form_role = membership.role
     AND connection.status = 'connected'
    LEFT JOIN LATERAL (
        SELECT * FROM public.google_form_imports response
        WHERE response.connection_id = connection.id
          AND response.submitted_by = membership.user_id
        ORDER BY response.response_submitted_at DESC NULLS LAST, response.created_at DESC
        LIMIT 1
    ) form_import ON TRUE
    WHERE membership.school_id = input_school_id
      AND membership.user_id = auth.uid()
      AND membership.active = TRUE
      AND membership.role IN ('parent', 'teacher')
    ORDER BY connection.display_order, connection.created_at;
$$;

CREATE OR REPLACE FUNCTION public.begin_google_form_submission(input_connection_id UUID)
RETURNS TABLE (connection_id UUID, launch_url TEXT, expires_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    connection public.google_form_connections%ROWTYPE;
    membership public.school_memberships%ROWTYPE;
    reference_mapping public.google_form_question_mappings%ROWTYPE;
    raw_token TEXT := replace(gen_random_uuid()::TEXT, '-', '') || replace(gen_random_uuid()::TEXT, '-', '');
    snapshot JSONB;
    joiner TEXT;
    query_key TEXT;
BEGIN
    SELECT * INTO connection FROM public.google_form_connections WHERE id = input_connection_id AND status = 'connected';
    IF NOT FOUND THEN RAISE EXCEPTION 'This form is no longer available'; END IF;
    SELECT * INTO membership FROM public.school_memberships
    WHERE school_id = connection.school_id AND user_id = actor AND active = TRUE AND role = connection.form_role;
    IF NOT FOUND THEN RAISE EXCEPTION 'This form is not assigned to your role'; END IF;
    SELECT * INTO reference_mapping FROM public.google_form_question_mappings
    WHERE connection_id = connection.id AND field_key = 'submission_reference' AND active = TRUE;
    IF NOT FOUND THEN RAISE EXCEPTION 'This Form needs a submission-reference mapping before it can be sent'; END IF;

    SELECT jsonb_build_object('form_url', connection.form_url, 'form_role', connection.form_role,
        'mappings', COALESCE(jsonb_agg(jsonb_build_object(
            'question_id', mapping.question_id, 'question_title', mapping.question_title,
            'field_key', mapping.field_key, 'required', mapping.required, 'active', mapping.active,
            'prefill_parameter', mapping.prefill_parameter
        )), '[]'::JSONB))
    INTO snapshot
    FROM public.google_form_question_mappings mapping WHERE mapping.connection_id = connection.id;

    INSERT INTO public.google_form_submission_sessions (
        connection_id, school_id, membership_id, user_id, token_hash, connection_snapshot, expires_at
    ) VALUES (
        connection.id, connection.school_id, membership.id, actor, encode(digest(raw_token, 'sha256'), 'hex'),
        snapshot, NOW() + INTERVAL '2 hours'
    );
    joiner := CASE WHEN position('?' IN connection.form_url) > 0 THEN '&' ELSE '?' END;
    query_key := COALESCE(NULLIF(reference_mapping.prefill_parameter, ''), 'entry.' || reference_mapping.question_id);
    RETURN QUERY SELECT connection.id,
        connection.form_url || joiner || 'usp=pp_url&' || query_key || '=' || raw_token,
        NOW() + INTERVAL '2 hours';
END;
$$;

-- Called after a service-role sync inserts the immutable raw import.  It
-- reconciles the short-lived reference to the member, then creates exactly one
-- pending child request for parent intake.  No child is created here.
CREATE OR REPLACE FUNCTION public.ingest_google_form_import(input_import_id UUID)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    form_import public.google_form_imports%ROWTYPE;
    connection public.google_form_connections%ROWTYPE;
    reference_mapping public.google_form_question_mappings%ROWTYPE;
    session_record public.google_form_submission_sessions%ROWTYPE;
    first_name TEXT;
    last_name TEXT;
    birthdate_text TEXT;
    relationship_text TEXT;
    responder_email TEXT;
    request_id UUID;
    answer_token TEXT;
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role' THEN RAISE EXCEPTION 'Only the Google Forms synchronizer may import responses'; END IF;
    SELECT * INTO form_import FROM public.google_form_imports WHERE id = input_import_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Google Form import not found'; END IF;
    IF form_import.submission_session_id IS NOT NULL THEN RETURN form_import.child_connection_request_id; END IF;
    SELECT * INTO connection FROM public.google_form_connections WHERE id = form_import.connection_id;
    SELECT * INTO reference_mapping FROM public.google_form_question_mappings
    WHERE connection_id = connection.id AND field_key = 'submission_reference' AND active = TRUE;
    answer_token := public.google_form_scalar_answer(form_import.submitted_payload, reference_mapping.question_id);
    SELECT * INTO session_record FROM public.google_form_submission_sessions
    WHERE connection_id = connection.id AND token_hash = encode(digest(COALESCE(answer_token, ''), 'sha256'), 'hex')
    FOR UPDATE;
    IF NOT FOUND OR session_record.expires_at < NOW() OR session_record.consumed_at IS NOT NULL THEN
        UPDATE public.google_form_imports
        SET status = 'ambiguous', error_message = 'The Form submission reference was missing, expired, or already used.', updated_at = NOW()
        WHERE id = form_import.id;
        RETURN NULL;
    END IF;
    UPDATE public.google_form_submission_sessions SET consumed_at = NOW(), import_id = form_import.id WHERE id = session_record.id;
    UPDATE public.google_form_imports SET submitted_by = session_record.user_id, membership_id = session_record.membership_id,
        submission_session_id = session_record.id, status = 'pending_review', error_message = NULL, updated_at = NOW()
    WHERE id = form_import.id;

    IF connection.form_role <> 'parent' THEN RETURN NULL; END IF;
    SELECT public.google_form_scalar_answer(form_import.submitted_payload, question_id) INTO first_name
    FROM public.google_form_question_mappings WHERE connection_id = connection.id AND field_key = 'child_first_name' AND active = TRUE;
    SELECT public.google_form_scalar_answer(form_import.submitted_payload, question_id) INTO last_name
    FROM public.google_form_question_mappings WHERE connection_id = connection.id AND field_key = 'child_last_name' AND active = TRUE;
    SELECT public.google_form_scalar_answer(form_import.submitted_payload, question_id) INTO birthdate_text
    FROM public.google_form_question_mappings WHERE connection_id = connection.id AND field_key = 'child_birthdate' AND active = TRUE;
    SELECT public.google_form_scalar_answer(form_import.submitted_payload, question_id) INTO relationship_text
    FROM public.google_form_question_mappings WHERE connection_id = connection.id AND field_key = 'relationship' AND active = TRUE;
    SELECT public.google_form_scalar_answer(form_import.submitted_payload, question_id) INTO responder_email
    FROM public.google_form_question_mappings WHERE connection_id = connection.id AND field_key = 'respondent_email' AND active = TRUE;
    IF first_name IS NULL OR last_name IS NULL OR relationship_text IS NULL
       OR birthdate_text !~ '^\\d{4}-\\d{2}-\\d{2}$' THEN
        UPDATE public.google_form_imports SET status = 'ambiguous', respondent_email = responder_email,
            error_message = 'The required child-intake fields are incomplete or invalid.', updated_at = NOW()
        WHERE id = form_import.id;
        RETURN NULL;
    END IF;
    INSERT INTO public.child_connection_requests (
        school_id, requested_by, legal_first_name, legal_last_name, birthdate, relationship,
        idempotency_key, source_google_form_import_id
    ) VALUES (
        connection.school_id, session_record.user_id, first_name, last_name, birthdate_text::DATE,
        relationship_text, 'google-form:' || form_import.id::TEXT, form_import.id
    ) ON CONFLICT (source_google_form_import_id) WHERE source_google_form_import_id IS NOT NULL
    DO UPDATE SET updated_at = NOW()
    RETURNING id INTO request_id;
    UPDATE public.google_form_imports
    SET respondent_email = responder_email, child_connection_request_id = request_id, updated_at = NOW()
    WHERE id = form_import.id;
    RETURN request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_google_form_child_intake(
    input_import_id UUID,
    input_decision TEXT,
    input_matched_child_id UUID DEFAULT NULL,
    input_review_note TEXT DEFAULT NULL
)
RETURNS TABLE (import_id UUID, child_id UUID, access_state TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    form_import public.google_form_imports%ROWTYPE;
    connection public.google_form_connections%ROWTYPE;
    request_record public.child_connection_requests%ROWTYPE;
    child_uuid UUID;
    binding public.google_form_requirement_bindings%ROWTYPE;
    requirement_instance UUID;
    mapping_record public.google_form_question_mappings%ROWTYPE;
    value_text TEXT;
    resulting_access TEXT;
BEGIN
    SELECT * INTO form_import FROM public.google_form_imports WHERE id = input_import_id FOR UPDATE;
    IF NOT FOUND OR NOT public.has_school_role(form_import.school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can review this Form response';
    END IF;
    IF input_decision NOT IN ('approved', 'rejected', 'changes_requested') THEN RAISE EXCEPTION 'Unknown review decision'; END IF;
    IF input_decision <> 'approved' AND NULLIF(btrim(COALESCE(input_review_note, '')), '') IS NULL THEN
        RAISE EXCEPTION 'A note is required when requesting changes or rejecting a Form response';
    END IF;
    IF form_import.status = 'approved' THEN
        RETURN QUERY SELECT form_import.id, form_import.child_id,
            (SELECT membership.access_state FROM public.school_memberships membership WHERE membership.id = form_import.membership_id);
        RETURN;
    END IF;
    SELECT * INTO connection FROM public.google_form_connections WHERE id = form_import.connection_id;

    IF input_decision <> 'approved' THEN
        UPDATE public.google_form_imports SET status = input_decision, review_note = btrim(input_review_note),
            reviewed_by = actor, reviewed_at = NOW(), updated_at = NOW() WHERE id = form_import.id;
        IF form_import.child_connection_request_id IS NOT NULL AND input_decision = 'rejected' THEN
            UPDATE public.child_connection_requests SET status = 'rejected', review_note = btrim(input_review_note),
                reviewed_by = actor, reviewed_at = NOW(), updated_at = NOW() WHERE id = form_import.child_connection_request_id;
        END IF;
        RETURN QUERY SELECT form_import.id, NULL::UUID,
            (SELECT membership.access_state FROM public.school_memberships membership WHERE membership.id = form_import.membership_id);
        RETURN;
    END IF;

    IF connection.form_role = 'parent' THEN
        SELECT * INTO request_record FROM public.child_connection_requests WHERE id = form_import.child_connection_request_id FOR UPDATE;
        IF NOT FOUND OR request_record.status <> 'pending' THEN RAISE EXCEPTION 'A pending child connection is required before approval'; END IF;
        IF input_matched_child_id IS NOT NULL THEN
            SELECT child.id INTO child_uuid FROM public.children child
            WHERE child.id = input_matched_child_id AND child.school_id = form_import.school_id AND child.active = TRUE;
            IF child_uuid IS NULL THEN RAISE EXCEPTION 'The selected child is not active at this school'; END IF;
        ELSE
            INSERT INTO public.children (school_id, first_name, last_name, birthdate, active)
            VALUES (form_import.school_id, request_record.legal_first_name, request_record.legal_last_name, request_record.birthdate, TRUE)
            RETURNING id INTO child_uuid;
        END IF;
        INSERT INTO public.child_guardians (child_id, guardian_id, relationship, verification_status, verified_by, verified_at, ended_at)
        VALUES (child_uuid, request_record.requested_by, request_record.relationship, 'verified', actor, NOW(), NULL)
        ON CONFLICT (child_id, guardian_id) DO UPDATE SET relationship = EXCLUDED.relationship,
            verification_status = 'verified', verified_by = actor, verified_at = NOW(), ended_at = NULL;
        PERFORM public.instantiate_child_onboarding(child_uuid, request_record.requested_by);

        -- Mapped health text is intentionally stored as notes.  Emergency contacts remain
        -- reviewable text rather than guessed structured people/phone records.
        INSERT INTO public.child_medical_profiles (
            child_id, allergies, immunization_status, physical_status, medicine_requirements,
            dietary_notes, emergency_notes, updated_by, updated_at
        ) VALUES (
            child_uuid,
            (SELECT public.google_form_scalar_answer(form_import.submitted_payload, question_id) FROM public.google_form_question_mappings WHERE connection_id = connection.id AND field_key = 'allergies' AND active = TRUE),
            (SELECT public.google_form_scalar_answer(form_import.submitted_payload, question_id) FROM public.google_form_question_mappings WHERE connection_id = connection.id AND field_key = 'immunization_status' AND active = TRUE),
            (SELECT public.google_form_scalar_answer(form_import.submitted_payload, question_id) FROM public.google_form_question_mappings WHERE connection_id = connection.id AND field_key = 'physical_status' AND active = TRUE),
            (SELECT public.google_form_scalar_answer(form_import.submitted_payload, question_id) FROM public.google_form_question_mappings WHERE connection_id = connection.id AND field_key = 'medicine_requirements' AND active = TRUE),
            (SELECT public.google_form_scalar_answer(form_import.submitted_payload, question_id) FROM public.google_form_question_mappings WHERE connection_id = connection.id AND field_key = 'dietary_notes' AND active = TRUE),
            (SELECT public.google_form_scalar_answer(form_import.submitted_payload, question_id) FROM public.google_form_question_mappings WHERE connection_id = connection.id AND field_key = 'emergency_contacts' AND active = TRUE),
            actor, NOW()
        ) ON CONFLICT (child_id) DO UPDATE SET
            allergies = COALESCE(EXCLUDED.allergies, child_medical_profiles.allergies),
            immunization_status = COALESCE(EXCLUDED.immunization_status, child_medical_profiles.immunization_status),
            physical_status = COALESCE(EXCLUDED.physical_status, child_medical_profiles.physical_status),
            medicine_requirements = COALESCE(EXCLUDED.medicine_requirements, child_medical_profiles.medicine_requirements),
            dietary_notes = COALESCE(EXCLUDED.dietary_notes, child_medical_profiles.dietary_notes),
            emergency_notes = COALESCE(EXCLUDED.emergency_notes, child_medical_profiles.emergency_notes),
            updated_by = actor, updated_at = NOW();

        INSERT INTO public.child_documents (school_id, child_id, title, document_type, file_name, file_path, uploaded_by, verification_status, reviewed_by, reviewed_at)
        SELECT form_import.school_id, child_uuid, attachment.file_name, attachment.document_type, attachment.file_name,
               attachment.private_file_path, form_import.submitted_by, 'verified', actor, NOW()
        FROM public.google_form_import_attachments attachment
        WHERE attachment.import_id = form_import.id AND attachment.private_file_path IS NOT NULL
        ON CONFLICT DO NOTHING;
        UPDATE public.google_form_import_attachments attachment
        SET child_document_id = document.id
        FROM public.child_documents document
        WHERE attachment.import_id = form_import.id AND document.child_id = child_uuid
          AND document.file_path = attachment.private_file_path AND attachment.child_document_id IS NULL;

        UPDATE public.child_connection_requests SET status = 'approved', matched_child_id = child_uuid,
            reviewed_by = actor, reviewed_at = NOW(), review_note = NULLIF(btrim(COALESCE(input_review_note, '')), ''), updated_at = NOW()
        WHERE id = request_record.id;
    END IF;

    SELECT * INTO binding FROM public.google_form_requirement_bindings WHERE connection_id = connection.id;
    IF FOUND AND form_import.membership_id IS NOT NULL THEN
        SELECT requirement.id INTO requirement_instance
        FROM public.onboarding_requirement_instances requirement
        WHERE requirement.onboarding_instance_id IN (
            SELECT id FROM public.onboarding_instances WHERE membership_id = form_import.membership_id
        ) AND requirement.template_requirement_id = binding.onboarding_template_requirement_id
          AND ((child_uuid IS NULL AND requirement.child_id IS NULL) OR requirement.child_id = child_uuid)
        ORDER BY CASE WHEN requirement.child_id IS NULL THEN 0 ELSE 1 END DESC
        LIMIT 1;
        IF requirement_instance IS NOT NULL THEN
            UPDATE public.onboarding_requirement_instances SET status = 'approved', completed_at = COALESCE(completed_at, NOW())
            WHERE id = requirement_instance;
            INSERT INTO public.google_form_requirement_evidence (import_id, requirement_instance_id, approved_by)
            VALUES (form_import.id, requirement_instance, actor) ON CONFLICT DO NOTHING;
        END IF;
    END IF;

    UPDATE public.google_form_imports SET status = 'approved', child_id = child_uuid,
        review_note = NULLIF(btrim(COALESCE(input_review_note, '')), ''), reviewed_by = actor, reviewed_at = NOW(), updated_at = NOW()
    WHERE id = form_import.id;
    IF form_import.membership_id IS NOT NULL THEN resulting_access := public.refresh_onboarding_access(form_import.membership_id); END IF;
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id, metadata)
    VALUES (form_import.school_id, actor, 'approved', 'google_form_import', form_import.id,
        jsonb_build_object('child_id', child_uuid, 'connection_id', connection.id));
    RETURN QUERY SELECT form_import.id, child_uuid, resulting_access;
END;
$$;

-- Private Form uploads remain quarantined until the import is approved and a
-- child has been linked.  Directors retain review access through table APIs.
DROP POLICY IF EXISTS "Approved Google Form uploads are visible to child users" ON storage.objects;
CREATE POLICY "Approved Google Form uploads are visible to child users"
    ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'school_private_files'
        AND EXISTS (
            SELECT 1 FROM public.google_form_import_attachments attachment
            JOIN public.google_form_imports form_import ON form_import.id = attachment.import_id
            WHERE attachment.private_file_path = name
              AND form_import.status = 'approved'
              AND form_import.child_id IS NOT NULL
              AND public.can_access_child(form_import.child_id, auth.uid())
        )
    );

REVOKE ALL ON FUNCTION public.ingest_google_form_import(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ingest_google_form_import(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.upsert_google_form_connection_v2(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, INTEGER, JSONB, JSONB, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_google_form_steps(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.begin_google_form_submission(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_google_form_child_intake(UUID, TEXT, UUID, TEXT) TO authenticated;
