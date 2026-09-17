BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(37);

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000181', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'qr-director-a@test.fireflyfm.local', '', '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000182', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'qr-parent-a@test.fireflyfm.local', '', '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000183', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'qr-teacher-a@test.fireflyfm.local', '', '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000184', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'qr-director-b@test.fireflyfm.local', '', '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000185', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'qr-parent-b@test.fireflyfm.local', '', '{}', '{}', NOW(), NOW());

UPDATE public.profiles
SET display_name = CASE id
    WHEN '10000000-0000-0000-0000-000000000181'::UUID THEN 'QR Director A'
    WHEN '10000000-0000-0000-0000-000000000182'::UUID THEN 'QR Parent A'
    WHEN '10000000-0000-0000-0000-000000000183'::UUID THEN 'QR Teacher A'
    WHEN '10000000-0000-0000-0000-000000000184'::UUID THEN 'QR Director B'
    ELSE 'QR Parent B'
END
WHERE id IN (
    '10000000-0000-0000-0000-000000000181',
    '10000000-0000-0000-0000-000000000182',
    '10000000-0000-0000-0000-000000000183',
    '10000000-0000-0000-0000-000000000184',
    '10000000-0000-0000-0000-000000000185'
);

INSERT INTO public.schools (id, name) VALUES
    ('20000000-0000-0000-0000-000000000181', 'QR School A'),
    ('20000000-0000-0000-0000-000000000182', 'QR School B');

INSERT INTO public.school_memberships (id, school_id, user_id, role, active, access_state) VALUES
    ('30000000-0000-0000-0000-000000000181', '20000000-0000-0000-0000-000000000181', '10000000-0000-0000-0000-000000000181', 'school_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000182', '20000000-0000-0000-0000-000000000181', '10000000-0000-0000-0000-000000000182', 'parent', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000183', '20000000-0000-0000-0000-000000000181', '10000000-0000-0000-0000-000000000183', 'teacher', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000184', '20000000-0000-0000-0000-000000000182', '10000000-0000-0000-0000-000000000184', 'school_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000185', '20000000-0000-0000-0000-000000000182', '10000000-0000-0000-0000-000000000185', 'parent', TRUE, 'full');

-- The membership insert trigger derives onboarding state from active templates.
-- These fixtures explicitly model fully onboarded adults.
UPDATE public.school_memberships
SET access_state = 'full'
WHERE id IN (
    '30000000-0000-0000-0000-000000000181',
    '30000000-0000-0000-0000-000000000182',
    '30000000-0000-0000-0000-000000000183',
    '30000000-0000-0000-0000-000000000184',
    '30000000-0000-0000-0000-000000000185'
);

INSERT INTO public.children (id, school_id, first_name, last_name, birthdate, active) VALUES
    ('40000000-0000-0000-0000-000000000181', '20000000-0000-0000-0000-000000000181', 'Avery', 'QR', '2021-01-01', TRUE),
    ('40000000-0000-0000-0000-000000000182', '20000000-0000-0000-0000-000000000182', 'Blake', 'QR', '2021-02-01', TRUE);

INSERT INTO public.child_guardians (
    child_id, guardian_id, relationship, verification_status, verified_by, verified_at
) VALUES
    ('40000000-0000-0000-0000-000000000181', '10000000-0000-0000-0000-000000000182', 'Parent', 'verified', '10000000-0000-0000-0000-000000000181', NOW()),
    ('40000000-0000-0000-0000-000000000182', '10000000-0000-0000-0000-000000000185', 'Parent', 'verified', '10000000-0000-0000-0000-000000000184', NOW());

CREATE TEMP TABLE qr_test_state (
    code_id UUID,
    token TEXT,
    first_session_id UUID,
    second_code_id UUID,
    second_token TEXT
);
GRANT ALL ON qr_test_state TO authenticated;

