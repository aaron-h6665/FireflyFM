BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT no_plan();

SELECT has_function(
    'public', 'google_form_snapshot_answer', ARRAY['jsonb', 'jsonb', 'text'],
    'Google Form ingestion keeps its snapshot answer helper'
);
SELECT is(
    public.google_form_snapshot_answer(
        '{"first":"Synthetic"}'::JSONB,
        '{"mappings":[{"question_id":"first","field_key":"child_first_name","active":true}]}'::JSONB,
        'child_first_name'::TEXT
    ),
    'Synthetic',
    'snapshot helper resolves the mapped Form answer'
);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
    ('10000000-0000-0000-0000-000000000121', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'timeline-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000122', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'timeline-payer@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000123', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'timeline-guardian@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

INSERT INTO public.schools (id, name)
VALUES ('20000000-0000-0000-0000-000000000121', 'Timeline Test School');
INSERT INTO public.school_memberships (id, school_id, user_id, role, active, access_state)
VALUES ('30000000-0000-0000-0000-000000000121', '20000000-0000-0000-0000-000000000121', '10000000-0000-0000-0000-000000000121', 'school_director', TRUE, 'full');
-- The global director onboarding template may provision a limited membership.
-- This fixture represents a director who has already completed that setup.
UPDATE public.school_memberships SET access_state = 'full'
WHERE id = '30000000-0000-0000-0000-000000000121';
INSERT INTO public.school_zelle_profiles (school_id, recipient_display_name, recipient_type, recipient_value, memo_prefix, active)
VALUES ('20000000-0000-0000-0000-000000000121', 'Timeline Office', 'email', 'timeline-office@example.test', 'TIMELINE', TRUE);

INSERT INTO public.onboarding_templates (id, school_id, target_role, name, version, status, created_by, published_at)
VALUES ('40000000-0000-0000-0000-000000000121', '20000000-0000-0000-0000-000000000121', 'parent', 'Parent Timeline', 1, 'published', '10000000-0000-0000-0000-000000000121', NOW());
INSERT INTO public.onboarding_template_requirements (id, template_id, position, requirement_type, title, subject_scope, blocks_access, child_record_binding, payment_amount_cents, payment_due_days)
VALUES
    ('41000000-0000-0000-0000-000000000121', '40000000-0000-0000-0000-000000000121', 0, 'document', 'Family Form', 'member', TRUE, 'none', NULL, NULL),
    ('41000000-0000-0000-0000-000000000122', '40000000-0000-0000-0000-000000000121', 1, 'payment', 'Enrollment payment', 'member', TRUE, 'none', 2500, 7);
INSERT INTO public.google_form_connections (id, school_id, form_role, form_key, form_id, form_url, form_title, status, is_required, display_order, form_snapshot, created_by)
VALUES ('42000000-0000-0000-0000-000000000121', '20000000-0000-0000-0000-000000000121', 'parent', 'family-form-v1', 'form-timeline-121', 'https://docs.google.com/forms/d/e/timeline/viewform', 'Family Form', 'connected', TRUE, 0, '{}'::jsonb, '10000000-0000-0000-0000-000000000121');
INSERT INTO public.google_form_question_mappings (connection_id, question_id, question_title, field_key, required, active)
VALUES ('42000000-0000-0000-0000-000000000121', '7181a7e3', 'FireflyFM submission reference', 'submission_reference', TRUE, TRUE);
INSERT INTO public.google_form_question_mappings (connection_id, question_id, question_title, field_key, required, active)
VALUES
('42000000-0000-0000-0000-000000000121', 'first', 'Child first name', 'child_first_name', TRUE, TRUE),
('42000000-0000-0000-0000-000000000121', 'last', 'Child last name', 'child_last_name', TRUE, TRUE),
('42000000-0000-0000-0000-000000000121', 'dob', 'Child birthdate', 'child_birthdate', TRUE, TRUE),
('42000000-0000-0000-0000-000000000121', 'relationship', 'Relationship', 'relationship', TRUE, TRUE);
INSERT INTO public.google_form_requirement_bindings (connection_id, onboarding_template_requirement_id, published_snapshot)
VALUES ('42000000-0000-0000-0000-000000000121', '41000000-0000-0000-0000-000000000121', '{}'::jsonb);

INSERT INTO public.school_memberships (id, school_id, user_id, role, active, access_state, is_onboarding_payment_payer)
VALUES
    ('30000000-0000-0000-0000-000000000122', '20000000-0000-0000-0000-000000000121', '10000000-0000-0000-0000-000000000122', 'parent', TRUE, 'onboarding', TRUE),
    ('30000000-0000-0000-0000-000000000123', '20000000-0000-0000-0000-000000000121', '10000000-0000-0000-0000-000000000123', 'parent', TRUE, 'onboarding', FALSE);

SELECT is((SELECT COUNT(*)::INTEGER FROM public.onboarding_requirement_instances instance
    JOIN public.onboarding_instances onboarding ON onboarding.id = instance.onboarding_instance_id
    WHERE onboarding.membership_id IN ('30000000-0000-0000-0000-000000000122', '30000000-0000-0000-0000-000000000123')
      AND instance.template_requirement_id = '41000000-0000-0000-0000-000000000121'), 2, 'every invited parent receives the Form');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.onboarding_requirement_instances instance
    JOIN public.onboarding_instances onboarding ON onboarding.id = instance.onboarding_instance_id
    WHERE onboarding.membership_id IN ('30000000-0000-0000-0000-000000000122', '30000000-0000-0000-0000-000000000123')
      AND instance.template_requirement_id = '41000000-0000-0000-0000-000000000122'), 1, 'only the designated payer receives the payment requirement');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.zelle_invoices WHERE school_id = '20000000-0000-0000-0000-000000000121'), 1, 'only one onboarding invoice is issued');
