-- Deny-by-default media storage and path-based references.

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_path TEXT;
ALTER TABLE public.schools ADD COLUMN IF NOT EXISTS profile_image_path TEXT;
ALTER TABLE public.chat_rooms ADD COLUMN IF NOT EXISTS profile_image_path TEXT;
ALTER TABLE public.messages
    ADD COLUMN IF NOT EXISTS media_path TEXT,
    ADD COLUMN IF NOT EXISTS file_path TEXT,
    ADD COLUMN IF NOT EXISTS audio_path TEXT;

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('profile_assets', 'profile_assets', FALSE, 10485760)
ON CONFLICT (id) DO UPDATE
SET public = FALSE, file_size_limit = EXCLUDED.file_size_limit;

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('legacy_media_recovery', 'legacy_media_recovery', FALSE, 10485760)
ON CONFLICT (id) DO UPDATE
SET public = FALSE, file_size_limit = EXCLUDED.file_size_limit;

-- Closing public access is intentionally part of the coordinated beta
-- deployment. Existing signed URLs remain a temporary read fallback while the
-- idempotent migration tool copies objects into their private destinations.
UPDATE storage.buckets SET public = FALSE WHERE id = 'chat_attachments';
DROP POLICY IF EXISTS "Public Access" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can update uploads" ON storage.objects;

