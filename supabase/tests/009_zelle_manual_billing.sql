BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(50);

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
    ('10000000-0000-0000-0000-000000000097', 'Zelle New Director')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

INSERT INTO public.schools (id, name) VALUES
    ('20000000-0000-0000-0000-000000000091', 'Zelle School A'),
    ('20000000-0000-0000-0000-000000000092', 'Zelle School B');

INSERT INTO public.school_memberships (id, school_id, user_id, role, active, access_state) VALUES
    ('30000000-0000-0000-0000-000000000091', '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000091', 'school_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000092', '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000092', 'parent', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000093', '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000093', 'teacher', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000094', '20000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000094', 'school_director', FALSE, 'full'),
    ('30000000-0000-0000-0000-000000000095', '20000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000095', 'parent', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000096', '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000096', 'hq_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000097', '20000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000097', 'school_director', TRUE, 'onboarding');

-- Membership creation intentionally fails closed into onboarding when a role
-- does not yet have a published template. These fixtures represent already
-- approved members, so restore their production-equivalent access state after
-- the membership trigger has run. Keep the new director in onboarding.
UPDATE public.school_memberships
SET access_state = 'full'
WHERE id IN (
    '30000000-0000-0000-0000-000000000091',
    '30000000-0000-0000-0000-000000000092',
    '30000000-0000-0000-0000-000000000093',
    '30000000-0000-0000-0000-000000000095',
    '30000000-0000-0000-0000-000000000096'
);

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

SELECT is(public.get_firefly_schema_version(), 20260907200000::BIGINT, 'Zelle payment hardening schema version is current');
SELECT ok(to_regclass('public.school_zelle_profiles') IS NOT NULL, 'school Zelle profile table exists');
SELECT ok(to_regclass('public.zelle_invoices') IS NOT NULL, 'Zelle invoice table exists');
SELECT ok(to_regclass('public.zelle_payment_submissions') IS NOT NULL, 'Zelle submission table exists');
SELECT ok(to_regclass('public.zelle_billing_audit_log') IS NOT NULL, 'Zelle audit table exists');
SELECT ok(public.zelle_can_review_invoice('52000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000091'), 'school director reviews own school parent payment');
SELECT ok(public.zelle_can_review_invoice('52000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000096'), 'HQ reviews school director onboarding payment');
SELECT isnt(public.zelle_can_review_invoice('52000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000094'), TRUE, 'former school director cannot review a new director enrollment payment');
SELECT ok(public.zelle_is_active_payer('20000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000097', '10000000-0000-0000-0000-000000000097'), 'new director is the named active payer for the enrollment fee');
SELECT throws_ok(
    $$INSERT INTO public.onboarding_template_requirements (
        id, template_id, position, requirement_type, title, subject_scope,
        blocks_access, child_record_binding, payment_amount_cents, payment_due_days
    ) VALUES (
        '51100000-0000-0000-0000-000000000099', '51000000-0000-0000-0000-000000000092',
        9, 'payment', 'Invalid empty payment', 'member', TRUE, 'none', NULL, 7
    )$$,
    '23514', NULL,
    'database rejects a payment requirement without an amount'
);
SELECT isnt(
    has_function_privilege('authenticated', 'public.create_onboarding_assignment(uuid,uuid,uuid)', 'EXECUTE'),
    TRUE,
    'untrusted clients cannot call the internal onboarding assignment helper'
);

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
SELECT is((SELECT COUNT(*)::INTEGER FROM public.zelle_invoices), 0, 'former school director cannot read director onboarding payment assigned to HQ');

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
-- Materialize the draft in its own statement so the following assertions use
-- a fresh command snapshot that can see the cloned requirement rows.
SELECT COUNT(*) FROM public.ensure_onboarding_template_draft(
    '20000000-0000-0000-0000-000000000092', 'school_director'
);
SELECT is(
    (SELECT requirement_type FROM public.onboarding_template_requirements
     WHERE template_id = (SELECT id FROM public.onboarding_templates
         WHERE school_id = '20000000-0000-0000-0000-000000000092'
           AND target_role = 'school_director' AND status = 'draft' LIMIT 1) LIMIT 1),
    'payment', 'draft cloning preserves the payment requirement type'
);
SELECT is(
    (SELECT payment_amount_cents FROM public.onboarding_template_requirements
     WHERE template_id = (SELECT id FROM public.onboarding_templates
         WHERE school_id = '20000000-0000-0000-0000-000000000092'
           AND target_role = 'school_director' AND status = 'draft' LIMIT 1) LIMIT 1),
    5000::BIGINT, 'draft cloning preserves the payment amount'
);
SELECT is(
    (SELECT payment_due_days FROM public.onboarding_template_requirements
     WHERE template_id = (SELECT id FROM public.onboarding_templates
         WHERE school_id = '20000000-0000-0000-0000-000000000092'
           AND target_role = 'school_director' AND status = 'draft' LIMIT 1) LIMIT 1),
    7, 'draft cloning preserves the payment due period'
);
SELECT is(
    (SELECT blocks_access FROM public.onboarding_template_requirements
     WHERE template_id = (SELECT id FROM public.onboarding_templates
         WHERE school_id = '20000000-0000-0000-0000-000000000092'
           AND target_role = 'school_director' AND status = 'draft' LIMIT 1) LIMIT 1),
    TRUE, 'draft cloning preserves the blocking-access setting'
);

RESET ROLE;
INSERT INTO public.children (id, school_id, first_name, last_name, birthdate, active)
VALUES ('40000000-0000-0000-0000-000000000099', '20000000-0000-0000-0000-000000000091', 'Unverified', 'Guardian', '2021-01-01', TRUE);
INSERT INTO public.child_guardians (child_id, guardian_id, relationship, verification_status)
VALUES ('40000000-0000-0000-0000-000000000099', '10000000-0000-0000-0000-000000000092', 'Parent', 'pending');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000091', TRUE);
SELECT lives_ok(
    $$SELECT public.save_school_zelle_profile(
        '20000000-0000-0000-0000-000000000091', 'School A Office', 'email',
        'billing-a@example.test', 'FFA', NULL, FALSE, TRUE
    )$$,
    'school director can pause new invoice issuance'
);
SELECT throws_ok(
    $$SELECT public.issue_zelle_invoice(
        '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000092',
        NULL, 'Blocked invoice', NOW() + INTERVAL '7 days',
        '[{"description":"Fee","quantity":1,"unit_amount_cents":100}]'::JSONB,
        'inactive-profile-test'
    )$$,
    'P0001', 'Activate this school''s Zelle recipient instructions before issuing an invoice',
    'invoice issuance is blocked while the recipient profile is inactive'
);
SELECT lives_ok(
    $$SELECT public.save_school_zelle_profile(
        '20000000-0000-0000-0000-000000000091', 'School A Office', 'email',
        'billing-a@example.test', 'FFA', NULL, TRUE, TRUE
    )$$,
    'school director can reactivate invoice issuance'
);
SELECT throws_ok(
    $$SELECT public.issue_zelle_invoice(
        '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000092',
        '40000000-0000-0000-0000-000000000099', 'Unverified child invoice', NOW() + INTERVAL '7 days',
        '[{"description":"Fee","quantity":1,"unit_amount_cents":100}]'::JSONB,
        'unverified-guardian-test'
    )$$,
    'P0001', 'The selected child is not linked to this verified parent',
    'invoice issuance requires a verified guardian relationship'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.issue_zelle_invoice(
        '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000092',
        '40000000-0000-0000-0000-000000000091', 'Hardening test invoice', NOW() + INTERVAL '7 days',
        '[{"description":"Fee","quantity":1,"unit_amount_cents":100}]'::JSONB,
        'invoice-hardening-test'
    )),
    1, 'director can issue an invoice with an active profile and verified relationship'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.issue_zelle_invoice(
        '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000092',
        '40000000-0000-0000-0000-000000000091', 'Hardening test invoice', NOW() + INTERVAL '7 days',
        '[{"description":"Fee","quantity":1,"unit_amount_cents":100}]'::JSONB,
        'invoice-hardening-test'
    )),
    1, 'invoice issuance retries return the original invoice'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.zelle_invoices
     WHERE school_id = '20000000-0000-0000-0000-000000000091'
       AND description = 'Hardening test invoice'),
    1, 'invoice issuance idempotency prevents duplicates'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000097', TRUE);
