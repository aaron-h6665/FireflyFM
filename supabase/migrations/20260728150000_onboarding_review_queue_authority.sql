-- Keep onboarding review queues aligned with notification/detail authority.
-- The authorized role reviewer may differ from the account that originally
-- published the template and was recorded as assignments.assigned_by.
BEGIN;

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
           COUNT(DISTINCT recipient.user_id) FILTER (
               WHERE assignment.due_at < NOW()
                 AND (latest.submitted_by IS NULL OR latest.status = 'changes_requested')
           ),
           COUNT(DISTINCT latest.submitted_by) FILTER (WHERE latest.status = 'accepted')
    FROM public.assignments assignment
    JOIN public.schools school ON school.id = assignment.school_id
    LEFT JOIN public.assignment_recipients recipient ON recipient.assignment_id = assignment.id
    LEFT JOIN latest ON latest.assignment_id = assignment.id AND latest.submitted_by = recipient.user_id
    LEFT JOIN public.children child ON child.id = assignment.child_id
    WHERE assignment.school_id = input_school_id
      AND public.can_review_assignment(assignment.id, auth.uid())
      AND ((input_archived AND assignment.status = 'archived') OR (NOT input_archived AND assignment.status <> 'archived'))
      AND (input_categories IS NULL OR cardinality(input_categories) = 0 OR assignment.category = ANY(input_categories))
    GROUP BY assignment.id, school.name, child.first_name, child.last_name
    ORDER BY MAX(latest.submitted_at) DESC NULLS LAST, assignment.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260728150000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
