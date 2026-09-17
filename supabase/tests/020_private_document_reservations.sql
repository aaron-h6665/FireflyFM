BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT no_plan();

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
    ('30000000-0000-0000-0000-000000000153', '20000000-0000-0000-0000-000000000151', '10000000-0000-0000-0000-000000000153', 'parent', TRUE, 'full');

-- Membership creation intentionally fails closed when no matching published
-- template exists. These fixtures represent already-approved members.
UPDATE public.school_memberships
SET access_state = 'full'
WHERE school_id = '20000000-0000-0000-0000-000000000151';


INSERT INTO public.schools(id,name) VALUES('20000000-0000-0000-0000-000000000152','Other School');
INSERT INTO public.onboarding_requirements(id,school_id,title,target_role)
VALUES('41000000-0000-0000-0000-000000000151','20000000-0000-0000-0000-000000000151','Shared parent requirement','parent');
INSERT INTO storage.buckets(id,name,public) VALUES('school_private_files','school_private_files',false) ON CONFLICT DO NOTHING;
CREATE TEMP TABLE reserved(reservation_id UUID, submission_id UUID, file_path TEXT);
GRANT ALL ON reserved TO authenticated;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000152',true);
INSERT INTO reserved SELECT * FROM public.reserve_required_document_upload('41000000-0000-0000-0000-000000000151','evidence.pdf');
SELECT ok(public.can_write_school_private_file((SELECT file_path FROM reserved),auth.uid()),'owner may upload reserved path');
SELECT is((SELECT submission_id FROM public.reserve_required_document_upload('41000000-0000-0000-0000-000000000151','second-attempt.pdf')),(SELECT submission_id FROM reserved),'parallel reservations retain the same submission identity');
SELECT throws_ok($$SELECT public.finalize_required_document_upload((SELECT reservation_id FROM reserved))$$,'P0001','Upload the document before submitting','finalization requires an object');
SELECT throws_ok($$SELECT public.reserve_required_document_upload('41000000-0000-0000-0000-000000000151','../bad.pdf')$$,'P0001','Invalid document file name','reject path traversal');
SELECT throws_ok($$INSERT INTO public.document_submissions(requirement_id,school_id,submitted_by) VALUES('41000000-0000-0000-0000-000000000151','20000000-0000-0000-0000-000000000151',auth.uid())$$,'42501',NULL,'direct table insert is forbidden');
SELECT throws_ok($$SELECT public.submit_required_document('41000000-0000-0000-0000-000000000151','forged.pdf','forged')$$,'P0001','Update FireflyFM and select the document again','legacy RPC cannot forge a path');
SELECT is(public.can_write_school_private_file(replace((SELECT file_path FROM reserved),'20000000-0000-0000-0000-000000000151','20000000-0000-0000-0000-000000000152'),auth.uid()),false,'forged school denied');
SELECT is(public.can_write_school_private_file(replace((SELECT file_path FROM reserved),(SELECT submission_id::text FROM reserved),gen_random_uuid()::text),auth.uid()),false,'forged submission denied');
SELECT lives_ok($$INSERT INTO storage.objects(bucket_id,name) SELECT 'school_private_files',file_path FROM reserved$$,'owner can INSERT the reserved object through RLS');
SELECT lives_ok($$SELECT public.finalize_required_document_upload((SELECT reservation_id FROM reserved))$$,'owner finalizes uploaded object');
SELECT lives_ok($$SELECT public.finalize_required_document_upload((SELECT reservation_id FROM reserved))$$,'finalization retry is idempotent');
SELECT is((SELECT count(*)::integer FROM public.document_submissions),1,'one submission after retry');
SELECT is((SELECT count(*)::integer FROM storage.objects WHERE name=(SELECT file_path FROM reserved)),1,'owner can read finalized file through storage RLS');
SELECT is(public.can_write_school_private_file((SELECT file_path FROM reserved),auth.uid()),false,'finalized reservation no longer writable');
UPDATE storage.objects SET metadata='{"tampered":true}' WHERE name=(SELECT file_path FROM reserved);
SELECT is((SELECT metadata->>'tampered' FROM storage.objects WHERE name=(SELECT file_path FROM reserved)),NULL,'even owner cannot overwrite reviewed evidence');
SELECT set_config('storage.allow_delete_query','true',true);
DELETE FROM storage.objects WHERE name=(SELECT file_path FROM reserved);
SELECT is((SELECT count(*)::integer FROM storage.objects WHERE name=(SELECT file_path FROM reserved)),1,'owner cannot delete submitted evidence');
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000153',true);
SELECT is((SELECT count(*)::integer FROM storage.objects WHERE name=(SELECT file_path FROM reserved)),0,'same-requirement recipient cannot read another recipient file');
SELECT is(public.can_write_school_private_file((SELECT file_path FROM reserved),auth.uid()),false,'same-requirement recipient cannot overwrite another recipient file');
SELECT throws_ok($$SELECT public.finalize_required_document_upload((SELECT reservation_id FROM reserved))$$,'P0001','Document upload is unavailable','another recipient cannot finalize reservation');
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000151',true);
SELECT is((SELECT count(*)::integer FROM storage.objects WHERE name=(SELECT file_path FROM reserved)),1,'authorized director can read recipient file');
SELECT throws_ok($$UPDATE public.document_submissions SET file_path='forged'$$,'42501',NULL,'reviewer cannot change the evidence association via REST');
RESET ROLE;
UPDATE public.school_memberships SET active=false WHERE user_id='10000000-0000-0000-0000-000000000152';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000152',true);
SELECT is((SELECT count(*)::integer FROM storage.objects WHERE name=(SELECT file_path FROM reserved)),0,'revoked recipient loses file access');
SELECT is((SELECT count(*)::integer FROM public.document_submissions),0,'revoked recipient loses submission metadata access');
SELECT throws_ok($$SELECT public.reserve_required_document_upload('41000000-0000-0000-0000-000000000151','new.pdf')$$,'P0001','You are not assigned to this required document','revoked recipient cannot reserve');
RESET ROLE;
UPDATE public.school_memberships SET active=true,access_state='onboarding' WHERE user_id='10000000-0000-0000-0000-000000000152';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000152',true);
TRUNCATE reserved;
INSERT INTO reserved SELECT * FROM public.reserve_required_document_upload('41000000-0000-0000-0000-000000000151','new.pdf');
SELECT ok(public.can_write_school_private_file((SELECT file_path FROM reserved),auth.uid()),'assigned onboarding member can upload');
RESET ROLE;
UPDATE public.document_upload_reservations SET expires_at=now()-interval '1 second' WHERE id=(SELECT reservation_id FROM reserved);
SET LOCAL ROLE authenticated;
SELECT is(public.can_write_school_private_file((SELECT file_path FROM reserved),auth.uid()),false,'expired reservation cannot upload');
SELECT throws_ok($$INSERT INTO storage.objects(bucket_id,name) SELECT 'school_private_files',file_path FROM reserved$$,'42501',NULL,'expired upload fails storage RLS');
SELECT throws_ok($$SELECT public.finalize_required_document_upload((SELECT reservation_id FROM reserved))$$,'P0001','Document upload expired; select the file again','expired reservation cannot finalize');
RESET ROLE;
-- Staff roles retain only their explicitly authorized review scope.
UPDATE public.school_memberships SET role='teacher' WHERE user_id='10000000-0000-0000-0000-000000000153';
SELECT is(public.can_access_school_private_file((SELECT file_path FROM public.document_submissions LIMIT 1),'10000000-0000-0000-0000-000000000153'),false,'teacher cannot read parent evidence');
UPDATE public.school_memberships SET role='school_director',school_id='20000000-0000-0000-0000-000000000152',access_state='full' WHERE user_id='10000000-0000-0000-0000-000000000153';
SELECT is(public.can_access_school_private_file((SELECT file_path FROM public.document_submissions LIMIT 1),'10000000-0000-0000-0000-000000000153'),false,'other-school director cannot read evidence');
UPDATE public.school_memberships SET role='hq_director',access_state='full' WHERE user_id='10000000-0000-0000-0000-000000000153';
SELECT ok(public.can_access_school_private_file((SELECT file_path FROM public.document_submissions LIMIT 1),'10000000-0000-0000-0000-000000000153'),'HQ reviewer retains authorized access');
UPDATE public.school_memberships SET role='parent',school_id='20000000-0000-0000-0000-000000000151',access_state='full' WHERE user_id='10000000-0000-0000-0000-000000000153';
-- Existing paths are mapped by their authoritative record, never by requirement alone.
UPDATE public.document_submissions SET file_path='schools/20000000-0000-0000-0000-000000000151/document_submissions/41000000-0000-0000-0000-000000000151/legacy.pdf';
SELECT ok(public.can_access_school_private_file((SELECT file_path FROM public.document_submissions LIMIT 1),'10000000-0000-0000-0000-000000000152'),'unique legacy file remains readable to owner');
SELECT is(public.can_access_school_private_file((SELECT file_path FROM public.document_submissions LIMIT 1),'10000000-0000-0000-0000-000000000153'),false,'legacy file is not shared with sibling recipient');
SELECT is(public.can_access_school_private_file('schools/20000000-0000-0000-0000-000000000151/document_submissions/41000000-0000-0000-0000-000000000151/orphan.pdf','10000000-0000-0000-0000-000000000151'),false,'even reviewer cannot read orphaned evidence');
INSERT INTO public.document_submissions(requirement_id,school_id,submitted_by,file_path)
SELECT requirement_id,school_id,'10000000-0000-0000-0000-000000000153',file_path FROM public.document_submissions LIMIT 1;
SELECT is(public.can_access_school_private_file((SELECT file_path FROM public.document_submissions LIMIT 1),'10000000-0000-0000-0000-000000000152'),false,'ambiguous legacy association fails closed');
SELECT ok(EXISTS(SELECT 1 FROM public.document_upload_reconciliation),'orphaned old objects are reported for reconciliation');
SET LOCAL ROLE anon;
SELECT throws_ok($$SELECT public.reserve_required_document_upload('41000000-0000-0000-0000-000000000151','anon.pdf')$$,'42501',NULL,'anonymous caller cannot reserve');
RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
