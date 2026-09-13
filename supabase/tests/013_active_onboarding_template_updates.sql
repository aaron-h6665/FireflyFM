BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT no_plan();

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000131', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'active-update-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000132', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'active-update-hq@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000133', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'active-update-parent@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000134', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'active-update-teacher@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000135', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'active-update-new-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000136', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'future-update-parent@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000137', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'future-update-teacher@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000138', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'future-update-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

INSERT INTO public.schools (id, name)
VALUES ('20000000-0000-0000-0000-000000000131', 'Active Update School');

INSERT INTO public.school_memberships (id, school_id, user_id, role, active, access_state)
VALUES
    ('30000000-0000-0000-0000-000000000131', '20000000-0000-0000-0000-000000000131', '10000000-0000-0000-0000-000000000131', 'school_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000132', '20000000-0000-0000-0000-000000000131', '10000000-0000-0000-0000-000000000132', 'hq_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000133', '20000000-0000-0000-0000-000000000131', '10000000-0000-0000-0000-000000000133', 'parent', TRUE, 'onboarding'),
    ('30000000-0000-0000-0000-000000000134', '20000000-0000-0000-0000-000000000131', '10000000-0000-0000-0000-000000000134', 'teacher', TRUE, 'onboarding'),
    ('30000000-0000-0000-0000-000000000135', '20000000-0000-0000-0000-000000000131', '10000000-0000-0000-0000-000000000135', 'school_director', FALSE, 'onboarding');

INSERT INTO public.onboarding_templates (id, school_id, target_role, name, version, status, created_by, published_at)
VALUES
    ('40000000-0000-0000-0000-000000000131', '20000000-0000-0000-0000-000000000131', 'parent', 'Parent V1', 1, 'published', '10000000-0000-0000-0000-000000000131', NOW()),
    ('40000000-0000-0000-0000-000000000132', '20000000-0000-0000-0000-000000000131', 'teacher', 'Teacher V1', 1, 'published', '10000000-0000-0000-0000-000000000131', NOW()),
    ('40000000-0000-0000-0000-000000000133', '20000000-0000-0000-0000-000000000131', 'school_director', 'Director V1', 1, 'published', '10000000-0000-0000-0000-000000000132', NOW()),
    ('40000000-0000-0000-0000-000000000134', '20000000-0000-0000-0000-000000000131', 'parent', 'Parent V2', 2, 'draft', '10000000-0000-0000-0000-000000000131', NULL),
    ('40000000-0000-0000-0000-000000000135', '20000000-0000-0000-0000-000000000131', 'teacher', 'Teacher V2', 2, 'draft', '10000000-0000-0000-0000-000000000131', NULL),
    ('40000000-0000-0000-0000-000000000136', '20000000-0000-0000-0000-000000000131', 'school_director', 'Director V2', 2, 'draft', '10000000-0000-0000-0000-000000000132', NULL);

INSERT INTO public.onboarding_template_requirements (
    id, template_id, requirement_key, position, requirement_type, title, subject_scope, blocks_access, child_record_binding
) VALUES
    ('41000000-0000-0000-0000-000000000131', '40000000-0000-0000-0000-000000000131', '49000000-0000-0000-0000-000000000131', 0, 'document', 'Old parent directions', 'member', TRUE, 'none'),
    ('41000000-0000-0000-0000-000000000132', '40000000-0000-0000-0000-000000000132', '49000000-0000-0000-0000-000000000132', 0, 'document', 'Old teacher directions', 'member', TRUE, 'none'),
    ('41000000-0000-0000-0000-000000000133', '40000000-0000-0000-0000-000000000133', '49000000-0000-0000-0000-000000000133', 0, 'document', 'Old director directions', 'member', TRUE, 'none'),
    ('41000000-0000-0000-0000-000000000134', '40000000-0000-0000-0000-000000000134', '49000000-0000-0000-0000-000000000131', 0, 'document', 'Current parent directions', 'member', TRUE, 'none'),
    ('41000000-0000-0000-0000-000000000135', '40000000-0000-0000-0000-000000000134', '49000000-0000-0000-0000-000000000134', 1, 'document', 'New parent step', 'member', TRUE, 'none'),
    ('41000000-0000-0000-0000-000000000136', '40000000-0000-0000-0000-000000000135', '49000000-0000-0000-0000-000000000132', 0, 'document', 'Current teacher directions', 'member', TRUE, 'none'),
    ('41000000-0000-0000-0000-000000000137', '40000000-0000-0000-0000-000000000135', '49000000-0000-0000-0000-000000000135', 1, 'document', 'New teacher step', 'member', TRUE, 'none'),
    ('41000000-0000-0000-0000-000000000138', '40000000-0000-0000-0000-000000000136', '49000000-0000-0000-0000-000000000133', 0, 'document', 'Current director directions', 'member', TRUE, 'none'),
    ('41000000-0000-0000-0000-000000000139', '40000000-0000-0000-0000-000000000136', '49000000-0000-0000-0000-000000000136', 1, 'document', 'New director step', 'member', TRUE, 'none');

