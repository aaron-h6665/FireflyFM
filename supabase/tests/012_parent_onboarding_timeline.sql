BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(14);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
    ('10000000-0000-0000-0000-000000000121', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'timeline-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000122', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'timeline-payer@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000123', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'timeline-guardian@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

INSERT INTO public.schools (id, name)
VALUES ('20000000-0000-0000-0000-000000000121', 'Timeline Test School');
INSERT INTO public.school_memberships (id, school_id, user_id, role, active, access_state)
VALUES ('30000000-0000-0000-0000-000000000121', '20000000-0000-0000-0000-000000000121', '10000000-0000-0000-0000-000000000121', 'school_director', TRUE, 'full');
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
VALUES ('42000000-0000-0000-0000-000000000121', 'routing-question-121', 'FireflyFM submission reference', 'submission_reference', TRUE, TRUE);
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
SELECT throws_ok(
    $$SELECT * FROM public.submit_zelle_payment((SELECT id FROM public.zelle_invoices WHERE school_id = '20000000-0000-0000-0000-000000000121'), 2500, NOW(), 'PAY-121', 'timeline-payment-121')$$,
    'P0001', 'Complete the earlier onboarding step first',
    'payer cannot submit payment before the preceding Form is complete'
);
SELECT lives_ok(
    $$SELECT * FROM public.begin_google_form_submission('42000000-0000-0000-0000-000000000121')$$,
    'parent can begin the next assigned Form'
);
RESET ROLE;
SELECT is((SELECT COUNT(*)::INTEGER FROM public.google_form_submission_sessions
    WHERE membership_id = '30000000-0000-0000-0000-000000000122' AND consumed_at IS NULL), 1, 'opening the Form creates one server-side submission session');
SELECT ok((SELECT expires_at <= NOW() + INTERVAL '2 hours 1 minute' AND expires_at >= NOW() + INTERVAL '1 hour 59 minutes'
    FROM public.google_form_submission_sessions WHERE membership_id = '30000000-0000-0000-0000-000000000122' LIMIT 1), 'submission session expires in two hours');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000123', TRUE);
SELECT set_config('request.jwt.claim.email', 'timeline-guardian@test.fireflyfm.local', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000123","email":"timeline-guardian@test.fireflyfm.local"}', TRUE);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.fetch_my_parent_onboarding_timeline('20000000-0000-0000-0000-000000000121')), 1, 'non-payer sees Forms but no duplicate payment card');

RESET ROLE;
-- This fixture includes the app's seeded director onboarding. Make the test
-- director fully approved before exercising director-only setup APIs.
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
