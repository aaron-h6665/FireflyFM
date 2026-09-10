BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT no_plan();

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


SELECT is(public.zelle_is_demo_environment(), FALSE, 'normal migrations never enable simulation');
SELECT ok(to_regclass('public.zelle_demo_transfers') IS NULL, 'demo bank is absent from production migrations');
UPDATE public.school_zelle_profiles SET recipient_value = 'changed@example.test' WHERE school_id='20000000-0000-0000-0000-000000000091';
SELECT is((SELECT recipient_snapshot->>'value' FROM public.zelle_invoices WHERE id='52000000-0000-0000-0000-000000000091'), 'billing-a@example.test', 'issued recipient remains immutable');
SELECT throws_ok($$UPDATE public.zelle_invoices SET is_demo=TRUE WHERE id='52000000-0000-0000-0000-000000000091'$$, 'P0001','Invoice recipient and environment are immutable','cannot relabel live invoice as demo');
INSERT INTO public.zelle_invoices(school_id,payer_user_id,payer_role,description,amount_due_cents,status)
VALUES('20000000-0000-0000-0000-000000000091','10000000-0000-0000-0000-000000000091','parent','Self payment test',100,'open');
SELECT isnt(public.zelle_can_review_invoice((SELECT id FROM public.zelle_invoices WHERE description='Self payment test'),'10000000-0000-0000-0000-000000000091'),TRUE,'director cannot self-approve');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000092',TRUE);
SELECT throws_ok($$SELECT public.submit_zelle_payment('52000000-0000-0000-0000-000000000091',100000,NOW(),'TEST-0001','test-live-reject')$$,'P0001','Test references require the isolated demo environment','production rejects practice reference');
SELECT lives_ok($$SELECT public.submit_zelle_payment('52000000-0000-0000-0000-000000000091',100000,NOW(),'BANK-CORRECT','correction-attempt-1')$$,'parent submits');
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000091',TRUE);
SELECT lives_ok($$SELECT public.review_zelle_payment((SELECT id FROM public.zelle_payment_submissions WHERE confirmation_reference='BANK-CORRECT'),'rejected','Please correct the sent date; do not pay again.')$$,'director requests correction');
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000092',TRUE);
SELECT is((SELECT reviewer_note FROM public.zelle_payment_submissions WHERE confirmation_reference='BANK-CORRECT'),'Please correct the sent date; do not pay again.','payer can read correction feedback');
SELECT lives_ok($$SELECT public.submit_zelle_payment('52000000-0000-0000-0000-000000000091',100000,NOW(),'BANK-CORRECT','correction-attempt-2')$$,'same reference can be corrected on same invoice');
SELECT is((SELECT count(*)::INTEGER FROM public.zelle_payment_submissions WHERE confirmation_reference='BANK-CORRECT'),2,'prior attempt retained');
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000091',TRUE);
SELECT lives_ok($$SELECT public.review_zelle_payment((SELECT id FROM public.zelle_payment_submissions WHERE idempotency_key='correction-attempt-2'),'approved',NULL)$$,'corrected payment approved');
RESET ROLE;
SELECT is((SELECT count(*)::INTEGER FROM public.notifications WHERE dedupe_key LIKE 'zelle:invoice:%:review'),2,'each submission gets a distinct review notification');
SELECT ok(NOT EXISTS(SELECT 1 FROM public.notifications WHERE body LIKE '%correct the sent date%'),'private review note is not in notification previews');
SELECT is((SELECT access_state FROM public.school_memberships WHERE user_id='10000000-0000-0000-0000-000000000092'),'full','ordinary invoice does not affect onboarding');
-- A second blocker models an independently approved form.
INSERT INTO public.onboarding_template_requirements(id,template_id,position,requirement_type,title,subject_scope,blocks_access,child_record_binding)
VALUES('51100000-0000-0000-0000-000000000093','51000000-0000-0000-0000-000000000092',1,'acknowledgement','Other form','member',TRUE,'none');
INSERT INTO public.onboarding_requirement_instances(id,onboarding_instance_id,template_requirement_id,status)
VALUES('51300000-0000-0000-0000-000000000093','51200000-0000-0000-0000-000000000092','51100000-0000-0000-0000-000000000093','not_started');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000096',TRUE);
SELECT lives_ok($$SELECT public.void_zelle_invoice('52000000-0000-0000-0000-000000000092','Incorrect instructions')$$,'HQ voids enrollment bill');
SELECT lives_ok($$SELECT public.replace_zelle_invoice('52000000-0000-0000-0000-000000000092','Use corrected instructions')$$,'HQ issues replacement');
SELECT lives_ok($$SELECT public.replace_zelle_invoice('52000000-0000-0000-0000-000000000092','Retry')$$,'replacement retry returns same invoice');
RESET ROLE;
SELECT is((SELECT count(*)::INTEGER FROM public.zelle_invoices WHERE replaces_invoice_id='52000000-0000-0000-0000-000000000092'),1,'only one replacement');
SELECT is((SELECT access_state FROM public.school_memberships WHERE user_id='10000000-0000-0000-0000-000000000097'),'onboarding','void and replacement do not release access');
SELECT isnt(public.zelle_can_review_invoice('52000000-0000-0000-0000-000000000092','10000000-0000-0000-0000-000000000094'),TRUE,'historical invoice preserves HQ review boundary');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000097',TRUE);
SELECT lives_ok($$SELECT public.submit_zelle_payment((SELECT id FROM public.zelle_invoices WHERE replaces_invoice_id='52000000-0000-0000-0000-000000000092'),5000,NOW(),'BANK-REPLACEMENT','replacement-payment-1')$$,'payer submits replacement');
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000096',TRUE);
SELECT lives_ok($$SELECT public.review_zelle_payment((SELECT id FROM public.zelle_payment_submissions WHERE confirmation_reference='BANK-REPLACEMENT'),'approved',NULL)$$,'HQ approves replacement');
RESET ROLE;
SELECT is((SELECT access_state FROM public.school_memberships WHERE user_id='10000000-0000-0000-0000-000000000097'),'onboarding','payment alone leaves form blocker');
SELECT like((SELECT body FROM public.notifications WHERE dedupe_key LIKE 'zelle:invoice:%:decision:approved' AND user_id='10000000-0000-0000-0000-000000000097' ORDER BY created_at DESC LIMIT 1),'%FireflyFM HQ%','director approval notification names the HQ reviewer');
UPDATE public.onboarding_requirement_instances SET status='approved' WHERE id='51300000-0000-0000-0000-000000000093';
SELECT public.refresh_onboarding_access('30000000-0000-0000-0000-000000000097');
SELECT is((SELECT access_state FROM public.school_memberships WHERE user_id='10000000-0000-0000-0000-000000000097'),'full','form plus payment releases access');
-- Reverse order and explicit waiver: clear only fixture payment outcome.
UPDATE public.onboarding_requirement_instances SET status='not_started' WHERE id='51300000-0000-0000-0000-000000000092';
UPDATE public.zelle_invoices SET status='open',amount_paid_cents=0,paid_at=NULL WHERE replaces_invoice_id='52000000-0000-0000-0000-000000000092';
SELECT public.refresh_onboarding_access('30000000-0000-0000-0000-000000000097');
SELECT is((SELECT access_state FROM public.school_memberships WHERE user_id='10000000-0000-0000-0000-000000000097'),'onboarding','form alone leaves payment blocker');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000096',TRUE);
SELECT lives_ok($$SELECT public.waive_zelle_requirement((SELECT id FROM public.zelle_invoices WHERE replaces_invoice_id='52000000-0000-0000-0000-000000000092'),'Scholarship approved')$$,'explicit waiver permitted');
RESET ROLE;
SELECT is((SELECT access_state FROM public.school_memberships WHERE user_id='10000000-0000-0000-0000-000000000097'),'full','explicit waiver releases last blocker');
SELECT is((SELECT status FROM public.zelle_invoices WHERE replaces_invoice_id='52000000-0000-0000-0000-000000000092'),'void','waiver produces no paid receipt');