SELECT has_table('public', 'attendance_location_codes', 'Attendance location-code table exists');
SELECT ok(
    (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.attendance_location_codes'::regclass),
    'Attendance location codes have RLS enabled'
);
SELECT ok(
    NOT has_table_privilege('authenticated', 'public.attendance_location_codes', 'SELECT'),
    'Authenticated clients cannot select raw location-code rows'
);
SELECT ok(
    has_function_privilege('authenticated', 'public.rotate_attendance_location_code(uuid,uuid)', 'EXECUTE'),
    'Authenticated users can call the context-authorized rotate RPC'
);
SELECT ok(
    NOT has_function_privilege('anon', 'public.rotate_attendance_location_code(uuid,uuid)', 'EXECUTE'),
    'Anonymous users cannot rotate attendance codes'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000181', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000181"}', TRUE);
INSERT INTO qr_test_state (code_id, token)
SELECT result.id, split_part(result.qr_payload, 'token=', 2)
FROM public.rotate_attendance_location_code('20000000-0000-0000-0000-000000000181', NULL) result;
SELECT is((SELECT COUNT(*)::INTEGER FROM qr_test_state), 1, 'School director creates one school code');
SELECT ok((SELECT token ~ '^[0-9a-f]{64}$' FROM qr_test_state), 'The QR payload uses an opaque 256-bit token');
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.fetch_attendance_location_code('20000000-0000-0000-0000-000000000181')),
    1,
    'The school director can retrieve the active code for phone display'
);

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000183', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000183"}', TRUE);
SELECT throws_ok(
    $$SELECT * FROM public.fetch_attendance_location_code('20000000-0000-0000-0000-000000000181')$$,
    'P0001', 'Only an authorized director can manage attendance codes',
    'A teacher cannot retrieve the school attendance code'
);

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000184', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000184"}', TRUE);
SELECT throws_ok(
    $$SELECT * FROM public.fetch_attendance_location_code('20000000-0000-0000-0000-000000000181')$$,
    'P0001', 'Only an authorized director can manage attendance codes',
    'Another school director cannot retrieve the code'
);

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000182', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000182"}', TRUE);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.preview_guardian_qr_attendance((SELECT token FROM qr_test_state))),
    1,
    'A verified full-access guardian previews one linked child'
);
SELECT is(
    (SELECT child_id FROM public.preview_guardian_qr_attendance((SELECT token FROM qr_test_state))),
    '40000000-0000-0000-0000-000000000181'::UUID,
    'The preview returns only the guardian-linked child'
);

RESET ROLE;
UPDATE public.child_guardians
SET verification_status = 'pending'
WHERE child_id = '40000000-0000-0000-0000-000000000181'
  AND guardian_id = '10000000-0000-0000-0000-000000000182';
SET LOCAL ROLE authenticated;
SELECT throws_ok(
    $$SELECT * FROM public.preview_guardian_qr_attendance((SELECT token FROM qr_test_state))$$,
    'P0001', 'This check-in code is unavailable for your account',
    'An unverified guardian cannot use the code'
);

RESET ROLE;
UPDATE public.child_guardians
SET verification_status = 'verified'
WHERE child_id = '40000000-0000-0000-0000-000000000181'
  AND guardian_id = '10000000-0000-0000-0000-000000000182';
UPDATE public.school_memberships
SET access_state = 'onboarding'
WHERE id = '30000000-0000-0000-0000-000000000182';
SET LOCAL ROLE authenticated;
SELECT throws_ok(
    $$SELECT * FROM public.preview_guardian_qr_attendance((SELECT token FROM qr_test_state))$$,
    'P0001', 'This check-in code is unavailable for your account',
    'A guardian with incomplete access cannot use the code'
);

RESET ROLE;
UPDATE public.school_memberships
SET access_state = 'full'
WHERE id = '30000000-0000-0000-0000-000000000182';
UPDATE public.child_guardians
SET ended_at = NOW()
WHERE child_id = '40000000-0000-0000-0000-000000000181'
  AND guardian_id = '10000000-0000-0000-0000-000000000182';