SELECT is((SELECT payer_user_id FROM public.zelle_invoices WHERE school_id = '20000000-0000-0000-0000-000000000121'), '10000000-0000-0000-0000-000000000122'::UUID, 'the designated payer owns the invoice');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000122', TRUE);
SELECT set_config('request.jwt.claim.email', 'timeline-payer@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000122","email":"timeline-payer@test.fireflyfm.local"}', TRUE);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.fetch_my_parent_onboarding_timeline('20000000-0000-0000-0000-000000000121')), 2, 'payer receives the ordered Form and payment timeline');
SELECT is((SELECT step_position FROM public.fetch_my_parent_onboarding_timeline('20000000-0000-0000-0000-000000000121') LIMIT 1), 0, 'Form is the first actionable timeline step');
SELECT lives_ok(
    $$SELECT * FROM public.submit_zelle_payment((SELECT id FROM public.zelle_invoices WHERE school_id = '20000000-0000-0000-0000-000000000121'), 2500, NOW(), 'PAY-121', 'timeline-payment-121')$$,
    'payer can submit payment while the preceding Form is still unfinished'
);
SELECT is(
    (SELECT zelle_invoice_status FROM public.fetch_my_parent_onboarding_timeline('20000000-0000-0000-0000-000000000121') WHERE step_position = 1),
    'payment_submitted',
    'parallel checklist reports the submitted payment while Form review is pending'
);
SELECT lives_ok(
    $$CREATE TEMP TABLE first_form_launch AS SELECT * FROM public.begin_google_form_submission('42000000-0000-0000-0000-000000000121')$$,
    'parent can begin the next assigned Form'
);
SELECT is(
    (SELECT form_submission_status FROM public.fetch_my_parent_onboarding_timeline('20000000-0000-0000-0000-000000000121') WHERE connection_id = '42000000-0000-0000-0000-000000000121'),
    'awaiting_sync',
    'opening the Form immediately marks the parent timeline as checking for the response'
);
SELECT is(
    (SELECT launch_url FROM public.resume_google_form_submission('42000000-0000-0000-0000-000000000121',
        (SELECT substring(launch_url from 'entry.[0-9]+=([0-9a-f]+)') FROM first_form_launch))),
    (SELECT launch_url FROM first_form_launch),
    'reopening resumes the same reference rather than locking the recipient out'
);
SELECT ok((SELECT launch_url LIKE '%entry.1904322531=%' FROM first_form_launch), 'routing URL uses the observed decimal entry ID');
SELECT is(public.google_form_prefill_parameter('12345678'), 'entry.305419896', 'numeric-only IDs are interpreted as hexadecimal');
RESET ROLE;
SELECT is((SELECT COUNT(*)::INTEGER FROM public.google_form_submission_sessions
    WHERE membership_id = '30000000-0000-0000-0000-000000000122' AND consumed_at IS NULL), 1, 'opening the Form creates one server-side submission session');
