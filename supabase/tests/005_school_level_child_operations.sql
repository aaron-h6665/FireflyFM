BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(71);

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000051', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'director-a@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000052', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'teacher-a@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000053', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'parent-a@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000054', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'teacher-b@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000055', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'director-b@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000056', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'parent-b@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

INSERT INTO public.profiles (id, display_name) VALUES
    ('10000000-0000-0000-0000-000000000051', 'Director Alpha'),
    ('10000000-0000-0000-0000-000000000052', 'Teacher Alpha'),
    ('10000000-0000-0000-0000-000000000053', 'Parent Alpha'),
    ('10000000-0000-0000-0000-000000000054', 'Teacher Beta'),
    ('10000000-0000-0000-0000-000000000055', 'Director Beta'),
    ('10000000-0000-0000-0000-000000000056', 'Parent Beta')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

INSERT INTO public.schools (id, name) VALUES
    ('20000000-0000-0000-0000-000000000051', 'Alpha School'),
    ('20000000-0000-0000-0000-000000000052', 'Beta School');

INSERT INTO public.school_memberships (id, school_id, user_id, role, active) VALUES
    ('30000000-0000-0000-0000-000000000051', '20000000-0000-0000-0000-000000000051', '10000000-0000-0000-0000-000000000051', 'school_director', TRUE),
    ('30000000-0000-0000-0000-000000000052', '20000000-0000-0000-0000-000000000051', '10000000-0000-0000-0000-000000000052', 'teacher', TRUE),
    ('30000000-0000-0000-0000-000000000053', '20000000-0000-0000-0000-000000000051', '10000000-0000-0000-0000-000000000053', 'parent', TRUE),
    ('30000000-0000-0000-0000-000000000054', '20000000-0000-0000-0000-000000000052', '10000000-0000-0000-0000-000000000054', 'teacher', TRUE),
    ('30000000-0000-0000-0000-000000000055', '20000000-0000-0000-0000-000000000052', '10000000-0000-0000-0000-000000000055', 'school_director', TRUE),
    ('30000000-0000-0000-0000-000000000056', '20000000-0000-0000-0000-000000000052', '10000000-0000-0000-0000-000000000056', 'parent', TRUE);

UPDATE public.school_memberships
SET access_state = 'full'
WHERE TRUE;

INSERT INTO public.children (id, school_id, first_name, last_name, birthdate, active) VALUES
    ('40000000-0000-0000-0000-000000000051', '20000000-0000-0000-0000-000000000051', 'Avery', 'Alpha', '2021-01-10', TRUE),
    ('40000000-0000-0000-0000-000000000052', '20000000-0000-0000-0000-000000000051', 'Blake', 'Alpha', '2022-02-11', TRUE),
    ('40000000-0000-0000-0000-000000000053', '20000000-0000-0000-0000-000000000052', 'Casey', 'Beta', '2021-03-12', TRUE);

INSERT INTO public.child_guardians (
    child_id, guardian_id, relationship, verification_status, verified_by, verified_at
) VALUES (
    '40000000-0000-0000-0000-000000000051',
    '10000000-0000-0000-0000-000000000053',
    'Parent', 'verified', '10000000-0000-0000-0000-000000000051', NOW()
);

INSERT INTO public.community_posts (id, school_id, body, created_by)
VALUES (
    '45000000-0000-0000-0000-000000000051',
    '20000000-0000-0000-0000-000000000051',
    'Visible to every active school adult',
    '10000000-0000-0000-0000-000000000051'
);

SELECT is(public.get_firefly_schema_version(), 20260904150100::BIGINT, 'schema version includes Zelle onboarding billing');
SELECT isnt(
    has_function_privilege('authenticated', 'public.create_child_for_current_parent(uuid,text,text,date)', 'EXECUTE'),
    TRUE,
    'parents cannot execute the legacy direct-child creation RPC'
);
SELECT isnt(
    has_function_privilege('authenticated', 'public.join_chat_room(text)', 'EXECUTE'),
    TRUE,
    'members cannot execute the legacy join-code RPC'
);
SELECT isnt(
    has_function_privilege('authenticated', 'public.escalate_missed_medication_tasks()', 'EXECUTE'),
    TRUE,
    'clients cannot run the legacy medication escalation scheduler'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM pg_trigger WHERE tgname = 'assign_child_to_default_classroom_trigger' AND NOT tgisinternal),
    0,
    'new children are not assigned to classrooms'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM pg_constraint WHERE conrelid = 'public.children'::regclass AND conname = 'children_birthdate_required'),
    1,
    'new child records require a birthdate'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000052', TRUE);
