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


INSERT INTO public.school_zelle_profiles(school_id,recipient_display_name,recipient_type,recipient_value,active)
VALUES('20000000-0000-0000-0000-000000000091','School A','email','school@example.test',TRUE);
INSERT INTO public.hq_zelle_profile(recipient_display_name,recipient_type,recipient_value,active)
VALUES('HQ','email','hq@example.test',TRUE);
INSERT INTO public.zelle_invoices(id,school_id,payer_user_id,payer_role,description,amount_due_cents,status)
VALUES('52000000-0000-0000-0000-000000000091','20000000-0000-0000-0000-000000000091','10000000-0000-0000-0000-000000000092','parent','Parent fee',1000,'open'),
('52000000-0000-0000-0000-000000000092','20000000-0000-0000-0000-000000000092','10000000-0000-0000-0000-000000000097','school_director','Director fee',1000,'open');
SELECT is((SELECT recipient_snapshot->>'value' FROM public.zelle_invoices WHERE id='52000000-0000-0000-0000-000000000091'),'school@example.test','parent pays school');
SELECT is((SELECT recipient_snapshot->>'value' FROM public.zelle_invoices WHERE id='52000000-0000-0000-0000-000000000092'),'hq@example.test','director pays HQ even without school receiving settings');
UPDATE public.hq_zelle_profile SET recipient_value='new-hq@example.test';
SELECT is((SELECT recipient_snapshot->>'value' FROM public.zelle_invoices WHERE id='52000000-0000-0000-0000-000000000092'),'hq@example.test','issued HQ recipient immutable after profile edit');
SELECT throws_ok($$UPDATE public.zelle_invoices SET recipient_owner='school' WHERE id='52000000-0000-0000-0000-000000000092'$$,'P0001','Invoice recipient and environment are immutable','cannot change issued owner');
SELECT is(public.zelle_can_review_invoice('52000000-0000-0000-0000-000000000092','10000000-0000-0000-0000-000000000097'),FALSE,'payer cannot approve own invoice');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000093',TRUE);
SELECT throws_ok($$SELECT public.save_hq_zelle_profile('Intruder','email','intruder@example.test','HQ','',TRUE)$$,'P0001','HQ access required','teacher cannot edit HQ receiving settings');
SELECT is((SELECT count(*)::INTEGER FROM public.fetch_workspace_payer_labels(NULL)),0,'teacher cannot enumerate other payers');
SELECT throws_ok($$SELECT * FROM public.create_paperwork_request('20000000-0000-0000-0000-000000000091','Unauthorized',NULL,'document_upload','parent',NULL,ARRAY['10000000-0000-0000-0000-000000000092'::UUID],NULL,TRUE)$$,'P0001','You cannot create paperwork for this school','teacher cannot create paperwork');
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000091',TRUE);
SELECT lives_ok($$SELECT * FROM public.create_paperwork_request('20000000-0000-0000-0000-000000000091','Beta policy','Policy text v1','acknowledgement','parent',NULL,ARRAY['10000000-0000-0000-0000-000000000092'::UUID],NULL,FALSE)$$,'director creates policy');
RESET ROLE;
SELECT is((SELECT count(*)::INTEGER FROM public.notifications n JOIN public.notification_recipients r ON r.notification_id=n.id
    WHERE n.source_type='paperwork_request' AND n.body='Beta policy' AND r.user_id='10000000-0000-0000-0000-000000000092'),1,
    'new paperwork notifies its recipient once');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000091',TRUE);
SELECT is((SELECT count(*)::INTEGER FROM public.fetch_my_paperwork_items_v2('20000000-0000-0000-0000-000000000091',FALSE)),1,'manager sees one obligation');
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000092',TRUE);
SELECT is((SELECT count(*)::INTEGER FROM public.fetch_my_paperwork_items_v2('20000000-0000-0000-0000-000000000092',FALSE)),0,'recipient cannot read other school');
SELECT lives_ok($$SELECT * FROM public.acknowledge_paperwork_request((SELECT id FROM public.paperwork_assignments WHERE title='Beta policy'),'beta-policy-ack')$$,'recipient acknowledges native policy');
SELECT is((SELECT count(*)::INTEGER FROM public.fetch_my_paperwork_items_v2('20000000-0000-0000-0000-000000000091',FALSE)),0,'completed obligation leaves active view');
SELECT is((SELECT count(*)::INTEGER FROM public.fetch_my_paperwork_items_v2('20000000-0000-0000-0000-000000000091',TRUE)),1,'completed obligation appears once in history');
SELECT is((SELECT structured_payload->'policy_snapshot'->>'description' FROM public.paperwork_submissions WHERE assignment_id=(SELECT id FROM public.paperwork_assignments WHERE title='Beta policy')),'Policy text v1','acknowledgement retains exact policy text');
RESET ROLE;
SELECT throws_ok($$UPDATE public.paperwork_assignments SET description='Edited' WHERE title='Beta policy'$$,'P0001','Issue a new policy request to change published policy content','published content cannot be rewritten');
SELECT is(public.zelle_is_demo_environment(),FALSE,'beta never enables simulated transfers');

