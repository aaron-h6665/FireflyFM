-- Read-only assignment relationship/RLS smoke test for the seeded Alpha accounts.
-- Prerequisite: create one HQ-owned Alpha assignment that explicitly includes the
-- Alpha director and Alpha teacher, then submit one attempt from each recipient.
-- Run in the Supabase SQL editor as an admin.

BEGIN;

CREATE TEMP TABLE assignment_rls_context AS
SELECT
    assignments.id AS assignment_id,
    hq.id AS hq_id,
    alpha_director.id AS director_id,
    alpha_teacher.id AS teacher_id,
    beta_director.id AS unrelated_director_id,
    director_submission.id AS director_submission_id,
    teacher_submission.id AS teacher_submission_id
FROM public.assignments assignments
JOIN public.schools schools
  ON schools.id = assignments.school_id
JOIN auth.users hq
  ON hq.id = assignments.assigned_by
JOIN auth.users alpha_director
  ON alpha_director.email = 'alpha.director@test.fireflyfm.local'
JOIN auth.users alpha_teacher
  ON alpha_teacher.email = 'alpha.teacher@test.fireflyfm.local'
JOIN auth.users beta_director
  ON beta_director.email = 'beta.director@test.fireflyfm.local'
JOIN LATERAL (
    SELECT submissions.id
    FROM public.assignment_submissions submissions
    WHERE submissions.assignment_id = assignments.id
      AND submissions.submitted_by = alpha_director.id
    ORDER BY submissions.attempt_number DESC
    LIMIT 1
) director_submission ON TRUE
JOIN LATERAL (
    SELECT submissions.id
    FROM public.assignment_submissions submissions
    WHERE submissions.assignment_id = assignments.id
      AND submissions.submitted_by = alpha_teacher.id
    ORDER BY submissions.attempt_number DESC
    LIMIT 1
) teacher_submission ON TRUE
WHERE schools.name = 'FireflyFM Test School Alpha'
  AND hq.email = 'hq.director@test.fireflyfm.local'
  AND EXISTS (
      SELECT 1 FROM public.assignment_recipients recipients
      WHERE recipients.assignment_id = assignments.id
        AND recipients.user_id = alpha_director.id
  )
  AND EXISTS (
      SELECT 1 FROM public.assignment_recipients recipients
      WHERE recipients.assignment_id = assignments.id
        AND recipients.user_id = alpha_teacher.id
  )
ORDER BY assignments.created_at DESC
LIMIT 1;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM assignment_rls_context) THEN
        RAISE EXCEPTION 'Create an HQ-owned Alpha assignment for the Alpha director and teacher and submit one attempt from each before running this test';
    END IF;
END;
$$;

GRANT SELECT ON assignment_rls_context TO authenticated;
SET LOCAL ROLE authenticated;

-- The Alpha director is a recipient, not the owner, on this assignment.
SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT director_id::TEXT FROM assignment_rls_context),
    TRUE
);
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);

DO $$
DECLARE
    context_row RECORD;
BEGIN
    SELECT * INTO context_row FROM assignment_rls_context;

    IF public.can_manage_assignment(context_row.assignment_id, context_row.director_id) THEN
        RAISE EXCEPTION 'Alpha director incorrectly gained management access to the HQ-owned assignment';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.assignment_recipients
        WHERE assignment_id = context_row.assignment_id
          AND user_id = context_row.teacher_id
    ) THEN
        RAISE EXCEPTION 'Alpha director can see the teacher recipient row';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.assignment_submissions
        WHERE assignment_id = context_row.assignment_id
          AND submitted_by = context_row.teacher_id
    ) THEN
        RAISE EXCEPTION 'Alpha director can see the teacher submission on an HQ-owned assignment';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.assignment_submissions
        WHERE id = context_row.director_submission_id
    ) THEN
        RAISE EXCEPTION 'Alpha director cannot see their own submission';
    END IF;
END;
$$;

-- The teacher sees only the teacher recipient row and attempts.
SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT teacher_id::TEXT FROM assignment_rls_context),
    TRUE
);

DO $$
DECLARE
    context_row RECORD;
BEGIN
    SELECT * INTO context_row FROM assignment_rls_context;

    IF EXISTS (
        SELECT 1 FROM public.assignment_recipients
        WHERE assignment_id = context_row.assignment_id
          AND user_id = context_row.director_id
    ) THEN
        RAISE EXCEPTION 'Teacher can see the director recipient row';
    END IF;

    IF public.can_manage_assignment(context_row.assignment_id, context_row.teacher_id) THEN
        RAISE EXCEPTION 'Teacher incorrectly gained management access';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.assignment_submissions
        WHERE id = context_row.director_submission_id
    ) THEN
        RAISE EXCEPTION 'Teacher can see the director submission';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.assignment_submissions
        WHERE id = context_row.teacher_submission_id
    ) THEN
        RAISE EXCEPTION 'Teacher cannot see their own submission';
    END IF;
END;
$$;

-- A director in another school has no relationship to the assignment.
SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT unrelated_director_id::TEXT FROM assignment_rls_context),
    TRUE
);

DO $$
DECLARE
    context_row RECORD;
BEGIN
    SELECT * INTO context_row FROM assignment_rls_context;

    IF EXISTS (SELECT 1 FROM public.assignments WHERE id = context_row.assignment_id) THEN
        RAISE EXCEPTION 'Unrelated director can see the Alpha assignment';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.assignment_submissions
        WHERE assignment_id = context_row.assignment_id
    ) THEN
        RAISE EXCEPTION 'Unrelated director can see assignment submissions';
    END IF;
END;
$$;

-- The HQ creator manages the assignment but is not a recipient unless explicitly added.
SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT hq_id::TEXT FROM assignment_rls_context),
    TRUE
);

DO $$
DECLARE
    context_row RECORD;
BEGIN
    SELECT * INTO context_row FROM assignment_rls_context;

    IF NOT public.can_manage_assignment(context_row.assignment_id, context_row.hq_id) THEN
        RAISE EXCEPTION 'HQ creator cannot manage their own assignment';
    END IF;

    IF public.is_assignment_recipient(context_row.assignment_id, context_row.hq_id) THEN
        RAISE EXCEPTION 'HQ creator unexpectedly became a recipient';
    END IF;

    IF NOT public.can_review_assignment_submission(context_row.teacher_submission_id, context_row.hq_id) THEN
        RAISE EXCEPTION 'HQ creator cannot review the teacher submission';
    END IF;

    IF (SELECT COUNT(*) FROM public.assignment_submissions WHERE assignment_id = context_row.assignment_id) < 2 THEN
        RAISE EXCEPTION 'HQ creator cannot see all recipient attempts';
    END IF;
END;
$$;

RESET ROLE;
ROLLBACK;