SELECT set_config('request.jwt.claim.email', 'teacher-a@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000052","email":"teacher-a@test.fireflyfm.local"}', TRUE);

SELECT ok(public.can_access_child('40000000-0000-0000-0000-000000000051', auth.uid()), 'teacher can access one child at their school');
SELECT ok(public.can_access_child('40000000-0000-0000-0000-000000000052', auth.uid()), 'teacher can access every active child at their school');
SELECT isnt(public.can_access_child('40000000-0000-0000-0000-000000000053', auth.uid()), TRUE, 'teacher cannot access another school child');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.children), 2, 'child RLS returns only the teacher school roster');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.community_posts), 1, 'an active teacher can view school community posts');
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.fetch_school_directory('20000000-0000-0000-0000-000000000051')),
    3,
    'directory returns every active adult school member'
);
SELECT ok(
    (SELECT bool_and(
        (to_jsonb(directory_row) - ARRAY['user_id', 'display_name', 'avatar_url', 'school_role']::TEXT[]) = '{}'::JSONB
    ) FROM public.fetch_school_directory('20000000-0000-0000-0000-000000000051') directory_row),
    'directory rows expose only name, avatar, role, and user identifier'
);
SELECT throws_ok(
    $$SELECT * FROM public.create_director_chat_room(
        '20000000-0000-0000-0000-000000000051', 'Teacher Room', NULL, NULL,
        ARRAY['10000000-0000-0000-0000-000000000053'::UUID], 'teacher-create'
    )$$,
    'P0001', 'Only a school director can create rooms',
    'teachers cannot create rooms'
);
SELECT throws_ok(
    $$INSERT INTO public.notifications (school_id, title, body, category)
      VALUES ('20000000-0000-0000-0000-000000000051', 'Direct', 'Not allowed', 'general')$$,
    '42501', 'new row violates row-level security policy for table "notifications"',
    'clients cannot create a notification outside a workflow transaction'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000051', TRUE);
SELECT set_config('request.jwt.claim.email', 'director-a@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000051","email":"director-a@test.fireflyfm.local"}', TRUE);

SELECT throws_ok(
    $$INSERT INTO public.children (school_id, first_name, last_name, active)
      VALUES ('20000000-0000-0000-0000-000000000051', 'Missing', 'Birthdate', TRUE)$$,
    '23514', 'new row for relation "children" violates check constraint "children_birthdate_required"',
    'a director cannot create a new child without a birthdate'
);
SELECT lives_ok(
    $$SELECT * FROM public.create_director_chat_room(
        '20000000-0000-0000-0000-000000000051', 'School Updates', 'Selected families and staff', NULL,
        ARRAY['10000000-0000-0000-0000-000000000052'::UUID, '10000000-0000-0000-0000-000000000053'::UUID],
        'director-room-1'
    )$$,
    'director creates a selected-member room transactionally'
);
SELECT lives_ok(
    $$SELECT * FROM public.create_director_chat_room(
        '20000000-0000-0000-0000-000000000051', 'School Updates', 'Selected families and staff', NULL,
        ARRAY['10000000-0000-0000-0000-000000000052'::UUID, '10000000-0000-0000-0000-000000000053'::UUID],
        'director-room-1'
    )$$,
    'room creation is idempotent'
);

RESET ROLE;
SELECT is((SELECT COUNT(*)::INTEGER FROM public.chat_rooms WHERE school_id = '20000000-0000-0000-0000-000000000051'), 3, 'idempotent room retry adds one custom room beside the automatic rooms');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.chat_participants WHERE room_id = (SELECT result_id FROM public.school_workflow_mutations WHERE idempotency_key = 'director-room-1')), 3, 'room and initial participants commit together');
SELECT is((SELECT room_type FROM public.chat_rooms WHERE id = (SELECT result_id FROM public.school_workflow_mutations WHERE idempotency_key = 'director-room-1')), 'custom', 'manually created room has the custom lifecycle');
SELECT ok((SELECT invite_hash IS NULL FROM public.chat_rooms WHERE id = (SELECT result_id FROM public.school_workflow_mutations WHERE idempotency_key = 'director-room-1')), 'director-managed rooms have no join code');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000052', TRUE);
SELECT set_config('request.jwt.claim.email', 'teacher-a@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000052","email":"teacher-a@test.fireflyfm.local"}', TRUE);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.fetch_my_managed_chat_rooms('20000000-0000-0000-0000-000000000051')),
    3,
    'an added teacher discovers automatic and custom rooms through the server-authorized room list'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000053', TRUE);