SELECT ok((SELECT expires_at <= NOW() + INTERVAL '2 hours 1 minute' AND expires_at >= NOW() + INTERVAL '1 hour 59 minutes'
    FROM public.google_form_submission_sessions WHERE membership_id = '30000000-0000-0000-0000-000000000122' LIMIT 1), 'submission session expires in two hours');
UPDATE public.google_form_connections SET status = 'syncing' WHERE id = '42000000-0000-0000-0000-000000000121';
SET LOCAL ROLE authenticated;
SELECT is((SELECT step_kind FROM public.fetch_my_parent_onboarding_timeline('20000000-0000-0000-0000-000000000121') WHERE step_position = 0), 'form', 'a running worker cannot hide the Form');
RESET ROLE;
UPDATE public.google_form_connections SET status = 'error' WHERE id = '42000000-0000-0000-0000-000000000121';
SET LOCAL ROLE authenticated;
SELECT is((SELECT step_kind FROM public.fetch_my_parent_onboarding_timeline('20000000-0000-0000-0000-000000000121') WHERE step_position = 0), 'form', 'a failed sync cannot hide the Form');
RESET ROLE;
UPDATE public.google_form_connections SET status = 'connected' WHERE id = '42000000-0000-0000-0000-000000000121';
INSERT INTO public.google_form_imports (id, connection_id, school_id, google_response_id, submitted_payload, status)
SELECT '60000000-0000-0000-0000-000000000129', '42000000-0000-0000-0000-000000000121',
    '20000000-0000-0000-0000-000000000121', 'routing-regression-129',
    jsonb_build_object('7181a7e3', substring(launch_url from 'entry.[0-9]+=([0-9a-f]+)'),
      'first', 'Synthetic', 'last', 'Child', 'dob', '2022-01-02', 'relationship', 'parent'), 'pending_review'
FROM first_form_launch;
SELECT ok(
    (SELECT question_snapshot @> '[{"id":"dob","title":"Child birthdate","field_key":"child_birthdate"}]'::JSONB
     FROM public.google_form_imports WHERE id = '60000000-0000-0000-0000-000000000129'),
    'the import snapshots a human-readable question title'
);
SELECT ok(
    (SELECT question_snapshot @> '[{"id":"7181a7e3","field_key":"submission_reference"}]'::JSONB
     FROM public.google_form_imports WHERE id = '60000000-0000-0000-0000-000000000129'),
    'the import marks the private routing answer so clients can hide it'
);
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claim.role', 'service_role', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', TRUE);
SELECT lives_ok($$SELECT public.ingest_google_form_import('60000000-0000-0000-0000-000000000129')$$, 'response with the launched reference is ingested');
RESET ROLE;
SELECT is((SELECT membership_id FROM public.google_form_imports WHERE id = '60000000-0000-0000-0000-000000000129'),
    '30000000-0000-0000-0000-000000000122'::UUID, 'reference matches the correct recipient');
