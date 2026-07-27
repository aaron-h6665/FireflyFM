BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(35);

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000071', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'chat-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000072', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'chat-teacher@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000073', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'chat-parent@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000074', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'chat-hq@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000075', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'chat-second-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

INSERT INTO public.profiles (id, display_name) VALUES
    ('10000000-0000-0000-0000-000000000071', 'Original Director'),
    ('10000000-0000-0000-0000-000000000072', 'Classroom Teacher'),
    ('10000000-0000-0000-0000-000000000073', 'Family Guardian'),
    ('10000000-0000-0000-0000-000000000074', 'HQ Director'),
    ('10000000-0000-0000-0000-000000000075', 'Second Director')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

INSERT INTO public.schools (id, name)
VALUES ('20000000-0000-0000-0000-000000000071', 'Chat First School');

INSERT INTO public.school_memberships (id, school_id, user_id, role, active) VALUES
    ('30000000-0000-0000-0000-000000000071', '20000000-0000-0000-0000-000000000071', '10000000-0000-0000-0000-000000000071', 'school_director', TRUE),
    ('30000000-0000-0000-0000-000000000072', '20000000-0000-0000-0000-000000000071', '10000000-0000-0000-0000-000000000072', 'teacher', TRUE),
    ('30000000-0000-0000-0000-000000000073', '20000000-0000-0000-0000-000000000071', '10000000-0000-0000-0000-000000000073', 'parent', TRUE),
    ('30000000-0000-0000-0000-000000000074', '20000000-0000-0000-0000-000000000071', '10000000-0000-0000-0000-000000000074', 'hq_director', TRUE);
UPDATE public.school_memberships
SET access_state = 'full'
WHERE school_id = '20000000-0000-0000-0000-000000000071';

INSERT INTO public.children (id, school_id, first_name, last_name, birthdate, active) VALUES
    ('40000000-0000-0000-0000-000000000071', '20000000-0000-0000-0000-000000000071', 'Avery', 'Firefly', '2022-04-15', TRUE),
    ('40000000-0000-0000-0000-000000000072', '20000000-0000-0000-0000-000000000071', 'Blake', 'Firefly', '2021-05-16', TRUE);
INSERT INTO public.child_guardians (
    child_id, guardian_id, relationship, verification_status, verified_by, verified_at
) VALUES (
    '40000000-0000-0000-0000-000000000071', '10000000-0000-0000-0000-000000000073',
    'Parent', 'verified', '10000000-0000-0000-0000-000000000071', NOW()
);