SELECT is(
    (SELECT status FROM public.submit_zelle_payment('52000000-0000-0000-0000-000000000092', 5000, NOW(), 'BANK-0001', 'test-submission-0001') LIMIT 1),
    'submitted', 'onboarding director can submit a test confirmation without Zelle'
);
SELECT is((SELECT status FROM public.zelle_invoices WHERE id = '52000000-0000-0000-0000-000000000092'), 'payment_submitted', 'submission moves invoice to review state');
SELECT is(
    (SELECT status FROM public.submit_zelle_payment(
        '52000000-0000-0000-0000-000000000092', 5000, NOW(), 'BANK-0001', 'test-submission-0001'
    ) LIMIT 1),
    'submitted', 'a submission retry returns the original result after the invoice state changes'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.zelle_payment_submissions
     WHERE invoice_id = '52000000-0000-0000-0000-000000000092'),
    1, 'submission idempotency prevents duplicate rows'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000096', TRUE);
SELECT is(
    (SELECT status FROM public.void_zelle_invoice(
        '52000000-0000-0000-0000-000000000092', 'Contract fee waived for test'
    ) LIMIT 1),
    'void', 'HQ can void a submitted director onboarding invoice'
);
SELECT is(
    (SELECT status FROM public.zelle_payment_submissions
     WHERE invoice_id = '52000000-0000-0000-0000-000000000092'),
    'rejected', 'voiding closes the pending submission'
);
SELECT is(
    (SELECT access_state FROM public.school_memberships
     WHERE id = '30000000-0000-0000-0000-000000000097'),
    'onboarding', 'voiding preserves the payment onboarding blocker'
);
SELECT throws_ok(
    $$SELECT public.review_zelle_payment(
        (SELECT id FROM public.zelle_payment_submissions
         WHERE invoice_id = '52000000-0000-0000-0000-000000000092'),
        'approved', NULL
    )$$,
    'P0001', 'This payment submission cannot be reviewed',
    'a voided invoice cannot later be approved'
);