INSERT INTO public.google_form_connections (
    id, school_id, form_role, form_key, form_id, form_url, form_title, status,
    is_required, display_order, form_snapshot, created_by
) VALUES (
    '42000000-0000-0000-0000-000000000131', '20000000-0000-0000-0000-000000000131',
    'parent', 'active-parent-v2', 'active-parent-form',
    'https://docs.google.com/forms/d/e/active-update/viewform', 'Current parent directions',
    'connected', TRUE, 0, '{}'::JSONB, '10000000-0000-0000-0000-000000000131'
), (
    '42000000-0000-0000-0000-000000000132', '20000000-0000-0000-0000-000000000131',
    'teacher', 'active-teacher-v2', 'active-teacher-form',
    'https://docs.google.com/forms/d/e/active-teacher-update/viewform', 'Current teacher directions',
    'connected', TRUE, 0, '{}'::JSONB, '10000000-0000-0000-0000-000000000131'
);
INSERT INTO public.google_form_question_mappings (
    connection_id, question_id, question_title, field_key, required, active
) VALUES (
    '42000000-0000-0000-0000-000000000132', 'routing-question-132',
    'FireflyFM submission reference', 'submission_reference', TRUE, TRUE
);
INSERT INTO public.google_form_requirement_bindings (
    connection_id, onboarding_template_requirement_id, published_snapshot
) VALUES (
    '42000000-0000-0000-0000-000000000131',
    '41000000-0000-0000-0000-000000000134', '{}'::JSONB
), (
    '42000000-0000-0000-0000-000000000132',
    '41000000-0000-0000-0000-000000000136', '{}'::JSONB
);

INSERT INTO public.onboarding_instances (id, school_id, membership_id, template_id, status)
VALUES
    ('50000000-0000-0000-0000-000000000131', '20000000-0000-0000-0000-000000000131', '30000000-0000-0000-0000-000000000133', '40000000-0000-0000-0000-000000000131', 'in_progress'),
    ('50000000-0000-0000-0000-000000000132', '20000000-0000-0000-0000-000000000131', '30000000-0000-0000-0000-000000000134', '40000000-0000-0000-0000-000000000132', 'in_progress'),
    ('50000000-0000-0000-0000-000000000133', '20000000-0000-0000-0000-000000000131', '30000000-0000-0000-0000-000000000135', '40000000-0000-0000-0000-000000000133', 'in_progress');
INSERT INTO public.onboarding_requirement_instances (
    id, onboarding_instance_id, template_requirement_id, status, completed_at
) VALUES
    ('51000000-0000-0000-0000-000000000131', '50000000-0000-0000-0000-000000000131', '41000000-0000-0000-0000-000000000131', 'approved', NOW()),
    ('51000000-0000-0000-0000-000000000132', '50000000-0000-0000-0000-000000000132', '41000000-0000-0000-0000-000000000132', 'not_started', NULL),
    ('51000000-0000-0000-0000-000000000133', '50000000-0000-0000-0000-000000000133', '41000000-0000-0000-0000-000000000133', 'not_started', NULL);

-- The membership trigger correctly gates a school director when no director
-- template exists yet. This fixture's first director is the already-approved
-- manager; the second director remains the active HQ-managed recipient.
UPDATE public.school_memberships
SET access_state = 'full'
WHERE id = '30000000-0000-0000-0000-000000000131';

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000131', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.publish_onboarding_template('40000000-0000-0000-0000-000000000134')$$,
    'school director publishes parent changes for active onboarding'
);
SELECT lives_ok(
    $$SELECT * FROM public.publish_onboarding_template('40000000-0000-0000-0000-000000000135')$$,
    'school director publishes teacher changes for active onboarding'
);
UPDATE public.school_memberships SET active = FALSE
WHERE id = '30000000-0000-0000-0000-000000000131';
UPDATE public.school_memberships SET active = TRUE
WHERE id = '30000000-0000-0000-0000-000000000135';
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000132', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.publish_onboarding_template('40000000-0000-0000-0000-000000000136')$$,
    'HQ publishes school-director changes for active onboarding'
);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000134', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.begin_google_form_submission('42000000-0000-0000-0000-000000000132')$$,
    'active teacher can begin the Form assigned by the school director'
);
SELECT is(
    (SELECT submission_status FROM public.fetch_my_google_form_steps('20000000-0000-0000-0000-000000000131') WHERE connection_id = '42000000-0000-0000-0000-000000000132'),
    'awaiting_sync',
    'teacher onboarding immediately shows that FireflyFM is checking the response'
);
SELECT throws_ok(
    $$SELECT * FROM public.begin_google_form_submission('42000000-0000-0000-0000-000000000132')$$,
    'P0001', 'FireflyFM is already checking this Form response',
    'teacher cannot open a duplicate Form session while delivery is pending'
);
RESET ROLE;