SELECT is(public.get_firefly_schema_version(), 20260727000000::BIGINT, 'chat-first schema version is current');
SELECT ok(has_function_privilege('authenticated', 'public.record_attendance_batch(uuid[],text,text)', 'EXECUTE'), 'authenticated staff can call batch attendance');
SELECT ok(has_function_privilege('authenticated', 'public.update_assignment_details(uuid,text,text,timestamptz,boolean)', 'EXECUTE'), 'assignment creators can call the edit RPC');
SELECT ok(has_function_privilege('authenticated', 'public.review_assignment_submission_v2(uuid,text,text,text,integer)', 'EXECUTE'), 'assignment creators can score a submission');
SELECT ok(has_function_privilege('authenticated', 'public.set_school_event_archived(uuid,boolean)', 'EXECUTE'), 'authorized event managers can call archive');
SELECT is(
    (SELECT COUNT(*)::INTEGER
     FROM pg_constraint
     WHERE conrelid = 'public.assignment_submissions'::regclass
       AND conname = 'assignment_submissions_score_check'),
    1,
    'submission scores are constrained to the supported scale'
);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.chat_rooms WHERE room_type = 'school_group'), 1, 'a school group room is created automatically');
SELECT ok((SELECT system_managed FROM public.chat_rooms WHERE room_type = 'school_group'), 'the school group room is lifecycle managed');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.chat_rooms WHERE room_type = 'child_family'), 1, 'a verified full-access guardian creates one child-family room');
SELECT is((SELECT name FROM public.chat_rooms WHERE room_type = 'child_family'), 'Avery Firefly • Family Team', 'the family room is easy to identify');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.chat_participants WHERE room_id = (SELECT id FROM public.chat_rooms WHERE room_type = 'child_family')), 3, 'the family room includes guardian, teacher, and director');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.chat_participants WHERE room_id = (SELECT id FROM public.chat_rooms WHERE room_type = 'school_group')), 3, 'the school group includes all non-HQ school adults');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.chat_participants WHERE user_id = '10000000-0000-0000-0000-000000000074'), 0, 'HQ is not silently added to communication rooms');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000072', TRUE);
SELECT set_config('request.jwt.claim.email', 'chat-teacher@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000072","email":"chat-teacher@test.fireflyfm.local"}', TRUE);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.fetch_my_managed_chat_rooms('20000000-0000-0000-0000-000000000071')),
    2,
    'a teacher sees the school group and eligible child-family room'
);
SELECT throws_ok(
    $$UPDATE public.chat_participants
      SET membership_source = 'manual'
      WHERE room_id = (SELECT id FROM public.chat_rooms WHERE room_type = 'school_group')
        AND user_id = auth.uid()$$,
    'P0001', 'Membership in this room is managed by the school lifecycle',
    'a participant cannot rewrite automatic room membership'
);
SELECT lives_ok(
    $$SELECT * FROM public.record_child_care_event(
        '40000000-0000-0000-0000-000000000071', 'potty', NOW(),
        '{"result":"successful"}', 'parent', NULL, 'chat-first-care'
    )$$,
    'a teacher records an everyday care update'
);
SELECT lives_ok(
    $$SELECT * FROM public.record_attendance_batch(
        ARRAY[
            '40000000-0000-0000-0000-000000000071'::UUID,
            '40000000-0000-0000-0000-000000000072'::UUID
        ],
        'absent', 'chat-first-batch'
    )$$,
    'a teacher records attendance for a selected child grid in one action'
);
RESET ROLE;
SELECT is((SELECT COUNT(*)::INTEGER FROM public.messages WHERE entry_kind = 'care_event'), 1, 'parent-visible care is mirrored into the child timeline');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.attendance_sessions WHERE idempotency_key LIKE 'chat-first-batch:%'), 2, 'batch attendance records one idempotent result per child');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000073', TRUE);
SELECT set_config('request.jwt.claim.email', 'chat-parent@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000073","email":"chat-parent@test.fireflyfm.local"}', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.submit_family_request(
        '40000000-0000-0000-0000-000000000071', 'absence',
        '{"date":"2026-07-28"}', 'chat-first-absence'
    )$$,
    'a guardian submits a structured family request from chat'
);
RESET ROLE;
SELECT is((SELECT COUNT(*)::INTEGER FROM public.messages WHERE entry_kind = 'family_request'), 1, 'the family request is mirrored into the child timeline');

SELECT lives_ok(
    $$UPDATE public.school_memberships
      SET active = FALSE
      WHERE id = '30000000-0000-0000-0000-000000000071';
      UPDATE public.school_memberships
      SET role = 'school_director'
      WHERE id = '30000000-0000-0000-0000-000000000072'$$,
    'a teacher can become the sole director without breaking automatic room sync'
);
SELECT ok(
    (SELECT role = 'owner' AND membership_source = 'director'
     FROM public.chat_participants
     WHERE room_id = (SELECT id FROM public.chat_rooms WHERE room_type = 'school_group')
       AND user_id = '10000000-0000-0000-0000-000000000072'),
    'the promoted director owns the school group room'
);
SELECT ok(
    (SELECT role = 'owner' AND membership_source = 'director'
     FROM public.chat_participants
     WHERE room_id = (SELECT id FROM public.chat_rooms WHERE room_type = 'child_family')
       AND user_id = '10000000-0000-0000-0000-000000000072'),
    'the promoted director owns the family room'
);
SELECT throws_ok(
    $$INSERT INTO public.school_memberships (school_id, user_id, role, active, access_state)
      VALUES (
        '20000000-0000-0000-0000-000000000071',
        '10000000-0000-0000-0000-000000000075',
        'school_director', TRUE, 'full'
      )$$,
    '23505', 'duplicate key value violates unique constraint "idx_school_memberships_one_active_director"',
    'the database rejects a second active director'
);

