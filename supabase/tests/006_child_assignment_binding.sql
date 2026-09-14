BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(23);

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000061', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'binding-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000062', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'binding-parent@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000064', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'binding-teacher@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

INSERT INTO public.schools (id, name)
VALUES ('20000000-0000-0000-0000-000000000061', 'Binding Test School');

INSERT INTO public.school_memberships (id, school_id, user_id, role, active) VALUES
    ('30000000-0000-0000-0000-000000000061', '20000000-0000-0000-0000-000000000061', '10000000-0000-0000-0000-000000000061', 'school_director', TRUE),
    ('30000000-0000-0000-0000-000000000062', '20000000-0000-0000-0000-000000000061', '10000000-0000-0000-0000-000000000062', 'parent', TRUE),
    ('30000000-0000-0000-0000-000000000064', '20000000-0000-0000-0000-000000000061', '10000000-0000-0000-0000-000000000064', 'teacher', TRUE);
UPDATE public.school_memberships
SET access_state = CASE WHEN role = 'school_director' THEN 'full' ELSE 'onboarding' END
WHERE school_id = '20000000-0000-0000-0000-000000000061';

INSERT INTO public.children (id, school_id, first_name, last_name, birthdate, active)
VALUES ('40000000-0000-0000-0000-000000000061', '20000000-0000-0000-0000-000000000061', 'Morgan', 'Firefly', '2022-04-15', TRUE);
INSERT INTO public.child_guardians (
    child_id, guardian_id, relationship, verification_status, verified_by, verified_at
) VALUES (
    '40000000-0000-0000-0000-000000000061', '10000000-0000-0000-0000-000000000062',
    'Parent', 'verified', '10000000-0000-0000-0000-000000000061', NOW()
);

INSERT INTO public.onboarding_templates (
    id, school_id, target_role, name, version, status, created_by, published_at
) VALUES (
    '50000000-0000-0000-0000-000000000061', '20000000-0000-0000-0000-000000000061',
    'parent', 'Parent child records', 1, 'published', '10000000-0000-0000-0000-000000000061', NOW()
);
INSERT INTO public.onboarding_template_requirements (
    id, template_id, requirement_key, position, requirement_type, title,
    subject_scope, blocks_access, child_record_binding
) VALUES
    ('51000000-0000-0000-0000-000000000061', '50000000-0000-0000-0000-000000000061', '52000000-0000-0000-0000-000000000061', 0, 'acknowledgement', 'Core identity', 'member', TRUE, 'none'),
    ('51000000-0000-0000-0000-000000000062', '50000000-0000-0000-0000-000000000061', '52000000-0000-0000-0000-000000000062', 1, 'document', 'Immunization record', 'child', FALSE, 'immunization_record'),
    ('51000000-0000-0000-0000-000000000063', '50000000-0000-0000-0000-000000000061', '52000000-0000-0000-0000-000000000063', 2, 'document', 'Medication authorization', 'child', FALSE, 'medication_authorization');

INSERT INTO public.onboarding_instances (id, school_id, membership_id, template_id, status)
VALUES (
    '53000000-0000-0000-0000-000000000061', '20000000-0000-0000-0000-000000000061',
    '30000000-0000-0000-0000-000000000062', '50000000-0000-0000-0000-000000000061', 'in_progress'
);

INSERT INTO public.assignments (
    id, school_id, child_id, title, category, audience_role, assigned_by,
    status, visibility, requires_review, legacy_source_type, legacy_source_id
) VALUES
    ('60000000-0000-0000-0000-000000000061', '20000000-0000-0000-0000-000000000061', '40000000-0000-0000-0000-000000000061', 'Immunization record', 'onboarding', 'parent', '10000000-0000-0000-0000-000000000061', 'published', 'assigned', TRUE, 'test_fixture', '60000000-0000-0000-0000-000000000061'),
    ('60000000-0000-0000-0000-000000000062', '20000000-0000-0000-0000-000000000061', '40000000-0000-0000-0000-000000000061', 'Medication authorization', 'onboarding', 'parent', '10000000-0000-0000-0000-000000000061', 'published', 'assigned', TRUE, 'test_fixture', '60000000-0000-0000-0000-000000000062');
