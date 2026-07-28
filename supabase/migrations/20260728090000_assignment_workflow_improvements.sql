BEGIN;

CREATE TABLE IF NOT EXISTS public.assignment_revisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL REFERENCES public.assignments(id) ON DELETE CASCADE,
    revision_number INTEGER NOT NULL CHECK (revision_number > 0),
    title TEXT NOT NULL,
    description TEXT,
    due_at TIMESTAMPTZ,
    allow_resubmission BOOLEAN NOT NULL DEFAULT TRUE,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (assignment_id, revision_number)
);

CREATE TABLE IF NOT EXISTS public.assignment_revision_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    revision_id UUID NOT NULL REFERENCES public.assignment_revisions(id) ON DELETE CASCADE,
    material_type TEXT NOT NULL DEFAULT 'file' CHECK (material_type IN ('article', 'link', 'image', 'video', 'file', 'mixed')),
    title TEXT,
    url TEXT,
    private_file_path TEXT,
    file_name TEXT,
    content_type TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.assignments
    ADD COLUMN IF NOT EXISTS current_revision_id UUID REFERENCES public.assignment_revisions(id) ON DELETE SET NULL;

ALTER TABLE public.assignment_submissions
    ADD COLUMN IF NOT EXISTS assignment_revision_id UUID REFERENCES public.assignment_revisions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_assignment_revisions_assignment
    ON public.assignment_revisions(assignment_id, revision_number DESC);
CREATE INDEX IF NOT EXISTS idx_assignment_revision_materials_revision
    ON public.assignment_revision_materials(revision_id);
CREATE INDEX IF NOT EXISTS idx_assignment_submissions_revision
    ON public.assignment_submissions(assignment_revision_id);

ALTER TABLE public.assignment_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assignment_revision_materials ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Assignment participants can view revisions" ON public.assignment_revisions;
CREATE POLICY "Assignment participants can view revisions"
    ON public.assignment_revisions FOR SELECT
    USING (public.can_view_assignment(assignment_id, auth.uid()));

DROP POLICY IF EXISTS "Assignment participants can view revision materials" ON public.assignment_revision_materials;
CREATE POLICY "Assignment participants can view revision materials"
    ON public.assignment_revision_materials FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.assignment_revisions revision
            WHERE revision.id = assignment_revision_materials.revision_id
              AND public.can_view_assignment(revision.assignment_id, auth.uid())
        )
    );

INSERT INTO public.assignment_revisions (
    assignment_id, revision_number, title, description, due_at,
    allow_resubmission, created_by, created_at
)
SELECT assignment.id, 1, assignment.title, assignment.description, assignment.due_at,
       COALESCE(assignment.allow_resubmission, TRUE), assignment.assigned_by,
       COALESCE(assignment.updated_at, assignment.created_at, NOW())
FROM public.assignments assignment
WHERE NOT EXISTS (
    SELECT 1 FROM public.assignment_revisions revision
    WHERE revision.assignment_id = assignment.id
);

INSERT INTO public.assignment_revision_materials (
    revision_id, material_type, title, url, private_file_path,
    file_name, content_type, created_at
)
SELECT revision.id, material.material_type, material.title, material.url,
       material.private_file_path, material.file_name, material.content_type,
       COALESCE(material.created_at, revision.created_at)
FROM public.assignment_revisions revision
JOIN public.assignment_materials material ON material.assignment_id = revision.assignment_id
WHERE revision.revision_number = 1
  AND NOT EXISTS (
      SELECT 1 FROM public.assignment_revision_materials existing
      WHERE existing.revision_id = revision.id
  );

UPDATE public.assignments assignment
SET current_revision_id = revision.id
FROM public.assignment_revisions revision
WHERE revision.assignment_id = assignment.id
  AND revision.revision_number = 1
  AND assignment.current_revision_id IS NULL;