SELECT ok((SELECT consumed_at IS NOT NULL FROM public.google_form_submission_sessions
    WHERE token_hash = encode(extensions.digest((SELECT substring(launch_url from 'entry.[0-9]+=([0-9a-f]+)') FROM first_form_launch), 'sha256'), 'hex')), 'matching consumes the one-time session');
SELECT ok((SELECT child_connection_request_id IS NOT NULL FROM public.google_form_imports WHERE id = '60000000-0000-0000-0000-000000000129'), 'valid submitted child details create the review request');
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000121', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000121"}', TRUE);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $$SELECT * FROM public.approve_google_form_child_intake('60000000-0000-0000-0000-000000000129', 'approved', NULL, NULL)$$,
    'director can approve a member-scoped parent Form that creates a child'
);
RESET ROLE;
SELECT is(
    (SELECT requirement_instance.status
     FROM public.onboarding_requirement_instances requirement_instance
     JOIN public.onboarding_instances instance ON instance.id = requirement_instance.onboarding_instance_id
     WHERE instance.membership_id = '30000000-0000-0000-0000-000000000122'
       AND requirement_instance.template_requirement_id = '41000000-0000-0000-0000-000000000121'),
    'approved',
    'approved parent Form completes its member-scoped onboarding requirement'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.google_form_requirement_evidence
     WHERE import_id = '60000000-0000-0000-0000-000000000129'),
    1,
    'approved parent Form records requirement evidence'
);
SELECT is(
    (SELECT access_state FROM public.school_memberships WHERE id = '30000000-0000-0000-0000-000000000122'),
    'onboarding',
    'the independently unfinished payment still gates access after Form approval'
);
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000122', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000122"}', TRUE);
SET LOCAL ROLE authenticated;
CREATE TEMP TABLE second_form_launch AS SELECT * FROM public.resume_google_form_submission(
    '42000000-0000-0000-0000-000000000121', (SELECT substring(launch_url from 'entry.[0-9]+=([0-9a-f]+)') FROM first_form_launch));
SELECT isnt((SELECT launch_url FROM second_form_launch), (SELECT launch_url FROM first_form_launch), 'a consumed reference is never reused');
RESET ROLE;
UPDATE public.google_form_submission_sessions SET expires_at = NOW() - INTERVAL '1 second'
WHERE token_hash = encode(extensions.digest((SELECT substring(launch_url from 'entry.[0-9]+=([0-9a-f]+)') FROM second_form_launch), 'sha256'), 'hex');
SET LOCAL ROLE authenticated;
CREATE TEMP TABLE third_form_launch AS SELECT * FROM public.resume_google_form_submission(
    '42000000-0000-0000-0000-000000000121', (SELECT substring(launch_url from 'entry.[0-9]+=([0-9a-f]+)') FROM second_form_launch));
SELECT isnt((SELECT launch_url FROM third_form_launch), (SELECT launch_url FROM second_form_launch), 'an expired reference is never reused');
RESET ROLE;
INSERT INTO public.google_form_imports (id, connection_id, school_id, google_response_id, submitted_payload, status)
SELECT '60000000-0000-0000-0000-000000000128', '42000000-0000-0000-0000-000000000121',
    '20000000-0000-0000-0000-000000000121', 'invalid-date-128',
    jsonb_build_object('7181a7e3', substring(launch_url from 'entry.[0-9]+=([0-9a-f]+)'),
      'first', 'Synthetic', 'last', 'Child', 'dob', '2022-02-31', 'relationship', 'parent'), 'pending_review'
FROM third_form_launch;
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claim.role', 'service_role', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', TRUE);
SELECT lives_ok($$SELECT public.ingest_google_form_import('60000000-0000-0000-0000-000000000128')$$, 'invalid calendar date does not abort the worker');
RESET ROLE;
SELECT is((SELECT status FROM public.google_form_imports WHERE id = '60000000-0000-0000-0000-000000000128'), 'ambiguous', 'invalid date remains available for school attention');
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000122', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000122"}', TRUE);
SET LOCAL ROLE authenticated;
CREATE TEMP TABLE active_form_launch AS SELECT * FROM public.resume_google_form_submission('42000000-0000-0000-0000-000000000121', NULL);
RESET ROLE;

