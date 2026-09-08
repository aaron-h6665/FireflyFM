BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(16);

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'parent@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'other@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'publisher-hq@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'reviewer-hq@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

INSERT INTO public.schools (id, name) VALUES
    ('20000000-0000-0000-0000-000000000001', 'Onboarding Test School'),
    ('20000000-0000-0000-0000-000000000002', 'Second Test School');

INSERT INTO public.school_memberships (id, school_id, user_id, role, active, access_state) VALUES
    ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'parent', TRUE, 'onboarding'),
    ('30000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000003', 'hq_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000004', 'hq_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000005', 'school_director', TRUE, 'onboarding');

-- Reproduce a malformed/generated onboarding assignment whose recipient was
-- also recorded as assigned_by. Recipient status must never grant management.
INSERT INTO public.assignments (
    id, school_id, title, category, audience_role, assigned_by,
    status, visibility, requires_review, allow_resubmission, publish_at
) VALUES (
    '60000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    'Director setup checklist', 'onboarding', 'parent',
    '10000000-0000-0000-0000-000000000001',
    'published', 'assigned', TRUE, TRUE, NOW()
);
INSERT INTO public.assignment_recipients (
    assignment_id, user_id, role_at_assignment, completion_status
) VALUES (
    '60000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'parent', 'not_started'
);

-- A different HQ account published this director template. Role authority,
-- rather than exact creator identity, must still surface the submission.
INSERT INTO public.onboarding_templates (
    id, school_id, target_role, name, status, created_by, published_at
) VALUES (
    '50000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    'school_director', 'Director Setup', 'published',
    '10000000-0000-0000-0000-000000000003', NOW()
);
INSERT INTO public.onboarding_template_requirements (
    id, template_id, position, requirement_type, title, subject_scope
) VALUES (
    '51000000-0000-0000-0000-000000000001',
    '50000000-0000-0000-0000-000000000001',
    0, 'acknowledgement', 'Director policy', 'member'
);
INSERT INTO public.assignments (
    id, school_id, title, category, audience_role, assigned_by,
    status, visibility, requires_review, allow_resubmission, publish_at
) VALUES (
    '60000000-0000-0000-0000-000000000002',
    '20000000-0000-0000-0000-000000000001',
    'Director policy', 'onboarding', 'school_director',
    '10000000-0000-0000-0000-000000000003',
    'published', 'assigned', TRUE, TRUE, NOW()
);
INSERT INTO public.assignment_recipients (
    assignment_id, user_id, role_at_assignment, completion_status
) VALUES (
    '60000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000005',
    'school_director', 'submitted'
);
INSERT INTO public.onboarding_instances (
    id, school_id, membership_id, template_id, status
) VALUES (
    '70000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000005',
    '50000000-0000-0000-0000-000000000001', 'in_progress'
);
INSERT INTO public.onboarding_requirement_instances (
    id, onboarding_instance_id, template_requirement_id, assignment_id, status
) VALUES (
    '71000000-0000-0000-0000-000000000001',
    '70000000-0000-0000-0000-000000000001',
    '51000000-0000-0000-0000-000000000001',
    '60000000-0000-0000-0000-000000000002', 'in_review'
);
INSERT INTO public.assignment_submissions (
    id, assignment_id, school_id, submitted_by, status, submitted_at
) VALUES (
    '72000000-0000-0000-0000-000000000001',
    '60000000-0000-0000-0000-000000000002',
    '20000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000005', 'submitted', NOW()
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', TRUE);
SELECT set_config('request.jwt.claim.email', 'parent@test.fireflyfm.local', TRUE);
SELECT set_config(
    'request.jwt.claims',
    '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000001","email":"parent@test.fireflyfm.local"}',
    TRUE
);

SELECT is(
    public.get_firefly_schema_version(),
    20260907220000::BIGINT,
    'schema reports the Zelle payment hardening version'
);
SELECT ok(
    public.has_school_membership('20000000-0000-0000-0000-000000000001', auth.uid()),
    'onboarding parent retains the school shell relationship'
);
SELECT isnt(
    public.has_full_school_access('20000000-0000-0000-0000-000000000001', auth.uid()),
    TRUE,
    'onboarding parent does not receive full school access'
);
SELECT isnt(
    public.has_school_role(
        '20000000-0000-0000-0000-000000000001',
        auth.uid(),
        ARRAY['parent']
    ),
    TRUE,
    'onboarding membership does not grant normal role management privileges'
);
SELECT isnt(
    public.can_manage_assignment(
        '60000000-0000-0000-0000-000000000001',
        auth.uid()
    ),
    TRUE,
    'onboarding recipient cannot manage its checklist even when assigned_by is malformed'
);
SELECT throws_ok(
    $$SELECT * FROM public.update_assignment_v2(
        '60000000-0000-0000-0000-000000000001', 'Bypassed instructions', NULL, NULL, TRUE, '[]'
    )$$,
    'P0001', 'Only the assignment creator can edit this assignment',
    'malformed creator identity cannot bypass onboarding content permissions'
);
SELECT throws_ok(
    $$SELECT * FROM public.set_assignment_status(
        '60000000-0000-0000-0000-000000000001', 'archived'
    )$$,
    'P0001',
    'You cannot manage this assignment',
    'onboarding recipient cannot archive its checklist'
);
SELECT is(
    (SELECT status FROM public.assignments WHERE id = '60000000-0000-0000-0000-000000000001'),
    'published',
    'rejected lifecycle mutation leaves the checklist published'
);
SELECT throws_ok(
    $$SELECT public.create_child_for_current_parent(
        '20000000-0000-0000-0000-000000000001', 'Avery', 'Firefly', '2022-01-10'
    )$$,
    '42501',
    'permission denied for function create_child_for_current_parent',
    'an onboarding parent cannot directly create a child'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.children WHERE school_id = '20000000-0000-0000-0000-000000000001'),
    0,
    'no child is created before director review'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.child_guardians WHERE guardian_id = auth.uid()),
    0,
    'no guardian relationship is created before director review'
);