CREATE OR REPLACE FUNCTION public.can_view_profile_asset(object_name TEXT, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parts TEXT[];
    owner_uuid UUID;
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL THEN RETURN FALSE; END IF;
    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 4 OR parts[1] <> 'users' OR parts[3] <> 'avatars' THEN RETURN FALSE; END IF;
    owner_uuid := parts[2]::UUID;

    RETURN owner_uuid = user_uuid
        OR public.is_hq_director(user_uuid)
        OR EXISTS (
            SELECT 1
            FROM public.school_memberships owner_membership
            JOIN public.school_memberships viewer_membership
              ON viewer_membership.school_id = owner_membership.school_id
             AND viewer_membership.user_id = user_uuid
             AND viewer_membership.active = TRUE
            WHERE owner_membership.user_id = owner_uuid
              AND owner_membership.active = TRUE
        )
        OR EXISTS (
            SELECT 1
            FROM public.chat_participants owner_participant
            JOIN public.chat_participants viewer_participant
              ON viewer_participant.room_id = owner_participant.room_id
             AND viewer_participant.user_id = user_uuid
            WHERE owner_participant.user_id = owner_uuid
        );
EXCEPTION WHEN invalid_text_representation THEN RETURN FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_write_profile_asset(object_name TEXT, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parts TEXT[];
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL THEN RETURN FALSE; END IF;
    parts := string_to_array(object_name, '/');
    RETURN array_length(parts, 1) >= 4
       AND parts[1] = 'users'
       AND parts[2]::UUID = user_uuid
       AND parts[3] = 'avatars';
EXCEPTION WHEN invalid_text_representation THEN RETURN FALSE;
END;
$$;

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

    IF category = 'chat_rooms' THEN
        record_uuid := parts[4]::UUID;
        RETURN EXISTS (
            SELECT 1
            FROM public.chat_rooms rooms
            JOIN public.chat_participants participants ON participants.room_id = rooms.id
            WHERE rooms.id = record_uuid
              AND rooms.school_id = school_uuid
              AND participants.user_id = user_uuid
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
        RETURN EXISTS (SELECT 1 FROM public.paperwork_assignment_recipients WHERE assignment_id = record_uuid AND parent_id = user_uuid);
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
    ELSIF category = 'document_submissions' THEN
        record_uuid := parts[4]::UUID;
        RETURN public.can_submit_onboarding_requirement(record_uuid, user_uuid) OR public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']);
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
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL THEN RETURN FALSE; END IF;
    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 4 OR parts[1] <> 'schools' THEN RETURN FALSE; END IF;
    school_uuid := parts[2]::UUID;
    category := parts[3];

    IF category = 'chat_rooms' THEN
        IF array_length(parts, 1) < 6 THEN RETURN FALSE; END IF;
        room_uuid := parts[4]::UUID;
        owner_uuid := parts[5]::UUID;
        RETURN owner_uuid = user_uuid AND EXISTS (
            SELECT 1
            FROM public.chat_rooms rooms
            JOIN public.chat_participants participants ON participants.room_id = rooms.id
            WHERE rooms.id = room_uuid
              AND rooms.school_id = school_uuid
              AND participants.user_id = user_uuid
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
              AND templates.status = 'draft'
              AND public.is_onboarding_template_manager(templates.school_id, templates.target_role, user_uuid)
        );
    END IF;

    IF category IN ('paperwork_assignments', 'curriculum_resources', 'training_assignments', 'onboarding_requirements') THEN
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']);
    END IF;
    IF category = 'assignments' THEN
        IF array_length(parts, 1) < 5 THEN RETURN FALSE; END IF;
        IF parts[5] = 'materials' THEN
            RETURN public.can_manage_assignment(parts[4]::UUID, user_uuid);
        ELSIF parts[5] = 'submissions' THEN
            IF array_length(parts, 1) < 6 THEN RETURN FALSE; END IF;
            owner_uuid := parts[6]::UUID;
            RETURN owner_uuid = user_uuid AND public.can_submit_assignment(parts[4]::UUID, user_uuid);
        END IF;
        RETURN FALSE;
    END IF;
    IF array_length(parts, 1) < 5 THEN RETURN FALSE; END IF;
    owner_uuid := parts[4]::UUID;
    IF category = 'paperwork_submissions' THEN
        RETURN owner_uuid = user_uuid AND public.has_school_membership(school_uuid, user_uuid);
    ELSIF category = 'training_submissions' THEN
        RETURN owner_uuid = user_uuid AND public.has_school_role(school_uuid, user_uuid, ARRAY['teacher']);
    ELSIF category = 'document_submissions' THEN
        RETURN public.can_submit_onboarding_requirement(owner_uuid, user_uuid);
    ELSIF category = 'child_documents' THEN
        RETURN public.can_access_child(owner_uuid, user_uuid);
    ELSIF category IN ('community_posts', 'community_albums') THEN
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['teacher', 'school_director', 'hq_director']);
    END IF;
    RETURN FALSE;
EXCEPTION WHEN invalid_text_representation THEN RETURN FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.can_view_profile_asset(TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_write_profile_asset(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_view_profile_asset(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_write_profile_asset(TEXT, UUID) TO authenticated;

DROP POLICY IF EXISTS "Profile assets are relationship private" ON storage.objects;
DROP POLICY IF EXISTS "Users can upload their profile assets" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their profile assets" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their profile assets" ON storage.objects;

CREATE POLICY "Profile assets are relationship private"
    ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'profile_assets' AND public.can_view_profile_asset(name, auth.uid()));
CREATE POLICY "Users can upload their profile assets"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'profile_assets' AND public.can_write_profile_asset(name, auth.uid()));
CREATE POLICY "Users can update their profile assets"
    ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'profile_assets' AND public.can_write_profile_asset(name, auth.uid()))
    WITH CHECK (bucket_id = 'profile_assets' AND public.can_write_profile_asset(name, auth.uid()));
CREATE POLICY "Users can delete their profile assets"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'profile_assets' AND public.can_write_profile_asset(name, auth.uid()));

DROP POLICY IF EXISTS "School members can delete own private uploads" ON storage.objects;
DROP POLICY IF EXISTS "School members can delete private files" ON storage.objects;
DROP POLICY IF EXISTS "School private file deletes are owner scoped" ON storage.objects;
CREATE POLICY "School private file deletes are owner scoped"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'school_private_files' AND public.can_delete_school_private_file(name, auth.uid()));

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260721020000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
