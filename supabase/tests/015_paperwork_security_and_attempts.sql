BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(14);

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000151', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'paperwork-security-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000152', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'paperwork-security-parent@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000153', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'paperwork-security-other@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

INSERT INTO public.schools (id, name)
VALUES ('20000000-0000-0000-0000-000000000151', 'Paperwork Security School');

INSERT INTO public.school_memberships (id, school_id, user_id, role, active, access_state) VALUES
    ('30000000-0000-0000-0000-000000000151', '20000000-0000-0000-0000-000000000151', '10000000-0000-0000-0000-000000000151', 'school_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000152', '20000000-0000-0000-0000-000000000151', '10000000-0000-0000-0000-000000000152', 'parent', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000153', '20000000-0000-0000-0000-000000000151', '10000000-0000-0000-0000-000000000153', 'teacher', TRUE, 'full');

-- Membership creation intentionally fails closed when no matching published
-- template exists. These fixtures represent already-approved members.
UPDATE public.school_memberships
SET access_state = 'full'
WHERE school_id = '20000000-0000-0000-0000-000000000151';

INSERT INTO public.onboarding_templates (
    id, school_id, target_role, name, version, status, created_by, published_at
) VALUES (
    '40000000-0000-0000-0000-000000000151', '20000000-0000-0000-0000-000000000151',
    'teacher', 'Storage binding', 1, 'published', '10000000-0000-0000-0000-000000000151', NOW()
);

INSERT INTO public.onboarding_template_requirements (
    id, template_id, requirement_key, position, requirement_type, title,
    subject_scope, blocks_access, child_record_binding
) VALUES
    ('41000000-0000-0000-0000-000000000151', '40000000-0000-0000-0000-000000000151', '42000000-0000-0000-0000-000000000151', 0, 'document', 'Authorized document', 'member', TRUE, 'none'),
    ('41000000-0000-0000-0000-000000000152', '40000000-0000-0000-0000-000000000151', '42000000-0000-0000-0000-000000000152', 1, 'document', 'Sibling document', 'member', TRUE, 'none');

INSERT INTO public.onboarding_instances (id, school_id, membership_id, template_id, status)
VALUES (
    '43000000-0000-0000-0000-000000000151', '20000000-0000-0000-0000-000000000151',
    '30000000-0000-0000-0000-000000000153', '40000000-0000-0000-0000-000000000151', 'in_progress'
);

INSERT INTO public.assignments (
    id, school_id, title, category, audience_role, assigned_by, status, visibility, requires_review
) VALUES (
    '44000000-0000-0000-0000-000000000151', '20000000-0000-0000-0000-000000000151',
    'Authorized document', 'training', 'teacher', '10000000-0000-0000-0000-000000000151',
    'published', 'assigned', TRUE
);
INSERT INTO public.assignment_recipients (assignment_id, user_id, role_at_assignment)
VALUES ('44000000-0000-0000-0000-000000000151', '10000000-0000-0000-0000-000000000153', 'teacher');
INSERT INTO public.onboarding_requirement_instances (
    id, onboarding_instance_id, template_requirement_id, assignment_id, status
) VALUES (
    '45000000-0000-0000-0000-000000000151', '43000000-0000-0000-0000-000000000151',
    '41000000-0000-0000-0000-000000000151', '44000000-0000-0000-0000-000000000151', 'in_progress'
);

INSERT INTO public.paperwork_assignments (id, school_id, title, assigned_by, status, requires_review) VALUES
    ('46000000-0000-0000-0000-000000000151', '20000000-0000-0000-0000-000000000151', 'Attempt review', '10000000-0000-0000-0000-000000000151', 'published', TRUE),
    ('46000000-0000-0000-0000-000000000152', '20000000-0000-0000-0000-000000000151', 'Identity normalization', '10000000-0000-0000-0000-000000000151', 'published', TRUE);

INSERT INTO public.paperwork_assignment_recipients (assignment_id, parent_id, completion_status)
VALUES ('46000000-0000-0000-0000-000000000151', '10000000-0000-0000-0000-000000000152', 'resubmitted');
INSERT INTO public.paperwork_assignment_recipients (assignment_id, parent_id, user_id)
VALUES (
    '46000000-0000-0000-0000-000000000152',
    '10000000-0000-0000-0000-000000000152',
    '10000000-0000-0000-0000-000000000153'
);

INSERT INTO public.paperwork_submissions (
    id, assignment_id, school_id, submitted_by, status, attempt_number, submitted_at
) VALUES
    ('47000000-0000-0000-0000-000000000151', '46000000-0000-0000-0000-000000000151', '20000000-0000-0000-0000-000000000151', '10000000-0000-0000-0000-000000000152', 'submitted', 1, '2026-09-15T12:00:00Z'),
    ('47000000-0000-0000-0000-000000000152', '46000000-0000-0000-0000-000000000151', '20000000-0000-0000-0000-000000000151', '10000000-0000-0000-0000-000000000152', 'resubmitted', 2, '2026-09-16T12:00:00Z');

SELECT ok(
    EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'paperwork_assignment_recipients_user_identity_check'
    ),
    'recipient identity equality is enforced by a database constraint'
);
SELECT is(
    (SELECT user_id FROM public.paperwork_assignment_recipients
     WHERE assignment_id = '46000000-0000-0000-0000-000000000151'),
    '10000000-0000-0000-0000-000000000152'::UUID,
    'legacy parent_id-only writes populate canonical user_id'
);
SELECT is(
    (SELECT parent_id FROM public.paperwork_assignment_recipients
     WHERE assignment_id = '46000000-0000-0000-0000-000000000152'),
    '10000000-0000-0000-0000-000000000153'::UUID,
    'conflicting legacy parent_id is normalized to canonical user_id'
);