-- Teacher onboarding uses the same manual transfer, correction feedback, and
-- access-release loop, with the school director as the reviewer.
INSERT INTO public.onboarding_templates (id, school_id, target_role, name, version, status, published_at)
VALUES ('51000000-0000-0000-0000-000000000094', '20000000-0000-0000-0000-000000000091', 'teacher', 'Teacher enrollment', 1, 'published', NOW());
INSERT INTO public.onboarding_template_requirements (
    id, template_id, position, requirement_type, title, subject_scope, blocks_access,
    child_record_binding, payment_amount_cents, payment_due_days
) VALUES (
    '51100000-0000-0000-0000-000000000094', '51000000-0000-0000-0000-000000000094', 0,
    'payment', 'Teacher onboarding payment', 'member', TRUE, 'none', 7500, 7
);
INSERT INTO public.onboarding_instances (id, school_id, membership_id, template_id)
VALUES (
    '51200000-0000-0000-0000-000000000094', '20000000-0000-0000-0000-000000000091',
    '30000000-0000-0000-0000-000000000093', '51000000-0000-0000-0000-000000000094'
);
INSERT INTO public.onboarding_requirement_instances (id, onboarding_instance_id, template_requirement_id, status)
VALUES (
    '51300000-0000-0000-0000-000000000094', '51200000-0000-0000-0000-000000000094',
    '51100000-0000-0000-0000-000000000094', 'not_started'
);
INSERT INTO public.zelle_invoices (
    id, school_id, payer_user_id, payer_role, description, amount_due_cents, status, due_at, issued_at
) VALUES (
    '52000000-0000-0000-0000-000000000094', '20000000-0000-0000-0000-000000000091',
    '10000000-0000-0000-0000-000000000093', 'teacher', 'Teacher onboarding payment', 7500,
    'open', NOW() + INTERVAL '7 days', NOW()
);
UPDATE public.zelle_invoices
SET onboarding_requirement_instance_id = '51300000-0000-0000-0000-000000000094'
WHERE id = '52000000-0000-0000-0000-000000000094';
UPDATE public.school_memberships
SET access_state = 'onboarding'
WHERE id = '30000000-0000-0000-0000-000000000093';