INSERT INTO public.assignments (
    id, school_id, title, description, category, audience_role, assigned_by,
    status, visibility, requires_review, allow_resubmission
) VALUES (
    '60000000-0000-0000-0000-000000000071',
    '20000000-0000-0000-0000-000000000071',
    'Original assignment', 'Original directions', 'general', 'parent',
    '10000000-0000-0000-0000-000000000072', 'published', 'assigned', TRUE, TRUE
);
INSERT INTO public.assignment_recipients (
    assignment_id, user_id, role_at_assignment, child_id, completion_status
) VALUES (
    '60000000-0000-0000-0000-000000000071',
    '10000000-0000-0000-0000-000000000073', 'parent',
    '40000000-0000-0000-0000-000000000071', 'submitted'
);
INSERT INTO public.assignment_submissions (
    id, assignment_id, school_id, submitted_by, status, attempt_number
) VALUES (
    '70000000-0000-0000-0000-000000000071',
    '60000000-0000-0000-0000-000000000071',
    '20000000-0000-0000-0000-000000000071',
    '10000000-0000-0000-0000-000000000073', 'submitted', 1
);
INSERT INTO public.school_events (
    id, school_id, title, start_at, created_by
) VALUES (
    '80000000-0000-0000-0000-000000000071',
    '20000000-0000-0000-0000-000000000071',
    'Family Picnic', NOW() + INTERVAL '7 days',
    '10000000-0000-0000-0000-000000000072'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000072', TRUE);
SELECT set_config('request.jwt.claim.email', 'chat-teacher@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000072","email":"chat-teacher@test.fireflyfm.local"}', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.update_assignment_details(
        '60000000-0000-0000-0000-000000000071',
        'Updated assignment', 'Clearer directions', NOW() + INTERVAL '5 days', FALSE
    )$$,
    'the assignment creator edits their assignment and revision rule'
);
SELECT ok(
    (SELECT title = 'Updated assignment' AND allow_resubmission = FALSE
     FROM public.assignments WHERE id = '60000000-0000-0000-0000-000000000071'),
    'assignment edits are stored'
);
SELECT lives_ok(
    $$SELECT * FROM public.review_assignment_submission_v2(
        '70000000-0000-0000-0000-000000000071',
        'accepted', 'Strong work', 'chat-first-review', 9
    )$$,
    'the assignment creator can accept and score a submission'
);
SELECT is(
    (SELECT score::INTEGER FROM public.assignment_submissions WHERE id = '70000000-0000-0000-0000-000000000071'),
    9,
    'the 1-10 score is stored with the review'
);
SELECT lives_ok(
    $$SELECT * FROM public.set_school_event_archived(
        '80000000-0000-0000-0000-000000000071', TRUE
    )$$,
    'an authorized school manager archives an event'
);
RESET ROLE;
SELECT ok((SELECT archived_at IS NOT NULL FROM public.school_events WHERE id = '80000000-0000-0000-0000-000000000071'), 'archived events retain their record');

SELECT lives_ok(
    $$UPDATE public.children
      SET active = FALSE
      WHERE id = '40000000-0000-0000-0000-000000000071'$$,
    'graduation archives the automatic family room'
);
SELECT ok(
    (SELECT archived_at IS NOT NULL
        AND archive_reason = 'child_left_school'
        AND retention_until > NOW()
     FROM public.chat_rooms WHERE room_type = 'child_family'),
    'a graduated child room is read-only with a bounded retention window'
);
SELECT ok(
    public.is_chat_room_member(
        (SELECT id FROM public.chat_rooms WHERE room_type = 'child_family'),
        '10000000-0000-0000-0000-000000000073'
    ),
    'the guardian can read the archived room during retention'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000074', TRUE);
SELECT set_config('request.jwt.claim.email', 'chat-hq@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000074","email":"chat-hq@test.fireflyfm.local"}', TRUE);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.fetch_my_managed_chat_rooms('20000000-0000-0000-0000-000000000071')),
    0,
    'HQ has no implicit access to private or school communication history'
);

SELECT * FROM finish();
ROLLBACK;