SELECT set_config('request.jwt.claim.email', 'parent-a@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000053","email":"parent-a@test.fireflyfm.local"}', TRUE);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.community_posts), 1, 'an active full-access parent can view school community posts');
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.fetch_my_managed_chat_rooms('20000000-0000-0000-0000-000000000051')),
    3,
    'an added parent discovers automatic and custom rooms through the server-authorized room list'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000051', TRUE);
SELECT set_config('request.jwt.claim.email', 'director-a@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000051","email":"director-a@test.fireflyfm.local"}', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.set_director_chat_participants(
        (SELECT id FROM public.chat_rooms WHERE name = 'School Updates'),
        ARRAY['10000000-0000-0000-0000-000000000052'::UUID]
    )$$,
    'director can replace room membership'
);
RESET ROLE;
SELECT is((SELECT COUNT(*)::INTEGER FROM public.chat_participants WHERE room_id = (SELECT result_id FROM public.school_workflow_mutations WHERE idempotency_key = 'director-room-1')), 2, 'removed participants lose room membership immediately');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000052', TRUE);
SELECT set_config('request.jwt.claim.email', 'teacher-a@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000052","email":"teacher-a@test.fireflyfm.local"}', TRUE);
SELECT lives_ok(
    $$SELECT public.leave_managed_chat_room(
        (SELECT id FROM public.chat_rooms WHERE name = 'School Updates')
    )$$,
    'an invited teacher can leave a managed room'
);
RESET ROLE;
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.chat_participants WHERE room_id = (SELECT result_id FROM public.school_workflow_mutations WHERE idempotency_key = 'director-room-1')),
    1,
    'self-leave immediately revokes access while retaining the director participant'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.notifications WHERE category = 'chat_participant_left'),
    1,
    'self-leave transaction notifies the school director once'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000053', TRUE);
SELECT set_config('request.jwt.claim.email', 'parent-a@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000053","email":"parent-a@test.fireflyfm.local"}', TRUE);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.chat_rooms), 2, 'a parent removed from a custom room retains only automatic family and school rooms');
SELECT lives_ok(
    $$SELECT * FROM public.submit_child_connection_request(
        '20000000-0000-0000-0000-000000000051', 'Blake', 'Alpha', '2022-02-11', 'Parent', 'connect-blake'
    )$$,
    'an onboarding parent can submit a child connection request'
);
SELECT lives_ok(
    $$SELECT * FROM public.submit_child_connection_request(
        '20000000-0000-0000-0000-000000000051', 'Blake', 'Alpha', '2022-02-11', 'Parent', 'connect-blake'
    )$$,
    'a duplicate child connection retry is idempotent'
);

RESET ROLE;
SELECT is((SELECT COUNT(*)::INTEGER FROM public.child_connection_requests WHERE idempotency_key = 'connect-blake'), 1, 'duplicate request creates one pending review');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.child_guardians WHERE child_id = '40000000-0000-0000-0000-000000000052'), 0, 'pending connection grants no child relationship');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.notifications WHERE category = 'child_connection_request'), 1, 'connection request creates one deduplicated notification');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.notification_recipients recipient JOIN public.notifications notification ON notification.id = recipient.notification_id WHERE notification.category = 'child_connection_request' AND recipient.user_id = '10000000-0000-0000-0000-000000000051'), 1, 'connection request routes to the school director');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.notification_outbox outbox JOIN public.notifications notification ON notification.id = outbox.notification_id WHERE notification.category = 'child_connection_request'), 1, 'workflow transaction also creates its push outbox row');