UPDATE public.assignment_submissions submission
SET assignment_revision_id = assignment.current_revision_id
FROM public.assignments assignment
WHERE assignment.id = submission.assignment_id
  AND submission.assignment_revision_id IS NULL;

CREATE OR REPLACE FUNCTION public.snapshot_assignment_revision(
    input_assignment_id UUID,
    input_actor UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    assignment_record public.assignments%ROWTYPE;
    saved_revision public.assignment_revisions%ROWTYPE;
    next_revision INTEGER;
BEGIN
    SELECT * INTO assignment_record
    FROM public.assignments
    WHERE id = input_assignment_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Assignment was not found'; END IF;

    SELECT COALESCE(MAX(revision_number), 0) + 1 INTO next_revision
    FROM public.assignment_revisions
    WHERE assignment_id = input_assignment_id;

    INSERT INTO public.assignment_revisions (
        assignment_id, revision_number, title, description, due_at,
        allow_resubmission, created_by
    ) VALUES (
        assignment_record.id, next_revision, assignment_record.title,
        assignment_record.description, assignment_record.due_at,
        COALESCE(assignment_record.allow_resubmission, TRUE),
        COALESCE(input_actor, auth.uid())
    ) RETURNING * INTO saved_revision;

    INSERT INTO public.assignment_revision_materials (
        revision_id, material_type, title, url, private_file_path,
        file_name, content_type, created_at
    )
    SELECT saved_revision.id, material.material_type, material.title, material.url,
           material.private_file_path, material.file_name, material.content_type,
           COALESCE(material.created_at, NOW())
    FROM public.assignment_materials material
    WHERE material.assignment_id = assignment_record.id;

    UPDATE public.assignments
    SET current_revision_id = saved_revision.id
    WHERE id = assignment_record.id;

    RETURN saved_revision.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_assignment_v2(
    input_assignment_id UUID,
    input_title TEXT,
    input_description TEXT DEFAULT NULL,
    input_due_at TIMESTAMPTZ DEFAULT NULL,
    input_allow_resubmission BOOLEAN DEFAULT TRUE,
    input_materials JSONB DEFAULT '[]'::JSONB
)
RETURNS SETOF public.assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    assignment_record public.assignments%ROWTYPE;
    material JSONB;
    material_url TEXT;
    material_path TEXT;
    expected_prefix TEXT;
    revision_id UUID;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF NULLIF(btrim(COALESCE(input_title, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Assignment title is required';
    END IF;
    IF jsonb_typeof(COALESCE(input_materials, '[]'::JSONB)) <> 'array' THEN
        RAISE EXCEPTION 'Assignment materials must be a JSON array';
    END IF;

    SELECT * INTO assignment_record FROM public.assignments
    WHERE id = input_assignment_id FOR UPDATE;
    IF NOT FOUND OR assignment_record.assigned_by <> actor THEN
        RAISE EXCEPTION 'Only the assignment creator can edit this assignment';
    END IF;
    IF assignment_record.status = 'archived' THEN
        RAISE EXCEPTION 'Archived assignments cannot be edited';
    END IF;
    IF input_due_at IS NOT NULL
       AND input_due_at <= COALESCE(assignment_record.publish_at, assignment_record.created_at, NOW()) THEN
        RAISE EXCEPTION 'The due date must be after the assignment is published';
    END IF;

    expected_prefix := 'schools/' || assignment_record.school_id::TEXT
        || '/assignments/' || assignment_record.id::TEXT || '/materials/';

    FOR material IN SELECT * FROM jsonb_array_elements(COALESCE(input_materials, '[]'::JSONB)) LOOP
        IF COALESCE(material->>'material_type', '') NOT IN ('article', 'link', 'image', 'video', 'file', 'mixed') THEN
            RAISE EXCEPTION 'Material type is invalid';
        END IF;
        material_url := NULLIF(btrim(COALESCE(material->>'url', '')), '');
        material_path := NULLIF(btrim(COALESCE(material->>'private_file_path', '')), '');
        IF material_url IS NOT NULL AND material_url !~* '^https?://' THEN
            RAISE EXCEPTION 'Material links must use http or https';
        END IF;
        IF material_path IS NOT NULL AND LOWER(material_path) NOT LIKE LOWER(expected_prefix) || '%'
           AND NOT EXISTS (
               SELECT 1 FROM public.assignment_materials existing
               WHERE existing.assignment_id = input_assignment_id
                 AND existing.private_file_path = material_path
           ) THEN
            RAISE EXCEPTION 'Assignment material path is invalid';
        END IF;
        IF material_url IS NULL AND material_path IS NULL THEN
            RAISE EXCEPTION 'A material must include a link or private file';
        END IF;
    END LOOP;

    UPDATE public.assignments
    SET title = btrim(input_title),
        description = NULLIF(btrim(COALESCE(input_description, '')), ''),
        due_at = input_due_at,
        allow_resubmission = COALESCE(input_allow_resubmission, TRUE),
        updated_at = NOW()
    WHERE id = input_assignment_id
    RETURNING * INTO assignment_record;

    DELETE FROM public.assignment_materials WHERE assignment_id = input_assignment_id;
    FOR material IN SELECT * FROM jsonb_array_elements(COALESCE(input_materials, '[]'::JSONB)) LOOP
        INSERT INTO public.assignment_materials (
            assignment_id, material_type, title, url, private_file_path,
            file_name, content_type
        ) VALUES (
            input_assignment_id,
            material->>'material_type',
            NULLIF(btrim(COALESCE(material->>'title', '')), ''),
            NULLIF(btrim(COALESCE(material->>'url', '')), ''),
            NULLIF(btrim(COALESCE(material->>'private_file_path', '')), ''),
            NULLIF(btrim(COALESCE(material->>'file_name', '')), ''),
            NULLIF(btrim(COALESCE(material->>'content_type', '')), '')
        );
    END LOOP;

    revision_id := public.snapshot_assignment_revision(input_assignment_id, actor);

    INSERT INTO public.assignment_events (
        assignment_id, school_id, actor_id, event_type, metadata
    ) VALUES (
        assignment_record.id, assignment_record.school_id, actor, 'edited',
        jsonb_build_object(
            'allow_resubmission', assignment_record.allow_resubmission,
            'due_at', assignment_record.due_at,
            'revision_id', revision_id,
            'material_count', jsonb_array_length(COALESCE(input_materials, '[]'::JSONB))
        )
    );

    RETURN QUERY SELECT * FROM public.assignments WHERE id = input_assignment_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.post_assignment_comment_v2(
    input_assignment_id UUID,
    input_recipient_id UUID,
    input_body TEXT,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_feedback_messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    assignment_record public.assignments%ROWTYPE;
    saved_message public.assignment_feedback_messages%ROWTYPE;
    latest_submission_id UUID;
    existing_result_id UUID;
    target_user UUID;
    notification_id UUID;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF NULLIF(btrim(COALESCE(input_body, '')), '') IS NULL THEN RAISE EXCEPTION 'Comment cannot be empty'; END IF;

    SELECT * INTO assignment_record FROM public.assignments WHERE id = input_assignment_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Assignment was not found'; END IF;
    IF assignment_record.status IN ('closed', 'archived') THEN
        RAISE EXCEPTION 'Comments are read-only while this assignment is closed or archived';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.assignment_recipients recipient
        WHERE recipient.assignment_id = input_assignment_id
          AND recipient.user_id = input_recipient_id
    ) THEN RAISE EXCEPTION 'Assignment recipient was not found'; END IF;
    IF actor <> input_recipient_id AND actor <> assignment_record.assigned_by THEN
        RAISE EXCEPTION 'Only the recipient and assignment creator can comment';
    END IF;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended(actor::TEXT || ':comment-v2:' || btrim(input_idempotency_key), 0));
        SELECT result_id INTO existing_result_id
        FROM public.assignment_mutation_requests
        WHERE actor_id = actor AND idempotency_key = btrim(input_idempotency_key)
          AND operation = 'comment_v2';
        IF existing_result_id IS NOT NULL THEN
            RETURN QUERY SELECT * FROM public.assignment_feedback_messages WHERE id = existing_result_id;
            RETURN;
        END IF;
    END IF;

    SELECT submission.id INTO latest_submission_id
    FROM public.assignment_submissions submission
    WHERE submission.assignment_id = input_assignment_id
      AND submission.submitted_by = input_recipient_id
    ORDER BY submission.attempt_number DESC, submission.submitted_at DESC
    LIMIT 1;

    INSERT INTO public.assignment_feedback_messages (
        assignment_id, submission_id, school_id, sender_id, recipient_id, body
    ) VALUES (
        assignment_record.id, latest_submission_id, assignment_record.school_id,
        actor, input_recipient_id, btrim(input_body)
    ) RETURNING * INTO saved_message;

    target_user := CASE WHEN actor = input_recipient_id THEN assignment_record.assigned_by ELSE input_recipient_id END;
    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type, metadata)
    VALUES (
        assignment_record.id, assignment_record.school_id, actor, 'commented',
        jsonb_build_object('submission_id', latest_submission_id, 'recipient_id', input_recipient_id)
    );

    IF target_user IS NOT NULL AND target_user <> actor THEN
        INSERT INTO public.notifications (
            school_id, title, body, category, source_type, source_id, created_by, dedupe_key
        ) VALUES (
            assignment_record.school_id, assignment_record.title, btrim(input_body),
            'assignment_feedback', 'assignment', assignment_record.id, actor,
            'assignment:comment:' || saved_message.id::TEXT
        ) RETURNING id INTO notification_id;
        INSERT INTO public.notification_recipients (notification_id, user_id)
        VALUES (notification_id, target_user) ON CONFLICT DO NOTHING;
    END IF;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        INSERT INTO public.assignment_mutation_requests (actor_id, idempotency_key, operation, result_id)
        VALUES (actor, btrim(input_idempotency_key), 'comment_v2', saved_message.id);
    END IF;
    RETURN QUERY SELECT * FROM public.assignment_feedback_messages WHERE id = saved_message.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_assignment_submission_score(
    input_submission_id UUID,
    input_score INTEGER DEFAULT NULL,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    submission_record public.assignment_submissions%ROWTYPE;
    assignment_record public.assignments%ROWTYPE;
    old_score INTEGER;
    existing_result_id UUID;
    notification_id UUID;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF input_score IS NOT NULL AND (input_score < 1 OR input_score > 10) THEN
        RAISE EXCEPTION 'Score must be between 1 and 10';
    END IF;
    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended(actor::TEXT || ':score:' || btrim(input_idempotency_key), 0));
        SELECT result_id INTO existing_result_id FROM public.assignment_mutation_requests
        WHERE actor_id = actor AND idempotency_key = btrim(input_idempotency_key)
          AND operation = 'score_update';
        IF existing_result_id IS NOT NULL THEN
            RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = existing_result_id;
            RETURN;
        END IF;
    END IF;

    SELECT * INTO submission_record FROM public.assignment_submissions
    WHERE id = input_submission_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Assignment submission was not found'; END IF;
    SELECT * INTO assignment_record FROM public.assignments WHERE id = submission_record.assignment_id;
    IF assignment_record.assigned_by <> actor THEN
        RAISE EXCEPTION 'Only the assignment creator can update a score';
    END IF;
    IF submission_record.reviewed_at IS NULL THEN
        RAISE EXCEPTION 'A pending submission must be reviewed before its score can be changed';
    END IF;

    old_score := submission_record.score;
    UPDATE public.assignment_submissions SET score = input_score
    WHERE id = input_submission_id RETURNING * INTO submission_record;

    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type, metadata)
    VALUES (
        assignment_record.id, assignment_record.school_id, actor, 'score_updated',
        jsonb_build_object(
            'submission_id', submission_record.id,
            'recipient_id', submission_record.submitted_by,
            'attempt_number', submission_record.attempt_number,
            'old_score', old_score,
            'new_score', input_score
        )
    );

    INSERT INTO public.notifications (
        school_id, title, body, category, source_type, source_id, created_by, dedupe_key
    ) VALUES (
        assignment_record.school_id, assignment_record.title,
        CASE WHEN input_score IS NULL THEN 'Your score was cleared.' ELSE 'Your score is now ' || input_score::TEXT || '/10.' END,
        'assignment_reviewed', 'assignment', assignment_record.id, actor,
        'assignment:score:' || gen_random_uuid()::TEXT
    ) RETURNING id INTO notification_id;
    INSERT INTO public.notification_recipients (notification_id, user_id)
    VALUES (notification_id, submission_record.submitted_by) ON CONFLICT DO NOTHING;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        INSERT INTO public.assignment_mutation_requests (actor_id, idempotency_key, operation, result_id)
        VALUES (actor, btrim(input_idempotency_key), 'score_update', submission_record.id);
    END IF;
    RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = submission_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fetch_my_assignment_agenda_v2(
    input_categories TEXT[] DEFAULT NULL,
    input_archived BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    assignment_id UUID, school_id UUID, school_name TEXT, child_id UUID,
    title TEXT, description TEXT, category TEXT, due_at TIMESTAMPTZ,
    assigned_by UUID, created_at TIMESTAMPTZ, lifecycle_status TEXT,
    completion_status TEXT, viewed_at TIMESTAMPTZ, acknowledged_at TIMESTAMPTZ,
    has_unread_feedback BOOLEAN, submitted_at TIMESTAMPTZ, review_status TEXT,
    reviewed_at TIMESTAMPTZ, reviewer_message TEXT, child_first_name TEXT,
    child_last_name TEXT, material_count BIGINT, submission_count BIGINT,
    recipient_count BIGINT, needs_review_count BIGINT, changes_requested_count BIGINT,
    not_started_count BIGINT, overdue_count BIGINT, complete_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT assignment.id, assignment.school_id, school.name, assignment.child_id,
           assignment.title, assignment.description, assignment.category, assignment.due_at,
           assignment.assigned_by, assignment.created_at, assignment.status,
           recipient.completion_status, recipient.viewed_at, receipt.checked_at,
           EXISTS (
               SELECT 1 FROM public.assignment_feedback_messages feedback
               WHERE feedback.assignment_id = assignment.id
                 AND feedback.recipient_id = auth.uid()
                 AND feedback.sender_id <> auth.uid()
                 AND feedback.created_at > COALESCE(recipient.viewed_at, '-infinity'::TIMESTAMPTZ)
           ),
           latest.submitted_at, latest.status, latest.reviewed_at, latest.reviewer_message,
           child.first_name, child.last_name,
           (SELECT COUNT(*) FROM public.assignment_materials material WHERE material.assignment_id = assignment.id),
           (SELECT COUNT(*) FROM public.assignment_submissions submission WHERE submission.assignment_id = assignment.id AND submission.submitted_by = auth.uid()),
           1::BIGINT, NULL::BIGINT, NULL::BIGINT, NULL::BIGINT, NULL::BIGINT, NULL::BIGINT
    FROM public.assignment_recipients recipient
    JOIN public.assignments assignment ON assignment.id = recipient.assignment_id
    JOIN public.schools school ON school.id = assignment.school_id
    LEFT JOIN public.assignment_read_receipts receipt ON receipt.assignment_id = assignment.id AND receipt.user_id = auth.uid()
    LEFT JOIN LATERAL (
        SELECT submission.submitted_at, submission.status, submission.reviewed_at, submission.reviewer_message
        FROM public.assignment_submissions submission
        WHERE submission.assignment_id = assignment.id AND submission.submitted_by = auth.uid()
        ORDER BY submission.attempt_number DESC, submission.submitted_at DESC LIMIT 1
    ) latest ON TRUE
    LEFT JOIN public.children child ON child.id = assignment.child_id
    WHERE recipient.user_id = auth.uid()
      AND ((input_archived AND assignment.status = 'archived') OR
           (NOT input_archived AND assignment.status IN ('published', 'closed', 'scheduled')))
      AND (assignment.status <> 'scheduled' OR assignment.publish_at <= NOW())
      AND (input_categories IS NULL OR cardinality(input_categories) = 0 OR assignment.category = ANY(input_categories))
    ORDER BY assignment.due_at NULLS LAST, assignment.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.fetch_my_assignment_review_queue_v2(
    input_school_id UUID,
    input_categories TEXT[] DEFAULT NULL,
    input_archived BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    assignment_id UUID, school_id UUID, school_name TEXT, child_id UUID,
    title TEXT, description TEXT, category TEXT, due_at TIMESTAMPTZ,
    assigned_by UUID, created_at TIMESTAMPTZ, lifecycle_status TEXT,
    completion_status TEXT, viewed_at TIMESTAMPTZ, acknowledged_at TIMESTAMPTZ,
    has_unread_feedback BOOLEAN, submitted_at TIMESTAMPTZ, review_status TEXT,
    reviewed_at TIMESTAMPTZ, reviewer_message TEXT, child_first_name TEXT,
    child_last_name TEXT, material_count BIGINT, submission_count BIGINT,
    recipient_count BIGINT, needs_review_count BIGINT, changes_requested_count BIGINT,
    not_started_count BIGINT, overdue_count BIGINT, complete_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH latest AS (
        SELECT DISTINCT ON (assignment_id, submitted_by)
            assignment_id, submitted_by, status, submitted_at, reviewed_at
        FROM public.assignment_submissions
        ORDER BY assignment_id, submitted_by, attempt_number DESC, submitted_at DESC
    )
    SELECT assignment.id, assignment.school_id, school.name, assignment.child_id,
           assignment.title, assignment.description, assignment.category, assignment.due_at,
           assignment.assigned_by, assignment.created_at, assignment.status,
           CASE
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status = 'changes_requested') > 0 THEN 'changes_requested'
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status IN ('submitted', 'resubmitted')) > 0 THEN 'submitted'
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status = 'accepted') = COUNT(DISTINCT recipient.user_id)
                    AND COUNT(DISTINCT recipient.user_id) > 0 THEN 'accepted'
               ELSE 'not_started'
           END,
           NULL::TIMESTAMPTZ, NULL::TIMESTAMPTZ, FALSE, MAX(latest.submitted_at),
           CASE
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status = 'changes_requested') > 0 THEN 'changes_requested'
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status IN ('submitted', 'resubmitted')) > 0 THEN 'submitted'
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status = 'accepted') > 0 THEN 'accepted'
               ELSE NULL
           END,
           MAX(latest.reviewed_at), NULL::TEXT, child.first_name, child.last_name,
           (SELECT COUNT(*) FROM public.assignment_materials material WHERE material.assignment_id = assignment.id),
           COUNT(DISTINCT latest.submitted_by), COUNT(DISTINCT recipient.user_id),
           COUNT(DISTINCT latest.submitted_by) FILTER (WHERE latest.status IN ('submitted', 'resubmitted')),
           COUNT(DISTINCT latest.submitted_by) FILTER (WHERE latest.status = 'changes_requested'),
           COUNT(DISTINCT recipient.user_id) FILTER (WHERE latest.submitted_by IS NULL),
           COUNT(DISTINCT recipient.user_id) FILTER (WHERE assignment.due_at < NOW() AND (latest.submitted_by IS NULL OR latest.status = 'changes_requested')),
           COUNT(DISTINCT latest.submitted_by) FILTER (WHERE latest.status = 'accepted')
    FROM public.assignments assignment
    JOIN public.schools school ON school.id = assignment.school_id
    LEFT JOIN public.assignment_recipients recipient ON recipient.assignment_id = assignment.id
    LEFT JOIN latest ON latest.assignment_id = assignment.id AND latest.submitted_by = recipient.user_id
    LEFT JOIN public.children child ON child.id = assignment.child_id
    WHERE assignment.school_id = input_school_id
      AND assignment.assigned_by = auth.uid()
      AND ((input_archived AND assignment.status = 'archived') OR (NOT input_archived AND assignment.status <> 'archived'))
      AND (input_categories IS NULL OR cardinality(input_categories) = 0 OR assignment.category = ANY(input_categories))
    GROUP BY assignment.id, school.name, child.first_name, child.last_name
    ORDER BY MAX(latest.submitted_at) DESC NULLS LAST, assignment.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.set_assignment_status(
    input_assignment_id UUID,
    input_status TEXT
)
RETURNS SETOF public.assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    assignment_record public.assignments%ROWTYPE;
    previous_status TEXT;
    event_name TEXT;
    notification_id UUID;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF input_status NOT IN ('published', 'closed', 'archived') THEN
        RAISE EXCEPTION 'Status must be published, closed, or archived';
    END IF;
    SELECT * INTO assignment_record FROM public.assignments
    WHERE id = input_assignment_id FOR UPDATE;
    IF NOT FOUND OR assignment_record.assigned_by <> actor THEN
        RAISE EXCEPTION 'Only the assignment creator can change its lifecycle';
    END IF;
    IF assignment_record.status = input_status THEN
        RETURN QUERY SELECT * FROM public.assignments WHERE id = input_assignment_id; RETURN;
    END IF;
    previous_status := assignment_record.status;
    IF previous_status = 'archived' AND input_status <> 'closed' THEN
        RAISE EXCEPTION 'Archived assignments must be restored to closed';
    END IF;
    IF previous_status = 'closed' AND input_status = 'archived' THEN event_name := 'archived';
    ELSIF previous_status = 'closed' AND input_status = 'published' THEN event_name := 'reopened';
    ELSIF previous_status = 'archived' AND input_status = 'closed' THEN event_name := 'restored';
    ELSE event_name := input_status; END IF;

    UPDATE public.assignments
    SET status = input_status,
        publish_at = CASE WHEN input_status = 'published' THEN COALESCE(publish_at, NOW()) ELSE publish_at END,
        updated_at = NOW()
    WHERE id = input_assignment_id RETURNING * INTO assignment_record;

    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type, metadata)
    VALUES (assignment_record.id, assignment_record.school_id, actor, event_name,
            jsonb_build_object('previous_status', previous_status, 'new_status', input_status));

    INSERT INTO public.notifications (
        school_id, title, body, category, source_type, source_id, created_by, dedupe_key
    ) VALUES (
        assignment_record.school_id, assignment_record.title,
        CASE event_name
            WHEN 'closed' THEN 'This assignment is now closed and read-only.'
            WHEN 'reopened' THEN 'This assignment has reopened.'
            WHEN 'archived' THEN 'This assignment was archived.'
            WHEN 'restored' THEN 'This assignment was restored as closed.'
            ELSE 'This assignment is now available.'
        END,
        'assignment_lifecycle', 'assignment', assignment_record.id, actor,
        'assignment:lifecycle:' || gen_random_uuid()::TEXT
    ) RETURNING id INTO notification_id;
    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT notification_id, recipient.user_id FROM public.assignment_recipients recipient
    WHERE recipient.assignment_id = assignment_record.id ON CONFLICT DO NOTHING;

    RETURN QUERY SELECT * FROM public.assignments WHERE id = assignment_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_assignment_with_payload(
    input_assignment_id UUID,
    input_structured_payload JSONB DEFAULT '{}'::JSONB,
    input_feedback_text TEXT DEFAULT NULL,
    input_attachments JSONB DEFAULT '[]'::JSONB,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    saved_submission public.assignment_submissions%ROWTYPE;
    revision_id UUID;
BEGIN
    IF jsonb_typeof(COALESCE(input_structured_payload, '{}'::JSONB)) <> 'object' THEN
        RAISE EXCEPTION 'Structured answers must be a JSON object';
    END IF;
    SELECT current_revision_id INTO revision_id FROM public.assignments WHERE id = input_assignment_id;
    IF revision_id IS NULL THEN revision_id := public.snapshot_assignment_revision(input_assignment_id, auth.uid()); END IF;
    SELECT * INTO saved_submission FROM public.submit_assignment_v2(
        input_assignment_id, input_feedback_text, input_attachments, input_idempotency_key
    );
    UPDATE public.assignment_submissions
    SET structured_payload = CASE
            WHEN structured_payload = '{}'::JSONB THEN COALESCE(input_structured_payload, '{}'::JSONB)
            ELSE structured_payload END,
        assignment_revision_id = COALESCE(assignment_revision_id, revision_id)
    WHERE id = saved_submission.id RETURNING * INTO saved_submission;
    RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = saved_submission.id;
END;
$$;

-- Compatibility entry points keep older app releases revision-aware and apply
-- the same lifecycle checks as the versioned APIs.
CREATE OR REPLACE FUNCTION public.update_assignment_details(
    input_assignment_id UUID,
    input_title TEXT,
    input_description TEXT DEFAULT NULL,
    input_due_at TIMESTAMPTZ DEFAULT NULL,
    input_allow_resubmission BOOLEAN DEFAULT TRUE
)
RETURNS SETOF public.assignments
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT * FROM public.update_assignment_v2(
        input_assignment_id,
        input_title,
        input_description,
        input_due_at,
        input_allow_resubmission,
        COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'material_type', material.material_type,
                'title', material.title,
                'url', material.url,
                'private_file_path', material.private_file_path,
                'file_name', material.file_name,
                'content_type', material.content_type
            ) ORDER BY material.created_at, material.id)
            FROM public.assignment_materials material
            WHERE material.assignment_id = input_assignment_id
        ), '[]'::JSONB)
    );
