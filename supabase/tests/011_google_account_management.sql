BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(18);

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'google-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000112', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'google-other-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000113', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'google-teacher@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

INSERT INTO public.profiles (id, display_name) VALUES
    ('10000000-0000-0000-0000-000000000111', 'Google Director'),
    ('10000000-0000-0000-0000-000000000112', 'Other Google Director'),
    ('10000000-0000-0000-0000-000000000113', 'Google Teacher');

INSERT INTO public.schools (id, name) VALUES
    ('20000000-0000-0000-0000-000000000111', 'Google School'),
    ('20000000-0000-0000-0000-000000000112', 'Other Google School');

INSERT INTO public.school_memberships (id, school_id, user_id, role, active, access_state) VALUES
    ('30000000-0000-0000-0000-000000000111', '20000000-0000-0000-0000-000000000111', '10000000-0000-0000-0000-000000000111', 'school_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000112', '20000000-0000-0000-0000-000000000112', '10000000-0000-0000-0000-000000000112', 'school_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000113', '20000000-0000-0000-0000-000000000111', '10000000-0000-0000-0000-000000000113', 'teacher', TRUE, 'full');

UPDATE public.school_memberships SET access_state = 'full'
WHERE id IN (
    '30000000-0000-0000-0000-000000000111',
    '30000000-0000-0000-0000-000000000112',
    '30000000-0000-0000-0000-000000000113'
);

INSERT INTO public.google_oauth_credentials (
    id, school_id, director_id, google_account_email,
    refresh_token_ciphertext, refresh_token_iv, status, is_selected
) VALUES
    ('40000000-0000-0000-0000-000000000111', '20000000-0000-0000-0000-000000000111', '10000000-0000-0000-0000-000000000111', 'first@example.test', 'cipher-a', 'iv-a', 'connected', TRUE),
    ('40000000-0000-0000-0000-000000000112', '20000000-0000-0000-0000-000000000111', '10000000-0000-0000-0000-000000000111', 'second@example.test', 'cipher-b', 'iv-b', 'connected', FALSE),
    ('40000000-0000-0000-0000-000000000113', '20000000-0000-0000-0000-000000000112', '10000000-0000-0000-0000-000000000112', 'other@example.test', 'cipher-c', 'iv-c', 'connected', TRUE);

INSERT INTO public.google_form_connections (
    id, school_id, form_role, form_key, form_id, form_url, form_title,
    google_account_email, credential_id, status, created_by
) VALUES
    ('50000000-0000-0000-0000-000000000111', '20000000-0000-0000-0000-000000000111', 'parent', 'first-form', 'first-form', 'https://docs.google.com/forms/d/first-form/viewform', 'First Form', 'first@example.test', '40000000-0000-0000-0000-000000000111', 'connected', '10000000-0000-0000-0000-000000000111'),
    ('50000000-0000-0000-0000-000000000112', '20000000-0000-0000-0000-000000000111', 'teacher', 'second-form', 'second-form', 'https://docs.google.com/forms/d/second-form/viewform', 'Second Form', 'second@example.test', '40000000-0000-0000-0000-000000000112', 'connected', '10000000-0000-0000-0000-000000000111');

INSERT INTO public.google_form_imports (
    id, connection_id, school_id, google_response_id, submitted_payload, status
) VALUES (
    '60000000-0000-0000-0000-000000000112', '50000000-0000-0000-0000-000000000112',
    '20000000-0000-0000-0000-000000000111', 'preserved-response', '{}', 'pending_review'
);

SELECT is(public.get_firefly_schema_version(), 20260907220000::BIGINT, 'Google account management schema version is current');
SELECT ok((SELECT is_selected FROM public.google_oauth_credentials WHERE id = '40000000-0000-0000-0000-000000000111'), 'first account begins selected');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000111', TRUE);

SELECT lives_ok(
    $$SELECT public.select_google_oauth_credential('40000000-0000-0000-0000-000000000112')$$,
    'director can select another connected account'
);
SELECT ok((SELECT is_selected FROM public.google_oauth_credentials WHERE id = '40000000-0000-0000-0000-000000000112'), 'new account is selected');
SELECT isnt((SELECT is_selected FROM public.google_oauth_credentials WHERE id = '40000000-0000-0000-0000-000000000111'), TRUE, 'previous account is no longer selected');
SELECT is((SELECT credential_id FROM public.google_form_connections WHERE id = '50000000-0000-0000-0000-000000000111'), '40000000-0000-0000-0000-000000000111'::UUID, 'switching does not rebind an existing Form');
SELECT throws_ok(
    $$SELECT public.select_google_oauth_credential('40000000-0000-0000-0000-000000000113')$$,
    'P0001', 'Only the connected school director can select this Google account',
    'director cannot select another school director credential'
);
SELECT is(
    public.disconnect_google_oauth_credential('40000000-0000-0000-0000-000000000112'),
    1, 'disconnect reports the paused Form count'
);
SELECT is((SELECT status FROM public.google_oauth_credentials WHERE id = '40000000-0000-0000-0000-000000000112'), 'revoked', 'credential is marked revoked');
SELECT is((SELECT refresh_token_ciphertext FROM public.google_oauth_credentials WHERE id = '40000000-0000-0000-0000-000000000112'), NULL, 'encrypted refresh credential is deleted');
SELECT is((SELECT status FROM public.google_form_connections WHERE id = '50000000-0000-0000-0000-000000000112'), 'paused', 'linked Form is paused');
SELECT is((SELECT status FROM public.google_form_connections WHERE id = '50000000-0000-0000-0000-000000000111'), 'connected', 'another account Form remains connected');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.google_form_imports WHERE id = '60000000-0000-0000-0000-000000000112'), 1, 'existing imported response is preserved');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.workflow_audit_events WHERE source_id = '40000000-0000-0000-0000-000000000112' AND event_type = 'google_account_disconnected'), 1, 'disconnect creates an audit event');

RESET ROLE;
UPDATE public.google_oauth_credentials
SET refresh_token_ciphertext = 'new-cipher', refresh_token_iv = 'new-iv', status = 'connected'
WHERE id = '40000000-0000-0000-0000-000000000112';

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000111', TRUE);
SELECT is(
    public.activate_google_oauth_credential('40000000-0000-0000-0000-000000000112'),
    1, 'reconnect reports the resumed Form count'
);
SELECT is((SELECT status FROM public.google_form_connections WHERE id = '50000000-0000-0000-0000-000000000112'), 'connected', 'reconnect resumes the paused Form');
SELECT ok((SELECT is_selected FROM public.google_oauth_credentials WHERE id = '40000000-0000-0000-0000-000000000112'), 'reconnected account becomes selected');

RESET ROLE;
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