RESET ROLE;
INSERT INTO public.role_invites (
    id, school_id, email, role, token_hash, status, expires_at
) VALUES (
    '40000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000002',
    'parent@test.fireflyfm.local',
    'parent',
    encode(extensions.digest('test-role-token', 'sha256'), 'hex'),
    'pending', NOW() + INTERVAL '1 day'
);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', TRUE);
SELECT set_config('request.jwt.claim.email', 'parent@test.fireflyfm.local', TRUE);
SELECT set_config(
    'request.jwt.claims',
    '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000001","email":"parent@test.fireflyfm.local"}',
    TRUE
);

SELECT is(
    (SELECT school_name FROM public.preview_role_invite('test-role-token')),
    'Second Test School',
    'matching invitee can preview the destination school'
);

SELECT set_config('request.jwt.claim.email', 'other@test.fireflyfm.local', TRUE);
SELECT set_config(
    'request.jwt.claims',
    '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000001","email":"other@test.fireflyfm.local"}',
    TRUE
);
SELECT throws_ok(
    $$SELECT * FROM public.preview_role_invite('test-role-token')$$,
    'P0001',
    'This invitation is invalid, expired, or belongs to another account',
    'a different account cannot preview invitation details'
);

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', TRUE);
SELECT set_config('request.jwt.claim.email', 'reviewer-hq@test.fireflyfm.local', TRUE);
SELECT set_config(
    'request.jwt.claims',
    '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000004","email":"reviewer-hq@test.fireflyfm.local"}',
    TRUE
);
SELECT is(
    (
        SELECT COUNT(*)::INTEGER
        FROM public.fetch_my_assignment_review_queue_v2(
            '20000000-0000-0000-0000-000000000001',
            ARRAY['onboarding'],
            FALSE
        )
        WHERE assignment_id = '60000000-0000-0000-0000-000000000002'
    ),
    1,
    'authorized HQ reviewer sees director submissions created by another HQ account'
);

SELECT lives_ok(
    $$SELECT * FROM public.update_assignment_v2(
        '60000000-0000-0000-0000-000000000002', 'Reviewed director policy', NULL, NULL, TRUE, '[]'
    )$$,
    'authorized HQ manager can edit a checklist created by a different HQ account'
);
SELECT lives_ok(
    $$SELECT * FROM public.set_assignment_status(
        '60000000-0000-0000-0000-000000000002', 'closed'
    )$$,
    'authorized HQ manager can close a checklist created by a different HQ account'
);
SELECT * FROM finish();
ROLLBACK;
