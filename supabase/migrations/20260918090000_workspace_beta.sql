-- Additive workspace beta contracts. Existing clients and invoice snapshots remain supported.
BEGIN;

CREATE OR REPLACE FUNCTION public.fetch_my_paperwork_items_v2(
    input_school_id UUID DEFAULT NULL,
    input_archived BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    item_id UUID,
    school_id UUID,
    source_kind TEXT,
    title TEXT,
    description TEXT,
    child_id UUID,
    recipient_id UUID,
    status TEXT,
    due_at TIMESTAMPTZ,
    onboarding_requirement_instance_id UUID,
    google_form_connection_id UUID,
    google_form_import_id UUID,
    native_request_id UUID
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT request.id, request.school_id, request.request_kind, request.title,
           request.description, recipient.child_id, recipient.user_id,
           recipient.completion_status, request.due_at,
           instance_requirement.id, NULL::UUID, NULL::UUID, request.id
    FROM public.paperwork_assignments request
    JOIN public.paperwork_assignment_recipients recipient
      ON recipient.assignment_id = request.id
    LEFT JOIN LATERAL (
        SELECT ri.id FROM public.onboarding_requirement_instances ri
        JOIN public.onboarding_instances oi ON oi.id = ri.onboarding_instance_id
        JOIN public.school_memberships sm ON sm.id = oi.membership_id
        WHERE ri.paperwork_request_id = request.id AND sm.user_id = recipient.user_id
          AND ri.child_id IS NOT DISTINCT FROM recipient.child_id
        ORDER BY oi.started_at DESC, ri.id LIMIT 1
    ) instance_requirement ON TRUE
    WHERE (input_school_id IS NULL OR request.school_id = input_school_id)
      AND (
          recipient.user_id = auth.uid()
          OR public.can_manage_paperwork_assignment(request.id, auth.uid())
      )
      AND (
          input_archived = (request.status = 'archived' OR recipient.completion_status IN ('accepted', 'excused'))
      )
    UNION ALL
    SELECT instance_requirement.id, instance.school_id, 'google_form',
           COALESCE(connection.form_title, requirement.title), requirement.description,
           instance_requirement.child_id, membership.user_id,
           COALESCE(form_import.status, instance_requirement.status), NULL::TIMESTAMPTZ,
           instance_requirement.id, connection.id, form_import.id, NULL::UUID
    FROM public.onboarding_requirement_instances instance_requirement
    JOIN public.onboarding_instances instance
      ON instance.id = instance_requirement.onboarding_instance_id
    JOIN public.school_memberships membership
      ON membership.id = instance.membership_id
    JOIN public.onboarding_template_requirements requirement
      ON requirement.id = instance_requirement.template_requirement_id
    JOIN public.google_form_requirement_bindings binding
      ON binding.onboarding_template_requirement_id = requirement.id
    JOIN public.google_form_connections connection
      ON connection.id = binding.connection_id
    LEFT JOIN LATERAL (
        SELECT response.id, response.status
        FROM public.google_form_imports response
        JOIN public.google_form_submission_sessions session ON session.id = response.submission_session_id
        WHERE response.connection_id = connection.id
          AND response.membership_id = membership.id
          AND (session.connection_snapshot ->> 'requirement_id' = requirement.id::TEXT
               OR EXISTS(SELECT 1 FROM public.google_form_requirement_evidence evidence
                         WHERE evidence.import_id=response.id AND evidence.requirement_instance_id=instance_requirement.id))
          AND (requirement.subject_scope = 'member'
               OR response.child_id IS NOT DISTINCT FROM instance_requirement.child_id)
        ORDER BY response.response_submitted_at DESC NULLS LAST,
                 response.created_at DESC
        LIMIT 1
    ) form_import ON TRUE
    WHERE instance.status IN ('in_progress', 'complete')
      AND (input_school_id IS NULL OR instance.school_id = input_school_id)
      AND (
          membership.user_id = auth.uid()
          OR public.has_school_role(
              instance.school_id,
              auth.uid(),
              ARRAY['school_director', 'hq_director']
          )
      )
      AND input_archived = (
          COALESCE(form_import.status, instance_requirement.status)
          IN ('approved', 'rejected', 'waived')
      );
$$;


REVOKE ALL ON FUNCTION public.fetch_my_paperwork_items_v2(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fetch_my_paperwork_items_v2(UUID, BOOLEAN) TO authenticated;

-- Read names only for records the caller can already see; never expose a directory.
CREATE FUNCTION public.fetch_workspace_payer_labels(input_school_id UUID DEFAULT NULL)
RETURNS TABLE(user_id UUID, school_id UUID, display_name TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT DISTINCT i.payer_user_id, i.school_id, COALESCE(NULLIF(p.display_name, ''), 'Payer')
    FROM public.zelle_invoices i LEFT JOIN public.profiles p ON p.id = i.payer_user_id
    WHERE (input_school_id IS NULL OR i.school_id = input_school_id)
      AND (i.payer_user_id = auth.uid() OR public.zelle_can_review_invoice(i.id, auth.uid()));
$$;
REVOKE ALL ON FUNCTION public.fetch_workspace_payer_labels(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fetch_workspace_payer_labels(UUID) TO authenticated;

CREATE FUNCTION public.fetch_workspace_recipient_labels(input_school_id UUID)
RETURNS TABLE(user_id UUID, display_name TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT DISTINCT q.recipient_id, COALESCE(NULLIF(p.display_name, ''), 'Recipient')
    FROM (
        SELECT recipient_id FROM public.fetch_my_paperwork_items_v2(input_school_id, FALSE)
        UNION SELECT recipient_id FROM public.fetch_my_paperwork_items_v2(input_school_id, TRUE)
    ) q LEFT JOIN public.profiles p ON p.id = q.recipient_id;
$$;
REVOKE ALL ON FUNCTION public.fetch_workspace_recipient_labels(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fetch_workspace_recipient_labels(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_manage_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignments assignments
        WHERE assignments.id = assignment_uuid
          AND (public.has_direct_school_role(assignments.school_id, user_uuid, ARRAY['school_director'])
               OR public.is_hq_director(user_uuid))
          AND (
              assignments.assigned_by = user_uuid
              OR EXISTS (
                  SELECT 1
                  FROM public.onboarding_requirement_instances requirement_instances
                  JOIN public.onboarding_instances instances ON instances.id = requirement_instances.onboarding_instance_id
                  JOIN public.onboarding_templates templates ON templates.id = instances.template_id
                  WHERE requirement_instances.assignment_id = assignments.id
                    AND public.is_onboarding_template_manager(templates.school_id, templates.target_role, user_uuid)
              )
          )
    );
$$;

-- Immutable correction targets belong to a particular attempt, never an entire person.
CREATE TABLE public.paperwork_corrections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    google_import_id UUID REFERENCES public.google_form_imports(id) ON DELETE CASCADE,
    submission_id UUID REFERENCES public.paperwork_submissions(id) ON DELETE CASCADE,
    target_kind TEXT NOT NULL CHECK (target_kind IN ('answer', 'file', 'general')),
    target_id TEXT NOT NULL,
    title TEXT NOT NULL,
    note TEXT NOT NULL CHECK (length(btrim(note)) BETWEEN 1 AND 2000),
    created_by UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (num_nonnulls(google_import_id, submission_id) = 1)
);
ALTER TABLE public.paperwork_corrections ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Visible submission corrections" ON public.paperwork_corrections FOR SELECT TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.google_form_imports i WHERE i.id = google_import_id)
    OR EXISTS (SELECT 1 FROM public.paperwork_submissions s WHERE s.id = submission_id)
);
GRANT SELECT ON public.paperwork_corrections TO authenticated;
GRANT ALL ON public.paperwork_corrections TO service_role;

CREATE FUNCTION public.review_google_form_with_corrections(
    input_import_id UUID, input_decision TEXT, input_matched_child_id UUID DEFAULT NULL,
    input_review_note TEXT DEFAULT NULL, input_corrections JSONB DEFAULT '[]'::JSONB
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE source public.google_form_imports%ROWTYPE; correction JSONB;
BEGIN
    SELECT * INTO source FROM public.google_form_imports WHERE id = input_import_id FOR UPDATE;
    IF NOT FOUND OR source.status NOT IN ('pending_review', 'ambiguous', 'error') THEN
        RAISE EXCEPTION 'This response is no longer awaiting review';
    END IF;
    IF source.submitted_by = auth.uid() OR EXISTS(SELECT 1 FROM public.school_memberships m WHERE m.id=source.membership_id AND m.user_id=auth.uid()) THEN
        RAISE EXCEPTION 'You cannot review your own response';
    END IF;
    IF jsonb_typeof(input_corrections) <> 'array' OR jsonb_array_length(input_corrections) > 100 THEN
        RAISE EXCEPTION 'Invalid corrections';
    END IF;
    IF input_decision <> 'changes_requested' AND jsonb_array_length(input_corrections) > 0 THEN
        RAISE EXCEPTION 'Only a change request can contain corrections';
    END IF;
    -- Existing RPC remains the authority for role, child matching, and review transitions.
    PERFORM public.approve_google_form_child_intake(input_import_id, input_decision, input_matched_child_id, input_review_note);
    FOR correction IN SELECT value FROM jsonb_array_elements(input_corrections) LOOP
        IF correction->>'target_kind' = 'answer' AND NOT (
            source.submitted_payload ? (correction->>'target_id')
            OR EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(source.question_snapshot,'[]'::JSONB)) q
                      WHERE q->>'id'=correction->>'target_id' AND q->>'field_key' IS DISTINCT FROM 'submission_reference')
        ) THEN
            RAISE EXCEPTION 'Answer does not belong to this submission';
        ELSIF correction->>'target_kind' = 'file' AND NOT EXISTS (
            SELECT 1 FROM public.google_form_import_attachments a
            WHERE a.import_id = source.id AND a.id::TEXT = correction->>'target_id'
        ) THEN RAISE EXCEPTION 'File does not belong to this submission'; END IF;
        INSERT INTO public.paperwork_corrections(google_import_id, target_kind, target_id, title, note, created_by)
        VALUES(source.id, correction->>'target_kind', correction->>'target_id', correction->>'title', correction->>'note', auth.uid());
    END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.review_google_form_with_corrections(UUID,TEXT,UUID,TEXT,JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_google_form_with_corrections(UUID,TEXT,UUID,TEXT,JSONB) TO authenticated;

-- Published acknowledgements retain exactly what the recipient agreed to.
ALTER TABLE public.paperwork_assignments ADD COLUMN policy_snapshot JSONB;
CREATE FUNCTION public.freeze_paperwork_policy() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.policy_snapshot IS NOT NULL THEN
        IF NEW.title IS DISTINCT FROM OLD.title OR NEW.description IS DISTINCT FROM OLD.description
           OR NEW.policy_snapshot IS DISTINCT FROM OLD.policy_snapshot THEN
            RAISE EXCEPTION 'Issue a new policy request to change published policy content';
        END IF;
    ELSIF NEW.request_kind = 'acknowledgement' AND NEW.status = 'published' THEN
        NEW.policy_snapshot := jsonb_build_object('version', NEW.id, 'title', NEW.title,
            'description', NEW.description, 'published_at', now(), 'materials',
            COALESCE((SELECT jsonb_agg(to_jsonb(m)) FROM public.paperwork_request_materials m WHERE m.request_id = NEW.id), '[]'::JSONB));
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER freeze_paperwork_policy BEFORE INSERT OR UPDATE ON public.paperwork_assignments
FOR EACH ROW EXECUTE FUNCTION public.freeze_paperwork_policy();
CREATE FUNCTION public.snapshot_policy_acknowledgement() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE snapshot JSONB;
BEGIN
    SELECT policy_snapshot INTO snapshot FROM public.paperwork_assignments WHERE id = NEW.assignment_id;
    IF NEW.structured_payload->>'acknowledged' = 'true' AND snapshot IS NOT NULL THEN
        NEW.structured_payload := NEW.structured_payload || jsonb_build_object('policy_snapshot', snapshot);
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER snapshot_policy_acknowledgement BEFORE INSERT ON public.paperwork_submissions
FOR EACH ROW EXECUTE FUNCTION public.snapshot_policy_acknowledgement();

CREATE FUNCTION public.review_paperwork_with_corrections(input_submission_id UUID, input_decision TEXT,
    input_message TEXT DEFAULT NULL, input_corrections JSONB DEFAULT '[]'::JSONB)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE correction JSONB;
BEGIN
    PERFORM 1 FROM public.paperwork_submissions WHERE id = input_submission_id FOR UPDATE;
    IF jsonb_typeof(input_corrections) <> 'array' OR jsonb_array_length(input_corrections) > 100 THEN
        RAISE EXCEPTION 'Invalid corrections'; END IF;
    PERFORM public.review_paperwork_submission_v2(input_submission_id, input_decision, input_message);
    FOR correction IN SELECT value FROM jsonb_array_elements(input_corrections) LOOP
        IF input_decision <> 'changes_requested' OR correction->>'target_kind' <> 'file'
           OR correction->>'target_id' <> input_submission_id::TEXT THEN
            RAISE EXCEPTION 'Correction must target this submitted file'; END IF;
        INSERT INTO public.paperwork_corrections(submission_id, target_kind, target_id, title, note, created_by)
        VALUES(input_submission_id, 'file', input_submission_id::TEXT, correction->>'title', correction->>'note', auth.uid());
    END LOOP;
END; $$;
REVOKE ALL ON FUNCTION public.review_paperwork_with_corrections(UUID,TEXT,TEXT,JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_paperwork_with_corrections(UUID,TEXT,TEXT,JSONB) TO authenticated;
CREATE FUNCTION public.guard_published_policy_materials() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF EXISTS(SELECT 1 FROM public.paperwork_assignments WHERE id = CASE WHEN TG_OP='DELETE' THEN OLD.request_id ELSE NEW.request_id END AND policy_snapshot IS NOT NULL)
       OR (TG_OP = 'UPDATE' AND EXISTS(SELECT 1 FROM public.paperwork_assignments WHERE id = OLD.request_id AND policy_snapshot IS NOT NULL)) THEN
        RAISE EXCEPTION 'Issue a new policy request to change published policy materials';
    END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END; $$;
CREATE TRIGGER guard_published_policy_materials BEFORE INSERT OR UPDATE OR DELETE ON public.paperwork_request_materials
FOR EACH ROW EXECUTE FUNCTION public.guard_published_policy_materials();
CREATE FUNCTION public.fetch_paperwork_response_history(input_requirement_id UUID)
RETURNS SETOF public.google_form_imports
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT response.* FROM public.onboarding_requirement_instances ri
    JOIN public.onboarding_instances oi ON oi.id=ri.onboarding_instance_id
    JOIN public.school_memberships membership ON membership.id=oi.membership_id
    JOIN public.onboarding_template_requirements requirement ON requirement.id=ri.template_requirement_id
    JOIN public.google_form_imports response ON response.membership_id=membership.id
    JOIN public.google_form_submission_sessions session ON response.submission_session_id=session.id
      AND (session.connection_snapshot->>'requirement_id'=requirement.id::TEXT
           OR EXISTS(SELECT 1 FROM public.google_form_requirement_evidence evidence
                     WHERE evidence.import_id=response.id AND evidence.requirement_instance_id=ri.id))
    WHERE ri.id=input_requirement_id
      AND (membership.user_id=auth.uid() OR public.has_school_role(oi.school_id,auth.uid(),ARRAY['school_director','hq_director']))
      AND (requirement.subject_scope='member' OR response.child_id IS NOT DISTINCT FROM ri.child_id)
    ORDER BY response.response_submitted_at DESC NULLS LAST, response.created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.fetch_paperwork_response_history(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fetch_paperwork_response_history(UUID) TO authenticated;
CREATE OR REPLACE FUNCTION public.create_paperwork_request(
    input_school_id UUID,
    input_title TEXT,
    input_description TEXT DEFAULT NULL,
    input_request_kind TEXT DEFAULT 'document_upload',
    input_audience_role TEXT DEFAULT NULL,
    input_child_id UUID DEFAULT NULL,
    input_recipient_ids UUID[] DEFAULT '{}'::UUID[],
    input_due_at TIMESTAMPTZ DEFAULT NULL,
    input_requires_review BOOLEAN DEFAULT TRUE
)
RETURNS SETOF public.paperwork_assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    saved public.paperwork_assignments%ROWTYPE;
BEGIN
    IF NOT public.has_school_role(input_school_id, actor, ARRAY['school_director', 'hq_director']) THEN
        RAISE EXCEPTION 'You cannot create paperwork for this school';
    END IF;
    IF input_request_kind NOT IN ('document_upload', 'acknowledgement') THEN
        RAISE EXCEPTION 'Paperwork type is invalid';
    END IF;
    IF NULLIF(btrim(COALESCE(input_title, '')), '') IS NULL THEN
        RAISE EXCEPTION 'A paperwork title is required';
    END IF;
    IF COALESCE(cardinality(input_recipient_ids), 0) = 0 THEN
        RAISE EXCEPTION 'Choose at least one recipient';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM unnest(input_recipient_ids) recipient_id
        WHERE recipient_id = actor
           OR NOT EXISTS (
               SELECT 1
               FROM public.school_memberships membership
               WHERE membership.school_id = input_school_id
                 AND membership.user_id = recipient_id
                 AND membership.active
                 AND membership.role IN ('parent', 'teacher', 'school_director')
                 AND (membership.role <> 'school_director' OR public.is_hq_director(actor))
           )
    ) THEN
        RAISE EXCEPTION 'One or more recipients are not eligible';
    END IF;

    INSERT INTO public.paperwork_assignments (
        school_id, title, description, assigned_by, due_at, request_kind,
        audience_role, child_id, requires_review, status, updated_at
    ) VALUES (
        input_school_id, btrim(input_title), NULLIF(btrim(COALESCE(input_description, '')), ''),
        actor, input_due_at, input_request_kind, input_audience_role, input_child_id,
        input_requires_review, 'published', NOW()
    )
    RETURNING * INTO saved;

    INSERT INTO public.paperwork_assignment_recipients (
        assignment_id, parent_id, user_id, role_at_request, child_id
    )
    SELECT saved.id, membership.user_id, membership.user_id, membership.role, input_child_id
    FROM public.school_memberships membership
    WHERE membership.school_id = input_school_id
      AND membership.user_id = ANY(input_recipient_ids)
      AND membership.active;

    INSERT INTO public.paperwork_events(request_id, school_id, actor_id, event_type)
    VALUES (saved.id, saved.school_id, actor, 'published');

    RETURN QUERY
    SELECT * FROM public.paperwork_assignments WHERE id = saved.id;
END;
$$;


CREATE FUNCTION public.fetch_unmatched_paperwork_responses(input_school_id UUID)
RETURNS SETOF public.google_form_imports
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT response.* FROM public.google_form_imports response
    WHERE response.school_id=input_school_id
      AND response.status IN ('pending_review','ambiguous','error')
      AND public.has_school_role(input_school_id,auth.uid(),ARRAY['school_director','hq_director'])
      AND NOT EXISTS (
          SELECT 1 FROM public.google_form_submission_sessions session
          JOIN public.onboarding_requirement_instances ri ON ri.template_requirement_id::TEXT=session.connection_snapshot->>'requirement_id'
          JOIN public.onboarding_instances oi ON oi.id=ri.onboarding_instance_id AND oi.membership_id=response.membership_id
          JOIN public.onboarding_template_requirements requirement ON requirement.id=ri.template_requirement_id
          WHERE session.id=response.submission_session_id
            AND (requirement.subject_scope='member' OR response.child_id IS NOT DISTINCT FROM ri.child_id)
      ) ORDER BY response.created_at;
$$;
REVOKE ALL ON FUNCTION public.fetch_unmatched_paperwork_responses(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fetch_unmatched_paperwork_responses(UUID) TO authenticated;
COMMIT;
