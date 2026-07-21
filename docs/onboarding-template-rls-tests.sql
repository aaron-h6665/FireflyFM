-- Read-only onboarding template/access-gate smoke test.
-- Prerequisite: publish an Alpha parent template, invite Alpha Parent 1, and
-- accept the invitation. For the shared-child assertion, connect Parent 1 and
-- Parent 2 to the same child and include one Each Child requirement.
-- Run in the Supabase SQL editor as an admin.

BEGIN;

CREATE TEMP TABLE onboarding_rls_context AS
SELECT
    schools.id AS school_id,
    memberships.id AS membership_id,
    parents.id AS parent_id,
    hq_director.id AS hq_director_id,
    alpha_director.id AS director_id,
    beta_director.id AS unrelated_director_id,
    instances.id AS onboarding_instance_id,
    instances.template_id,
    requirement_instances.id AS requirement_instance_id,
    requirement_instances.assignment_id
FROM public.schools schools
JOIN auth.users parents
  ON parents.email = 'alpha.parent1@test.fireflyfm.local'
JOIN auth.users alpha_director
  ON alpha_director.email = 'alpha.director@test.fireflyfm.local'
JOIN auth.users hq_director
  ON hq_director.email = 'hq.director@test.fireflyfm.local'
JOIN auth.users beta_director
  ON beta_director.email = 'beta.director@test.fireflyfm.local'
JOIN public.school_memberships memberships
  ON memberships.school_id = schools.id
 AND memberships.user_id = parents.id
 AND memberships.role = 'parent'
 AND memberships.active = TRUE
JOIN public.onboarding_instances instances
  ON instances.membership_id = memberships.id
JOIN public.onboarding_requirement_instances requirement_instances
  ON requirement_instances.onboarding_instance_id = instances.id
WHERE schools.name = 'FireflyFM Test School Alpha'
  AND requirement_instances.assignment_id IS NOT NULL
ORDER BY requirement_instances.created_at
LIMIT 1;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM onboarding_rls_context) THEN
        RAISE EXCEPTION 'Publish and accept the Alpha parent onboarding scenario before running this test';
    END IF;
END;
$$;

GRANT SELECT ON onboarding_rls_context TO authenticated;
SET LOCAL ROLE authenticated;

-- An onboarding parent can reach setup relationships, but the normal school
-- membership predicate remains locked until every requirement is satisfied.
SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT parent_id::TEXT FROM onboarding_rls_context),
    TRUE
);
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);

DO $$
DECLARE
    context_row RECORD;
    access_state_value TEXT;
BEGIN
    SELECT * INTO context_row FROM onboarding_rls_context;
    SELECT access_state INTO access_state_value
    FROM public.school_memberships
    WHERE id = context_row.membership_id;

    IF NOT public.has_school_membership(context_row.school_id, context_row.parent_id) THEN
        RAISE EXCEPTION 'Onboarding parent lost access to the selected school shell';
    END IF;

    IF access_state_value = 'onboarding'
       AND public.is_school_member(context_row.school_id, context_row.parent_id) THEN
        RAISE EXCEPTION 'Onboarding parent incorrectly passed the full-access predicate';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.onboarding_requirement_instances
        WHERE id = context_row.requirement_instance_id
    ) THEN
        RAISE EXCEPTION 'Parent cannot view their onboarding requirement instance';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.assignments
        WHERE id = context_row.assignment_id
    ) THEN
        RAISE EXCEPTION 'Parent cannot open the linked onboarding assignment';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.onboarding_templates
        WHERE id = context_row.template_id
    ) THEN
        RAISE EXCEPTION 'Recipient can read administrator template configuration';
    END IF;
END;
$$;

-- The approved Alpha director manages parent templates and linked reviews.
SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT director_id::TEXT FROM onboarding_rls_context),
    TRUE
);

DO $$
DECLARE
    context_row RECORD;
BEGIN
    SELECT * INTO context_row FROM onboarding_rls_context;

    IF NOT public.is_onboarding_template_manager(context_row.school_id, 'parent', context_row.director_id) THEN
        RAISE EXCEPTION 'Alpha director cannot manage the Alpha parent template';
    END IF;

    IF NOT public.can_review_assignment(context_row.assignment_id, context_row.director_id) THEN
        RAISE EXCEPTION 'Alpha director cannot review the linked parent assignment';
    END IF;
END;
$$;

-- HQ owns director onboarding, but cannot review or edit a school's parent
-- onboarding workflow.
SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT hq_director_id::TEXT FROM onboarding_rls_context),
    TRUE
);

DO $$
DECLARE
    context_row RECORD;
BEGIN
    SELECT * INTO context_row FROM onboarding_rls_context;

    IF public.is_onboarding_template_manager(context_row.school_id, 'parent', context_row.hq_director_id) THEN
        RAISE EXCEPTION 'HQ incorrectly gained parent template authority';
    END IF;

    IF public.can_review_assignment(context_row.assignment_id, context_row.hq_director_id) THEN
        RAISE EXCEPTION 'HQ incorrectly gained parent onboarding review authority';
    END IF;
END;
$$;

-- A director from another school cannot see or manage Alpha setup data.
SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT unrelated_director_id::TEXT FROM onboarding_rls_context),
    TRUE
);

DO $$
DECLARE
    context_row RECORD;
BEGIN
    SELECT * INTO context_row FROM onboarding_rls_context;

    IF public.is_onboarding_template_manager(context_row.school_id, 'parent', context_row.unrelated_director_id) THEN
        RAISE EXCEPTION 'Unrelated director gained Alpha template authority';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.onboarding_requirement_instances
        WHERE id = context_row.requirement_instance_id
    ) THEN
        RAISE EXCEPTION 'Unrelated director can see an Alpha requirement instance';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.assignments
        WHERE id = context_row.assignment_id
    ) THEN
        RAISE EXCEPTION 'Unrelated director can see an Alpha onboarding assignment';
    END IF;
END;
$$;

RESET ROLE;

-- Admin-only structural assertions: invite secrets are hashed and child work
-- is represented by one assignment shared across linked guardian instances.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.role_invites
        WHERE created_at >= NOW() - INTERVAL '30 days'
          AND status = 'pending'
          AND (token IS NOT NULL OR token_hash IS NULL)
    ) THEN
        RAISE EXCEPTION 'A recent pending role invitation stores a recoverable raw token';
    END IF;

    IF EXISTS (
        SELECT
            requirement_instances.child_id,
            requirements.requirement_key
        FROM public.onboarding_requirement_instances requirement_instances
        JOIN public.onboarding_template_requirements requirements
          ON requirements.id = requirement_instances.template_requirement_id
        WHERE requirement_instances.child_id IS NOT NULL
        GROUP BY requirement_instances.child_id, requirements.requirement_key
        HAVING COUNT(DISTINCT requirement_instances.assignment_id) > 1
    ) THEN
        RAISE EXCEPTION 'A child requirement was duplicated instead of shared across guardians';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.onboarding_instances instances
        JOIN public.onboarding_templates templates ON templates.id = instances.template_id
        WHERE templates.status = 'draft'
    ) THEN
        RAISE EXCEPTION 'An active onboarding instance references a mutable draft';
    END IF;
END;
$$;

ROLLBACK;