-- Native per-file corrections are atomic with the review and cannot point elsewhere.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000091',TRUE);
SELECT * FROM public.create_paperwork_request('20000000-0000-0000-0000-000000000091','Beta upload','Upload a signed form','document_upload','parent',NULL,ARRAY['10000000-0000-0000-0000-000000000092'::UUID],NULL,TRUE);
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000092',TRUE);
SELECT * FROM public.submit_paperwork_request((SELECT id FROM public.paperwork_assignments WHERE title='Beta upload'),'unsigned.pdf','schools/20000000-0000-0000-0000-000000000091/paperwork_submissions/10000000-0000-0000-0000-000000000092/unsigned.pdf','beta-upload-attempt');
RESET ROLE;
SELECT is((SELECT count(*)::INTEGER FROM public.notifications n JOIN public.notification_recipients r ON r.notification_id=n.id
    WHERE n.source_type='paperwork_submission' AND n.title='Paperwork needs review' AND r.user_id='10000000-0000-0000-0000-000000000091'),1,
    'paperwork submission notifies the school director once');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000091',TRUE);
SELECT throws_ok($$SELECT public.review_paperwork_with_corrections((SELECT s.id FROM public.paperwork_submissions s JOIN public.paperwork_assignments a ON a.id=s.assignment_id WHERE a.title='Beta upload'),'changes_requested','Please sign', '[{"target_kind":"file","target_id":"wrong","title":"File","note":"Please sign"}]')$$,'P0001','Correction must target this submitted file','forged correction target is rejected');
SELECT is((SELECT s.status FROM public.paperwork_submissions s JOIN public.paperwork_assignments a ON a.id=s.assignment_id WHERE a.title='Beta upload'),'submitted','invalid corrections roll back review transition');
SELECT lives_ok($$SELECT public.review_paperwork_with_corrections((SELECT s.id FROM public.paperwork_submissions s JOIN public.paperwork_assignments a ON a.id=s.assignment_id WHERE a.title='Beta upload'),'changes_requested','Please sign', (SELECT jsonb_build_array(jsonb_build_object('target_kind','file','target_id',s.id,'title','unsigned.pdf','note','Please sign page 2')) FROM public.paperwork_submissions s JOIN public.paperwork_assignments a ON a.id=s.assignment_id WHERE a.title='Beta upload'))$$,'valid file correction saved');
RESET ROLE;
SELECT is((SELECT count(*)::INTEGER FROM public.notifications n JOIN public.notification_recipients r ON r.notification_id=n.id
    WHERE n.source_type='paperwork_submission' AND n.title='Paperwork changes requested' AND r.user_id='10000000-0000-0000-0000-000000000092'),1,
    'paperwork change request notifies the submitter once');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000092',TRUE);
SELECT is((SELECT count(*)::INTEGER FROM public.paperwork_corrections),1,'recipient can read their correction');
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000095',TRUE);
SELECT is((SELECT count(*)::INTEGER FROM public.paperwork_corrections),0,'unrelated parent cannot read corrections');
RESET ROLE;

-- Historical teacher authorship does not confer management.
INSERT INTO public.assignments(id, school_id, assigned_by, title, category, status)
VALUES('62000000-0000-0000-0000-000000000091','20000000-0000-0000-0000-000000000091','10000000-0000-0000-0000-000000000093','Legacy teacher assignment','training','published');
SELECT is(public.can_manage_assignment('62000000-0000-0000-0000-000000000091','10000000-0000-0000-0000-000000000093'),FALSE,'legacy teacher author cannot manage');