UPDATE public.notification_outbox
SET attempt_count = 8
WHERE notification_id = (SELECT id FROM public.notifications WHERE category = 'child_connection_request');
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claim.role', 'service_role', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', TRUE);
SELECT lives_ok(
    $$SELECT public.complete_notification_delivery(
        (SELECT outbox.id FROM public.notification_outbox outbox JOIN public.notifications notification ON notification.id = outbox.notification_id WHERE notification.category = 'child_connection_request'),
        FALSE, 'APNs unavailable'
    )$$,
    'outbox worker records a terminal delivery failure'
);
RESET ROLE;
SELECT is(
    (SELECT recipient.delivery_state FROM public.notification_recipients recipient JOIN public.notifications notification ON notification.id = recipient.notification_id WHERE notification.category = 'child_connection_request'),
    'expired',
    'delivery expires after the bounded retry limit'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000051', TRUE);
SELECT set_config('request.jwt.claim.email', 'director-a@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000051","email":"director-a@test.fireflyfm.local"}', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.review_child_connection_request(
        (SELECT id FROM public.child_connection_requests WHERE idempotency_key = 'connect-blake'),
        'approved', '40000000-0000-0000-0000-000000000052', 'Identity matched', 'review-connect-blake'
    )$$,
    'director approval creates the verified guardian relationship'
);
RESET ROLE;
SELECT is((SELECT COUNT(*)::INTEGER FROM public.child_guardians WHERE child_id = '40000000-0000-0000-0000-000000000052' AND guardian_id = '10000000-0000-0000-0000-000000000053' AND verification_status = 'verified'), 1, 'approved request links only the intended parent and child');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.notifications WHERE category = 'child_connection_decision'), 1, 'connection decision notifies the requesting parent');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.workflow_audit_events WHERE source_type = 'child_connection_request' AND event_type = 'approved'), 1, 'connection approval retains an audit event');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000052', TRUE);
SELECT set_config('request.jwt.claim.email', 'teacher-a@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000052","email":"teacher-a@test.fireflyfm.local"}', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.record_school_attendance(
        '40000000-0000-0000-0000-000000000052', 'check_in', NOW(), NULL, 'attendance-blake-in'
    )$$,
    'teacher records attendance for any child in their school'
);
SELECT lives_ok(
    $$SELECT * FROM public.record_school_attendance(
        '40000000-0000-0000-0000-000000000052', 'check_in', NOW(), NULL, 'attendance-blake-in'
    )$$,
    'attendance retry is idempotent'
);
RESET ROLE;
SELECT is((SELECT COUNT(*)::INTEGER FROM public.attendance_sessions WHERE idempotency_key = 'attendance-blake-in'), 1, 'attendance retry creates one session');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.notifications WHERE category = 'attendance_check_in'), 1, 'attendance check-in notifies the verified guardian');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000052', TRUE);
SELECT set_config('request.jwt.claim.email', 'teacher-a@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000052","email":"teacher-a@test.fireflyfm.local"}', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.record_child_care_event(
        '40000000-0000-0000-0000-000000000052', 'potty', NOW(), '{"result":"successful"}', 'parent', NULL, 'care-blake-potty'
    )$$,
    'teacher records a structured routine care event'
);
SELECT lives_ok(
    $$SELECT * FROM public.record_child_care_event(
        '40000000-0000-0000-0000-000000000052', 'potty', NOW(), '{"result":"successful"}', 'parent', NULL, 'care-blake-potty'
    )$$,
    'care event retry is idempotent'
);
SELECT lives_ok(
    $$SELECT * FROM public.record_child_care_event(
        '40000000-0000-0000-0000-000000000052', 'photo', NOW(),
        '{"summary":"Playground","photo_path":"schools/20000000-0000-0000-0000-000000000051/care_events/40000000-0000-0000-0000-000000000052/parent/10000000-0000-0000-0000-000000000052/photo.jpg"}',
        'parent', NULL, 'care-blake-photo'
    )$$,
    'teacher records a private parent-visible care photo reference'
);
SELECT ok(
    public.can_write_child_care_file(
        'schools/20000000-0000-0000-0000-000000000051/care_events/40000000-0000-0000-0000-000000000052/parent/10000000-0000-0000-0000-000000000052/photo.jpg',
        auth.uid()
    ),
    'same-school teacher can upload the care photo at their owner-scoped path'
);
SELECT lives_ok(
    $$SELECT * FROM public.record_school_attendance(
        '40000000-0000-0000-0000-000000000052', 'check_out', NOW(), NULL, 'attendance-blake-out'
    )$$,
    'checkout closes the attendance session and creates a daily summary'
);
RESET ROLE;
SELECT is((SELECT COUNT(*)::INTEGER FROM public.child_care_events WHERE idempotency_key = 'care-blake-potty'), 1, 'care retry creates one feed event');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.notifications WHERE source_type = 'child_care_event'), 0, 'routine care remains in the feed instead of notifying');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.notifications WHERE category = 'daily_care_summary'), 1, 'checkout sends one digest rather than per-routine-event notifications');
SELECT is((SELECT route->>'type' FROM public.notifications WHERE category = 'daily_care_summary'), 'child_feed', 'daily summary opens the exact child feed');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000052', TRUE);
SELECT set_config('request.jwt.claim.email', 'teacher-a@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000052","email":"teacher-a@test.fireflyfm.local"}', TRUE);
SELECT throws_ok(
    $$SELECT * FROM public.record_child_care_event(
        '40000000-0000-0000-0000-000000000052', 'medication', NOW(), '{}', 'parent', NULL, 'care-blake-medication'
    )$$,
    'P0001', 'Medication care requires an approved authorization task',
    'medication cannot be administered without an approved assignment-backed task'
);
SELECT throws_ok(
    $$SELECT * FROM public.record_school_attendance(
        '40000000-0000-0000-0000-000000000053', 'check_in', NOW(), NULL, 'cross-school-attendance'
    )$$,
    'P0001', 'You cannot record attendance for this child',
    'teacher cannot record attendance for another school'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000051', TRUE);
SELECT set_config('request.jwt.claim.email', 'director-a@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000051","email":"director-a@test.fireflyfm.local"}', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.correct_attendance_session(
        (SELECT id FROM public.attendance_sessions WHERE idempotency_key = 'attendance-blake-out'),
        (SELECT checked_in_at FROM public.attendance_sessions WHERE idempotency_key = 'attendance-blake-out'),
        (SELECT checked_out_at FROM public.attendance_sessions WHERE idempotency_key = 'attendance-blake-out') + INTERVAL '1 minute',
        'checked_out', 'Corrected checkout', 'Front desk verified the departure time'
    )$$,
    'director can correct attendance with an audit reason'
);
SELECT lives_ok(
    $$SELECT public.delete_director_chat_room(
        (SELECT id FROM public.chat_rooms WHERE name = 'School Updates')
    )$$,
    'director can soft-delete a managed room'
);
RESET ROLE;
SELECT is((SELECT COUNT(*)::INTEGER FROM public.attendance_corrections), 1, 'attendance correction preserves the prior and revised values');
SELECT ok((SELECT deleted_at IS NOT NULL FROM public.chat_rooms WHERE id = (SELECT result_id FROM public.school_workflow_mutations WHERE idempotency_key = 'director-room-1')), 'soft-deleted room is retained for audit');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.chat_participants WHERE room_id = (SELECT result_id FROM public.school_workflow_mutations WHERE idempotency_key = 'director-room-1')), 0, 'room deletion immediately revokes participant access');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000053', TRUE);
SELECT set_config('request.jwt.claim.email', 'parent-a@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000053","email":"parent-a@test.fireflyfm.local"}', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.submit_family_request(
        '40000000-0000-0000-0000-000000000052', 'pickup_change', '{"pickup_person":"Grandparent"}', 'family-blake-pickup'
    )$$,
    'verified parent submits a structured family request'
);
SELECT isnt(
    public.can_access_child_care_file(
        'schools/20000000-0000-0000-0000-000000000051/care_events/40000000-0000-0000-0000-000000000052/staff_only/10000000-0000-0000-0000-000000000052/private.jpg',
        auth.uid()
    ),
    TRUE,
    'guardian cannot read a staff-only care photo'
);
SELECT lives_ok(
    $$INSERT INTO public.notification_preferences (user_id, category, enabled)
      VALUES ('10000000-0000-0000-0000-000000000053', 'attendance', FALSE)$$,
    'member can disable a routine notification category'
);
SELECT throws_ok(
    $$INSERT INTO public.notification_preferences (user_id, category, enabled)
      VALUES ('10000000-0000-0000-0000-000000000053', 'medication', FALSE)$$,
    '23514', 'new row for relation "notification_preferences" violates check constraint "notification_preferences_check"',
    'medication safety alerts cannot be completely disabled'
);
RESET ROLE;
SELECT is(
    public.notification_delivery_available_at(
        '10000000-0000-0000-0000-000000000053', 'attendance_check_out', 'routine'
    ),
    NULL::TIMESTAMPTZ,
    'broad category preferences suppress their mapped routine delivery events'
);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.family_requests WHERE idempotency_key = 'family-blake-pickup'), 1, 'family request is stored once');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.notification_recipients recipient JOIN public.notifications notification ON notification.id = recipient.notification_id WHERE notification.category = 'family_request'), 2, 'family request routes to all active teachers and directors in the school');

SELECT * FROM finish();
ROLLBACK;
