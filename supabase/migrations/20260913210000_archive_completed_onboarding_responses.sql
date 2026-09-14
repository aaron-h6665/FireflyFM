-- Separate administrative paperwork from learning assignments while preserving
-- historical assignment records and the shared onboarding coordinator.

BEGIN;

ALTER TABLE public.paperwork_assignments
    ADD COLUMN IF NOT EXISTS request_kind TEXT NOT NULL DEFAULT 'document_upload',
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'published',
    ADD COLUMN IF NOT EXISTS child_id UUID REFERENCES public.children(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS audience_role TEXT,
    ADD COLUMN IF NOT EXISTS requires_review BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS allow_resubmission BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS legacy_assignment_id UUID REFERENCES public.assignments(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;
ALTER TABLE public.paperwork_assignments
    DROP CONSTRAINT IF EXISTS paperwork_assignments_request_kind_check,
    ADD CONSTRAINT paperwork_assignments_request_kind_check CHECK (request_kind IN ('document_upload', 'acknowledgement')),
    DROP CONSTRAINT IF EXISTS paperwork_assignments_status_check,
    ADD CONSTRAINT paperwork_assignments_status_check CHECK (status IN ('draft', 'scheduled', 'published', 'closed', 'archived')),
    DROP CONSTRAINT IF EXISTS paperwork_assignments_audience_role_check,
    ADD CONSTRAINT paperwork_assignments_audience_role_check CHECK (audience_role IS NULL OR audience_role IN ('parent', 'teacher', 'school_director'));
CREATE UNIQUE INDEX IF NOT EXISTS idx_paperwork_requests_legacy_assignment
    ON public.paperwork_assignments(legacy_assignment_id) WHERE legacy_assignment_id IS NOT NULL;

ALTER TABLE public.paperwork_assignment_recipients
    ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS role_at_request TEXT,
    ADD COLUMN IF NOT EXISTS child_id UUID REFERENCES public.children(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS completion_status TEXT NOT NULL DEFAULT 'not_started',
    ADD COLUMN IF NOT EXISTS viewed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;
UPDATE public.paperwork_assignment_recipients SET user_id = parent_id WHERE user_id IS NULL;
ALTER TABLE public.paperwork_assignment_recipients
    ALTER COLUMN parent_id DROP NOT NULL,
    DROP CONSTRAINT IF EXISTS paperwork_assignment_recipients_completion_status_check,
    ADD CONSTRAINT paperwork_assignment_recipients_completion_status_check CHECK (completion_status IN ('not_started', 'read', 'submitted', 'resubmitted', 'changes_requested', 'accepted', 'excused', 'overdue')),
    DROP CONSTRAINT IF EXISTS paperwork_assignment_recipients_role_at_request_check,
    ADD CONSTRAINT paperwork_assignment_recipients_role_at_request_check CHECK (role_at_request IS NULL OR role_at_request IN ('parent', 'teacher', 'school_director'));
ALTER TABLE public.paperwork_assignment_recipients DROP CONSTRAINT IF EXISTS paperwork_assignment_recipients_pkey;
CREATE UNIQUE INDEX IF NOT EXISTS idx_paperwork_request_recipient ON public.paperwork_assignment_recipients(assignment_id, user_id);

CREATE OR REPLACE FUNCTION public.normalize_paperwork_recipient_user()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    NEW.user_id := COALESCE(NEW.user_id, NEW.parent_id);
    NEW.parent_id := COALESCE(NEW.parent_id, NEW.user_id);
    IF NEW.user_id IS NULL THEN RAISE EXCEPTION 'A paperwork recipient is required'; END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS normalize_paperwork_recipient_user_trigger ON public.paperwork_assignment_recipients;
CREATE TRIGGER normalize_paperwork_recipient_user_trigger BEFORE INSERT OR UPDATE ON public.paperwork_assignment_recipients
FOR EACH ROW EXECUTE FUNCTION public.normalize_paperwork_recipient_user();

ALTER TABLE public.paperwork_submissions
    ADD COLUMN IF NOT EXISTS attempt_number INTEGER NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS structured_payload JSONB NOT NULL DEFAULT '{}'::JSONB,
    ADD COLUMN IF NOT EXISTS reviewer_message TEXT,
    ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
UPDATE public.paperwork_submissions
SET status = CASE WHEN status = 'flagged' THEN 'changes_requested' ELSE status END;
ALTER TABLE public.paperwork_submissions
    DROP CONSTRAINT IF EXISTS paperwork_submissions_status_check,
    ADD CONSTRAINT paperwork_submissions_status_check CHECK (status IN ('submitted', 'resubmitted', 'changes_requested', 'accepted'));
CREATE UNIQUE INDEX IF NOT EXISTS idx_paperwork_submission_mutation
    ON public.paperwork_submissions(assignment_id, submitted_by, idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.paperwork_request_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), request_id UUID NOT NULL REFERENCES public.paperwork_assignments(id) ON DELETE CASCADE,
    material_type TEXT NOT NULL DEFAULT 'file' CHECK (material_type IN ('link', 'file', 'mixed')),
    title TEXT, url TEXT, private_file_path TEXT, file_name TEXT, content_type TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS public.paperwork_submission_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), submission_id UUID NOT NULL REFERENCES public.paperwork_submissions(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE, private_file_path TEXT NOT NULL,
    file_name TEXT, content_type TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS public.paperwork_feedback_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), request_id UUID NOT NULL REFERENCES public.paperwork_assignments(id) ON DELETE CASCADE,
    submission_id UUID REFERENCES public.paperwork_submissions(id) ON DELETE CASCADE, school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    body TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CHECK (sender_id <> recipient_id), CHECK (length(btrim(body)) BETWEEN 1 AND 4000)
);
CREATE TABLE IF NOT EXISTS public.paperwork_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), request_id UUID NOT NULL REFERENCES public.paperwork_assignments(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE, actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL, metadata JSONB NOT NULL DEFAULT '{}'::JSONB, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.onboarding_requirement_instances ADD COLUMN IF NOT EXISTS paperwork_request_id UUID REFERENCES public.paperwork_assignments(id) ON DELETE RESTRICT;
CREATE INDEX IF NOT EXISTS idx_onboarding_requirement_paperwork_request ON public.onboarding_requirement_instances(paperwork_request_id) WHERE paperwork_request_id IS NOT NULL;

-- Convert non-learning assignments except Google Form shells. Form imports stay canonical.
INSERT INTO public.paperwork_assignments (
    id, school_id, title, description, assigned_by, due_at, created_at, request_kind, status, child_id,
    audience_role, requires_review, allow_resubmission, legacy_assignment_id, updated_at
)
SELECT assignment.id, assignment.school_id, assignment.title, assignment.description, assignment.assigned_by,
       assignment.due_at, assignment.created_at,
       CASE WHEN assignment.category = 'general' AND NOT EXISTS (
                SELECT 1 FROM public.assignment_submission_attachments attachment
                JOIN public.assignment_submissions submission ON submission.id = attachment.submission_id
                WHERE submission.assignment_id = assignment.id
            ) THEN 'acknowledgement'
            WHEN assignment.requires_review = FALSE THEN 'acknowledgement' ELSE 'document_upload' END,
       assignment.status, assignment.child_id, assignment.audience_role, COALESCE(assignment.requires_review, TRUE),
       COALESCE(assignment.allow_resubmission, TRUE), assignment.id, assignment.updated_at
FROM public.assignments assignment
WHERE assignment.category IN ('paperwork', 'onboarding', 'child_record', 'compliance', 'general')
  AND NOT EXISTS (
      SELECT 1 FROM public.onboarding_requirement_instances instance_requirement
      JOIN public.google_form_requirement_bindings binding ON binding.onboarding_template_requirement_id = instance_requirement.template_requirement_id
      WHERE instance_requirement.assignment_id = assignment.id
  )
ON CONFLICT (id) DO UPDATE SET legacy_assignment_id = EXCLUDED.legacy_assignment_id, request_kind = EXCLUDED.request_kind,
    status = EXCLUDED.status, child_id = EXCLUDED.child_id, audience_role = EXCLUDED.audience_role,
    requires_review = EXCLUDED.requires_review, allow_resubmission = EXCLUDED.allow_resubmission, updated_at = EXCLUDED.updated_at;

INSERT INTO public.paperwork_assignment_recipients (
    assignment_id, parent_id, user_id, role_at_request, child_id, completion_status, viewed_at, completed_at, created_at
)
SELECT recipient.assignment_id, recipient.user_id, recipient.user_id, recipient.role_at_assignment, recipient.child_id,
       CASE recipient.completion_status WHEN 'reviewed' THEN 'submitted' WHEN 'flagged' THEN 'changes_requested' ELSE recipient.completion_status END,
       recipient.viewed_at, recipient.completed_at, recipient.created_at
FROM public.assignment_recipients recipient
JOIN public.paperwork_assignments request ON request.legacy_assignment_id = recipient.assignment_id
ON CONFLICT (assignment_id, user_id) DO UPDATE SET completion_status = EXCLUDED.completion_status,
    viewed_at = EXCLUDED.viewed_at, completed_at = EXCLUDED.completed_at;

INSERT INTO public.paperwork_request_materials (id, request_id, material_type, title, url, private_file_path, file_name, content_type, created_at)
SELECT material.id, material.assignment_id, CASE WHEN material.material_type IN ('link', 'file', 'mixed') THEN material.material_type ELSE 'mixed' END,
       material.title, material.url, material.private_file_path, material.file_name, material.content_type, material.created_at
FROM public.assignment_materials material JOIN public.paperwork_assignments request ON request.legacy_assignment_id = material.assignment_id
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.paperwork_submissions (
    id, assignment_id, school_id, submitted_by, file_name, file_path, status, flag_reason, reviewer_message,
    reviewed_by, reviewed_at, submitted_at, attempt_number, structured_payload, idempotency_key
)
SELECT submission.id, submission.assignment_id, submission.school_id, submission.submitted_by,
       attachment.file_name, attachment.private_file_path,
       CASE submission.status WHEN 'flagged' THEN 'changes_requested' WHEN 'reviewed' THEN 'submitted' ELSE submission.status END,
       submission.reviewer_message, submission.reviewer_message, submission.reviewed_by, submission.reviewed_at,
       submission.submitted_at, COALESCE(submission.attempt_number, 1), COALESCE(submission.structured_payload, '{}'::JSONB), submission.idempotency_key
FROM public.assignment_submissions submission
JOIN public.paperwork_assignments request ON request.legacy_assignment_id = submission.assignment_id
LEFT JOIN LATERAL (
    SELECT item.file_name, item.private_file_path FROM public.assignment_submission_attachments item
    WHERE item.submission_id = submission.id ORDER BY item.created_at LIMIT 1
) attachment ON TRUE ON CONFLICT (id) DO NOTHING;

INSERT INTO public.paperwork_submission_attachments (id, submission_id, school_id, private_file_path, file_name, content_type, created_at)
SELECT attachment.id, attachment.submission_id, attachment.school_id, attachment.private_file_path,
       attachment.file_name, attachment.content_type, attachment.created_at
FROM public.assignment_submission_attachments attachment JOIN public.paperwork_submissions submission ON submission.id = attachment.submission_id
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.paperwork_feedback_messages (id, request_id, submission_id, school_id, sender_id, recipient_id, body, created_at)
SELECT feedback.id, feedback.assignment_id, feedback.submission_id, feedback.school_id, feedback.sender_id,
       feedback.recipient_id, feedback.body, feedback.created_at
FROM public.assignment_feedback_messages feedback JOIN public.paperwork_assignments request ON request.legacy_assignment_id = feedback.assignment_id
WHERE feedback.sender_id <> feedback.recipient_id ON CONFLICT (id) DO NOTHING;

INSERT INTO public.paperwork_events (id, request_id, school_id, actor_id, event_type, metadata, created_at)
SELECT event.id, event.assignment_id, event.school_id, event.actor_id, event.event_type, event.metadata, event.created_at
FROM public.assignment_events event JOIN public.paperwork_assignments request ON request.legacy_assignment_id = event.assignment_id
ON CONFLICT (id) DO NOTHING;

UPDATE public.onboarding_requirement_instances instance_requirement SET paperwork_request_id = request.id
FROM public.paperwork_assignments request
WHERE request.legacy_assignment_id = instance_requirement.assignment_id AND instance_requirement.paperwork_request_id IS NULL;
UPDATE public.assignments SET status = 'archived', updated_at = NOW()
WHERE category IN ('paperwork', 'onboarding', 'child_record', 'compliance', 'general') AND status <> 'archived';

CREATE OR REPLACE FUNCTION public.enforce_learning_assignment_boundary()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    IF NEW.category NOT IN ('training', 'curriculum') THEN RAISE EXCEPTION 'Use the Paperwork or Payments workspace for this work'; END IF;
    IF NEW.child_id IS NOT NULL OR NEW.audience_role NOT IN ('teacher', 'school_director') THEN
        RAISE EXCEPTION 'Training and curriculum can target staff only';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS enforce_learning_assignment_boundary_trigger ON public.assignments;
CREATE TRIGGER enforce_learning_assignment_boundary_trigger BEFORE INSERT OR UPDATE OF category, child_id, audience_role ON public.assignments
FOR EACH ROW WHEN (NEW.legacy_source_type IS NULL) EXECUTE FUNCTION public.enforce_learning_assignment_boundary();

CREATE OR REPLACE FUNCTION public.is_paperwork_assignment_recipient(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (SELECT 1 FROM public.paperwork_assignment_recipients recipient
                   WHERE recipient.assignment_id = assignment_uuid AND recipient.user_id = user_uuid);
$$;
CREATE OR REPLACE FUNCTION public.can_manage_paperwork_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (SELECT 1 FROM public.paperwork_assignments request WHERE request.id = assignment_uuid
                   AND public.has_school_role(request.school_id, user_uuid, ARRAY['school_director', 'hq_director']));
$$;
CREATE OR REPLACE FUNCTION public.can_submit_paperwork_assignment(assignment_uuid UUID, school_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (SELECT 1 FROM public.paperwork_assignments request
                   JOIN public.paperwork_assignment_recipients recipient ON recipient.assignment_id = request.id
                   WHERE request.id = assignment_uuid AND request.school_id = school_uuid AND recipient.user_id = user_uuid
                     AND request.status IN ('published', 'closed'));
$$;

CREATE OR REPLACE FUNCTION public.create_paperwork_request(
    input_school_id UUID, input_title TEXT, input_description TEXT DEFAULT NULL,
    input_request_kind TEXT DEFAULT 'document_upload', input_audience_role TEXT DEFAULT NULL,
    input_child_id UUID DEFAULT NULL, input_recipient_ids UUID[] DEFAULT '{}'::UUID[],
    input_due_at TIMESTAMPTZ DEFAULT NULL, input_requires_review BOOLEAN DEFAULT TRUE
)
RETURNS SETOF public.paperwork_assignments LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE actor UUID := auth.uid(); saved public.paperwork_assignments%ROWTYPE;
BEGIN
    IF NOT public.has_school_role(input_school_id, actor, ARRAY['school_director', 'hq_director']) THEN RAISE EXCEPTION 'You cannot create paperwork for this school'; END IF;
    IF input_request_kind NOT IN ('document_upload', 'acknowledgement') THEN RAISE EXCEPTION 'Paperwork type is invalid'; END IF;
    IF NULLIF(btrim(COALESCE(input_title, '')), '') IS NULL THEN RAISE EXCEPTION 'A paperwork title is required'; END IF;
    IF COALESCE(cardinality(input_recipient_ids), 0) = 0 THEN RAISE EXCEPTION 'Choose at least one recipient'; END IF;
    IF EXISTS (
        SELECT 1 FROM unnest(input_recipient_ids) recipient_id
        WHERE recipient_id = actor OR NOT EXISTS (
            SELECT 1 FROM public.school_memberships membership WHERE membership.school_id = input_school_id
              AND membership.user_id = recipient_id AND membership.active AND membership.role IN ('parent', 'teacher', 'school_director')
        )
    ) THEN RAISE EXCEPTION 'One or more recipients are not eligible'; END IF;
    INSERT INTO public.paperwork_assignments (school_id, title, description, assigned_by, due_at, request_kind,
        audience_role, child_id, requires_review, status, updated_at)
    VALUES (input_school_id, btrim(input_title), NULLIF(btrim(COALESCE(input_description, '')), ''), actor,
        input_due_at, input_request_kind, input_audience_role, input_child_id, input_requires_review, 'published', NOW())
    RETURNING * INTO saved;
    INSERT INTO public.paperwork_assignment_recipients (assignment_id, parent_id, user_id, role_at_request, child_id)
    SELECT saved.id, membership.user_id, membership.user_id, membership.role, input_child_id
    FROM public.school_memberships membership WHERE membership.school_id = input_school_id
      AND membership.user_id = ANY(input_recipient_ids) AND membership.active;
    INSERT INTO public.paperwork_events(request_id, school_id, actor_id, event_type)
    VALUES (saved.id, saved.school_id, actor, 'published');
    RETURN QUERY SELECT * FROM public.paperwork_assignments WHERE id = saved.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.acknowledge_paperwork_request(input_request_id UUID, input_idempotency_key TEXT)
RETURNS SETOF public.paperwork_submissions LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE actor UUID := auth.uid(); request public.paperwork_assignments%ROWTYPE; saved public.paperwork_submissions%ROWTYPE;
BEGIN
    SELECT * INTO request FROM public.paperwork_assignments WHERE id = input_request_id FOR UPDATE;
    IF request.request_kind <> 'acknowledgement' OR NOT public.can_submit_paperwork_assignment(request.id, request.school_id, actor) THEN
        RAISE EXCEPTION 'You cannot acknowledge this paperwork';
    END IF;
    INSERT INTO public.paperwork_submissions (assignment_id, school_id, submitted_by, status, structured_payload, attempt_number, idempotency_key)
    VALUES (request.id, request.school_id, actor, CASE WHEN request.requires_review THEN 'submitted' ELSE 'accepted' END,
        jsonb_build_object('acknowledged', TRUE), 1, input_idempotency_key)
    ON CONFLICT (assignment_id, submitted_by, idempotency_key) WHERE idempotency_key IS NOT NULL
    DO UPDATE SET idempotency_key = EXCLUDED.idempotency_key RETURNING * INTO saved;
    UPDATE public.paperwork_assignment_recipients
    SET completion_status = CASE WHEN request.requires_review THEN 'submitted' ELSE 'accepted' END,
        completed_at = CASE WHEN request.requires_review THEN NULL ELSE NOW() END
    WHERE assignment_id = request.id AND user_id = actor;
    RETURN QUERY SELECT * FROM public.paperwork_submissions WHERE id = saved.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_paperwork_submission_v2(input_submission_id UUID, input_decision TEXT, input_message TEXT DEFAULT NULL)
RETURNS SETOF public.paperwork_submissions LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE actor UUID := auth.uid(); saved public.paperwork_submissions%ROWTYPE; request public.paperwork_assignments%ROWTYPE;
BEGIN
    SELECT request_row.* INTO request FROM public.paperwork_submissions submission
    JOIN public.paperwork_assignments request_row ON request_row.id = submission.assignment_id
    WHERE submission.id = input_submission_id FOR UPDATE OF submission;
    IF request.id IS NULL OR NOT public.can_manage_paperwork_assignment(request.id, actor) OR request.assigned_by = actor THEN
        RAISE EXCEPTION 'You cannot review this paperwork submission';
    END IF;
    IF input_decision NOT IN ('accepted', 'changes_requested') THEN RAISE EXCEPTION 'Paperwork review decision is invalid'; END IF;
    IF input_decision = 'changes_requested' AND NULLIF(btrim(COALESCE(input_message, '')), '') IS NULL THEN RAISE EXCEPTION 'Explain the requested changes'; END IF;
    UPDATE public.paperwork_submissions SET status = input_decision,
        reviewer_message = NULLIF(btrim(COALESCE(input_message, '')), ''), reviewed_by = actor, reviewed_at = NOW()
    WHERE id = input_submission_id RETURNING * INTO saved;
    UPDATE public.paperwork_assignment_recipients SET completion_status = input_decision,
        completed_at = CASE WHEN input_decision = 'accepted' THEN NOW() ELSE NULL END
    WHERE assignment_id = saved.assignment_id AND user_id = saved.submitted_by;
    RETURN QUERY SELECT * FROM public.paperwork_submissions WHERE id = saved.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.waive_paperwork_request(input_request_id UUID, input_recipient_id UUID, input_reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE actor UUID := auth.uid();
BEGIN
    IF NOT public.can_manage_paperwork_assignment(input_request_id, actor) OR NULLIF(btrim(COALESCE(input_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Authorized waiver and reason required';
    END IF;
    UPDATE public.paperwork_assignment_recipients SET completion_status = 'excused', completed_at = NOW()
    WHERE assignment_id = input_request_id AND user_id = input_recipient_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Paperwork recipient not found'; END IF;
    INSERT INTO public.paperwork_events(request_id, school_id, actor_id, event_type, metadata)
    SELECT id, school_id, actor, 'waived', jsonb_build_object('recipient_id', input_recipient_id, 'reason', btrim(input_reason))
    FROM public.paperwork_assignments WHERE id = input_request_id;
END;
$$;

-- Terminal Google Form reviews are immutable history.
ALTER FUNCTION public.approve_google_form_child_intake(UUID, TEXT, UUID, TEXT) RENAME TO apply_google_form_child_intake_review;
REVOKE ALL ON FUNCTION public.apply_google_form_child_intake_review(UUID, TEXT, UUID, TEXT) FROM PUBLIC, anon, authenticated;
CREATE FUNCTION public.approve_google_form_child_intake(input_import_id UUID, input_decision TEXT,
    input_matched_child_id UUID DEFAULT NULL, input_review_note TEXT DEFAULT NULL)
RETURNS TABLE (import_id UUID, child_id UUID, access_state TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE actor UUID := auth.uid(); current_status TEXT;
BEGIN
    SELECT form_import.status INTO current_status FROM public.google_form_imports form_import
    WHERE form_import.id = input_import_id AND public.has_school_role(form_import.school_id, actor, ARRAY['school_director']) FOR UPDATE;
    IF current_status IS NULL THEN RAISE EXCEPTION 'Only a school director can review this Form response'; END IF;
    IF current_status IN ('approved', 'rejected', 'changes_requested') THEN RAISE EXCEPTION 'This Form response has already been reviewed and archived'; END IF;
    RETURN QUERY SELECT * FROM public.apply_google_form_child_intake_review(input_import_id, input_decision, input_matched_child_id, input_review_note);
END;
$$;
CREATE OR REPLACE FUNCTION public.prevent_reviewed_google_form_import_changes()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF OLD.status IN ('approved', 'rejected', 'changes_requested') AND NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION 'Reviewed Form responses are archived and cannot be changed';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS prevent_reviewed_google_form_import_changes_trigger ON public.google_form_imports;
CREATE TRIGGER prevent_reviewed_google_form_import_changes_trigger BEFORE UPDATE OF status ON public.google_form_imports
FOR EACH ROW EXECUTE FUNCTION public.prevent_reviewed_google_form_import_changes();

-- Onboarding stays the coordinator, delegating execution by requirement kind.
CREATE OR REPLACE FUNCTION public.instantiate_onboarding_requirement(input_instance_id UUID,
    input_template_requirement_id UUID, input_child_id UUID DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE instance_record RECORD; requirement_record public.onboarding_template_requirements%ROWTYPE;
    requirement_instance_id UUID; request_id UUID; notification_id UUID; form_connection_id UUID;
BEGIN
    SELECT instance.*, membership.user_id, membership.role, template.created_by INTO instance_record
    FROM public.onboarding_instances instance JOIN public.school_memberships membership ON membership.id = instance.membership_id
    JOIN public.onboarding_templates template ON template.id = instance.template_id WHERE instance.id = input_instance_id;
    SELECT * INTO requirement_record FROM public.onboarding_template_requirements
    WHERE id = input_template_requirement_id AND template_id = instance_record.template_id;
    IF instance_record.id IS NULL OR requirement_record.id IS NULL THEN RAISE EXCEPTION 'Onboarding requirement could not be instantiated'; END IF;
    IF requirement_record.requirement_type = 'payment' THEN
        IF input_child_id IS NOT NULL THEN RAISE EXCEPTION 'Payment requirements must be member-scoped'; END IF;
        INSERT INTO public.onboarding_requirement_instances (onboarding_instance_id, template_requirement_id, status)
        VALUES (input_instance_id, requirement_record.id, 'not_started')
        ON CONFLICT (onboarding_instance_id, template_requirement_id) WHERE child_id IS NULL
        DO UPDATE SET status = public.onboarding_requirement_instances.status RETURNING id INTO requirement_instance_id;
        RETURN public.create_zelle_onboarding_invoice(requirement_instance_id);
    END IF;
    SELECT binding.connection_id INTO form_connection_id FROM public.google_form_requirement_bindings binding
    WHERE binding.onboarding_template_requirement_id = requirement_record.id;
    IF form_connection_id IS NOT NULL THEN
        INSERT INTO public.onboarding_requirement_instances (onboarding_instance_id, template_requirement_id, child_id, status)
        VALUES (input_instance_id, requirement_record.id, input_child_id, 'not_started') ON CONFLICT DO NOTHING RETURNING id INTO requirement_instance_id;
        IF requirement_instance_id IS NULL THEN SELECT id INTO requirement_instance_id FROM public.onboarding_requirement_instances
            WHERE onboarding_instance_id = input_instance_id AND template_requirement_id = requirement_record.id
              AND child_id IS NOT DISTINCT FROM input_child_id; END IF;
        RETURN requirement_instance_id;
    END IF;
    IF input_child_id IS NOT NULL THEN
        SELECT existing.paperwork_request_id INTO request_id FROM public.onboarding_requirement_instances existing
        JOIN public.onboarding_instances other_instance ON other_instance.id = existing.onboarding_instance_id
        JOIN public.onboarding_template_requirements other_requirement ON other_requirement.id = existing.template_requirement_id
        WHERE other_instance.school_id = instance_record.school_id AND other_requirement.requirement_key = requirement_record.requirement_key
          AND existing.child_id = input_child_id AND existing.paperwork_request_id IS NOT NULL ORDER BY existing.created_at LIMIT 1;
    END IF;
    IF request_id IS NULL THEN
        INSERT INTO public.paperwork_assignments (school_id, title, description, assigned_by, request_kind, status,
            child_id, audience_role, requires_review, allow_resubmission, updated_at)
        VALUES (instance_record.school_id, requirement_record.title, requirement_record.description, instance_record.created_by,
            CASE WHEN requirement_record.requirement_type = 'acknowledgement' THEN 'acknowledgement' ELSE 'document_upload' END,
            'published', input_child_id, instance_record.role, TRUE, TRUE, NOW()) RETURNING id INTO request_id;
        INSERT INTO public.paperwork_request_materials (request_id, material_type, title, private_file_path, file_name, content_type)
        SELECT request_id, 'file', attachment.file_name, attachment.private_file_path, attachment.file_name, attachment.content_type
        FROM public.onboarding_template_attachments attachment WHERE attachment.requirement_id = requirement_record.id ORDER BY attachment.position;
    END IF;
    IF input_child_id IS NULL THEN
        INSERT INTO public.paperwork_assignment_recipients (assignment_id, parent_id, user_id, role_at_request, completion_status)
        VALUES (request_id, instance_record.user_id, instance_record.user_id, instance_record.role, 'not_started')
        ON CONFLICT (assignment_id, user_id) DO NOTHING;
    ELSE
        INSERT INTO public.paperwork_assignment_recipients (assignment_id, parent_id, user_id, role_at_request, child_id, completion_status)
        SELECT request_id, membership.user_id, membership.user_id, membership.role, input_child_id, 'not_started'
        FROM public.child_guardians guardian JOIN public.school_memberships membership ON membership.user_id = guardian.guardian_id
          AND membership.school_id = instance_record.school_id AND membership.role = 'parent' AND membership.active
        WHERE guardian.child_id = input_child_id ON CONFLICT (assignment_id, user_id) DO NOTHING;
    END IF;
    INSERT INTO public.onboarding_requirement_instances (onboarding_instance_id, template_requirement_id, paperwork_request_id, child_id, status)
    VALUES (input_instance_id, requirement_record.id, request_id, input_child_id, 'not_started') ON CONFLICT DO NOTHING
    RETURNING id INTO requirement_instance_id;
    IF requirement_instance_id IS NULL THEN SELECT id INTO requirement_instance_id FROM public.onboarding_requirement_instances
        WHERE onboarding_instance_id = input_instance_id AND template_requirement_id = requirement_record.id
          AND child_id IS NOT DISTINCT FROM input_child_id; END IF;
    INSERT INTO public.paperwork_events(request_id, school_id, actor_id, event_type)
    VALUES (request_id, instance_record.school_id, instance_record.created_by, 'onboarding_published');
    INSERT INTO public.notifications(school_id, title, body, category, source_type, source_id, created_by, dedupe_key)
    VALUES (instance_record.school_id, requirement_record.title, COALESCE(requirement_record.description, 'New paperwork is ready.'),
        'paperwork_due', 'paperwork_request', request_id, instance_record.created_by, 'onboarding:paperwork:' || request_id::TEXT)
    RETURNING id INTO notification_id;
    INSERT INTO public.notification_recipients(notification_id, user_id)
    SELECT notification_id, recipient.user_id FROM public.paperwork_assignment_recipients recipient
    WHERE recipient.assignment_id = request_id ON CONFLICT DO NOTHING;
    RETURN request_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.create_onboarding_assignment(input_instance_id UUID,
    input_template_requirement_id UUID, input_child_id UUID DEFAULT NULL)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
    SELECT public.instantiate_onboarding_requirement(input_instance_id, input_template_requirement_id, input_child_id);
$$;

CREATE OR REPLACE FUNCTION public.sync_paperwork_completion_to_onboarding()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NEW.completion_status NOT IN ('accepted', 'excused') THEN RETURN NEW; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.paperwork_assignment_recipients recipient
                   WHERE recipient.assignment_id = NEW.assignment_id AND recipient.completion_status NOT IN ('accepted', 'excused')) THEN
        UPDATE public.onboarding_requirement_instances
        SET status = CASE WHEN NEW.completion_status = 'accepted' THEN 'approved' ELSE 'waived' END,
            completed_at = COALESCE(completed_at, NOW())
        WHERE paperwork_request_id = NEW.assignment_id AND status NOT IN ('approved', 'waived');
        UPDATE public.paperwork_assignments SET status = 'archived', updated_at = NOW() WHERE id = NEW.assignment_id;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS sync_paperwork_completion_to_onboarding_trigger ON public.paperwork_assignment_recipients;
CREATE TRIGGER sync_paperwork_completion_to_onboarding_trigger AFTER INSERT OR UPDATE OF completion_status
ON public.paperwork_assignment_recipients FOR EACH ROW EXECUTE FUNCTION public.sync_paperwork_completion_to_onboarding();

ALTER TABLE public.paperwork_request_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.paperwork_submission_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.paperwork_feedback_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.paperwork_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view paperwork assignments" ON public.paperwork_assignments;
DROP POLICY IF EXISTS "Directors can manage paperwork assignments" ON public.paperwork_assignments;
CREATE POLICY "Users can view paperwork requests" ON public.paperwork_assignments FOR SELECT
USING (public.can_manage_paperwork_assignment(id, auth.uid()) OR public.is_paperwork_assignment_recipient(id, auth.uid()));
CREATE POLICY "Directors manage paperwork requests" ON public.paperwork_assignments FOR ALL
USING (public.can_manage_paperwork_assignment(id, auth.uid()))
WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));
DROP POLICY IF EXISTS "Users can view paperwork recipients" ON public.paperwork_assignment_recipients;
DROP POLICY IF EXISTS "Directors can manage paperwork recipients" ON public.paperwork_assignment_recipients;
CREATE POLICY "Users view paperwork recipients" ON public.paperwork_assignment_recipients FOR SELECT
USING (user_id = auth.uid() OR public.can_manage_paperwork_assignment(assignment_id, auth.uid()));
CREATE POLICY "Directors manage paperwork recipients" ON public.paperwork_assignment_recipients FOR ALL
USING (public.can_manage_paperwork_assignment(assignment_id, auth.uid())) WITH CHECK (public.can_manage_paperwork_assignment(assignment_id, auth.uid()));
DROP POLICY IF EXISTS "Users can view paperwork submissions" ON public.paperwork_submissions;
DROP POLICY IF EXISTS "Parents can create paperwork submissions" ON public.paperwork_submissions;
DROP POLICY IF EXISTS "Directors can review paperwork submissions" ON public.paperwork_submissions;
CREATE POLICY "Users view paperwork submissions" ON public.paperwork_submissions FOR SELECT
USING (submitted_by = auth.uid() OR public.can_manage_paperwork_assignment(assignment_id, auth.uid()));
CREATE POLICY "Users view paperwork materials" ON public.paperwork_request_materials FOR SELECT
USING (public.is_paperwork_assignment_recipient(request_id, auth.uid()) OR public.can_manage_paperwork_assignment(request_id, auth.uid()));
CREATE POLICY "Users view paperwork attachments" ON public.paperwork_submission_attachments FOR SELECT
USING (EXISTS (SELECT 1 FROM public.paperwork_submissions submission WHERE submission.id = submission_id
              AND (submission.submitted_by = auth.uid() OR public.can_manage_paperwork_assignment(submission.assignment_id, auth.uid()))));
CREATE POLICY "Participants view paperwork feedback" ON public.paperwork_feedback_messages FOR SELECT
USING (sender_id = auth.uid() OR recipient_id = auth.uid() OR public.can_manage_paperwork_assignment(request_id, auth.uid()));
CREATE POLICY "Participants view paperwork events" ON public.paperwork_events FOR SELECT
USING (public.is_paperwork_assignment_recipient(request_id, auth.uid()) OR public.can_manage_paperwork_assignment(request_id, auth.uid()));

REVOKE ALL ON FUNCTION public.create_paperwork_request(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID[], TIMESTAMPTZ, BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.acknowledge_paperwork_request(UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.review_paperwork_submission_v2(UUID, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.waive_paperwork_request(UUID, UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.instantiate_onboarding_requirement(UUID, UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_onboarding_assignment(UUID, UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.approve_google_form_child_intake(UUID, TEXT, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_paperwork_request(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID[], TIMESTAMPTZ, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.acknowledge_paperwork_request(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_paperwork_submission_v2(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.waive_paperwork_request(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_google_form_child_intake(UUID, TEXT, UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$ SELECT 20260913210000::BIGINT; $$;
NOTIFY pgrst, 'reload schema';
COMMIT;
