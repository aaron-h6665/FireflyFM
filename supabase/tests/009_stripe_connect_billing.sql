BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(31);

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000091', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'billing-director-a@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'billing-parent-a@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000093', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'billing-teacher-a@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000094', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'billing-director-b@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000095', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'billing-parent-b@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000096', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'billing-hq@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

INSERT INTO public.profiles (id, display_name) VALUES
    ('10000000-0000-0000-0000-000000000091', 'Billing Director A'),
    ('10000000-0000-0000-0000-000000000092', 'Billing Parent A'),
    ('10000000-0000-0000-0000-000000000093', 'Billing Teacher A'),
    ('10000000-0000-0000-0000-000000000094', 'Billing Director B'),
    ('10000000-0000-0000-0000-000000000095', 'Billing Parent B'),
    ('10000000-0000-0000-0000-000000000096', 'Billing HQ');

INSERT INTO public.schools (id, name) VALUES
    ('20000000-0000-0000-0000-000000000091', 'Billing School A'),
    ('20000000-0000-0000-0000-000000000092', 'Billing School B');

INSERT INTO public.school_memberships (id, school_id, user_id, role, active, access_state) VALUES
    ('30000000-0000-0000-0000-000000000091', '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000091', 'school_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000092', '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000092', 'parent', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000093', '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000093', 'teacher', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000094', '20000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000094', 'school_director', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000095', '20000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000095', 'parent', TRUE, 'full'),
    ('30000000-0000-0000-0000-000000000096', '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000096', 'hq_director', TRUE, 'full');

INSERT INTO public.children (id, school_id, first_name, last_name, birthdate, active) VALUES
    ('40000000-0000-0000-0000-000000000091', '20000000-0000-0000-0000-000000000091', 'Avery', 'Billing', '2021-01-01', TRUE);
INSERT INTO public.child_guardians (child_id, guardian_id, relationship, verification_status, verified_by, verified_at)
VALUES ('40000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000092', 'Parent', 'verified', '10000000-0000-0000-0000-000000000091', NOW());

INSERT INTO public.school_payment_accounts (id, school_id, stripe_account_id, status, details_submitted, charges_enabled, payouts_enabled) VALUES
    ('50000000-0000-0000-0000-000000000091', '20000000-0000-0000-0000-000000000091', 'acct_test_a', 'ready', TRUE, TRUE, TRUE),
    ('50000000-0000-0000-0000-000000000092', '20000000-0000-0000-0000-000000000092', 'acct_test_b', 'ready', TRUE, TRUE, TRUE);
INSERT INTO public.billing_customers (id, school_id, parent_user_id, stripe_customer_id) VALUES
    ('51000000-0000-0000-0000-000000000091', '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000092', 'cus_test_a'),
    ('51000000-0000-0000-0000-000000000092', '20000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000095', 'cus_test_b');
INSERT INTO public.billing_invoices (
    id, school_id, parent_user_id, child_id, stripe_invoice_id, stripe_customer_id,
    description, amount_due_cents, amount_paid_cents, amount_remaining_cents, status, payment_status, due_at
) VALUES
    ('52000000-0000-0000-0000-000000000091', '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000092', '40000000-0000-0000-0000-000000000091', 'in_test_a', 'cus_test_a', 'August tuition', 100000, 0, 100000, 'open', 'pending', NOW() + INTERVAL '7 days'),
    ('52000000-0000-0000-0000-000000000092', '20000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000095', NULL, 'in_test_b', 'cus_test_b', 'September tuition', 90000, 90000, 0, 'paid', 'succeeded', NOW());
INSERT INTO public.billing_invoice_items (id, invoice_id, description, quantity, unit_amount_cents, amount_cents)
VALUES ('53000000-0000-0000-0000-000000000091', '52000000-0000-0000-0000-000000000091', 'Tuition', 1, 100000, 100000);
INSERT INTO public.billing_payments (id, invoice_id, school_id, parent_user_id, stripe_payment_intent_id, amount_cents, status)
VALUES ('54000000-0000-0000-0000-000000000091', '52000000-0000-0000-0000-000000000091', '20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000092', 'pi_test_a', 100000, 'processing');
INSERT INTO public.billing_audit_log (school_id, actor_id, action, entity_type, entity_id) VALUES
    ('20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000091', 'invoice_issued', 'billing_invoice', '52000000-0000-0000-0000-000000000091'),
    ('20000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000094', 'invoice_paid', 'billing_invoice', '52000000-0000-0000-0000-000000000092');

SELECT is(public.get_firefly_schema_version(), 20260807090000::BIGINT, 'billing schema version is current');
SELECT ok(to_regclass('public.school_payment_accounts') IS NOT NULL, 'school payment accounts table exists');
SELECT ok(to_regclass('public.billing_customers') IS NOT NULL, 'billing customers table exists');
SELECT ok(to_regclass('public.billing_schedules') IS NOT NULL, 'billing schedules table exists');
SELECT ok(to_regclass('public.billing_invoices') IS NOT NULL, 'billing invoices table exists');
SELECT ok(to_regclass('public.billing_invoice_items') IS NOT NULL, 'billing invoice items table exists');
SELECT ok(to_regclass('public.billing_payments') IS NOT NULL, 'billing payments table exists');
SELECT ok(to_regclass('public.billing_provider_events') IS NOT NULL, 'billing provider events table exists');
SELECT ok(to_regclass('public.billing_audit_log') IS NOT NULL, 'billing audit table exists');
SELECT ok(public.billing_is_school_director('20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000091'), 'school director manages own school');
SELECT isnt(public.billing_is_school_director('20000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000091'), TRUE, 'school director cannot manage another school');
SELECT ok(public.billing_is_hq_director('10000000-0000-0000-0000-000000000096'), 'HQ role is recognized');
SELECT ok(public.billing_is_named_parent('20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000092'), 'named parent is recognized');
SELECT isnt(public.billing_is_named_parent('20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000092', '10000000-0000-0000-0000-000000000095'), TRUE, 'another parent is not the named payer');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000092', TRUE);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.billing_invoices), 1, 'parent sees only named invoice');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.billing_invoice_items), 1, 'parent sees own line items');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.billing_payments), 1, 'parent sees own payment status');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.school_payment_accounts), 0, 'parent cannot inspect merchant account state');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.billing_audit_log), 0, 'parent cannot inspect staff audit history');
SELECT throws_ok(
    $$INSERT INTO public.billing_invoices (school_id, parent_user_id, stripe_invoice_id, stripe_customer_id, description)
      VALUES ('20000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000092', 'in_forbidden', 'cus_test_a', 'Forbidden')$$,
    '42501', 'permission denied for table billing_invoices',
    'parent cannot write provider projections'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000094', TRUE);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.billing_invoices), 1, 'school B director sees school B invoice');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.billing_invoices WHERE school_id = '20000000-0000-0000-0000-000000000091'), 0, 'school B director cannot see school A invoice');
SELECT throws_ok(
    $$UPDATE public.billing_invoices SET status = 'paid' WHERE id = '52000000-0000-0000-0000-000000000092'$$,
    '42501', 'permission denied for table billing_invoices',
    'school director cannot mark an invoice paid directly'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000093', TRUE);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.billing_invoices), 0, 'teacher has no billing access');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000096', TRUE);
SELECT is((SELECT COUNT(*)::INTEGER FROM public.billing_invoices), 2, 'HQ sees cross-school invoices');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.school_payment_accounts), 2, 'HQ sees cross-school merchant readiness');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.billing_audit_log), 2, 'HQ sees cross-school billing audit history');
SELECT throws_ok(
    $$UPDATE public.school_payment_accounts SET live_payments_enabled = TRUE$$,
    '42501', 'permission denied for table school_payment_accounts',
    'HQ oversight is read-only'
);

RESET ROLE;
SELECT isnt(has_table_privilege('authenticated', 'public.billing_provider_events', 'SELECT'), TRUE, 'provider event inbox is service-only');
SELECT ok(has_table_privilege('authenticated', 'public.billing_invoices', 'SELECT'), 'authenticated users query invoices through RLS');
SELECT ok(to_regclass('public.payment_setup_records') IS NOT NULL, 'legacy payment setup table remains for released clients');

SELECT * FROM finish();
ROLLBACK;