SELECT public.refresh_onboarding_access('30000000-0000-0000-0000-000000000093');
SELECT is((SELECT access_state FROM public.school_memberships WHERE id='30000000-0000-0000-0000-000000000093'),'onboarding','teacher payment blocks access');
SELECT is(public.zelle_can_review_invoice('52000000-0000-0000-0000-000000000094','10000000-0000-0000-0000-000000000091'),TRUE,'school director reviews teacher onboarding payment');
SELECT is(public.zelle_can_review_invoice('52000000-0000-0000-0000-000000000094','10000000-0000-0000-0000-000000000096'),FALSE,'HQ cannot review a teacher onboarding payment');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000093',TRUE);
SELECT lives_ok($$SELECT public.submit_zelle_payment('52000000-0000-0000-0000-000000000094',7500,NOW(),'BANK-TEACHER-1','teacher-attempt-1')$$,'teacher submits onboarding payment');
SELECT is((SELECT COUNT(*)::INTEGER FROM public.zelle_invoices WHERE id='52000000-0000-0000-0000-000000000094'),1,'teacher can read the assigned invoice');
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000091',TRUE);
SELECT lives_ok($$SELECT public.review_zelle_payment((SELECT id FROM public.zelle_payment_submissions WHERE idempotency_key='teacher-attempt-1'),'rejected','Please correct the reference; do not pay again.')$$,'director sends correction feedback to teacher');
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000093',TRUE);
SELECT is((SELECT reviewer_note FROM public.zelle_payment_submissions WHERE idempotency_key='teacher-attempt-1'),'Please correct the reference; do not pay again.','teacher can read director feedback');
SELECT lives_ok($$SELECT public.submit_zelle_payment('52000000-0000-0000-0000-000000000094',7500,NOW(),'BANK-TEACHER-2','teacher-attempt-2')$$,'teacher resubmits corrected confirmation');
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000091',TRUE);
SELECT lives_ok($$SELECT public.review_zelle_payment((SELECT id FROM public.zelle_payment_submissions WHERE idempotency_key='teacher-attempt-2'),'approved',NULL)$$,'director approves teacher onboarding payment');
RESET ROLE;

SELECT is((SELECT access_state FROM public.school_memberships WHERE id='30000000-0000-0000-0000-000000000093'),'full','approved teacher payment releases access');
SELECT is((SELECT status FROM public.onboarding_requirement_instances WHERE id='51300000-0000-0000-0000-000000000094'),'approved','teacher payment requirement records approval');
SELECT like((SELECT body FROM public.notifications WHERE dedupe_key LIKE 'zelle:invoice:%:decision:approved' AND user_id='10000000-0000-0000-0000-000000000093' ORDER BY created_at DESC LIMIT 1),'%school director%','teacher approval notification names the school director reviewer');
SELECT * FROM finish();
ROLLBACK;