-- Memberships accepted after publication continue to instantiate the same
-- current versions through the existing invitation/membership trigger path.
UPDATE public.school_memberships SET active = FALSE
WHERE id = '30000000-0000-0000-0000-000000000135';
INSERT INTO public.school_memberships (id, school_id, user_id, role, active, access_state)
VALUES
    ('30000000-0000-0000-0000-000000000136', '20000000-0000-0000-0000-000000000131', '10000000-0000-0000-0000-000000000136', 'parent', TRUE, 'onboarding'),
    ('30000000-0000-0000-0000-000000000137', '20000000-0000-0000-0000-000000000131', '10000000-0000-0000-0000-000000000137', 'teacher', TRUE, 'onboarding'),
    ('30000000-0000-0000-0000-000000000138', '20000000-0000-0000-0000-000000000131', '10000000-0000-0000-0000-000000000138', 'school_director', TRUE, 'onboarding');

SELECT is((SELECT template_id FROM public.onboarding_instances WHERE id='50000000-0000-0000-0000-000000000131'), '40000000-0000-0000-0000-000000000134'::UUID, 'active parent moves to the published version');
SELECT is((SELECT template_id FROM public.onboarding_instances WHERE id='50000000-0000-0000-0000-000000000132'), '40000000-0000-0000-0000-000000000135'::UUID, 'active teacher moves to the published version');
SELECT is((SELECT template_id FROM public.onboarding_instances WHERE id='50000000-0000-0000-0000-000000000133'), '40000000-0000-0000-0000-000000000136'::UUID, 'active school director moves to the HQ-published version');

SELECT is((SELECT status FROM public.onboarding_requirement_instances WHERE id='51000000-0000-0000-0000-000000000131'), 'approved', 'matching approved parent progress is preserved');
SELECT is((SELECT template_requirement_id FROM public.onboarding_requirement_instances WHERE id='51000000-0000-0000-0000-000000000131'), '41000000-0000-0000-0000-000000000134'::UUID, 'approved parent progress follows its stable requirement key');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.onboarding_requirement_instances WHERE onboarding_instance_id='50000000-0000-0000-0000-000000000131' AND template_requirement_id='41000000-0000-0000-0000-000000000135'), 1, 'active parent receives a newly published step');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.onboarding_requirement_instances WHERE onboarding_instance_id='50000000-0000-0000-0000-000000000132' AND template_requirement_id='41000000-0000-0000-0000-000000000137'), 1, 'active teacher receives a newly published step');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.onboarding_requirement_instances WHERE onboarding_instance_id='50000000-0000-0000-0000-000000000133' AND template_requirement_id='41000000-0000-0000-0000-000000000139'), 1, 'active school director receives a newly published HQ step');

SELECT is((SELECT access_state FROM public.school_memberships WHERE id='30000000-0000-0000-0000-000000000133'), 'onboarding', 'new parent step keeps access gated');
SELECT is((SELECT access_state FROM public.school_memberships WHERE id='30000000-0000-0000-0000-000000000134'), 'onboarding', 'new teacher step keeps access gated');
SELECT is((SELECT access_state FROM public.school_memberships WHERE id='30000000-0000-0000-0000-000000000135'), 'onboarding', 'new director step keeps access gated');
SELECT is((SELECT template_id FROM public.onboarding_instances WHERE membership_id='30000000-0000-0000-0000-000000000136'), '40000000-0000-0000-0000-000000000134'::UUID, 'future parent receives the current published version');
SELECT is((SELECT template_id FROM public.onboarding_instances WHERE membership_id='30000000-0000-0000-0000-000000000137'), '40000000-0000-0000-0000-000000000135'::UUID, 'future teacher receives the current published version');
SELECT is((SELECT template_id FROM public.onboarding_instances WHERE membership_id='30000000-0000-0000-0000-000000000138'), '40000000-0000-0000-0000-000000000136'::UUID, 'future school director receives the current HQ-published version');

SELECT * FROM finish();
ROLLBACK;
