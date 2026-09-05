BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(27);

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000091', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'zelle-director-a@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'zelle-parent-a@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000093', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'zelle-teacher-a@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000094', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'zelle-director-b@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000095', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'zelle-parent-b@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000096', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'zelle-hq@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000097', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'zelle-new-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

INSERT INTO public.profiles (id, display_name) VALUES
    ('10000000-0000-0000-0000-000000000091', 'Zelle Director A'),
    ('10000000-0000-0000-0000-000000000092', 'Zelle Parent A'),
    ('10000000-0000-0000-0000-000000000093', 'Zelle Teacher A'),
    ('10000000-0000-0000-0000-000000000094', 'Zelle Director B'),
    ('10000000-0000-0000-0000-000000000095', 'Zelle Parent B'),
    ('10000000-0000-0000-0000-000000000096', 'Zelle HQ'),
    ('10000000-0000-0000-0000-000000000097', 'Zelle New Director');

INSERT INTO public.schools (id, name) VALUES
    ('20000000-0000-0000-0000-000000000091', 'Zelle School A'),
    ('20000000-0000-0000-0000-000000000092', 'Zelle School B');

INSERT INTO public.school_memberships (id, school_id, user_id, role, active, access_state) VALUES
    ('30000000-0000-0000-0000-000000000091', '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000091', 'school_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000092', '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000092', 'parent', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000093', '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000093', 'teacher', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000094', '20000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000094', 'school_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000095', '20000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000095', 'parent', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000096', '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000096', 'hq_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000097', '20000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000097', 'school_director', TRUE, 'onboarding');

INSERT INTO public.children (id, school_id, first_name, last_name, birthdate, active) VALUES
    ('40000000-0000-0000-0000-000000000091', '20000000-0000-0000-0000-000000000091', 'Avery', 'Zelle', '2021-01-01', TRUE);
INSERT INTO public.child_guardians (child_id, guardian_id, relationship, verification_status, verified_by, verified_at)
VALUES ('40000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000092', 'Parent', 'verified', '10000000-0000-0000-0000-000000000091', NOW());

INSERT INTO public.school_zelle_profiles (id, school_id, recipient_display_name, recipient_type, recipient_value, memo_prefix, active, beta_simulation_enabled) VALUES
    ('50000000-0000-0000-0000-000000000091', '20000000-0000-0000-0000-000000000091', 'School A Office', 'email', 'billing-a@example.test', 'FFA', TRUE, TRUE),
    ('50000000-0000-0000-0000-000000000092', '20000000-0000-0000-0000-000000000092', 'School B Office', 'mobile', '5550100200', 'FFB', TRUE, TRUE);

INSERT INTO public.onboarding_templates (id, school_id, target_role, name, version, status)
VALUES ('51000000-0000-0000-0000-000000000092', '20000000-0000-0000-0000-000000000092', 'school_director', 'Director enrollment', 1, 'published');
INSERT INTO public.onboarding_template_requirements (
    id, template_id, position, requirement_type, title, subject_scope, blocks_access, child_record_binding, payment_amount_cents, payment_due_days
) VALUES
    ('51100000-0000-0000-0000-000000000092', '51000000-0000-0000-0000-000000000092', 0, 'payment', 'Director contract fee', 'member', TRUE, 'none', 5000, 7);
INSERT INTO public.onboarding_instances (id, school_id, membership_id, template_id)
VALUES ('51200000-0000-0000-0000-000000000092', '20000000-0000-0000-0000-000000000092', '30000000-0000-0000-0000-000000000097', '51000000-0000-0000-0000-000000000092');
INSERT INTO public.onboarding_requirement_instances (id, onboarding_instance_id, template_requirement_id, status)
VALUES ('51300000-0000-0000-0000-000000000092', '51200000-0000-0000-0000-000000000092', '51100000-0000-0000-0000-000000000092', 'not_started');

INSERT INTO public.zelle_invoices (
    id, school_id, payer_user_id, payer_role, child_id, description, amount_due_cents, status, due_at, issued_at
) VALUES
    ('52000000-0000-0000-0000-000000000091', '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000092', 'parent', '40000000-0000-0000-0000-000000000091', 'August tuition', 100000, 'open', NOW() + INTERVAL '7 days', NOW()),
    ('52000000-0000-0000-0000-000000000092', '20000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000097', 'school_director', NULL, 'Director contract fee', 5000, 'open', NOW() + INTERVAL '7 days', NOW());
UPDATE public.zelle_invoices
SET onboarding_requirement_instance_id = '51300000-0000-0000-0000-000000000092'
WHERE id = '52000000-0000-0000-0000-000000000092';
INSERT INTO public.zelle_invoice_items (id, invoice_id, description, quantity, unit_amount_cents, amount_cents)
VALUES ('53000000-0000-0000-0000-000000000091', '52000000-0000-0000-0000-000000000091', 'Tuition', 1, 100000, 100000);
INSERT INTO public.zelle_billing_audit_log (school_id, actor_id, action, entity_type, entity_id) VALUES
    ('20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000091', 'invoice_issued', 'invoice', '52000000-0000-0000-0000-000000000091'),
    ('20000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000096', 'onboarding_invoice_issued', 'invoice', '52000000-0000-0000-0000-000000000092');

SELECT is(public.get_firefly_schema_version(), 20260904150100::BIGINT, 'Zelle manual billing schema version is current');
SELECT ok(to_regclass('public.school_zelle_profiles') IS NOT NULL, 'school Zelle profile table exists');
SELECT ok(to_regclass('public.zelle_invoices') IS NOT NULL, 'Zelle invoice table exists');
SELECT ok(to_regclass('public.zelle_payment_submissions') IS NOT NULL, 'Zelle submission table exists');
SELECT ok(to_regclass('public.zelle_billing_audit_log') IS NOT NULL, 'Zelle audit table exists');
SELECT ok(public.zelle_can_review_invoice('52000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000091'), 'school director reviews own school parent payment');
SELECT ok(public.zelle_can_review_invoice('52000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000096'), 'HQ reviews school director onboarding payment');
SELECT isnt(public.zelle_can_review_invoice('52000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000094'), TRUE, 'school director cannot review another director enrollment payment');
SELECT ok(public.zelle_is_active_payer('20000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000097', '10000000-0000-0000-0000-000000000097'), 'new director is the named active payer for the enrollment fee');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000092', TRUE);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.zelle_invoices), 1, 'parent sees only named invoice');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.zelle_invoice_items), 1, 'parent sees own line items');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.school_zelle_profiles), 1, 'parent sees recipient instructions only after receiving an invoice');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.zelle_billing_audit_log), 0, 'parent cannot inspect staff audit history');
SELECT throws_ok(
    $$UPDATE public.zelle_invoices SET status = 'paid' WHERE id = '52000000-0000-0000-0000-000000000091'$$,
    '42501', 'permission denied for table zelle_invoices',
    'parent cannot mark an invoice paid directly'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000093', TRUE);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.zelle_invoices), 0, 'teacher cannot see another member payment data');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000094', TRUE);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.zelle_invoices), 0, 'school director cannot read director onboarding payment assigned to HQ');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000096', TRUE);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.zelle_invoices), 2, 'HQ can read cross-school payment records');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.zelle_billing_audit_log), 2, 'HQ can read cross-school audit history');
