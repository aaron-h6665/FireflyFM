BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(22);

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'google-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000112', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'google-other-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000113', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'google-teacher@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

UPDATE public.profiles
SET display_name = CASE id
    WHEN '10000000-0000-0000-0000-000000000111'::UUID THEN 'Google Director'
    WHEN '10000000-0000-0000-0000-000000000112'::UUID THEN 'Other Google Director'
    WHEN '10000000-0000-0000-0000-000000000113'::UUID THEN 'Google Teacher'
END
WHERE id IN (
    '10000000-0000-0000-0000-000000000111',
    '10000000-0000-0000-0000-000000000112',
    '10000000-0000-0000-0000-000000000113'
);

INSERT INTO public.schools (id, name) VALUES
    ('20000000-0000-0000-0000-000000000111', 'Google School'),
    ('20000000-0000-0000-0000-000000000112', 'Other Google School');

INSERT INTO public.school_memberships (id, school_id, user_id, role, active, access_state) VALUES
    ('30000000-0000-0000-0000-000000000111', '20000000-0000-0000-0000-000000000111', '10000000-0000-0000-0000-000000000111', 'school_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000112', '20000000-0000-0000-0000-000000000112', '10000000-0000-0000-0000-000000000112', 'school_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000113', '20000000-0000-0000-0000-000000000111', '10000000-0000-0000-0000-000000000113', 'teacher', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000114', '20000000-0000-0000-0000-000000000111', '10000000-0000-0000-0000-000000000112', 'school_director', FALSE, 'full');

UPDATE public.school_memberships SET access_state = 'full'
WHERE id IN (
    '30000000-0000-0000-0000-000000000111',
    '30000000-0000-0000-0000-000000000112',
    '30000000-0000-0000-0000-000000000113',
    '30000000-0000-0000-0000-000000000114'
);

INSERT INTO public.google_oauth_credentials (
    id, school_id, director_id, google_account_email,
    refresh_token_ciphertext, refresh_token_iv, status, is_selected
) VALUES
    ('40000000-0000-0000-0000-000000000111', '20000000-0000-0000-0000-000000000111', '10000000-0000-0000-0000-000000000111', 'first@example.test', 'cipher-a', 'iv-a', 'connected', TRUE),
    ('40000000-0000-0000-0000-000000000112', '20000000-0000-0000-0000-000000000111', '10000000-0000-0000-0000-000000000111', 'second@example.test', 'cipher-b', 'iv-b', 'connected', FALSE),
    ('40000000-0000-0000-0000-000000000113', '20000000-0000-0000-0000-000000000112', '10000000-0000-0000-0000-000000000112', 'other@example.test', 'cipher-c', 'iv-c', 'connected', TRUE),
    ('40000000-0000-0000-0000-000000000114', '20000000-0000-0000-0000-000000000111', '10000000-0000-0000-0000-000000000112', 'first@example.test', 'cipher-d', 'iv-d', 'connected', TRUE);

INSERT INTO public.google_form_connections (
    id, school_id, form_role, form_key, form_id, form_url, form_title,
    google_account_email, credential_id, status, created_by
) VALUES
    ('50000000-0000-0000-0000-000000000111', '20000000-0000-0000-0000-000000000111', 'parent', 'first-form', 'first-form', 'https://docs.google.com/forms/d/first-form/viewform', 'First Form', 'first@example.test', '40000000-0000-0000-0000-000000000111', 'connected', '10000000-0000-0000-0000-000000000111'),
    ('50000000-0000-0000-0000-000000000112', '20000000-0000-0000-0000-000000000111', 'teacher', 'second-form', 'second-form', 'https://docs.google.com/forms/d/second-form/viewform', 'Second Form', 'second@example.test', '40000000-0000-0000-0000-000000000112', 'connected', '10000000-0000-0000-0000-000000000111'),
    ('50000000-0000-0000-0000-000000000113', '20000000-0000-0000-0000-000000000111', 'parent', 'manually-paused-form', 'manually-paused-form', 'https://docs.google.com/forms/d/manually-paused-form/viewform', 'Manually Paused Form', 'second@example.test', '40000000-0000-0000-0000-000000000112', 'paused', '10000000-0000-0000-0000-000000000111');

UPDATE public.google_form_connections
SET last_error = 'Manually paused for review.'
WHERE id = '50000000-0000-0000-0000-000000000113';

INSERT INTO public.google_form_imports (
    id, connection_id, school_id, google_response_id, submitted_payload, status
) VALUES (
    '60000000-0000-0000-0000-000000000112', '50000000-0000-0000-0000-000000000112',
    '20000000-0000-0000-0000-000000000111', 'preserved-response', '{}', 'pending_review'
);

SELECT ok(public.get_firefly_schema_version() >= 20260907221000::BIGINT, 'schema includes completed Google account management');
SELECT ok((SELECT is_selected FROM public.google_oauth_credentials WHERE id = '40000000-0000-0000-0000-000000000111'), 'first account begins selected');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.google_oauth_credentials WHERE school_id = '20000000-0000-0000-0000-000000000111' AND google_account_email = 'first@example.test'), 2, 'the same Google email can be scoped independently to two directors');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000111', TRUE);