SET LOCAL ROLE authenticated;
SELECT throws_ok(
    $$SELECT * FROM public.preview_guardian_qr_attendance((SELECT token FROM qr_test_state))$$,
    'P0001', 'This check-in code is unavailable for your account',
    'A revoked guardian relationship cannot use the code'
);

RESET ROLE;
UPDATE public.child_guardians
SET ended_at = NULL
WHERE child_id = '40000000-0000-0000-0000-000000000181'
  AND guardian_id = '10000000-0000-0000-0000-000000000182';
UPDATE public.children
SET active = FALSE
WHERE id = '40000000-0000-0000-0000-000000000181';
SET LOCAL ROLE authenticated;
SELECT throws_ok(
    $$SELECT * FROM public.preview_guardian_qr_attendance((SELECT token FROM qr_test_state))$$,
    'P0001', 'This check-in code is unavailable for your account',
    'An inactive child is not eligible for QR attendance'
);
RESET ROLE;
UPDATE public.children SET active = TRUE WHERE id = '40000000-0000-0000-0000-000000000181';
SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000185', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000185"}', TRUE);
SELECT throws_ok(
    $$SELECT * FROM public.preview_guardian_qr_attendance((SELECT token FROM qr_test_state))$$,
    'P0001', 'This check-in code is unavailable for your account',
    'A guardian from another school cannot use the code'
);

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000182', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000182"}', TRUE);
WITH recorded AS (
    SELECT result.session_id
    FROM public.record_guardian_qr_attendance(
        (SELECT token FROM qr_test_state),
        ARRAY['40000000-0000-0000-0000-000000000181'::UUID],
        'check_in',
        'guardian-qr-check-in-1'
    ) result
)
UPDATE qr_test_state
SET first_session_id = (SELECT session_id FROM recorded LIMIT 1);
SELECT ok((SELECT first_session_id IS NOT NULL FROM qr_test_state), 'Guardian QR check-in succeeds');
SELECT is(
    (SELECT checked_in_method FROM public.attendance_sessions WHERE id = (SELECT first_session_id FROM qr_test_state)),
    'guardian_qr',
    'Check-in records the guardian QR method'
);
SELECT is(
    (SELECT checked_in_by FROM public.attendance_sessions WHERE id = (SELECT first_session_id FROM qr_test_state)),
    '10000000-0000-0000-0000-000000000182'::UUID,
    'Check-in records the authenticated guardian'
);
RESET ROLE;
SELECT is(
    (SELECT metadata->>'method' FROM public.workflow_audit_events
     WHERE source_id = (SELECT first_session_id FROM qr_test_state) AND event_type = 'check_in'
     ORDER BY created_at DESC LIMIT 1),
    'guardian_qr',
    'Audit metadata records the QR source'
);
SET LOCAL ROLE authenticated;
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.record_guardian_qr_attendance(
        (SELECT token FROM qr_test_state),
        ARRAY['40000000-0000-0000-0000-000000000181'::UUID],
        'check_in', 'guardian-qr-check-in-1'
    )),
    1,
    'An idempotent replay returns the prior result'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.attendance_sessions
     WHERE child_id = '40000000-0000-0000-0000-000000000181' AND checked_in_at IS NOT NULL),
    1,
    'An idempotent replay does not duplicate attendance'
);
SELECT ok(
    (SELECT success FROM public.record_guardian_qr_attendance(
        (SELECT token FROM qr_test_state),
        ARRAY['40000000-0000-0000-0000-000000000181'::UUID],
        'check_out', 'guardian-qr-check-out-1'
    )),
    'Guardian QR checkout succeeds'
);
SELECT is(
    (SELECT checked_out_method FROM public.attendance_sessions WHERE id = (SELECT first_session_id FROM qr_test_state)),
    'guardian_qr',
    'Checkout records the guardian QR method'
);
SELECT is(
    (SELECT session_id FROM public.record_guardian_qr_attendance(
        (SELECT token FROM qr_test_state),
        ARRAY['40000000-0000-0000-0000-000000000181'::UUID],
        'check_out', 'guardian-qr-check-out-1'
    )),
    (SELECT first_session_id FROM qr_test_state),
    'A checkout replay returns the original session'
);
SELECT is(
    (SELECT session_id FROM public.record_guardian_qr_attendance(
        (SELECT token FROM qr_test_state),
        ARRAY['40000000-0000-0000-0000-000000000181'::UUID],
        'check_in', 'guardian-qr-check-in-1'
    )),
    (SELECT first_session_id FROM qr_test_state),
    'A check-in replay remains idempotent after checkout'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER
     FROM public.record_guardian_qr_attendance(
        (SELECT token FROM qr_test_state),
        ARRAY[
            '40000000-0000-0000-0000-000000000181'::UUID,
            '40000000-0000-0000-0000-000000000182'::UUID
        ],
        'check_in', 'guardian-qr-partial-1'
     ) result
     WHERE result.success = TRUE),
    1,
    'A mixed multi-child request records its eligible child'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER
     FROM public.record_guardian_qr_attendance(
        (SELECT token FROM qr_test_state),
        ARRAY[
            '40000000-0000-0000-0000-000000000181'::UUID,
            '40000000-0000-0000-0000-000000000182'::UUID
        ],
        'check_in', 'guardian-qr-partial-1'
     ) result
     WHERE result.success = FALSE),
    1,
    'A mixed multi-child request explicitly reports its denied child'
);
DO $$
BEGIN
    PERFORM * FROM public.record_guardian_qr_attendance(
        (SELECT token FROM qr_test_state),
        ARRAY['40000000-0000-0000-0000-000000000181'::UUID],
        'check_out', 'guardian-qr-partial-cleanup-1'
    );