SELECT ok(public.can_access_school_private_file(
    'schools/20000000-0000-0000-0000-000000000151/document_submissions/41000000-0000-0000-0000-000000000151/evidence.pdf',
    '10000000-0000-0000-0000-000000000153'
), 'assignment recipient can read the exact linked requirement path');
SELECT isnt(public.can_access_school_private_file(
    'schools/20000000-0000-0000-0000-000000000151/document_submissions/41000000-0000-0000-0000-000000000152/forged.pdf',
    '10000000-0000-0000-0000-000000000153'
), TRUE, 'assignment recipient cannot read a sibling requirement path');
SELECT ok(public.can_write_school_private_file(
    'schools/20000000-0000-0000-0000-000000000151/document_submissions/41000000-0000-0000-0000-000000000151/evidence.pdf',
    '10000000-0000-0000-0000-000000000153'
), 'assignment recipient can write the exact linked requirement path');
SELECT isnt(public.can_write_school_private_file(
    'schools/20000000-0000-0000-0000-000000000151/document_submissions/41000000-0000-0000-0000-000000000152/forged.pdf',
    '10000000-0000-0000-0000-000000000153'
), TRUE, 'assignment recipient cannot write a sibling requirement path');
SELECT isnt(public.can_write_school_private_file(
    'schools/not-a-uuid/document_submissions/not-a-uuid/forged.pdf',
    '10000000-0000-0000-0000-000000000153'
), TRUE, 'malformed private paths fail closed');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000151', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000151"}', TRUE);
SELECT throws_ok(
    $$SELECT * FROM public.review_paperwork_submission_v2(
        '47000000-0000-0000-0000-000000000151', 'accepted', NULL
    )$$,
    'P0001', 'Only the latest paperwork submission can be reviewed',
    'a stale paperwork attempt cannot be reviewed'
);
SELECT lives_ok(
    $$SELECT * FROM public.review_paperwork_submission_v2(
        '47000000-0000-0000-0000-000000000152', 'accepted', NULL
    )$$,
    'the latest paperwork attempt can be reviewed'
);
RESET ROLE;

SELECT is(
    (SELECT status FROM public.paperwork_submissions WHERE id = '47000000-0000-0000-0000-000000000151'),
    'submitted',
    'reviewing the latest attempt does not mutate stale history'
);
SELECT is(
    (SELECT status FROM public.paperwork_submissions WHERE id = '47000000-0000-0000-0000-000000000152'),
    'accepted',
    'the latest attempt stores the review decision'
);
SELECT is(
    (SELECT completion_status FROM public.paperwork_assignment_recipients
     WHERE assignment_id = '46000000-0000-0000-0000-000000000151'),
    'accepted',
    'the recipient completion follows the latest attempt'
);
SELECT is(
    (SELECT status FROM public.paperwork_assignments WHERE id = '46000000-0000-0000-0000-000000000151'),
    'archived',
    'an accepted final recipient archives the request'
);

SELECT * FROM finish();
ROLLBACK;
