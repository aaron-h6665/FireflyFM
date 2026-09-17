-- Bind private document objects to server-authorized submission attempts.
BEGIN;
CREATE TABLE public.document_upload_reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    submission_id UUID NOT NULL,
    requirement_id UUID NOT NULL REFERENCES public.onboarding_requirements(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    submitted_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    file_name TEXT NOT NULL,
    file_path TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + interval '1 hour',
    finalized_at TIMESTAMPTZ
);
ALTER TABLE public.document_upload_reservations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.document_upload_reservations FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.document_upload_reservations TO service_role;

-- Onboarding recipients must be able to finish their assigned documents before
-- gaining full access. Do not borrow management-role helpers for this decision.
CREATE FUNCTION public.can_upload_required_document(requirement_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.onboarding_requirements q
        JOIN public.school_memberships m ON m.school_id = q.school_id AND m.user_id = user_uuid AND m.active
        WHERE q.id = requirement_uuid
          AND (q.target_user_id = user_uuid OR (q.target_user_id IS NULL AND (q.target_role IS NULL OR q.target_role = m.role)))
    );
$$;
REVOKE ALL ON FUNCTION public.can_upload_required_document(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_upload_required_document(UUID, UUID) TO authenticated;

CREATE FUNCTION public.reserve_required_document_upload(input_requirement_id UUID, input_file_name TEXT)
RETURNS TABLE(reservation_id UUID, submission_id UUID, file_path TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    requirement public.onboarding_requirements%ROWTYPE;
    reserved public.document_upload_reservations%ROWTYPE;
    actor UUID := auth.uid();
BEGIN
    SELECT * INTO requirement FROM public.onboarding_requirements WHERE id = input_requirement_id;
    IF actor IS NULL OR requirement.id IS NULL
       OR NOT public.has_school_membership(requirement.school_id, actor)
       OR NOT public.can_upload_required_document(requirement.id, actor) THEN
        RAISE EXCEPTION 'You are not assigned to this required document';
    END IF;
    IF input_file_name IS NULL OR length(btrim(input_file_name)) NOT BETWEEN 1 AND 180
       OR input_file_name ~ '[/\\[:cntrl:]]' OR input_file_name IN ('.', '..') THEN
        RAISE EXCEPTION 'Invalid document file name';
    END IF;
    -- A requirement has one current submission per recipient; attempts get unique paths.
    PERFORM pg_advisory_xact_lock(hashtextextended(requirement.id::text || ':' || actor::text, 0));
    SELECT d.id INTO reserved.submission_id FROM public.document_submissions d
    WHERE d.requirement_id = requirement.id AND d.submitted_by = actor;
    IF reserved.submission_id IS NULL THEN
        SELECT r.submission_id INTO reserved.submission_id FROM public.document_upload_reservations r
        WHERE r.requirement_id = requirement.id AND r.submitted_by = actor
        ORDER BY r.expires_at DESC, r.id LIMIT 1;
    END IF;
    reserved.submission_id := COALESCE(reserved.submission_id, gen_random_uuid());
    reserved.id := gen_random_uuid();
    reserved.file_path := 'schools/' || requirement.school_id || '/document_submissions/'
        || requirement.id || '/' || reserved.submission_id || '/' || reserved.id || '/' || input_file_name;
    INSERT INTO public.document_upload_reservations(id, submission_id, requirement_id, school_id, submitted_by, file_name, file_path)
    VALUES(reserved.id, reserved.submission_id, requirement.id, requirement.school_id, actor, input_file_name, reserved.file_path);
    RETURN QUERY SELECT reserved.id, reserved.submission_id, reserved.file_path;
END; $$;

CREATE FUNCTION public.can_access_reserved_document(object_name TEXT, user_uuid UUID, writing BOOLEAN DEFAULT FALSE)
RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE parts TEXT[] := string_to_array(object_name, '/');
BEGIN
    IF user_uuid IS NULL OR parts[1] <> 'schools' OR parts[3] <> 'document_submissions' THEN RETURN FALSE; END IF;
    IF writing THEN
        RETURN EXISTS (
            SELECT 1 FROM public.document_upload_reservations r
            JOIN public.onboarding_requirements q ON q.id = r.requirement_id AND q.school_id = r.school_id
            WHERE r.file_path = object_name AND r.school_id = parts[2]::uuid AND r.requirement_id = parts[4]::uuid
              AND r.submission_id = parts[5]::uuid AND r.id = parts[6]::uuid
              AND r.submitted_by = user_uuid AND r.finalized_at IS NULL AND r.expires_at > now()
              AND public.has_school_membership(r.school_id, user_uuid)
              AND public.can_upload_required_document(r.requirement_id, user_uuid)
        );
    END IF;
    -- Old paths remain readable only through a unique, correctly scoped submission.
    IF (SELECT count(*) FROM public.document_submissions WHERE file_path = object_name) <> 1 THEN RETURN FALSE; END IF;
    RETURN EXISTS (
        SELECT 1 FROM public.document_submissions d
        JOIN public.onboarding_requirements q ON q.id = d.requirement_id AND q.school_id = d.school_id
        WHERE d.file_path = object_name AND d.school_id = parts[2]::uuid AND d.requirement_id = parts[4]::uuid
          AND ((d.submitted_by = user_uuid AND public.has_school_membership(d.school_id, user_uuid))
               OR public.can_manage_onboarding_requirement(d.requirement_id, user_uuid))
    );
EXCEPTION WHEN invalid_text_representation THEN RETURN FALSE;
END; $$;

CREATE FUNCTION public.finalize_required_document_upload(input_reservation_id UUID)
RETURNS SETOF public.document_submissions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r public.document_upload_reservations%ROWTYPE;
BEGIN
    SELECT * INTO r FROM public.document_upload_reservations WHERE id = input_reservation_id FOR UPDATE;
    IF r.id IS NULL OR r.submitted_by IS DISTINCT FROM auth.uid()
       OR NOT public.has_school_membership(r.school_id, auth.uid())
       OR NOT public.can_upload_required_document(r.requirement_id, auth.uid()) THEN
        RAISE EXCEPTION 'Document upload is unavailable';
    END IF;
    PERFORM 1 FROM public.onboarding_requirements q WHERE q.id = r.requirement_id AND q.school_id = r.school_id FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Document upload is unavailable'; END IF;
    -- Retry is idempotent, but an old attempt cannot replace a newer submission.
    IF r.finalized_at IS NOT NULL THEN
        RETURN QUERY SELECT d.* FROM public.document_submissions d WHERE d.id = r.submission_id;
        RETURN;
    END IF;
    IF r.expires_at <= now() THEN RAISE EXCEPTION 'Document upload expired; select the file again'; END IF;
    PERFORM 1 FROM storage.objects o WHERE o.bucket_id = 'school_private_files' AND o.name = r.file_path FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Upload the document before submitting'; END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(r.requirement_id::text || ':' || r.submitted_by::text, 0));
    INSERT INTO public.document_submissions(id, requirement_id, school_id, submitted_by, file_name, file_path, status)
    VALUES(r.submission_id, r.requirement_id, r.school_id, r.submitted_by, r.file_name, r.file_path, 'submitted')
    ON CONFLICT ON CONSTRAINT document_submissions_requirement_id_submitted_by_key
    DO UPDATE SET file_name = EXCLUDED.file_name, file_path = EXCLUDED.file_path, status = 'submitted',
        reviewer_message = NULL, reviewed_by = NULL, reviewed_at = NULL, submitted_at = now()
    RETURNING id INTO r.submission_id;
    UPDATE public.document_upload_reservations SET finalized_at = now(), submission_id = r.submission_id WHERE id = r.id;
    RETURN QUERY SELECT d.* FROM public.document_submissions d WHERE d.id = r.submission_id;
END; $$;

-- Retain the old RPC signature, but require the new reservation contract.
CREATE OR REPLACE FUNCTION public.submit_required_document(requirement_id UUID, file_name TEXT, file_path TEXT)
RETURNS SETOF public.document_submissions LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE reserved_id UUID;
BEGIN
    SELECT r.id INTO reserved_id FROM public.document_upload_reservations r
    WHERE r.requirement_id = $1 AND r.file_name = $2 AND r.file_path = $3 AND r.submitted_by = auth.uid();
    IF reserved_id IS NULL THEN RAISE EXCEPTION 'Update FireflyFM and select the document again'; END IF;
    RETURN QUERY SELECT * FROM public.finalize_required_document_upload(reserved_id);
END; $$;

-- Clients cannot forge a file association or rewrite reviewed evidence through REST.
REVOKE INSERT, UPDATE, DELETE ON public.document_submissions FROM PUBLIC, anon, authenticated;
DROP POLICY IF EXISTS "Users can submit required documents" ON public.document_submissions;
DROP POLICY IF EXISTS "Directors can review required documents" ON public.document_submissions;

DROP POLICY IF EXISTS "Users can view document submissions" ON public.document_submissions;
CREATE POLICY "Users can view document submissions" ON public.document_submissions FOR SELECT TO authenticated
USING (EXISTS (
    SELECT 1 FROM public.onboarding_requirements q
    WHERE q.id = requirement_id AND q.school_id = document_submissions.school_id
      AND ((submitted_by = auth.uid() AND public.has_school_membership(q.school_id, auth.uid()))
           OR public.can_manage_onboarding_requirement(q.id, auth.uid()))
));

-- INSERT-only objects avoid overwrite/delete races with finalization. Cleanup is server-owned.
CREATE POLICY "Document evidence cannot be overwritten" ON storage.objects AS RESTRICTIVE
FOR UPDATE TO authenticated USING (bucket_id <> 'school_private_files' OR split_part(name, '/', 3) <> 'document_submissions')
WITH CHECK (bucket_id <> 'school_private_files' OR split_part(name, '/', 3) <> 'document_submissions');
CREATE POLICY "Document evidence cannot be deleted by clients" ON storage.objects AS RESTRICTIVE
FOR DELETE TO authenticated USING (bucket_id <> 'school_private_files' OR split_part(name, '/', 3) <> 'document_submissions');

CREATE OR REPLACE FUNCTION public.can_access_school_private_file(object_name TEXT, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parts TEXT[];
    school_uuid UUID;
    category TEXT;
    record_uuid UUID;
    owner_uuid UUID;
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL THEN RETURN FALSE; END IF;
    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 4 OR parts[1] <> 'schools' THEN RETURN FALSE; END IF;
    school_uuid := parts[2]::UUID;
    category := parts[3];
    IF category = 'document_submissions' THEN
        RETURN public.can_access_reserved_document(object_name, user_uuid, FALSE);
    END IF;

    IF category = 'chat_rooms' THEN
        record_uuid := parts[4]::UUID;
        RETURN EXISTS (
            SELECT 1
            FROM public.chat_rooms rooms
            JOIN public.chat_participants participants ON participants.room_id = rooms.id
            WHERE rooms.id = record_uuid
              AND (rooms.school_id = school_uuid OR rooms.room_type = 'hq_custom')
              AND participants.user_id = user_uuid
              AND participants.role != 'invited'
        );
    ELSIF category = 'school_assets' THEN
        RETURN public.is_school_member(school_uuid, user_uuid);
    ELSIF category = 'onboarding_templates' THEN
        RETURN EXISTS (
            SELECT 1
            FROM public.onboarding_templates templates
            WHERE templates.id = parts[4]::UUID
              AND templates.school_id = school_uuid
              AND public.is_onboarding_template_manager(templates.school_id, templates.target_role, user_uuid)
        ) OR EXISTS (
            SELECT 1
            FROM public.onboarding_template_attachments attachments
            JOIN public.onboarding_template_requirements requirements ON requirements.id = attachments.requirement_id
            LEFT JOIN public.onboarding_requirement_instances requirement_instances ON requirement_instances.template_requirement_id = requirements.id
            WHERE attachments.private_file_path = object_name
              AND requirement_instances.assignment_id IS NOT NULL
              AND public.can_view_assignment(requirement_instances.assignment_id, user_uuid)
        );
    END IF;

    IF category <> 'assignments'
       AND public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']) THEN RETURN TRUE; END IF;
    IF category = 'paperwork_assignments' THEN
        record_uuid := parts[4]::UUID;
        RETURN EXISTS (
            SELECT 1
            FROM public.paperwork_assignment_recipients
            WHERE assignment_id = record_uuid
              AND (user_id = user_uuid OR parent_id = user_uuid)
        );
    ELSIF category = 'paperwork_submissions' THEN
        owner_uuid := parts[4]::UUID;
        RETURN owner_uuid = user_uuid AND public.has_school_membership(school_uuid, user_uuid);
    ELSIF category IN ('curriculum_resources', 'training_assignments') THEN
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['teacher']);
    ELSIF category = 'training_submissions' THEN
        owner_uuid := parts[4]::UUID;
        RETURN owner_uuid = user_uuid AND public.has_school_role(school_uuid, user_uuid, ARRAY['teacher']);
    ELSIF category = 'onboarding_requirements' THEN
        record_uuid := parts[4]::UUID;
        RETURN public.can_manage_onboarding_requirement(record_uuid, user_uuid) OR public.can_submit_onboarding_requirement(record_uuid, user_uuid);
    ELSIF category = 'child_documents' THEN
        record_uuid := parts[4]::UUID;
        RETURN public.can_access_child(record_uuid, user_uuid);
    ELSIF category = 'assignments' THEN
        IF array_length(parts, 1) < 5 THEN RETURN FALSE; END IF;
        record_uuid := parts[4]::UUID;
        IF parts[5] = 'submissions' THEN
            IF array_length(parts, 1) < 6 THEN RETURN FALSE; END IF;
            owner_uuid := parts[6]::UUID;
            RETURN owner_uuid = user_uuid OR public.can_manage_assignment(record_uuid, user_uuid);
        END IF;
        RETURN public.can_view_assignment(record_uuid, user_uuid);
    ELSIF category IN ('community_posts', 'community_albums') THEN
        RETURN public.is_school_member(school_uuid, user_uuid);
    END IF;
    RETURN FALSE;
EXCEPTION WHEN invalid_text_representation THEN RETURN FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_write_school_private_file(object_name TEXT, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parts TEXT[];
    school_uuid UUID;
    category TEXT;
    owner_uuid UUID;
    room_uuid UUID;
    record_uuid UUID;
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL THEN RETURN FALSE; END IF;
    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 4 OR parts[1] <> 'schools' THEN RETURN FALSE; END IF;
    school_uuid := parts[2]::UUID;
    category := parts[3];
    IF category = 'document_submissions' THEN
        RETURN public.can_access_reserved_document(object_name, user_uuid, TRUE);
    END IF;

    IF category = 'chat_rooms' THEN
        IF array_length(parts, 1) < 6 THEN RETURN FALSE; END IF;
        room_uuid := parts[4]::UUID;
        owner_uuid := parts[5]::UUID;
        RETURN owner_uuid = user_uuid AND EXISTS (
            SELECT 1
            FROM public.chat_rooms rooms
            JOIN public.chat_participants participants ON participants.room_id = rooms.id
            WHERE rooms.id = room_uuid
              AND (rooms.school_id = school_uuid OR rooms.room_type = 'hq_custom')
              AND participants.user_id = user_uuid
              AND participants.role != 'invited'
        );
    ELSIF category = 'school_assets' THEN
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']);
    ELSIF category = 'onboarding_templates' THEN
        IF array_length(parts, 1) < 5 THEN RETURN FALSE; END IF;
        RETURN EXISTS (
            SELECT 1
            FROM public.onboarding_templates templates
            WHERE templates.id = parts[4]::UUID
              AND templates.school_id = school_uuid
              AND public.is_onboarding_template_manager(templates.school_id, templates.target_role, user_uuid)
        );
    END IF;

    IF category = 'paperwork_submissions' THEN
        IF array_length(parts, 1) < 5 THEN RETURN FALSE; END IF;
        owner_uuid := parts[4]::UUID;
        RETURN owner_uuid = user_uuid AND public.has_school_membership(school_uuid, user_uuid);
    ELSIF category = 'training_submissions' THEN
        IF array_length(parts, 1) < 5 THEN RETURN FALSE; END IF;
        owner_uuid := parts[4]::UUID;
        RETURN owner_uuid = user_uuid AND public.has_school_role(school_uuid, user_uuid, ARRAY['teacher']);
    ELSIF category = 'child_documents' THEN
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']);
    ELSIF category = 'assignments' THEN
        IF array_length(parts, 1) < 5 THEN RETURN FALSE; END IF;
        room_uuid := parts[4]::UUID;
        IF parts[5] = 'submissions' THEN
            IF array_length(parts, 1) < 6 THEN RETURN FALSE; END IF;
            owner_uuid := parts[6]::UUID;
            RETURN owner_uuid = user_uuid AND public.can_submit_assignment(room_uuid, user_uuid);
        END IF;
        RETURN public.can_manage_assignment(room_uuid, user_uuid);
    ELSIF category IN ('community_posts', 'community_albums') THEN
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']);
    END IF;
    RETURN FALSE;
EXCEPTION WHEN invalid_text_representation THEN RETURN FALSE;
END;
$$;

-- Service-only reconciliation inventory; no existing object is removed by this migration.
CREATE VIEW public.document_upload_reconciliation WITH (security_invoker = true) AS
SELECT o.name AS file_path,
       CASE WHEN count(d.id) = 0 THEN 'orphaned' WHEN count(d.id) > 1 THEN 'ambiguous' ELSE 'scope_mismatch' END AS reason
FROM storage.objects o
LEFT JOIN public.document_submissions d ON d.file_path = o.name
LEFT JOIN public.onboarding_requirements q ON q.id = d.requirement_id AND q.school_id = d.school_id
WHERE o.bucket_id = 'school_private_files' AND split_part(o.name, '/', 3) = 'document_submissions'
  AND NOT EXISTS (SELECT 1 FROM public.document_upload_reservations r WHERE r.file_path = o.name AND r.finalized_at IS NULL AND r.expires_at > now())
GROUP BY o.name
HAVING count(d.id) <> 1 OR bool_or(q.id IS NULL OR lower(split_part(o.name, '/', 2)) <> d.school_id::text OR lower(split_part(o.name, '/', 4)) <> d.requirement_id::text);
REVOKE ALL ON public.document_upload_reconciliation FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.document_upload_reconciliation TO service_role;
REVOKE ALL ON FUNCTION public.reserve_required_document_upload(UUID, TEXT), public.finalize_required_document_upload(UUID), public.can_access_reserved_document(TEXT, UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reserve_required_document_upload(UUID, TEXT), public.finalize_required_document_upload(UUID), public.can_access_reserved_document(TEXT, UUID, BOOLEAN) TO authenticated;
CREATE OR REPLACE FUNCTION public.get_firefly_schema_version() RETURNS BIGINT
LANGUAGE sql STABLE AS $$ SELECT 20260918100000::BIGINT $$;
NOTIFY pgrst, 'reload schema';
COMMIT;