$$;

CREATE OR REPLACE FUNCTION public.post_assignment_comment(
    input_submission_id UUID,
    input_body TEXT,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_feedback_messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    submission_record public.assignment_submissions%ROWTYPE;
BEGIN
    SELECT * INTO submission_record
    FROM public.assignment_submissions
    WHERE id = input_submission_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assignment submission was not found';
    END IF;

    RETURN QUERY
    SELECT * FROM public.post_assignment_comment_v2(
        submission_record.assignment_id,
        submission_record.submitted_by,
        input_body,
        input_idempotency_key
    );
END;
$$;

REVOKE ALL ON FUNCTION public.snapshot_assignment_revision(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_assignment_v2(UUID, TEXT, TEXT, TIMESTAMPTZ, BOOLEAN, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.post_assignment_comment_v2(UUID, UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_assignment_submission_score(UUID, INTEGER, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fetch_my_assignment_agenda_v2(TEXT[], BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fetch_my_assignment_review_queue_v2(UUID, TEXT[], BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_assignment_v2(UUID, TEXT, TEXT, TIMESTAMPTZ, BOOLEAN, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.post_assignment_comment_v2(UUID, UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_assignment_submission_score(UUID, INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_assignment_agenda_v2(TEXT[], BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_assignment_review_queue_v2(UUID, TEXT[], BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260728090000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