SELECT lives_ok(
    $$SELECT public.select_google_oauth_credential('40000000-0000-0000-0000-000000000112')$$,
    'director can select another connected account'
);
RESET ROLE;
SELECT ok((SELECT is_selected FROM public.google_oauth_credentials WHERE id = '40000000-0000-0000-0000-000000000112'), 'new account is selected');
SELECT isnt((SELECT is_selected FROM public.google_oauth_credentials WHERE id = '40000000-0000-0000-0000-000000000111'), TRUE, 'previous account is no longer selected');
SELECT is((SELECT credential_id FROM public.google_form_connections WHERE id = '50000000-0000-0000-0000-000000000111'), '40000000-0000-0000-0000-000000000111'::UUID, 'switching does not rebind an existing Form');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000111', TRUE);
SELECT throws_ok(
    $$SELECT public.select_google_oauth_credential('40000000-0000-0000-0000-000000000113')$$,
    'P0001', 'Only the connected school director can select this Google account',
    'director cannot select another school director credential'
);
SELECT throws_ok(
    $$SELECT public.select_google_oauth_credential('40000000-0000-0000-0000-000000000114')$$,
    'P0001', 'Only the connected school director can select this Google account',
    'director cannot select another director credential in the same school'
);
SELECT is(
    public.disconnect_google_oauth_credential('40000000-0000-0000-0000-000000000112'),
    1, 'disconnect reports the paused Form count'
);
RESET ROLE;
SELECT is((SELECT status FROM public.google_oauth_credentials WHERE id = '40000000-0000-0000-0000-000000000112'), 'revoked', 'credential is marked revoked');
SELECT is((SELECT refresh_token_ciphertext FROM public.google_oauth_credentials WHERE id = '40000000-0000-0000-0000-000000000112'), NULL, 'encrypted refresh credential is deleted');
SELECT is((SELECT status FROM public.google_form_connections WHERE id = '50000000-0000-0000-0000-000000000112'), 'paused', 'linked Form is paused');
SELECT is((SELECT status FROM public.google_form_connections WHERE id = '50000000-0000-0000-0000-000000000111'), 'connected', 'another account Form remains connected');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.google_form_imports WHERE id = '60000000-0000-0000-0000-000000000112'), 1, 'existing imported response is preserved');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.workflow_audit_events WHERE source_id = '40000000-0000-0000-0000-000000000112' AND event_type = 'google_account_disconnected'), 1, 'disconnect creates an audit event');

RESET ROLE;
UPDATE public.google_oauth_credentials
SET refresh_token_ciphertext = 'new-cipher', refresh_token_iv = 'new-iv'
WHERE id = '40000000-0000-0000-0000-000000000112';

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000111', TRUE);
SELECT is(
    public.activate_google_oauth_credential('40000000-0000-0000-0000-000000000112'),
    1, 'reconnect reports the resumed Form count'
);
RESET ROLE;
SELECT is((SELECT status FROM public.google_form_connections WHERE id = '50000000-0000-0000-0000-000000000112'), 'connected', 'reconnect resumes the paused Form');
SELECT is((SELECT status FROM public.google_form_connections WHERE id = '50000000-0000-0000-0000-000000000113'), 'paused', 'reconnect leaves Forms paused for another reason untouched');
SELECT ok((SELECT is_selected FROM public.google_oauth_credentials WHERE id = '40000000-0000-0000-0000-000000000112'), 'reconnected account becomes selected');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.workflow_audit_events WHERE source_id = '40000000-0000-0000-0000-000000000112' AND event_type = 'google_account_reconnected'), 1, 'reconnect creates a reconnection audit event');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000113', TRUE);
SELECT throws_ok(
    $$SELECT public.disconnect_google_oauth_credential('40000000-0000-0000-0000-000000000111')$$,
    'P0001', 'Only the connected school director can disconnect this Google account',
    'teacher cannot disconnect a Google account'
);

SELECT * FROM finish();
ROLLBACK;
