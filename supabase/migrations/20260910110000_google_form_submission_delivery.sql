-- Make Google Form delivery visible immediately to active onboarding members,
-- prevent duplicate launches while a response is being collected, and keep the
-- recipient status consistent across parent and teacher onboarding.

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
     AND connection.status = 'connected'
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
    LEFT JOIN public.google_form_connections connection ON connection.id = binding.connection_id AND connection.status = 'connected'
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

CREATE OR REPLACE FUNCTION public.begin_google_form_submission(input_connection_id UUID)
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
    bound_requirement_id UUID;
    bound_position INTEGER;
    joiner TEXT;
    query_key TEXT;
BEGIN
    SELECT * INTO connection FROM public.google_form_connections WHERE id = input_connection_id AND status = 'connected';
    IF NOT FOUND THEN RAISE EXCEPTION 'This Form is not available'; END IF;
    SELECT * INTO membership FROM public.school_memberships
    WHERE school_id = connection.school_id AND user_id = actor AND active = TRUE AND role = connection.form_role
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'This Form is not assigned to your role'; END IF;
    IF EXISTS (
        SELECT 1 FROM public.google_form_submission_sessions session
        WHERE session.connection_id = connection.id
          AND session.membership_id = membership.id
          AND session.consumed_at IS NULL
          AND session.expires_at > NOW()
    ) THEN
        RAISE EXCEPTION 'FireflyFM is already checking this Form response';
    END IF;
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

REVOKE ALL ON FUNCTION public.fetch_my_google_form_steps(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fetch_my_parent_onboarding_timeline(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.begin_google_form_submission(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fetch_my_google_form_steps(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_parent_onboarding_timeline(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.begin_google_form_submission(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.notify_google_form_import_reviewers()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE notification_uuid UUID;
BEGIN
    IF NEW.status NOT IN ('pending_review', 'ambiguous', 'error') THEN RETURN NEW; END IF;
    INSERT INTO public.notifications (
        school_id, title, body, category, source_type, source_id, created_by, dedupe_key
    ) VALUES (
        NEW.school_id,
        CASE WHEN NEW.status = 'pending_review'
             THEN 'New onboarding Form response' ELSE 'Form response needs attention' END,
        CASE WHEN NEW.status = 'pending_review'
             THEN 'An onboarding Form response is ready for review.'
             ELSE 'An onboarding Form response needs routing review.' END,
        'google_form_response', 'google_form_import', NEW.id, NEW.submitted_by,
        'google-form:review:' || NEW.id::TEXT
    )
    ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL
    DO UPDATE SET title = EXCLUDED.title, body = EXCLUDED.body,
                  created_by = COALESCE(EXCLUDED.created_by, notifications.created_by)
    RETURNING id INTO notification_uuid;

    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT notification_uuid, membership.user_id
    FROM public.school_memberships membership
    WHERE membership.school_id = NEW.school_id
      AND membership.role = 'school_director'
      AND membership.active = TRUE
      AND membership.access_state = 'full'
    ON CONFLICT DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_google_form_import_reviewers ON public.google_form_imports;
CREATE TRIGGER notify_google_form_import_reviewers
AFTER INSERT OR UPDATE OF status, submission_session_id ON public.google_form_imports
FOR EACH ROW EXECUTE FUNCTION public.notify_google_form_import_reviewers();

REVOKE ALL ON FUNCTION public.notify_google_form_import_reviewers() FROM PUBLIC, anon, authenticated;

-- Backfill the director inbox for responses already imported before inbox
-- delivery was added. The dedupe key makes this safe alongside function-level
-- retries and preserves any existing read state.
WITH review_notifications AS (
    INSERT INTO public.notifications (
        school_id, title, body, category, source_type, source_id, created_by, dedupe_key
    )
    SELECT form_import.school_id,
           CASE WHEN form_import.status = 'pending_review'
                THEN 'New onboarding Form response'
                ELSE 'Form response needs attention' END,
           CASE WHEN form_import.status = 'pending_review'
                THEN 'An onboarding Form response is ready for review.'
                ELSE 'An onboarding Form response needs routing review.' END,
           'google_form_response', 'google_form_import', form_import.id,
           form_import.submitted_by, 'google-form:review:' || form_import.id::TEXT
    FROM public.google_form_imports form_import
    WHERE form_import.status IN ('pending_review', 'ambiguous', 'error')
    ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL
    DO UPDATE SET dedupe_key = EXCLUDED.dedupe_key
    RETURNING id, school_id
)
INSERT INTO public.notification_recipients (notification_id, user_id)
SELECT notification.id, membership.user_id
FROM review_notifications notification
JOIN public.school_memberships membership
  ON membership.school_id = notification.school_id
 AND membership.role = 'school_director'
 AND membership.active = TRUE
 AND membership.access_state = 'full'
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260910110000::BIGINT; $$;
