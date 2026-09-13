BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(36);

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000081', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'workflow-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000082', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'workflow-parent@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000083', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'other-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

INSERT INTO public.profiles (id, display_name) VALUES
    ('10000000-0000-0000-0000-000000000081', 'Workflow Director'),
    ('10000000-0000-0000-0000-000000000082', 'Family Participant'),
    ('10000000-0000-0000-0000-000000000083', 'Other Director')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

INSERT INTO public.schools (id, name) VALUES
    ('20000000-0000-0000-0000-000000000081', 'Workflow School'),
    ('20000000-0000-0000-0000-000000000082', 'Other School');

INSERT INTO public.school_memberships (id, school_id, user_id, role, active, access_state) VALUES
    ('30000000-0000-0000-0000-000000000081', '20000000-0000-0000-0000-000000000081', '10000000-0000-0000-0000-000000000081', 'school_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000082', '20000000-0000-0000-0000-000000000081', '10000000-0000-0000-0000-000000000082', 'parent', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000083', '20000000-0000-0000-0000-000000000082', '10000000-0000-0000-0000-000000000083', 'school_director', TRUE, 'full');

INSERT INTO public.assignments (
    id, school_id, title, description, category, audience_role, assigned_by,
    status, visibility, requires_review, allow_resubmission, publish_at
) VALUES (
    '60000000-0000-0000-0000-000000000081',
    '20000000-0000-0000-0000-000000000081',
    'Original assignment', 'Original instructions', 'general', 'parent',
    '10000000-0000-0000-0000-000000000081', 'published', 'assigned', TRUE, TRUE, NOW()
);
INSERT INTO public.assignment_recipients (
    assignment_id, user_id, role_at_assignment, completion_status
) VALUES (
    '60000000-0000-0000-0000-000000000081',
    '10000000-0000-0000-0000-000000000082', 'parent', 'not_started'
);

SELECT is(public.get_firefly_schema_version(), 20260913190000::BIGINT, 'parallel onboarding schema version is current');
SELECT ok(to_regclass('public.assignment_revisions') IS NOT NULL, 'assignment revision table exists');
SELECT ok(to_regclass('public.assignment_revision_materials') IS NOT NULL, 'revision material snapshot table exists');
SELECT ok(has_function_privilege('authenticated', 'public.update_assignment_v2(uuid,text,text,timestamptz,boolean,jsonb)', 'EXECUTE'), 'authenticated creators can call versioned edits');
SELECT ok(has_function_privilege('authenticated', 'public.post_assignment_comment_v2(uuid,uuid,text,text)', 'EXECUTE'), 'participants can call assignment conversations');
SELECT ok(has_function_privilege('authenticated', 'public.update_assignment_submission_score(uuid,integer,text)', 'EXECUTE'), 'reviewers can call retroactive scoring');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000081', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000081"}', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.update_assignment_v2(
        '60000000-0000-0000-0000-000000000081', 'Revised assignment',
        'Revised instructions', NOW() + INTERVAL '5 days', TRUE,
        '[{"material_type":"link","title":"First reference","url":"https://example.com/first"}]'
    )$$,
    'creator atomically edits fields and materials'
);
RESET ROLE;
SELECT is((SELECT COUNT(*)::INTEGER FROM public.assignment_revisions WHERE assignment_id = '60000000-0000-0000-0000-000000000081'), 1, 'first edit creates the baseline immutable revision');
SELECT is((SELECT title FROM public.assignment_revision_materials WHERE revision_id = (SELECT current_revision_id FROM public.assignments WHERE id = '60000000-0000-0000-0000-000000000081')), 'First reference', 'current revision snapshots its material');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000082', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000082"}', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.post_assignment_comment_v2(
        '60000000-0000-0000-0000-000000000081',
        '10000000-0000-0000-0000-000000000082',
        'Can I ask before submitting?', 'pre-submit-comment'
    )$$,
    'recipient can comment before submission'
);
RESET ROLE;
SELECT ok((SELECT submission_id IS NULL FROM public.assignment_feedback_messages WHERE body = 'Can I ask before submitting?'), 'pre-submission comment belongs to the continuous assignment conversation');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000082', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000082"}', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.submit_assignment_with_payload(
        '60000000-0000-0000-0000-000000000081', '{}', NULL, '[]', 'workflow-submit'
    )$$,
    'recipient submits against the current revision'
);
SELECT lives_ok(
    $$SELECT * FROM public.post_assignment_comment(
        (SELECT id FROM public.assignment_submissions WHERE assignment_id = '60000000-0000-0000-0000-000000000081'),
        'Legacy clients continue the same conversation', 'legacy-comment-wrapper'
    )$$,
    'legacy attempt comment RPC delegates to the assignment conversation'
);
RESET ROLE;
SELECT is(
    (SELECT assignment_revision_id FROM public.assignment_submissions WHERE assignment_id = '60000000-0000-0000-0000-000000000081'),
    (SELECT current_revision_id FROM public.assignments WHERE id = '60000000-0000-0000-0000-000000000081'),
    'submission retains its assignment revision'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000081', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000081"}', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.review_assignment_submission_v2(
        (SELECT id FROM public.assignment_submissions WHERE assignment_id = '60000000-0000-0000-0000-000000000081'),
        'accepted', 'Well done', 'workflow-review', 7
    )$$,
    'creator reviews and scores the attempt'
);
SELECT lives_ok(
    $$SELECT * FROM public.update_assignment_submission_score(
        (SELECT id FROM public.assignment_submissions WHERE assignment_id = '60000000-0000-0000-0000-000000000081'), 9, 'retro-score'
      );
      SELECT * FROM public.update_assignment_submission_score(
        (SELECT id FROM public.assignment_submissions WHERE assignment_id = '60000000-0000-0000-0000-000000000081'), 9, 'retro-score'
      )$$,
    'retroactive score updates are idempotent'
);
RESET ROLE;
SELECT is((SELECT score::INTEGER FROM public.assignment_submissions WHERE assignment_id = '60000000-0000-0000-0000-000000000081'), 9, 'retroactive score is stored without changing review status');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.assignment_events WHERE assignment_id = '60000000-0000-0000-0000-000000000081' AND event_type = 'score_updated'), 1, 'score change is audited once');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.notifications WHERE dedupe_key LIKE 'assignment:score:%' AND source_id = '60000000-0000-0000-0000-000000000081'), 1, 'score change notifies the submitter');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000081', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000081"}', TRUE);
SELECT lives_ok($$SELECT * FROM public.set_assignment_status('60000000-0000-0000-0000-000000000081', 'closed')$$, 'creator closes an assignment');
RESET ROLE;
SELECT is((SELECT status FROM public.assignments WHERE id = '60000000-0000-0000-0000-000000000081'), 'closed', 'closed lifecycle state is visible');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000082', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000082"}', TRUE);
SELECT throws_ok(
    $$SELECT * FROM public.post_assignment_comment_v2('60000000-0000-0000-0000-000000000081', '10000000-0000-0000-0000-000000000082', 'Blocked comment', NULL)$$,
    'P0001', 'Comments are read-only while this assignment is closed or archived',
    'closed assignments reject comments server-side'
);
SELECT throws_ok(
    $$SELECT * FROM public.submit_assignment_with_payload('60000000-0000-0000-0000-000000000081', '{}', NULL, '[]', 'blocked-submit')$$,
    'P0001', 'You cannot submit this assignment in its current state',
    'closed assignments reject submissions server-side'
);
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000081', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000081"}', TRUE);
SELECT lives_ok($$SELECT * FROM public.set_assignment_status('60000000-0000-0000-0000-000000000081', 'published')$$, 'creator reopens a closed assignment');
RESET ROLE;
SELECT is((SELECT COUNT(*)::INTEGER FROM public.assignment_events WHERE assignment_id = '60000000-0000-0000-0000-000000000081' AND event_type = 'reopened'), 1, 'reopening is audited');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000082', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000082"}', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.post_assignment_comment_v2('60000000-0000-0000-0000-000000000081', '10000000-0000-0000-0000-000000000082', 'Thanks for reopening it.', 'reopened-comment')$$,
    'reopening restores comments'
);
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000081', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000081"}', TRUE);
SELECT lives_ok(
    $$SELECT * FROM public.update_assignment_v2(
        '60000000-0000-0000-0000-000000000081', 'Second revision',
        'New instructions', NOW() + INTERVAL '7 days', TRUE,
        '[{"material_type":"link","title":"Second reference","url":"https://example.com/second"}]'
    )$$,
    'a later edit creates another immutable revision'
);
RESET ROLE;
SELECT is((SELECT COUNT(*)::INTEGER FROM public.assignment_revisions WHERE assignment_id = '60000000-0000-0000-0000-000000000081'), 2, 'revision history contains both versions');
SELECT is((SELECT material.title FROM public.assignment_revision_materials material JOIN public.assignment_revisions revision ON revision.id = material.revision_id WHERE revision.assignment_id = '60000000-0000-0000-0000-000000000081' AND revision.revision_number = 1), 'First reference', 'historical revision material remains immutable');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000081', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000081"}', TRUE);
SELECT lives_ok($$SELECT * FROM public.set_assignment_status('60000000-0000-0000-0000-000000000081', 'archived')$$, 'creator archives an assignment');
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000082', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000082"}', TRUE);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.fetch_my_assignment_agenda_v2(NULL, TRUE)), 1, 'submitter archived filter includes the assignment');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.fetch_my_assignment_agenda_v2(NULL, FALSE)), 0, 'submitter active filter excludes archived assignments');
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000081', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000081"}', TRUE);
SELECT lives_ok($$SELECT * FROM public.set_assignment_status('60000000-0000-0000-0000-000000000081', 'closed')$$, 'creator restores an archived assignment');
RESET ROLE;
SELECT is((SELECT status FROM public.assignments WHERE id = '60000000-0000-0000-0000-000000000081'), 'closed', 'restoring returns an assignment to closed');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.assignment_events WHERE assignment_id = '60000000-0000-0000-0000-000000000081' AND event_type = 'restored'), 1, 'restoring is audited');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000083', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000083"}', TRUE);
SELECT throws_ok(
    $$SELECT * FROM public.update_assignment_v2('60000000-0000-0000-0000-000000000081', 'Cross-school edit', NULL, NULL, TRUE, '[]')$$,
    'P0001', 'Only the assignment creator can edit this assignment',
    'a director from another school cannot edit the assignment'
);

SELECT * FROM finish();
ROLLBACK;
