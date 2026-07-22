-- Qualify PL/pgSQL references that can otherwise resolve to either a function
-- parameter or a table column. These definitions preserve existing behavior.

-- The legacy hosted project has the standard Supabase Data API DML grants,
-- with access constrained by RLS. Capture them so a clean rebuild behaves like
-- the hosted project. Every public table is verified to have RLS enabled.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public
TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES
TO anon, authenticated, service_role;

-- CREATE TABLE IF NOT EXISTS did not add these baseline constraints/defaults
-- to the pre-existing hosted tables. Reconcile them without weakening the
-- local baseline. Hosted values were checked before this migration was added.
DO $constraints$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'curriculum_resources_material_type_check'
          AND conrelid = 'public.curriculum_resources'::regclass
    ) THEN
        ALTER TABLE public.curriculum_resources
            ADD CONSTRAINT curriculum_resources_material_type_check
            CHECK (material_type IN ('article', 'link', 'image', 'video', 'file', 'mixed'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'training_assignments_material_type_check'
          AND conrelid = 'public.training_assignments'::regclass
    ) THEN
        ALTER TABLE public.training_assignments
            ADD CONSTRAINT training_assignments_material_type_check
            CHECK (material_type IN ('article', 'link', 'image', 'video', 'file', 'mixed'));
    END IF;
END;
$constraints$;

ALTER TABLE public.chat_rooms
    ALTER COLUMN invite_hash SET DEFAULT gen_random_uuid()::TEXT;

DROP POLICY IF EXISTS "Users can view their own participant records"
    ON public.chat_participants;
CREATE POLICY "Users can view their own participant records"
    ON public.chat_participants FOR SELECT TO public
    USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.submit_required_document(
    requirement_id UUID,
    file_name TEXT,
    file_path TEXT
)
RETURNS SETOF public.document_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    requirement_record public.onboarding_requirements%ROWTYPE;
    saved_submission public.document_submissions%ROWTYPE;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT *
    INTO requirement_record
    FROM public.onboarding_requirements AS requirements
    WHERE requirements.id = $1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Required document was not found';
    END IF;

    IF NOT public.can_submit_onboarding_requirement($1, actor) THEN
        RAISE EXCEPTION 'You are not assigned to this required document';
    END IF;

    INSERT INTO public.document_submissions (
        requirement_id,
        school_id,
        submitted_by,
        file_name,
        file_path,
        status,
        reviewer_message,
        submitted_at
    )
    VALUES (
        requirement_record.id,
        requirement_record.school_id,
        actor,
        $2,
        $3,
        'submitted',
        NULL,
        NOW()
    )
    ON CONFLICT ON CONSTRAINT document_submissions_requirement_id_submitted_by_key
    DO UPDATE SET
        file_name = EXCLUDED.file_name,
        file_path = EXCLUDED.file_path,
        status = 'submitted',
        reviewer_message = NULL,
        reviewed_by = NULL,
        reviewed_at = NULL,
        submitted_at = NOW()
    RETURNING * INTO saved_submission;

    RETURN QUERY
    SELECT submissions.*
    FROM public.document_submissions AS submissions
    WHERE submissions.id = saved_submission.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_paperwork_assignment(
    assignment_id UUID,
    file_name TEXT,
    file_path TEXT
)
RETURNS SETOF public.paperwork_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    assignment_record public.paperwork_assignments%ROWTYPE;
    existing_submission_id UUID;
    expected_prefix TEXT;
    saved_submission public.paperwork_submissions%ROWTYPE;
    created_notification_id UUID;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT *
    INTO assignment_record
    FROM public.paperwork_assignments AS assignments
    WHERE assignments.id = $1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paperwork assignment was not found';
    END IF;

    IF NOT public.can_submit_paperwork_assignment($1, assignment_record.school_id, actor) THEN
        RAISE EXCEPTION 'You are not assigned to this paperwork';
    END IF;

    expected_prefix := 'schools/'
        || assignment_record.school_id::TEXT
        || '/paperwork_submissions/'
        || actor::TEXT
        || '/';

    IF $3 IS NULL OR LOWER($3) NOT LIKE LOWER(expected_prefix) || '%' THEN
        RAISE EXCEPTION 'Paperwork upload path is invalid';
    END IF;

    SELECT submissions.id
    INTO existing_submission_id
    FROM public.paperwork_submissions AS submissions
    WHERE submissions.assignment_id = assignment_record.id
      AND submissions.submitted_by = actor
    ORDER BY submissions.submitted_at DESC
    LIMIT 1;

    IF existing_submission_id IS NULL THEN
        INSERT INTO public.paperwork_submissions (
            assignment_id,
            school_id,
            submitted_by,
            file_name,
            file_path,
            status,
            flag_reason,
            reviewed_by,
            reviewed_at,
            submitted_at
        )
        VALUES (
            assignment_record.id,
            assignment_record.school_id,
            actor,
            $2,
            $3,
            'submitted',
            NULL,
            NULL,
            NULL,
            NOW()
        )
        RETURNING * INTO saved_submission;
    ELSE
        UPDATE public.paperwork_submissions AS submissions
        SET file_name = $2,
            file_path = $3,
            status = 'submitted',
            flag_reason = NULL,
            reviewed_by = NULL,
            reviewed_at = NULL,
            submitted_at = NOW()
        WHERE submissions.id = existing_submission_id
        RETURNING * INTO saved_submission;
    END IF;

    INSERT INTO public.notifications (
        school_id,
        title,
        body,
        category,
        source_type,
        source_id,
        created_by
    )
    VALUES (
        assignment_record.school_id,
        'Paperwork submitted',
        'A parent uploaded paperwork for "' || assignment_record.title || '".',
        'paperwork_submission',
        'paperwork_submission',
        saved_submission.id,
        actor
    )
    RETURNING id INTO created_notification_id;

    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT DISTINCT created_notification_id, memberships.user_id
    FROM public.school_memberships AS memberships
    WHERE memberships.active = TRUE
      AND memberships.user_id <> actor
      AND (
          (
              memberships.school_id = assignment_record.school_id
              AND memberships.role = 'school_director'
          )
          OR memberships.role = 'hq_director'
      )
    ON CONFLICT DO NOTHING;

    RETURN QUERY
    SELECT submissions.*
    FROM public.paperwork_submissions AS submissions
    WHERE submissions.id = saved_submission.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_medication_instruction(
    school_id UUID,
    child_id UUID,
    title TEXT,
    dosage TEXT DEFAULT NULL,
    instructions TEXT DEFAULT NULL,
    scheduled_at TIMESTAMPTZ DEFAULT NOW()
)
RETURNS SETOF public.medication_instructions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    created_instruction public.medication_instructions%ROWTYPE;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.children AS child_records
        WHERE child_records.id = $2
          AND child_records.school_id = $1
          AND public.can_access_child(child_records.id, actor)
    ) THEN
        RAISE EXCEPTION 'You cannot create medication instructions for this child';
    END IF;

    IF NULLIF(TRIM($3), '') IS NULL THEN
        RAISE EXCEPTION 'Medication title is required';
    END IF;

    INSERT INTO public.medication_instructions (
        school_id,
        child_id,
        title,
        dosage,
        instructions,
        scheduled_at,
        created_by
    )
    VALUES ($1, $2, TRIM($3), NULLIF(TRIM($4), ''), NULLIF(TRIM($5), ''), $6, actor)
    RETURNING * INTO created_instruction;

    INSERT INTO public.medication_tasks (school_id, child_id, instruction_id, due_at, status)
    VALUES ($1, $2, created_instruction.id, $6, 'pending');

    INSERT INTO public.notifications (school_id, title, body, category, source_type, source_id, created_by)
    VALUES ($1, 'Medication instruction', TRIM($3), 'medicine_instruction', 'medication_instruction', created_instruction.id, actor);

    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT notifications.id, memberships.user_id
    FROM public.notifications AS notifications
    JOIN public.school_memberships AS memberships
      ON memberships.school_id = notifications.school_id
     AND memberships.active = TRUE
     AND memberships.role IN ('teacher', 'school_director')
    WHERE notifications.source_id = created_instruction.id
      AND notifications.source_type = 'medication_instruction'
    ON CONFLICT DO NOTHING;

    RETURN QUERY
    SELECT instructions.*
    FROM public.medication_instructions AS instructions
    WHERE instructions.id = created_instruction.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260721030000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
