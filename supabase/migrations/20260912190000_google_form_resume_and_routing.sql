-- Restore recipient reopening, correct Google API hexadecimal question IDs,
-- and keep Forms visible during worker activity and recoverable sync errors.
CREATE OR REPLACE FUNCTION public.google_form_prefill_parameter(question_id TEXT, configured TEXT DEFAULT NULL)
RETURNS TEXT LANGUAGE plpgsql IMMUTABLE SET search_path = public AS $$
BEGIN
    IF NULLIF(btrim(configured), '') IS NOT NULL THEN RETURN configured; END IF;
    IF question_id ~ '^[0-9a-fA-F]{1,8}$' THEN
        RETURN 'entry.' || (('x' || lpad(question_id, 8, '0'))::bit(32)::bigint)::TEXT;
    END IF;
    RAISE EXCEPTION 'The Form routing field needs to be reconnected';
END;
$$;
REVOKE ALL ON FUNCTION public.google_form_prefill_parameter(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.google_form_prefill_parameter(TEXT, TEXT) TO authenticated, service_role;

UPDATE public.google_form_question_mappings
SET prefill_parameter = public.google_form_prefill_parameter(question_id, NULL), updated_at = NOW()
WHERE field_key = 'submission_reference' AND question_id ~ '^[0-9a-fA-F]{1,8}$'
  AND (NULLIF(btrim(prefill_parameter), '') IS NULL OR prefill_parameter = 'entry.' || question_id);

CREATE OR REPLACE FUNCTION public.fetch_my_google_form_steps(input_school_id UUID)
RETURNS TABLE (
    connection_id UUID, form_title TEXT, form_url TEXT, form_role TEXT, is_required BOOLEAN,
    display_order INTEGER, submission_status TEXT, review_note TEXT, submitted_at TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT connection.id, connection.form_title, connection.form_url, connection.form_role,
           connection.is_required, connection.display_order, latest.status,
           latest.review_note, latest.submitted_at
    FROM public.school_memberships membership
    JOIN public.google_form_connections connection
      ON connection.school_id = membership.school_id
     AND connection.form_role = membership.role
     AND connection.status IN ('connected', 'syncing', 'error')
    LEFT JOIN LATERAL (
        SELECT event.status, event.review_note, event.submitted_at
        FROM (
            SELECT response.status, response.review_note,
                   response.response_submitted_at AS submitted_at,
                   COALESCE(response.response_submitted_at, response.created_at) AS event_at
            FROM public.google_form_imports response
            WHERE response.connection_id = connection.id
              AND response.membership_id = membership.id
            UNION ALL
            SELECT 'awaiting_sync'::TEXT, NULL::TEXT, NULL::TIMESTAMPTZ, session.created_at
            FROM public.google_form_submission_sessions session
            WHERE session.connection_id = connection.id
              AND session.membership_id = membership.id
              AND session.consumed_at IS NULL
              AND session.expires_at > NOW()
        ) event
        ORDER BY event.event_at DESC
        LIMIT 1
    ) latest ON TRUE
    WHERE membership.school_id = input_school_id
      AND membership.user_id = auth.uid()
      AND membership.active = TRUE
      AND membership.role IN ('parent', 'teacher')
    ORDER BY connection.display_order, connection.created_at;
$$;

CREATE OR REPLACE FUNCTION public.fetch_my_parent_onboarding_timeline(input_school_id UUID)
RETURNS TABLE (
    requirement_instance_id UUID, step_position INTEGER, title TEXT, requirement_type TEXT, status TEXT,
    step_kind TEXT, connection_id UUID, form_title TEXT, form_submission_status TEXT, form_review_note TEXT,
    zelle_invoice_id UUID, zelle_invoice_status TEXT, zelle_amount_due_cents BIGINT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT instance_requirement.id, requirement.position AS step_position, requirement.title, requirement.requirement_type,
           instance_requirement.status,
           CASE WHEN connection.id IS NOT NULL THEN 'form'
                WHEN requirement.requirement_type = 'payment' THEN 'payment' ELSE 'paperwork' END,
           connection.id, connection.form_title, latest.status, latest.review_note,
           invoice.id, invoice.status, invoice.amount_due_cents
    FROM public.onboarding_instances instance
    JOIN public.school_memberships membership ON membership.id = instance.membership_id
    JOIN public.onboarding_requirement_instances instance_requirement ON instance_requirement.onboarding_instance_id = instance.id
    JOIN public.onboarding_template_requirements requirement
      ON requirement.id = instance_requirement.template_requirement_id
     AND requirement.template_id = instance.template_id
    LEFT JOIN public.google_form_requirement_bindings binding ON binding.onboarding_template_requirement_id = requirement.id
    LEFT JOIN public.google_form_connections connection ON connection.id = binding.connection_id AND connection.status IN ('connected', 'syncing', 'error')
    LEFT JOIN LATERAL (
        SELECT event.status, event.review_note
        FROM (
            SELECT response.status, response.review_note,
                   COALESCE(response.response_submitted_at, response.created_at) AS event_at
            FROM public.google_form_imports response
            WHERE response.connection_id = connection.id
              AND response.membership_id = membership.id
            UNION ALL
            SELECT 'awaiting_sync'::TEXT, NULL::TEXT, session.created_at
            FROM public.google_form_submission_sessions session
            WHERE session.connection_id = connection.id
              AND session.membership_id = membership.id
              AND session.consumed_at IS NULL
              AND session.expires_at > NOW()
        ) event
        ORDER BY event.event_at DESC
        LIMIT 1
    ) latest ON TRUE
    LEFT JOIN public.zelle_invoices invoice ON invoice.onboarding_requirement_instance_id = instance_requirement.id
    WHERE membership.user_id = auth.uid() AND membership.school_id = input_school_id
      AND membership.role = 'parent' AND membership.active AND instance.status IN ('in_progress', 'complete')
    ORDER BY requirement.position, instance_requirement.created_at;
$$;

CREATE OR REPLACE FUNCTION public.resume_google_form_submission(input_connection_id UUID, input_resume_token TEXT DEFAULT NULL)
RETURNS TABLE (connection_id UUID, launch_url TEXT, expires_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE
    actor UUID := auth.uid();
    connection public.google_form_connections%ROWTYPE;
    membership public.school_memberships%ROWTYPE;
    reference_mapping public.google_form_question_mappings%ROWTYPE;
    raw_token TEXT := replace(gen_random_uuid()::TEXT, '-', '') || replace(gen_random_uuid()::TEXT, '-', '');
    snapshot JSONB;
    session_record public.google_form_submission_sessions%ROWTYPE;
    deadline TIMESTAMPTZ := NOW() + INTERVAL '2 hours';
    bound_requirement_id UUID;
    bound_position INTEGER;
    joiner TEXT;
    query_key TEXT;
BEGIN
    SELECT * INTO connection FROM public.google_form_connections WHERE id = input_connection_id AND status IN ('connected', 'syncing', 'error');
    IF NOT FOUND THEN RAISE EXCEPTION 'This Form is not available'; END IF;
    SELECT * INTO membership FROM public.school_memberships
    WHERE school_id = connection.school_id AND user_id = actor AND active = TRUE AND role = connection.form_role
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'This Form is not assigned to your role'; END IF;
    SELECT onboarding_template_requirement_id INTO bound_requirement_id
    FROM public.google_form_requirement_bindings binding
    WHERE binding.connection_id = connection.id;
    SELECT position INTO bound_position FROM public.onboarding_template_requirements WHERE id = bound_requirement_id;
    IF bound_requirement_id IS NULL OR bound_position IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.onboarding_requirement_instances requirement_instance
        JOIN public.onboarding_instances instance ON instance.id = requirement_instance.onboarding_instance_id
        WHERE instance.membership_id = membership.id
          AND requirement_instance.template_requirement_id = bound_requirement_id
    ) THEN
        RAISE EXCEPTION 'This Form is not assigned to your onboarding timeline';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.onboarding_requirement_instances earlier_instance
        JOIN public.onboarding_instances instance ON instance.id = earlier_instance.onboarding_instance_id
        JOIN public.onboarding_template_requirements earlier_requirement
          ON earlier_requirement.id = earlier_instance.template_requirement_id
        WHERE instance.membership_id = membership.id
          AND earlier_requirement.position < bound_position
          AND earlier_instance.status NOT IN ('approved', 'waived')
    ) THEN
        RAISE EXCEPTION 'Complete the earlier onboarding step first';
    END IF;
    SELECT * INTO reference_mapping FROM public.google_form_question_mappings mapping
    WHERE mapping.connection_id = connection.id
      AND mapping.field_key = 'submission_reference'
      AND mapping.active = TRUE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reconnect Google to finish setup'; END IF;

    SELECT jsonb_build_object('form_url', connection.form_url, 'form_role', connection.form_role,
        'requirement_id', bound_requirement_id,
        'mappings', COALESCE(jsonb_agg(jsonb_build_object(
            'question_id', mapping.question_id, 'question_title', mapping.question_title,
            'field_key', mapping.field_key, 'required', mapping.required, 'active', mapping.active,
            'prefill_parameter', mapping.prefill_parameter
        )), '[]'::JSONB))
    INTO snapshot
    FROM public.google_form_question_mappings mapping WHERE mapping.connection_id = connection.id;

    -- A raw reference is held only in the recipient's device Keychain. Resume
    -- only after membership/assignment checks and an exact hash match.
    SELECT * INTO session_record FROM public.google_form_submission_sessions s
    WHERE s.connection_id = connection.id AND s.membership_id = membership.id
      AND s.user_id = actor AND s.consumed_at IS NULL AND s.expires_at > NOW()
      AND s.token_hash = encode(digest(input_resume_token, 'sha256'), 'hex')
    ORDER BY s.created_at DESC LIMIT 1;
    IF FOUND THEN
        raw_token := input_resume_token;
        deadline := session_record.expires_at;
    ELSE
        -- An older device may not have retained its link. Preserve old sessions
        -- so a response already submitted from them can still be matched.
        INSERT INTO public.google_form_submission_sessions (
            connection_id, school_id, membership_id, user_id, token_hash, connection_snapshot, expires_at
        ) VALUES (
            connection.id, connection.school_id, membership.id, actor, encode(digest(raw_token, 'sha256'), 'hex'),
            snapshot, deadline
        );
    END IF;
    joiner := CASE WHEN position('?' IN connection.form_url) > 0 THEN '&' ELSE '?' END;
    query_key := public.google_form_prefill_parameter(reference_mapping.question_id, reference_mapping.prefill_parameter);
    RETURN QUERY SELECT connection.id,
        connection.form_url || joiner || 'usp=pp_url&' || query_key || '=' || raw_token,
        deadline;
END;
$$;

CREATE OR REPLACE FUNCTION public.begin_google_form_submission(input_connection_id UUID)
RETURNS TABLE (connection_id UUID, launch_url TEXT, expires_at TIMESTAMPTZ)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
    SELECT * FROM public.resume_google_form_submission(input_connection_id, NULL);
$$;
REVOKE ALL ON FUNCTION public.resume_google_form_submission(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resume_google_form_submission(UUID, TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.begin_google_form_submission(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.begin_google_form_submission(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.ingest_google_form_import(input_import_id UUID)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE
    form_import public.google_form_imports%ROWTYPE;
    connection public.google_form_connections%ROWTYPE;
    session_record public.google_form_submission_sessions%ROWTYPE;
    first_name TEXT;
    last_name TEXT;
    birthdate_text TEXT;
    parsed_birthdate DATE;
    relationship_text TEXT;
    responder_email TEXT;
    request_id UUID;
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role' THEN RAISE EXCEPTION 'Only the Google Forms synchronizer may import responses'; END IF;
    SELECT * INTO form_import FROM public.google_form_imports WHERE id = input_import_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Google Form import not found'; END IF;
    IF form_import.submission_session_id IS NOT NULL THEN RETURN form_import.child_connection_request_id; END IF;
    SELECT * INTO connection FROM public.google_form_connections WHERE id = form_import.connection_id;
    SELECT submission_session.* INTO session_record
    FROM public.google_form_submission_sessions submission_session
    CROSS JOIN LATERAL jsonb_each_text(form_import.submitted_payload) answer(question_id, value)
    WHERE submission_session.connection_id = connection.id
      AND submission_session.token_hash = encode(digest(answer.value, 'sha256'), 'hex')
    ORDER BY submission_session.created_at DESC
    LIMIT 1
    FOR UPDATE OF submission_session;
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
    first_name := public.google_form_snapshot_answer(form_import.submitted_payload, session_record.connection_snapshot, 'child_first_name');
    last_name := public.google_form_snapshot_answer(form_import.submitted_payload, session_record.connection_snapshot, 'child_last_name');
    birthdate_text := public.google_form_snapshot_answer(form_import.submitted_payload, session_record.connection_snapshot, 'child_birthdate');
    relationship_text := public.google_form_snapshot_answer(form_import.submitted_payload, session_record.connection_snapshot, 'relationship');
    responder_email := public.google_form_snapshot_answer(form_import.submitted_payload, session_record.connection_snapshot, 'respondent_email');
    IF first_name IS NULL OR last_name IS NULL OR relationship_text IS NULL
       OR birthdate_text IS NULL OR birthdate_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
        UPDATE public.google_form_imports SET status = 'ambiguous', respondent_email = responder_email,
            error_message = 'The required child-intake fields are incomplete or invalid.', updated_at = NOW()
        WHERE id = form_import.id;
        RETURN NULL;
    END IF;
    BEGIN
        parsed_birthdate := birthdate_text::DATE;
    EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN
        UPDATE public.google_form_imports SET status = 'ambiguous',
            error_message = 'The child birthdate is not a valid calendar date.', updated_at = NOW()
        WHERE id = form_import.id;
        RETURN NULL;
    END;
    INSERT INTO public.child_connection_requests (
        school_id, requested_by, legal_first_name, legal_last_name, birthdate, relationship,
        idempotency_key, source_google_form_import_id
    ) VALUES (
        connection.school_id, session_record.user_id, first_name, last_name, parsed_birthdate,
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

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260912190000::BIGINT; $$;