INSERT INTO public.google_form_imports (
    id, connection_id, school_id, google_response_id, submitted_payload, status
) VALUES (
    '60000000-0000-0000-0000-000000000121', '42000000-0000-0000-0000-000000000121',
    '20000000-0000-0000-0000-000000000121', 'timeline-response-121', '{}'::JSONB, 'pending_review'
);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.notifications
    WHERE source_type = 'google_form_import' AND source_id = '60000000-0000-0000-0000-000000000121'), 1,
    'a reviewable Form import creates exactly one director inbox notification');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.notification_recipients recipient
    JOIN public.notifications notification ON notification.id = recipient.notification_id
    WHERE notification.source_id = '60000000-0000-0000-0000-000000000121'
      AND recipient.user_id = '10000000-0000-0000-0000-000000000121'), 1,
    'the Form response notification is delivered to the active school director');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000123', TRUE);
SELECT set_config('request.jwt.claim.email', 'timeline-guardian@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000123","email":"timeline-guardian@test.fireflyfm.local"}', TRUE);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.fetch_my_parent_onboarding_timeline('20000000-0000-0000-0000-000000000121')), 1, 'non-payer sees Forms but no duplicate payment card');
SELECT isnt((SELECT launch_url FROM public.resume_google_form_submission('42000000-0000-0000-0000-000000000121',
    (SELECT substring(launch_url from 'entry.[0-9]+=([0-9a-f]+)') FROM active_form_launch))),
    (SELECT launch_url FROM active_form_launch), 'another account cannot resume the original recipient reference');
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000199', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000199"}', TRUE);
SELECT throws_ok($$SELECT * FROM public.resume_google_form_submission('42000000-0000-0000-0000-000000000121', NULL)$$,
    'P0001', 'This Form is not assigned to your role', 'unassigned accounts cannot obtain a launch link');


RESET ROLE;
-- This fixture includes the app's seeded director onboarding. Make the test
-- director fully approved before exercising director-only setup APIs.
UPDATE public.onboarding_requirement_instances requirement_instance
SET status = 'approved', completed_at = NOW()
FROM public.onboarding_instances instance
WHERE instance.id = requirement_instance.onboarding_instance_id
  AND instance.membership_id = '30000000-0000-0000-0000-000000000122';
SELECT is(
    (SELECT access_state FROM public.school_memberships WHERE id = '30000000-0000-0000-0000-000000000122'),
    'full',
    'completing the final blocking item automatically releases app access'
);
UPDATE public.school_memberships SET access_state = 'onboarding'
WHERE id = '30000000-0000-0000-0000-000000000122';
SELECT is(
    public.refresh_onboarding_access('30000000-0000-0000-0000-000000000122'),
    'full',
    'access reconciliation repairs a completed membership stranded in onboarding'
);
UPDATE public.school_memberships
SET access_state = 'full'
WHERE id = '30000000-0000-0000-0000-000000000121';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000121', TRUE);
SELECT set_config('request.jwt.claim.email', 'timeline-director@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000121","email":"timeline-director@test.fireflyfm.local"}', TRUE);
SELECT ok(
    public.is_onboarding_template_manager('20000000-0000-0000-0000-000000000121', 'parent', auth.uid()),
    'director can manage the parent onboarding timeline'
);
SELECT lives_ok(
    $$SELECT * FROM public.ensure_onboarding_template_draft('20000000-0000-0000-0000-000000000121', 'parent')$$,
    'director can create the next draft timeline'
);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.google_form_requirement_bindings), 2, 'draft receives its own Form binding while the published binding remains');

SELECT * FROM finish();
ROLLBACK;