-- Two schools using the same bank recipient cannot reuse a transfer reference.
INSERT INTO public.school_zelle_profiles(school_id,recipient_display_name,recipient_type,recipient_value,active)
VALUES('20000000-0000-0000-0000-000000000092','Same receiving account','email','school@example.test',TRUE);
INSERT INTO public.zelle_invoices(id,school_id,payer_user_id,payer_role,description,amount_due_cents,status)
VALUES('52000000-0000-0000-0000-000000000093','20000000-0000-0000-0000-000000000092','10000000-0000-0000-0000-000000000095','parent','Other school fee',1000,'open');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000092',TRUE);
SELECT lives_ok($$SELECT public.submit_zelle_payment('52000000-0000-0000-0000-000000000091',1000,NOW(),'BANK-BETA-REF','beta-parent-reference-1')$$,'first account reference accepted');
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000095',TRUE);
SELECT throws_ok($$SELECT public.submit_zelle_payment('52000000-0000-0000-0000-000000000093',1000,NOW(),'BANK-BETA-REF','beta-parent-reference-2')$$,'23505','This reference belongs to another invoice for this recipient','reference cannot be reused across schools for same recipient');
RESET ROLE;

INSERT INTO public.google_form_connections(id,school_id,form_role,form_key,form_id,form_url,form_title,status,created_by)
VALUES('72000000-0000-0000-0000-000000000091','20000000-0000-0000-0000-000000000091','parent','beta-form','beta-form','https://docs.google.com/forms/d/beta-form/viewform','Beta Form','connected','10000000-0000-0000-0000-000000000091');
INSERT INTO public.google_form_imports(id,connection_id,school_id,google_response_id,submitted_payload,question_snapshot,status,membership_id,submitted_by)
VALUES('73000000-0000-0000-0000-000000000091','72000000-0000-0000-0000-000000000091','20000000-0000-0000-0000-000000000091','beta-response','{}','[{"id":"phone","title":"Phone number"}]','pending_review','30000000-0000-0000-0000-000000000092','10000000-0000-0000-0000-000000000092');
SELECT is((SELECT count(*)::INTEGER FROM public.notifications n JOIN public.notification_recipients r ON r.notification_id=n.id
    WHERE n.source_id='73000000-0000-0000-0000-000000000091' AND n.category='google_form_response'
      AND r.user_id='10000000-0000-0000-0000-000000000091'),1,
    'new Form response notifies the school director once');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000091',TRUE);
SELECT is((SELECT count(*)::INTEGER FROM public.fetch_unmatched_paperwork_responses('20000000-0000-0000-0000-000000000091')),1,'unmatched responses remain visible for review');
SELECT throws_ok($$SELECT public.review_google_form_with_corrections('73000000-0000-0000-0000-000000000091','changes_requested',NULL,'Correct phone','[{"target_kind":"answer","target_id":"forged","title":"Wrong question","note":"Update"}]')$$,'P0001','Answer does not belong to this submission','cannot target an unrelated answer');
SELECT is((SELECT status FROM public.google_form_imports WHERE id='73000000-0000-0000-0000-000000000091'),'pending_review','invalid answer correction leaves review unchanged');
SELECT lives_ok($$SELECT public.review_google_form_with_corrections('73000000-0000-0000-0000-000000000091','changes_requested',NULL,'Add phone','[{"target_kind":"answer","target_id":"phone","title":"Phone number","note":"Please add your phone number"}]')$$,'can flag an unanswered snapshot question');
RESET ROLE;
SELECT is((SELECT count(*)::INTEGER FROM public.notifications n JOIN public.notification_recipients r ON r.notification_id=n.id
    WHERE n.source_id='73000000-0000-0000-0000-000000000091' AND n.title='Form changes requested'
      AND r.user_id='10000000-0000-0000-0000-000000000092'),1,
    'Form change request notifies the respondent once');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000092',TRUE);
SELECT is((SELECT count(*)::INTEGER FROM public.paperwork_corrections WHERE google_import_id='73000000-0000-0000-0000-000000000091'),1,'recipient sees targeted Google answer feedback');
SELECT is((SELECT count(*)::INTEGER FROM public.fetch_unmatched_paperwork_responses('20000000-0000-0000-0000-000000000091')),0,'recipient cannot enumerate unmatched responses');
RESET ROLE;
SELECT is(public.zelle_recipient_account_key('{"type":"mobile","value":"(212) 555-0100"}'),
    public.zelle_recipient_account_key('{"type":"mobile","value":"+1 212 555 0100"}'),
    'US mobile recipient formatting cannot bypass duplicate reference checks');
SELECT * FROM finish();
ROLLBACK;
