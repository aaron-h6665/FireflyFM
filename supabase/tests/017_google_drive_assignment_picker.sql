BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(16);

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000171', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'drive-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000172', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'drive-teacher@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000173', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'drive-other@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

UPDATE public.profiles
SET display_name = CASE id
    WHEN '10000000-0000-0000-0000-000000000171'::UUID THEN 'Drive Director'
    WHEN '10000000-0000-0000-0000-000000000172'::UUID THEN 'Drive Teacher'
    ELSE 'Other Director'
END
WHERE id IN (
    '10000000-0000-0000-0000-000000000171',
    '10000000-0000-0000-0000-000000000172',
    '10000000-0000-0000-0000-000000000173'
);

INSERT INTO public.schools (id, name) VALUES
    ('20000000-0000-0000-0000-000000000171', 'Drive School'),
    ('20000000-0000-0000-0000-000000000172', 'Other Drive School');

INSERT INTO public.school_memberships (id, school_id, user_id, role, active, access_state) VALUES
    ('30000000-0000-0000-0000-000000000171', '20000000-0000-0000-0000-000000000171', '10000000-0000-0000-0000-000000000171', 'school_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000172', '20000000-0000-0000-0000-000000000171', '10000000-0000-0000-0000-000000000172', 'teacher', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000173', '20000000-0000-0000-0000-000000000172', '10000000-0000-0000-0000-000000000173', 'school_director', TRUE, 'full');

-- Membership creation fails closed into onboarding when no published template
-- exists. These fixtures represent already-approved members.
UPDATE public.school_memberships
SET access_state = 'full'
WHERE id IN (
    '30000000-0000-0000-0000-000000000171',
    '30000000-0000-0000-0000-000000000172',
    '30000000-0000-0000-0000-000000000173'
);

INSERT INTO public.assignments (
    id, school_id, title, category, audience_role, assigned_by,
    status, visibility, requires_review, allow_resubmission, publish_at
) VALUES (
    '60000000-0000-0000-0000-000000000171',
    '20000000-0000-0000-0000-000000000171',
    'Drive picker assignment', 'training', 'teacher',
    '10000000-0000-0000-0000-000000000171', 'published', 'assigned', TRUE, TRUE, NOW()
);

INSERT INTO public.assignment_recipients (
    assignment_id, user_id, role_at_assignment, completion_status
) VALUES (
    '60000000-0000-0000-0000-000000000171',
    '10000000-0000-0000-0000-000000000172', 'teacher', 'not_started'
);

SELECT has_table('public', 'google_drive_assignment_operations', 'Drive picker operation table exists');
SELECT ok(
    (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.google_drive_assignment_operations'::regclass),
    'Drive picker operation table has RLS enabled'
);
SELECT ok(
    NOT has_table_privilege('authenticated', 'public.google_drive_assignment_operations', 'SELECT'),
    'Authenticated clients cannot read picker OAuth material'
);
SELECT ok(
    NOT has_table_privilege('authenticated', 'public.google_drive_assignment_operations', 'INSERT'),
    'Authenticated clients cannot create picker OAuth operations directly'
);
SELECT ok(
    has_function_privilege('authenticated', 'public.authorize_google_drive_assignment_import(text,uuid,uuid)', 'EXECUTE'),
    'Authenticated users can request contextual authorization'
);
SELECT ok(
    NOT has_function_privilege('anon', 'public.authorize_google_drive_assignment_import(text,uuid,uuid)', 'EXECUTE'),
    'Anonymous users cannot request picker authorization'
);
SELECT ok(
    NOT has_function_privilege('authenticated', 'public.cleanup_expired_google_drive_assignment_operations()', 'EXECUTE'),
    'Authenticated clients cannot invoke service cleanup directly'
);

INSERT INTO public.google_drive_assignment_operations (
    user_id, school_id, assignment_id, context_kind, state_hash,
    pkce_verifier_ciphertext, pkce_verifier_iv, access_token_ciphertext,
    access_token_iv, selected_files, expires_at
) VALUES (
    '10000000-0000-0000-0000-000000000172',
    '20000000-0000-0000-0000-000000000171',
    '60000000-0000-0000-0000-000000000171',
    'submission', 'expired-test-state', 'encrypted-verifier', 'verifier-iv',
    'encrypted-access-token', 'access-token-iv', '[{"id":"selected-file"}]',
    NOW() - INTERVAL '1 minute'
);
SELECT is(
    public.cleanup_expired_google_drive_assignment_operations(),
    1::BIGINT,
    'Expired operations and encrypted token material are deleted by cleanup'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM cron.job WHERE jobname = 'firefly-google-drive-assignment-picker-cleanup'),
    1,
    'A scheduled cleanup removes expired picker operations every minute'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000171', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000171"}', TRUE);
SELECT ok(
    public.authorize_google_drive_assignment_import('material_create', '20000000-0000-0000-0000-000000000171', NULL),
    'school director can import material before creating an assignment'
);
SELECT ok(
    public.authorize_google_drive_assignment_import('material_manage', '20000000-0000-0000-0000-000000000171', '60000000-0000-0000-0000-000000000171'),
    'assignment creator can import replacement material'
);
SELECT ok(
    NOT public.authorize_google_drive_assignment_import('material_manage', '20000000-0000-0000-0000-000000000172', '60000000-0000-0000-0000-000000000171'),
    'assignment school must match the requested picker school'
);
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000172', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000172"}', TRUE);
SELECT ok(
    NOT public.authorize_google_drive_assignment_import('material_create', '20000000-0000-0000-0000-000000000171', NULL),
    'teacher cannot import creator material'
);
SELECT ok(
    public.authorize_google_drive_assignment_import('submission', '20000000-0000-0000-0000-000000000171', '60000000-0000-0000-0000-000000000171'),
    'eligible assignment recipient can import a submission'
);
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000173', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000173"}', TRUE);
SELECT ok(
    NOT public.authorize_google_drive_assignment_import('submission', '20000000-0000-0000-0000-000000000171', '60000000-0000-0000-0000-000000000171'),
    'cross-school director cannot import another recipient submission'
);
RESET ROLE;

UPDATE public.assignments SET status = 'closed'
WHERE id = '60000000-0000-0000-0000-000000000171';

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000172', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000172"}', TRUE);
SELECT ok(
    NOT public.authorize_google_drive_assignment_import('submission', '20000000-0000-0000-0000-000000000171', '60000000-0000-0000-0000-000000000171'),
    'closed assignment rejects a new Drive submission import'
);
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