SELECT throws_ok(
    $$UPDATE public.school_zelle_profiles SET active = FALSE$$,
    '42501', 'permission denied for table school_zelle_profiles',
    'HQ cannot directly mutate a profile outside the audited RPC'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000097', TRUE);
SELECT is(
    (SELECT status FROM public.submit_zelle_payment('52000000-0000-0000-0000-000000000092', 5000, NOW(), 'TEST-0001', 'test-submission-0001') LIMIT 1),
    'submitted', 'onboarding director can submit a test confirmation without Zelle'
);
SELECT is((SELECT status FROM public.zelle_invoices WHERE id = '52000000-0000-0000-0000-000000000092'), 'payment_submitted', 'submission moves invoice to review state');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000096', TRUE);
SELECT is(
    (SELECT status FROM public.review_zelle_payment((SELECT id FROM public.zelle_payment_submissions WHERE invoice_id = '52000000-0000-0000-0000-000000000092'), 'approved', NULL) LIMIT 1),
    'paid', 'HQ approval marks director contract invoice paid'
);
SELECT is((SELECT status FROM public.onboarding_requirement_instances WHERE id = '51300000-0000-0000-0000-000000000092'), 'approved', 'approval completes the payment onboarding requirement');
SELECT is((SELECT access_state FROM public.school_memberships WHERE id = '30000000-0000-0000-0000-000000000097'), 'full', 'approval unlocks the director membership');
SELECT isnt(has_table_privilege('authenticated', 'public.zelle_payment_submissions', 'INSERT'), TRUE, 'clients cannot insert submissions outside the audited RPC');
SELECT isnt(has_table_privilege('authenticated', 'public.zelle_invoices', 'UPDATE'), TRUE, 'clients cannot update invoices outside the audited RPC');
SELECT ok(NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name IN ('school_zelle_profiles', 'zelle_invoices', 'zelle_payment_submissions')
      AND column_name ~ '(account|routing|password|credential|token|screenshot)'
), 'Zelle tables contain no bank credential or screenshot fields');

SELECT * FROM finish();
ROLLBACK;