INSERT INTO public.assignment_recipients (
    assignment_id, user_id, role_at_assignment, child_id, completion_status
) VALUES
    ('60000000-0000-0000-0000-000000000061', '10000000-0000-0000-0000-000000000062', 'parent', '40000000-0000-0000-0000-000000000061', 'submitted'),
    ('60000000-0000-0000-0000-000000000062', '10000000-0000-0000-0000-000000000062', 'parent', '40000000-0000-0000-0000-000000000061', 'submitted');

INSERT INTO public.onboarding_requirement_instances (
    id, onboarding_instance_id, template_requirement_id, assignment_id, child_id, status
) VALUES
    ('54000000-0000-0000-0000-000000000061', '53000000-0000-0000-0000-000000000061', '51000000-0000-0000-0000-000000000061', NULL, NULL, 'approved'),
    ('54000000-0000-0000-0000-000000000062', '53000000-0000-0000-0000-000000000061', '51000000-0000-0000-0000-000000000062', '60000000-0000-0000-0000-000000000061', '40000000-0000-0000-0000-000000000061', 'in_review'),
    ('54000000-0000-0000-0000-000000000063', '53000000-0000-0000-0000-000000000061', '51000000-0000-0000-0000-000000000063', '60000000-0000-0000-0000-000000000062', '40000000-0000-0000-0000-000000000061', 'in_review');

INSERT INTO public.assignment_submissions (
    id, assignment_id, school_id, submitted_by, status, attempt_number, structured_payload
) VALUES
    ('70000000-0000-0000-0000-000000000061', '60000000-0000-0000-0000-000000000061', '20000000-0000-0000-0000-000000000061', '10000000-0000-0000-0000-000000000062', 'submitted', 1, '{"expires_on":"2027-08-31"}'),
    ('70000000-0000-0000-0000-000000000062', '60000000-0000-0000-0000-000000000062', '20000000-0000-0000-0000-000000000061', '10000000-0000-0000-0000-000000000062', 'submitted', 1, '{"medication_name":"Rescue medication","dosage":"5 mg","scheduled_at":"2026-07-23T14:00:00Z","starts_on":"2026-07-23","ends_on":"2027-07-23","instructions":"Administer as authorized"}');
INSERT INTO public.assignment_submission_attachments (
    id, submission_id, school_id, private_file_path, file_name, content_type
) VALUES
    ('71000000-0000-0000-0000-000000000061', '70000000-0000-0000-0000-000000000061', '20000000-0000-0000-0000-000000000061', 'schools/binding/immunization.pdf', 'immunization.pdf', 'application/pdf'),
    ('71000000-0000-0000-0000-000000000062', '70000000-0000-0000-0000-000000000062', '20000000-0000-0000-0000-000000000061', 'schools/binding/medication.pdf', 'medication.pdf', 'application/pdf');

SELECT lives_ok(
    $$SELECT public.refresh_onboarding_access('30000000-0000-0000-0000-000000000062')$$,
    'access gate can be recalculated from blocking requirements'
);
SELECT is(
    (SELECT access_state FROM public.school_memberships WHERE id = '30000000-0000-0000-0000-000000000062'),
    'full',
    'approved core identity grants access while nonblocking child forms remain open'
);