RESET ROLE;
DELETE FROM public.zelle_payment_submissions
WHERE invoice_id = '52000000-0000-0000-0000-000000000092';
UPDATE public.zelle_invoices
SET status = 'open', amount_paid_cents = 0, paid_at = NULL, voided_at = NULL
WHERE id = '52000000-0000-0000-0000-000000000092';
UPDATE public.onboarding_requirement_instances
SET status = 'not_started', completed_at = NULL, waived_by = NULL, waiver_reason = NULL
WHERE id = '51300000-0000-0000-0000-000000000092';
UPDATE public.onboarding_instances SET status = 'in_progress', completed_at = NULL
WHERE id = '51200000-0000-0000-0000-000000000092';
UPDATE public.school_memberships SET access_state = 'onboarding'
WHERE id = '30000000-0000-0000-0000-000000000097';

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000097', TRUE);
SELECT is(
    (SELECT status FROM public.submit_zelle_payment(
        '52000000-0000-0000-0000-000000000092', 5000, NOW(), 'BANK-0002', 'test-submission-0002'
    ) LIMIT 1),
    'submitted', 'payer can submit again after a rejected or reset test payment'
);

RESET ROLE;
INSERT INTO public.zelle_invoices (
    id, school_id, payer_user_id, payer_role, description, amount_due_cents, status, issued_at
) VALUES (
    '52000000-0000-0000-0000-000000000099', '20000000-0000-0000-0000-000000000092',
    '10000000-0000-0000-0000-000000000095', 'parent', 'Duplicate confirmation test', 5000, 'open', NOW()
);
SELECT throws_ok(
    $$INSERT INTO public.zelle_payment_submissions (
        invoice_id, school_id, payer_user_id, amount_cents, sent_at, confirmation_reference, idempotency_key
    ) VALUES (
        '52000000-0000-0000-0000-000000000099', '20000000-0000-0000-0000-000000000092',
        '10000000-0000-0000-0000-000000000095', 5000, NOW(), 'bank-0002', 'duplicate-reference-test'
    )$$,
    '23505', NULL,
    'the same confirmation reference cannot be credited to two school invoices'
);
DELETE FROM public.zelle_invoices WHERE id = '52000000-0000-0000-0000-000000000099';

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

RESET ROLE;
INSERT INTO public.schools (id, name)
VALUES ('20000000-0000-0000-0000-000000000099', 'Archived Zelle School');
INSERT INTO public.school_zelle_profiles (
    id, school_id, recipient_display_name, recipient_type, recipient_value, memo_prefix, active
) VALUES (
    '50000000-0000-0000-0000-000000000099', '20000000-0000-0000-0000-000000000099',
    'Archive Office', 'email', 'archive@example.test', 'ARC', TRUE
);
INSERT INTO public.school_deletion_backups (id, school_id, school_name, backup_payload, deleted_by)
VALUES (
    '59000000-0000-0000-0000-000000000099', '20000000-0000-0000-0000-000000000099',
    'Archived Zelle School', '{}'::JSONB, '10000000-0000-0000-0000-000000000096'
);
SELECT lives_ok(
    $$DELETE FROM public.schools WHERE id = '20000000-0000-0000-0000-000000000099'$$,
    'an archived school with Zelle records can be deleted cleanly'
);
SELECT is(
    jsonb_array_length((SELECT backup_payload->'school_zelle_profiles'
                        FROM public.school_deletion_backups
                        WHERE id = '59000000-0000-0000-0000-000000000099')),
    1, 'school deletion backup retains its Zelle profile'
);

SELECT * FROM finish();
ROLLBACK;
