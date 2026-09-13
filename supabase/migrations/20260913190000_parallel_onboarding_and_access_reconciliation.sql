-- Let recipients work through every assigned setup item in parallel, keep the
-- checklist projection aligned with the assigned template, and reconcile app
-- access whenever a blocking requirement changes state.

CREATE OR REPLACE FUNCTION public.refresh_my_onboarding_access(input_school_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    membership_uuid UUID;
BEGIN
    SELECT membership.id INTO membership_uuid
    FROM public.school_memberships membership
    WHERE membership.school_id = input_school_id
      AND membership.user_id = auth.uid()
      AND membership.active = TRUE
      AND membership.role IN ('parent', 'teacher', 'school_director')
    ORDER BY membership.created_at DESC
    LIMIT 1;

    IF membership_uuid IS NULL THEN
        RAISE EXCEPTION 'No active onboarding membership was found';
    END IF;
    RETURN public.refresh_onboarding_access(membership_uuid);
END;
$$;
REVOKE ALL ON FUNCTION public.refresh_my_onboarding_access(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refresh_my_onboarding_access(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.reconcile_onboarding_access_after_requirement_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    membership_uuid UUID;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.status IS NOT DISTINCT FROM OLD.status THEN
        RETURN NEW;
    END IF;
    SELECT instance.membership_id INTO membership_uuid
    FROM public.onboarding_instances instance
    WHERE instance.id = NEW.onboarding_instance_id;
    IF membership_uuid IS NOT NULL THEN
        PERFORM public.refresh_onboarding_access(membership_uuid);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reconcile_onboarding_access_after_requirement_change
ON public.onboarding_requirement_instances;
CREATE TRIGGER reconcile_onboarding_access_after_requirement_change
AFTER UPDATE OF status ON public.onboarding_requirement_instances
FOR EACH ROW EXECUTE FUNCTION public.reconcile_onboarding_access_after_requirement_change();

-- Repair memberships that reached a completed requirement state before the
-- trigger existed but were left in the onboarding shell.
DO $$
DECLARE
    membership_record RECORD;
BEGIN
    FOR membership_record IN
        SELECT DISTINCT instance.membership_id
        FROM public.onboarding_instances instance
        JOIN public.school_memberships membership ON membership.id = instance.membership_id
        WHERE membership.active = TRUE
          AND membership.access_state = 'onboarding'
    LOOP
        PERFORM public.refresh_onboarding_access(membership_record.membership_id);
    END LOOP;
END;
$$;

-- Show Forms only when they are part of this recipient's currently assigned
-- onboarding version. Return every assigned Form, not only a sequential next.
CREATE OR REPLACE FUNCTION public.fetch_my_google_form_steps(input_school_id UUID)
RETURNS TABLE (
    connection_id UUID, form_title TEXT, form_url TEXT, form_role TEXT, is_required BOOLEAN,
    display_order INTEGER, submission_status TEXT, review_note TEXT, submitted_at TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT connection.id, connection.form_title, connection.form_url, connection.form_role,
           connection.is_required, requirement.position, latest.status,
           latest.review_note, latest.submitted_at
    FROM public.school_memberships membership
    JOIN public.onboarding_instances instance
      ON instance.membership_id = membership.id
     AND instance.status IN ('in_progress', 'complete')
    JOIN public.onboarding_requirement_instances requirement_instance
      ON requirement_instance.onboarding_instance_id = instance.id
    JOIN public.onboarding_template_requirements requirement
      ON requirement.id = requirement_instance.template_requirement_id
     AND requirement.template_id = instance.template_id
    JOIN public.google_form_requirement_bindings binding
      ON binding.onboarding_template_requirement_id = requirement.id
    JOIN public.google_form_connections connection
      ON connection.id = binding.connection_id
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
    ORDER BY requirement.position, requirement_instance.created_at;
$$;

-- Expose which ordinary dashboard rows are represented by a Google Form so
-- the client can show one card per actual setup step.
DROP FUNCTION IF EXISTS public.fetch_my_onboarding_dashboard(UUID);
CREATE FUNCTION public.fetch_my_onboarding_dashboard(input_school_id UUID)
RETURNS TABLE (
    requirement_instance_id UUID, assignment_id UUID, child_id UUID, requirement_type TEXT,
    zelle_invoice_id UUID, zelle_invoice_status TEXT, zelle_amount_due_cents BIGINT,
    google_form_connection_id UUID,
    title TEXT, description TEXT, subject_scope TEXT, "position" INTEGER, status TEXT,
    material_count BIGINT, child_first_name TEXT, child_last_name TEXT, reviewer_label TEXT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT requirement_instances.id, requirement_instances.assignment_id, requirement_instances.child_id,
        requirements.requirement_type, invoice.id, invoice.status, invoice.amount_due_cents,
        form_binding.connection_id,
        requirements.title, requirements.description, requirements.subject_scope, requirements.position,
        requirement_instances.status,
        COALESCE((SELECT COUNT(*) FROM public.assignment_materials materials WHERE materials.assignment_id = requirement_instances.assignment_id), 0),
        children.first_name, children.last_name,
        CASE templates.target_role WHEN 'school_director' THEN 'Reviewed by FireflyFM HQ' ELSE 'Reviewed by your school director' END
    FROM public.onboarding_instances instances
    JOIN public.school_memberships memberships ON memberships.id = instances.membership_id
    JOIN public.onboarding_templates templates ON templates.id = instances.template_id
    JOIN public.onboarding_requirement_instances requirement_instances ON requirement_instances.onboarding_instance_id = instances.id
    JOIN public.onboarding_template_requirements requirements
      ON requirements.id = requirement_instances.template_requirement_id
     AND requirements.template_id = instances.template_id
    LEFT JOIN public.google_form_requirement_bindings form_binding
      ON form_binding.onboarding_template_requirement_id = requirements.id
    LEFT JOIN public.zelle_invoices invoice ON invoice.onboarding_requirement_instance_id = requirement_instances.id
    LEFT JOIN public.children children ON children.id = requirement_instances.child_id
    WHERE memberships.user_id = auth.uid() AND memberships.school_id = input_school_id
      AND memberships.active = TRUE AND instances.status IN ('in_progress', 'complete')
    ORDER BY requirements.position, children.first_name, children.last_name;
$$;
REVOKE ALL ON FUNCTION public.fetch_my_onboarding_dashboard(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fetch_my_onboarding_dashboard(UUID) TO authenticated;

-- Form launch authorization remains membership- and requirement-scoped, but
-- no longer depends on the status of unrelated earlier checklist items.
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
    joiner TEXT;
    query_key TEXT;
BEGIN
    SELECT * INTO connection FROM public.google_form_connections
    WHERE id = input_connection_id AND status IN ('connected', 'syncing', 'error');
    IF NOT FOUND THEN RAISE EXCEPTION 'This Form is not available'; END IF;
    SELECT * INTO membership FROM public.school_memberships
    WHERE school_id = connection.school_id AND user_id = actor AND active = TRUE AND role = connection.form_role
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'This Form is not assigned to your role'; END IF;
    SELECT binding.onboarding_template_requirement_id INTO bound_requirement_id
    FROM public.google_form_requirement_bindings binding
    JOIN public.onboarding_template_requirements requirement
      ON requirement.id = binding.onboarding_template_requirement_id
    JOIN public.onboarding_instances instance
      ON instance.template_id = requirement.template_id
     AND instance.membership_id = membership.id
     AND instance.status IN ('in_progress', 'complete')
    JOIN public.onboarding_requirement_instances requirement_instance
      ON requirement_instance.onboarding_instance_id = instance.id
     AND requirement_instance.template_requirement_id = requirement.id
    WHERE binding.connection_id = connection.id;
    IF bound_requirement_id IS NULL THEN
        RAISE EXCEPTION 'This Form is not assigned to your onboarding checklist';
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

    SELECT * INTO session_record FROM public.google_form_submission_sessions s
    WHERE input_resume_token IS NOT NULL
      AND s.connection_id = connection.id AND s.membership_id = membership.id
      AND s.user_id = actor AND s.consumed_at IS NULL AND s.expires_at > NOW()
      AND s.token_hash = encode(digest(input_resume_token, 'sha256'), 'hex')
    ORDER BY s.created_at DESC LIMIT 1;
    IF FOUND THEN
        raw_token := input_resume_token;
        deadline := session_record.expires_at;
    ELSE
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
REVOKE ALL ON FUNCTION public.resume_google_form_submission(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resume_google_form_submission(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.begin_google_form_submission(input_connection_id UUID)
RETURNS TABLE (connection_id UUID, launch_url TEXT, expires_at TIMESTAMPTZ)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
    SELECT * FROM public.resume_google_form_submission(input_connection_id, NULL);
$$;
REVOKE ALL ON FUNCTION public.begin_google_form_submission(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.begin_google_form_submission(UUID) TO authenticated;

-- Restore the hardened payment mutation without the later sequential-step
-- regression. Named payer, invoice state, validation, idempotency, audit, and
-- reviewer notification checks remain unchanged.
CREATE OR REPLACE FUNCTION public.submit_zelle_payment(
    input_invoice_id UUID,
    input_amount_cents BIGINT,
    input_sent_at TIMESTAMPTZ,
    input_confirmation_reference TEXT,
    input_idempotency_key TEXT
)
RETURNS SETOF public.zelle_payment_submissions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    invoice_record public.zelle_invoices%ROWTYPE;
    submission_record public.zelle_payment_submissions%ROWTYPE;
BEGIN
    SELECT * INTO invoice_record FROM public.zelle_invoices WHERE id = input_invoice_id FOR UPDATE;
    IF NOT FOUND OR NOT public.zelle_is_active_payer(invoice_record.school_id, invoice_record.payer_user_id, actor) THEN
        RAISE EXCEPTION 'Only the named payer can submit this payment';
    END IF;
    SELECT * INTO submission_record FROM public.zelle_payment_submissions
    WHERE invoice_id = input_invoice_id AND payer_user_id = actor AND idempotency_key = input_idempotency_key;
    IF FOUND THEN
        RETURN QUERY SELECT * FROM public.zelle_payment_submissions WHERE id = submission_record.id;
        RETURN;
    END IF;
    IF invoice_record.status NOT IN ('open', 'rejected') THEN RAISE EXCEPTION 'This invoice cannot accept a new payment submission'; END IF;
    IF input_amount_cents IS NULL OR input_sent_at IS NULL THEN RAISE EXCEPTION 'Amount and sent time are required'; END IF;
    IF NOT invoice_record.is_demo AND upper(input_confirmation_reference) LIKE 'TEST-%' THEN
        RAISE EXCEPTION 'Test references require the isolated demo environment';
    END IF;
    IF input_amount_cents <> invoice_record.amount_due_cents THEN RAISE EXCEPTION 'This beta requires the full invoice amount in one payment'; END IF;
    IF input_sent_at > NOW() + INTERVAL '15 minutes' OR input_sent_at < NOW() - INTERVAL '180 days'
       OR COALESCE(input_confirmation_reference, '') !~ '^[A-Za-z0-9-]{4,64}$'
       OR COALESCE(input_idempotency_key, '') !~ '^.{8,180}$' THEN
        RAISE EXCEPTION 'The payment submission is invalid';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.zelle_payment_submissions existing
        WHERE existing.school_id = invoice_record.school_id
          AND upper(existing.confirmation_reference) = upper(input_confirmation_reference)
          AND existing.invoice_id <> input_invoice_id
    ) THEN RAISE EXCEPTION 'This confirmation reference has already been used for this school'; END IF;

    INSERT INTO public.zelle_payment_submissions (
        invoice_id, school_id, payer_user_id, amount_cents, sent_at, confirmation_reference, idempotency_key
    ) VALUES (
        invoice_record.id, invoice_record.school_id, actor, input_amount_cents,
        input_sent_at, upper(input_confirmation_reference), input_idempotency_key
    ) RETURNING * INTO submission_record;
    UPDATE public.zelle_invoices SET status = 'payment_submitted', updated_at = NOW() WHERE id = invoice_record.id;
    IF invoice_record.onboarding_requirement_instance_id IS NOT NULL THEN
        UPDATE public.onboarding_requirement_instances SET status = 'in_review'
        WHERE id = invoice_record.onboarding_requirement_instance_id;
    END IF;
    INSERT INTO public.zelle_billing_audit_log (school_id, actor_id, action, entity_type, entity_id, metadata)
    VALUES (
        invoice_record.school_id, actor, 'payment_submitted', 'submission', submission_record.id,
        jsonb_build_object('invoice_id', invoice_record.id, 'amount_cents', input_amount_cents)
    );
    PERFORM public.notify_zelle_recipients(
        invoice_record.school_id, public.zelle_invoice_reviewers(invoice_record.id),
        'Zelle payment needs review',
        'A payer submitted a Zelle confirmation reference. Verify it in the school bank before approving.',
        invoice_record.id, 'zelle:invoice:' || submission_record.id::TEXT || ':review', actor
    );
    RETURN QUERY SELECT * FROM public.zelle_payment_submissions WHERE id = submission_record.id;
END;
$$;
REVOKE ALL ON FUNCTION public.submit_zelle_payment(UUID, BIGINT, TIMESTAMPTZ, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_zelle_payment(UUID, BIGINT, TIMESTAMPTZ, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260913190000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
