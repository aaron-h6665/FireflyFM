BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(17);

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000141', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'paperwork-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000142', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'paperwork-parent@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000143', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'learning-teacher@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

INSERT INTO public.profiles (id, display_name) VALUES
    ('10000000-0000-0000-0000-000000000141', 'Paperwork Director'),
    ('10000000-0000-0000-0000-000000000142', 'Paperwork Parent'),
    ('10000000-0000-0000-0000-000000000143', 'Learning Teacher')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

INSERT INTO public.schools (id, name) VALUES
    ('20000000-0000-0000-0000-000000000141', 'Separated Workspaces School'),
    ('20000000-0000-0000-0000-000000000142', 'Unrelated School');

INSERT INTO public.school_memberships (id, school_id, user_id, role, active, access_state) VALUES
    ('30000000-0000-0000-0000-000000000141', '20000000-0000-0000-0000-000000000141', '10000000-0000-0000-0000-000000000141', 'school_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000142', '20000000-0000-0000-0000-000000000141', '10000000-0000-0000-0000-000000000142', 'parent', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000143', '20000000-0000-0000-0000-000000000141', '10000000-0000-0000-0000-000000000143', 'teacher', TRUE, 'full');

-- Membership creation fails closed into onboarding when no published template
-- exists. These fixtures represent already-approved members.
UPDATE public.school_memberships
SET access_state = 'full'
WHERE id IN (
    '30000000-0000-0000-0000-000000000141',
    '30000000-0000-0000-0000-000000000142',
    '30000000-0000-0000-0000-000000000143'
);

SELECT ok(to_regclass('public.paperwork_assignments') IS NOT NULL, 'Paperwork requests have a dedicated table');
SELECT ok(has_function_privilege('authenticated', 'public.fetch_my_paperwork_items(uuid,boolean)', 'EXECUTE'), 'authenticated users can load the unified Paperwork projection');
SELECT ok(NOT has_function_privilege('anon', 'public.create_paperwork_request(uuid,text,text,text,text,uuid,uuid[],timestamptz,boolean)', 'EXECUTE'), 'anonymous users cannot create Paperwork');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000141', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000141"}', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.create_paperwork_request(
        '20000000-0000-0000-0000-000000000141', 'Family handbook',
        'Please acknowledge the current handbook.', 'acknowledgement', 'parent',
        NULL, ARRAY['10000000-0000-0000-0000-000000000142'::UUID], NULL, FALSE
    )$$,
    'a director creates a native acknowledgement in Paperwork'
);
RESET ROLE;

SELECT is((SELECT COUNT(*)::INTEGER FROM public.paperwork_assignments), 1, 'Paperwork request is stored once');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.paperwork_assignment_recipients), 1, 'Paperwork recipient is stored once');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.assignments), 0, 'creating Paperwork creates zero Assignment rows');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000142', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000142"}', TRUE);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.fetch_my_paperwork_items('20000000-0000-0000-0000-000000000141', FALSE)),
    1,
    'the parent sees the request in My Paperwork'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.fetch_my_paperwork_items('20000000-0000-0000-0000-000000000142', FALSE)),
    0,
    'the parent cannot project Paperwork into an unrelated school'
);
SELECT lives_ok(
    $$SELECT * FROM public.acknowledge_paperwork_request(
        (SELECT id FROM public.paperwork_assignments WHERE title = 'Family handbook'),
        'paperwork-domain-ack'
    )$$,
    'the parent completes the acknowledgement without an Assignment submission'
);
SELECT throws_ok(
    $$SELECT * FROM public.create_paperwork_request(
        '20000000-0000-0000-0000-000000000141', 'Unauthorized request', NULL,
        'document_upload', 'parent', NULL,
        ARRAY['10000000-0000-0000-0000-000000000143'::UUID], NULL, TRUE
    )$$,
    'P0001', 'You cannot create paperwork for this school',
    'a parent cannot create Paperwork'
);
RESET ROLE;

SELECT is((SELECT completion_status FROM public.paperwork_assignment_recipients), 'accepted', 'no-review acknowledgement completes natively');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.assignment_submissions), 0, 'native Paperwork completion creates zero Assignment attempts');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000141', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000141"}', TRUE);
SELECT throws_ok(
    $$SELECT * FROM public.create_assignment_v2(
        input_school_id => '20000000-0000-0000-0000-000000000141',
        input_title => 'Misrouted compliance', input_category => 'compliance',
        input_audience_role => 'parent',
        input_recipient_ids => ARRAY['10000000-0000-0000-0000-000000000142'::UUID]
    )$$,
    'P0001', 'Use the Paperwork or Payments workspace for this work',
    'Assignment creation rejects non-learning categories'
);
SELECT throws_ok(
    $$SELECT * FROM public.create_assignment_v2(
        input_school_id => '20000000-0000-0000-0000-000000000141',
        input_title => 'Parent training', input_category => 'training',
        input_audience_role => 'teacher',
        input_recipient_ids => ARRAY['10000000-0000-0000-0000-000000000142'::UUID]
    )$$,
    'P0001', 'Training and curriculum recipients must be active staff',
    'learning Assignments reject parent recipients'
);
SELECT lives_ok(
    $$SELECT * FROM public.create_assignment_v2(
        input_school_id => '20000000-0000-0000-0000-000000000141',
        input_title => 'Staff curriculum', input_category => 'curriculum',
        input_audience_role => 'teacher',
        input_recipient_ids => ARRAY['10000000-0000-0000-0000-000000000143'::UUID]
    )$$,
    'staff curriculum remains available in Assignments'
);
RESET ROLE;

SELECT is((SELECT COUNT(*)::INTEGER FROM public.assignments), 1, 'only the valid learning Assignment is created');

SELECT * FROM finish();
ROLLBACK;
