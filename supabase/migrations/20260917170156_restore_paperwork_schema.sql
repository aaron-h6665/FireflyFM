-- Restore Paperwork DDL that was added to an already-applied migration file.
-- The hosted migration ledger contains 20260913210000, but the live database
-- predates the Paperwork columns and RPCs now present in that local file.

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
    ADD CONSTRAINT paperwork_assignments_request_kind_check
        CHECK (request_kind IN ('document_upload', 'acknowledgement')),
    DROP CONSTRAINT IF EXISTS paperwork_assignments_status_check,
    ADD CONSTRAINT paperwork_assignments_status_check
        CHECK (status IN ('draft', 'scheduled', 'published', 'closed', 'archived')),
    DROP CONSTRAINT IF EXISTS paperwork_assignments_audience_role_check,
    ADD CONSTRAINT paperwork_assignments_audience_role_check
        CHECK (audience_role IS NULL OR audience_role IN ('parent', 'teacher', 'school_director'));

CREATE UNIQUE INDEX IF NOT EXISTS idx_paperwork_requests_legacy_assignment
    ON public.paperwork_assignments(legacy_assignment_id)
    WHERE legacy_assignment_id IS NOT NULL;

ALTER TABLE public.paperwork_assignment_recipients
    ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS role_at_request TEXT,
    ADD COLUMN IF NOT EXISTS child_id UUID REFERENCES public.children(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS completion_status TEXT NOT NULL DEFAULT 'not_started',
    ADD COLUMN IF NOT EXISTS viewed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

UPDATE public.paperwork_assignment_recipients
SET user_id = parent_id
WHERE user_id IS NULL;

ALTER TABLE public.paperwork_assignment_recipients
    ALTER COLUMN user_id SET NOT NULL,
    DROP CONSTRAINT IF EXISTS paperwork_assignment_recipients_completion_status_check,
    ADD CONSTRAINT paperwork_assignment_recipients_completion_status_check
        CHECK (completion_status IN ('not_started', 'read', 'submitted', 'resubmitted', 'changes_requested', 'accepted', 'excused', 'overdue')),
    DROP CONSTRAINT IF EXISTS paperwork_assignment_recipients_role_at_request_check,
    ADD CONSTRAINT paperwork_assignment_recipients_role_at_request_check
        CHECK (role_at_request IS NULL OR role_at_request IN ('parent', 'teacher', 'school_director'));

CREATE UNIQUE INDEX IF NOT EXISTS idx_paperwork_request_recipient
    ON public.paperwork_assignment_recipients(assignment_id, user_id);

ALTER TABLE public.paperwork_submissions
    ADD COLUMN IF NOT EXISTS attempt_number INTEGER NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS structured_payload JSONB NOT NULL DEFAULT '{}'::JSONB,
    ADD COLUMN IF NOT EXISTS reviewer_message TEXT,
    ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

UPDATE public.paperwork_submissions
SET status = CASE
    WHEN status = 'flagged' THEN 'changes_requested'
    ELSE status
END;

ALTER TABLE public.paperwork_submissions
    DROP CONSTRAINT IF EXISTS paperwork_submissions_status_check,
    ADD CONSTRAINT paperwork_submissions_status_check
        CHECK (status IN ('submitted', 'resubmitted', 'changes_requested', 'accepted'));

CREATE UNIQUE INDEX IF NOT EXISTS idx_paperwork_submission_mutation
    ON public.paperwork_submissions(assignment_id, submitted_by, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.paperwork_request_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id UUID NOT NULL REFERENCES public.paperwork_assignments(id) ON DELETE CASCADE,
    material_type TEXT NOT NULL DEFAULT 'file' CHECK (material_type IN ('link', 'file', 'mixed')),
    title TEXT,
    url TEXT,
    private_file_path TEXT,
    file_name TEXT,
    content_type TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.paperwork_submission_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    submission_id UUID NOT NULL REFERENCES public.paperwork_submissions(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    private_file_path TEXT NOT NULL,
    file_name TEXT,
    content_type TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.paperwork_feedback_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id UUID NOT NULL REFERENCES public.paperwork_assignments(id) ON DELETE CASCADE,
    submission_id UUID REFERENCES public.paperwork_submissions(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    body TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (sender_id <> recipient_id),
    CHECK (length(btrim(body)) BETWEEN 1 AND 4000)
);

CREATE TABLE IF NOT EXISTS public.paperwork_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id UUID NOT NULL REFERENCES public.paperwork_assignments(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.onboarding_requirement_instances
    ADD COLUMN IF NOT EXISTS paperwork_request_id UUID
        REFERENCES public.paperwork_assignments(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_onboarding_requirement_paperwork_request
    ON public.onboarding_requirement_instances(paperwork_request_id)
    WHERE paperwork_request_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.can_submit_paperwork_assignment(
    assignment_uuid UUID,
    school_uuid UUID,
    user_uuid UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.paperwork_assignments request
        JOIN public.paperwork_assignment_recipients recipient
          ON recipient.assignment_id = request.id
        WHERE request.id = assignment_uuid
          AND request.school_id = school_uuid
          AND recipient.user_id = user_uuid
          AND request.status IN ('published', 'closed')
    );
$$;

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

CREATE OR REPLACE FUNCTION public.acknowledge_paperwork_request(
    input_request_id UUID,
    input_idempotency_key TEXT
)
RETURNS SETOF public.paperwork_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    request public.paperwork_assignments%ROWTYPE;
    saved public.paperwork_submissions%ROWTYPE;
BEGIN
    SELECT * INTO request
    FROM public.paperwork_assignments
    WHERE id = input_request_id
    FOR UPDATE;

    IF request.request_kind <> 'acknowledgement'
       OR NOT public.can_submit_paperwork_assignment(request.id, request.school_id, actor) THEN
        RAISE EXCEPTION 'You cannot acknowledge this paperwork';
    END IF;

    INSERT INTO public.paperwork_submissions (
        assignment_id, school_id, submitted_by, status,
        structured_payload, attempt_number, idempotency_key
    ) VALUES (
        request.id, request.school_id, actor,
        CASE WHEN request.requires_review THEN 'submitted' ELSE 'accepted' END,
        jsonb_build_object('acknowledged', TRUE), 1, input_idempotency_key
    )
    ON CONFLICT (assignment_id, submitted_by, idempotency_key)
        WHERE idempotency_key IS NOT NULL
    DO UPDATE SET idempotency_key = EXCLUDED.idempotency_key
    RETURNING * INTO saved;

    UPDATE public.paperwork_assignment_recipients
    SET completion_status = CASE WHEN request.requires_review THEN 'submitted' ELSE 'accepted' END,
        completed_at = CASE WHEN request.requires_review THEN NULL ELSE NOW() END
    WHERE assignment_id = request.id
      AND user_id = actor;

    RETURN QUERY SELECT * FROM public.paperwork_submissions WHERE id = saved.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_paperwork_request(
    input_request_id UUID,
    input_file_name TEXT,
    input_file_path TEXT,
    input_idempotency_key TEXT
)
RETURNS SETOF public.paperwork_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    request public.paperwork_assignments%ROWTYPE;
    saved public.paperwork_submissions%ROWTYPE;
    next_attempt INTEGER;
    expected_prefix TEXT;
BEGIN
    SELECT * INTO request
    FROM public.paperwork_assignments
    WHERE id = input_request_id
    FOR UPDATE;

    IF request.request_kind <> 'document_upload'
       OR NOT public.can_submit_paperwork_assignment(request.id, request.school_id, actor) THEN
        RAISE EXCEPTION 'You cannot submit this paperwork';
    END IF;

    expected_prefix := 'schools/' || request.school_id::TEXT
        || '/paperwork_submissions/' || actor::TEXT || '/';
    IF input_file_path IS NULL
       OR LOWER(input_file_path) NOT LIKE LOWER(expected_prefix) || '%' THEN
        RAISE EXCEPTION 'Paperwork upload path is invalid';
    END IF;

    SELECT COALESCE(MAX(attempt_number), 0) + 1
    INTO next_attempt
    FROM public.paperwork_submissions
    WHERE assignment_id = request.id
      AND submitted_by = actor;

    INSERT INTO public.paperwork_submissions (
        assignment_id, school_id, submitted_by, file_name, file_path,
        status, attempt_number, idempotency_key
    ) VALUES (
        request.id, request.school_id, actor, input_file_name, input_file_path,
        CASE WHEN next_attempt = 1 THEN 'submitted' ELSE 'resubmitted' END,
        next_attempt, input_idempotency_key
    )
    ON CONFLICT (assignment_id, submitted_by, idempotency_key)
        WHERE idempotency_key IS NOT NULL
    DO UPDATE SET idempotency_key = EXCLUDED.idempotency_key
    RETURNING * INTO saved;

    INSERT INTO public.paperwork_submission_attachments (
        submission_id, school_id, private_file_path, file_name
    ) VALUES (
        saved.id, request.school_id, input_file_path, input_file_name
    )
    ON CONFLICT DO NOTHING;

    UPDATE public.paperwork_assignment_recipients
    SET completion_status = CASE WHEN next_attempt = 1 THEN 'submitted' ELSE 'resubmitted' END,
        completed_at = NULL
    WHERE assignment_id = request.id
      AND user_id = actor;

    RETURN QUERY SELECT * FROM public.paperwork_submissions WHERE id = saved.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_paperwork_submission_v2(
    input_submission_id UUID,
    input_decision TEXT,
    input_message TEXT DEFAULT NULL
)
RETURNS SETOF public.paperwork_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    saved public.paperwork_submissions%ROWTYPE;
    selected_submission public.paperwork_submissions%ROWTYPE;
    request_id UUID;
    request_status TEXT;
    latest_submission_id UUID;
BEGIN
    SELECT * INTO selected_submission
    FROM public.paperwork_submissions
    WHERE id = input_submission_id
    FOR UPDATE;

    SELECT request.id, request.status
    INTO request_id, request_status
    FROM public.paperwork_assignments request
    WHERE request.id = selected_submission.assignment_id
    FOR UPDATE;

    IF selected_submission.id IS NULL
       OR request_id IS NULL
       OR request_status NOT IN ('published', 'closed')
       OR selected_submission.status NOT IN ('submitted', 'resubmitted')
       OR NOT public.can_manage_paperwork_assignment(request_id, actor)
       OR selected_submission.submitted_by = actor THEN
        RAISE EXCEPTION 'You cannot review this paperwork submission';
    END IF;

    SELECT submission.id INTO latest_submission_id
    FROM public.paperwork_submissions submission
    WHERE submission.assignment_id = selected_submission.assignment_id
      AND submission.submitted_by = selected_submission.submitted_by
    ORDER BY submission.attempt_number DESC,
             submission.submitted_at DESC NULLS LAST,
             submission.id DESC
    LIMIT 1;

    IF latest_submission_id IS DISTINCT FROM selected_submission.id THEN
        RAISE EXCEPTION 'Only the latest paperwork submission can be reviewed';
    END IF;
    IF input_decision NOT IN ('accepted', 'changes_requested') THEN
        RAISE EXCEPTION 'Paperwork review decision is invalid';
    END IF;
    IF input_decision = 'changes_requested'
       AND NULLIF(btrim(COALESCE(input_message, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Explain the requested changes';
    END IF;

    UPDATE public.paperwork_submissions
    SET status = input_decision,
        reviewer_message = NULLIF(btrim(COALESCE(input_message, '')), ''),
        reviewed_by = actor,
        reviewed_at = NOW()
    WHERE id = selected_submission.id
    RETURNING * INTO saved;

    UPDATE public.paperwork_assignment_recipients
    SET completion_status = input_decision,
        completed_at = CASE WHEN input_decision = 'accepted' THEN NOW() ELSE NULL END
    WHERE assignment_id = saved.assignment_id
      AND user_id = saved.submitted_by;

    RETURN QUERY SELECT * FROM public.paperwork_submissions WHERE id = saved.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_paperwork_completion_to_onboarding()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.completion_status NOT IN ('accepted', 'excused') THEN
        RETURN NEW;
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM public.paperwork_assignment_recipients recipient
        WHERE recipient.assignment_id = NEW.assignment_id
          AND recipient.completion_status NOT IN ('accepted', 'excused')
    ) THEN
        UPDATE public.onboarding_requirement_instances
        SET status = CASE WHEN NEW.completion_status = 'accepted' THEN 'approved' ELSE 'waived' END,
            completed_at = COALESCE(completed_at, NOW())
        WHERE paperwork_request_id = NEW.assignment_id
          AND status NOT IN ('approved', 'waived');

        UPDATE public.paperwork_assignments
        SET status = 'archived', updated_at = NOW()
        WHERE id = NEW.assignment_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_paperwork_completion_to_onboarding_trigger
    ON public.paperwork_assignment_recipients;
CREATE TRIGGER sync_paperwork_completion_to_onboarding_trigger
AFTER INSERT OR UPDATE OF completion_status
ON public.paperwork_assignment_recipients
FOR EACH ROW
EXECUTE FUNCTION public.sync_paperwork_completion_to_onboarding();

CREATE OR REPLACE FUNCTION public.fetch_my_paperwork_items(
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
    LEFT JOIN public.onboarding_requirement_instances instance_requirement
      ON instance_requirement.paperwork_request_id = request.id
    WHERE (input_school_id IS NULL OR request.school_id = input_school_id)
      AND (
          recipient.user_id = auth.uid()
          OR public.can_manage_paperwork_assignment(request.id, auth.uid())
      )
      AND (
          (input_archived AND request.status = 'archived')
          OR (NOT input_archived AND request.status <> 'archived')
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
        WHERE response.connection_id = connection.id
          AND response.membership_id = membership.id
        ORDER BY response.response_submitted_at DESC NULLS LAST,
                 response.created_at DESC
        LIMIT 1
    ) form_import ON TRUE
    WHERE (input_school_id IS NULL OR instance.school_id = input_school_id)
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

ALTER TABLE public.paperwork_request_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.paperwork_submission_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.paperwork_feedback_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.paperwork_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view paperwork assignments" ON public.paperwork_assignments;
DROP POLICY IF EXISTS "Directors can manage paperwork assignments" ON public.paperwork_assignments;
DROP POLICY IF EXISTS "Users can view paperwork requests" ON public.paperwork_assignments;
DROP POLICY IF EXISTS "Directors manage paperwork requests" ON public.paperwork_assignments;
CREATE POLICY "Users can view paperwork requests"
ON public.paperwork_assignments FOR SELECT
USING (
    public.can_manage_paperwork_assignment(id, auth.uid())
    OR public.is_paperwork_assignment_recipient(id, auth.uid())
);
CREATE POLICY "Directors manage paperwork requests"
ON public.paperwork_assignments FOR ALL
USING (public.can_manage_paperwork_assignment(id, auth.uid()))
WITH CHECK (
    public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
);

DROP POLICY IF EXISTS "Users can view paperwork recipients" ON public.paperwork_assignment_recipients;
DROP POLICY IF EXISTS "Directors can manage paperwork recipients" ON public.paperwork_assignment_recipients;
DROP POLICY IF EXISTS "Users view paperwork recipients" ON public.paperwork_assignment_recipients;
DROP POLICY IF EXISTS "Directors manage paperwork recipients" ON public.paperwork_assignment_recipients;
CREATE POLICY "Users view paperwork recipients"
ON public.paperwork_assignment_recipients FOR SELECT
USING (
    user_id = auth.uid()
    OR parent_id = auth.uid()
    OR public.can_manage_paperwork_assignment(assignment_id, auth.uid())
);
CREATE POLICY "Directors manage paperwork recipients"
ON public.paperwork_assignment_recipients FOR ALL
USING (public.can_manage_paperwork_assignment(assignment_id, auth.uid()))
WITH CHECK (public.can_manage_paperwork_assignment(assignment_id, auth.uid()));

DROP POLICY IF EXISTS "Users can view paperwork submissions" ON public.paperwork_submissions;
DROP POLICY IF EXISTS "Parents can create paperwork submissions" ON public.paperwork_submissions;
DROP POLICY IF EXISTS "Directors can review paperwork submissions" ON public.paperwork_submissions;
DROP POLICY IF EXISTS "Users view paperwork submissions" ON public.paperwork_submissions;
CREATE POLICY "Users view paperwork submissions"
ON public.paperwork_submissions FOR SELECT
USING (
    submitted_by = auth.uid()
    OR public.can_manage_paperwork_assignment(assignment_id, auth.uid())
);

DROP POLICY IF EXISTS "Users view paperwork materials" ON public.paperwork_request_materials;
CREATE POLICY "Users view paperwork materials"
ON public.paperwork_request_materials FOR SELECT
USING (
    public.is_paperwork_assignment_recipient(request_id, auth.uid())
    OR public.can_manage_paperwork_assignment(request_id, auth.uid())
);

DROP POLICY IF EXISTS "Users view paperwork attachments" ON public.paperwork_submission_attachments;
CREATE POLICY "Users view paperwork attachments"
ON public.paperwork_submission_attachments FOR SELECT
USING (
    EXISTS (
        SELECT 1
        FROM public.paperwork_submissions submission
        WHERE submission.id = submission_id
          AND (
              submission.submitted_by = auth.uid()
              OR public.can_manage_paperwork_assignment(submission.assignment_id, auth.uid())
          )
    )
);

GRANT SELECT ON public.paperwork_request_materials TO authenticated;
GRANT SELECT ON public.paperwork_submission_attachments TO authenticated;
GRANT SELECT ON public.paperwork_feedback_messages TO authenticated;
GRANT SELECT ON public.paperwork_events TO authenticated;

REVOKE ALL ON FUNCTION public.create_paperwork_request(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID[], TIMESTAMPTZ, BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.acknowledge_paperwork_request(UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.submit_paperwork_request(UUID, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.review_paperwork_submission_v2(UUID, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fetch_my_paperwork_items(UUID, BOOLEAN) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_paperwork_request(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID[], TIMESTAMPTZ, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.acknowledge_paperwork_request(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_paperwork_request(UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_paperwork_submission_v2(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_paperwork_items(UUID, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT 20260917170156::BIGINT;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