END;
$$;
SELECT throws_ok(
    $$SELECT * FROM public.record_guardian_qr_attendance(
        (SELECT token FROM qr_test_state),
        ARRAY['40000000-0000-0000-0000-000000000181'::UUID],
        'absent', 'guardian-qr-absent-1'
    )$$,
    'P0001', 'Invalid QR attendance action',
    'Guardian QR attendance cannot mark a child absent'
);

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000183', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000183"}', TRUE);
SELECT ok(
    (SELECT id IS NOT NULL FROM public.record_school_attendance(
        '40000000-0000-0000-0000-000000000181', 'check_in', NOW(), NULL, 'teacher-manual-check-in-1'
    )),
    'Existing staff manual attendance still succeeds'
);
SELECT is(
    (SELECT checked_in_method FROM public.attendance_sessions
     WHERE idempotency_key = 'teacher-manual-check-in-1'),
    'staff_manual',
    'Existing staff attendance records the manual method'
);

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000181', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000181"}', TRUE);
UPDATE qr_test_state state
SET second_code_id = result.id,
    second_token = split_part(result.qr_payload, 'token=', 2)
FROM public.rotate_attendance_location_code('20000000-0000-0000-0000-000000000181', NULL) result;
SELECT isnt((SELECT second_token FROM qr_test_state), (SELECT token FROM qr_test_state), 'Rotation creates a different token');
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.fetch_attendance_location_code('20000000-0000-0000-0000-000000000181')),
    1,
    'Rotation leaves exactly one active school code'
);

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000182', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000182"}', TRUE);
SELECT throws_ok(
    $$SELECT * FROM public.preview_guardian_qr_attendance((SELECT token FROM qr_test_state))$$,
    'P0001', 'This check-in code is unavailable for your account',
    'A rotated poster stops working immediately'
);

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000181', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000181"}', TRUE);
SELECT public.revoke_attendance_location_code(
    (SELECT second_code_id FROM qr_test_state)
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.fetch_attendance_location_code('20000000-0000-0000-0000-000000000181')),
    0,
    'Revocation removes the active code from management retrieval'
);

RESET ROLE;
SELECT is(public.get_firefly_schema_version(), 20260917210000::BIGINT, 'Schema version includes guardian QR attendance');

SELECT * FROM finish();
ROLLBACK;
