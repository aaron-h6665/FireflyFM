BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'parent@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'other@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

INSERT INTO public.schools (id, name) VALUES
    ('20000000-0000-0000-0000-000000000001', 'Onboarding Test School'),
    ('20000000-0000-0000-0000-000000000002', 'Second Test School');

INSERT INTO public.school_memberships (id, school_id, user_id, role, active, access_state)
VALUES (
    '30000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'parent', TRUE, 'onboarding'
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
    20260721030000::BIGINT,
    'schema reports the private-media contract version'
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
SELECT lives_ok(
    $$SELECT public.create_child_for_current_parent(
        '20000000-0000-0000-0000-000000000001', 'Avery', 'Firefly', '2022-01-10'
    )$$,
    'onboarding parent can create the child needed by onboarding'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.children WHERE school_id = '20000000-0000-0000-0000-000000000001'),
    1,
    'one child is created'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.child_guardians WHERE guardian_id = auth.uid()),
    1,
    'the creating parent becomes the guardian'
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

SELECT * FROM finish();
ROLLBACK;