SELECT lives_ok(
    $$UPDATE public.assignment_submissions
      SET status = 'accepted', reviewed_by = '10000000-0000-0000-0000-000000000061', reviewed_at = NOW()
      WHERE id = '70000000-0000-0000-0000-000000000061'$$,
    'accepting an immunization submission binds the child document'
);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.child_documents WHERE source_assignment_submission_id = '70000000-0000-0000-0000-000000000061'), 1, 'approval creates one child document');
SELECT is((SELECT file_path FROM public.child_documents WHERE source_assignment_submission_id = '70000000-0000-0000-0000-000000000061'), 'schools/binding/immunization.pdf', 'child document references the evidence file without another upload');
SELECT is((SELECT source_attachment_id FROM public.child_documents WHERE source_assignment_submission_id = '70000000-0000-0000-0000-000000000061'), '71000000-0000-0000-0000-000000000061'::UUID, 'child document retains the exact assignment attachment source');
SELECT is((SELECT expires_on FROM public.child_documents WHERE source_assignment_submission_id = '70000000-0000-0000-0000-000000000061'), '2027-08-31'::DATE, 'verified document receives the structured expiry date');
SELECT lives_ok(
    $$UPDATE public.assignment_submissions SET status = 'changes_requested' WHERE id = '70000000-0000-0000-0000-000000000061';
      UPDATE public.assignment_submissions
      SET status = 'accepted', reviewed_by = '10000000-0000-0000-0000-000000000061', reviewed_at = NOW()
      WHERE id = '70000000-0000-0000-0000-000000000061'$$,
    'replayed approval updates the bound record idempotently'
);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.child_documents WHERE source_assignment_submission_id = '70000000-0000-0000-0000-000000000061'), 1, 'replayed approval does not duplicate evidence');

SELECT lives_ok(
    $$UPDATE public.assignment_submissions
      SET status = 'accepted', reviewed_by = '10000000-0000-0000-0000-000000000061', reviewed_at = NOW()
      WHERE id = '70000000-0000-0000-0000-000000000062'$$,
    'accepting medication evidence creates the verified instruction and task'
);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.medication_instructions WHERE source_assignment_submission_id = '70000000-0000-0000-0000-000000000062'), 1, 'medication approval creates one verified instruction');
SELECT is((SELECT title FROM public.medication_instructions WHERE source_assignment_submission_id = '70000000-0000-0000-0000-000000000062'), 'Rescue medication', 'medication instruction uses the approved structured values');
SELECT ok((SELECT verified_at IS NOT NULL FROM public.medication_instructions WHERE source_assignment_submission_id = '70000000-0000-0000-0000-000000000062'), 'medication instruction records its verification time');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.medication_tasks task JOIN public.medication_instructions instruction ON instruction.id = task.instruction_id WHERE instruction.source_assignment_submission_id = '70000000-0000-0000-0000-000000000062'), 1, 'medication approval creates its due operational task');
SELECT is((SELECT due_at FROM public.medication_tasks task JOIN public.medication_instructions instruction ON instruction.id = task.instruction_id WHERE instruction.source_assignment_submission_id = '70000000-0000-0000-0000-000000000062'), '2026-07-23T14:00:00Z'::TIMESTAMPTZ, 'medication task uses the approved schedule');
SELECT isnt(
    has_function_privilege('authenticated', 'public.create_medication_instruction(uuid,uuid,text,text,text,timestamptz)', 'EXECUTE'),
    TRUE,
    'clients cannot bypass assignment approval to create medication instructions'
);

UPDATE public.medication_tasks
SET due_at = NOW() - INTERVAL '20 minutes'
WHERE instruction_id = (
    SELECT id FROM public.medication_instructions
    WHERE source_assignment_submission_id = '70000000-0000-0000-0000-000000000062'
);
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claim.role', 'service_role', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', TRUE);
SELECT lives_ok(
    $$SELECT public.process_due_medication_tasks()$$,
    'service worker advances due and missed medication tasks'
);
SELECT lives_ok(
    $$SELECT public.process_due_medication_tasks()$$,
    'medication scheduler retry is idempotent'
);
RESET ROLE;
SELECT is(
    (SELECT status FROM public.medication_tasks task JOIN public.medication_instructions instruction ON instruction.id = task.instruction_id WHERE instruction.source_assignment_submission_id = '70000000-0000-0000-0000-000000000062'),
    'missed',
    'overdue unacknowledged medication becomes missed'
);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.medication_escalations), 1, 'missed medication creates one audited escalation');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.notifications WHERE category = 'medication_due'), 1, 'due medication creates one deduplicated notification');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.notifications WHERE category = 'medication_missed' AND priority = 'urgent'), 1, 'missed medication creates one urgent notification');
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.notification_recipients recipient JOIN public.notifications notification ON notification.id = recipient.notification_id WHERE notification.category IN ('medication_due', 'medication_missed')),
    4,
    'due and missed medication route to every active teacher and director'
);

SELECT * FROM finish();
ROLLBACK;
