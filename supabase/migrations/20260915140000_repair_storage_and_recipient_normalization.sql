-- Migration: 20260915140000_repair_storage_and_recipient_normalization.sql
-- Description: Repair can_write_school_private_file storage regression for document_submissions,
-- normalize recipient checks to accept both user_id and parent_id, and bump schema version.

-- 1. Ensure user_id and recipient normalization columns exist on paperwork_assignment_recipients
ALTER TABLE public.paperwork_assignment_recipients
    ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS role_at_request TEXT,
    ADD COLUMN IF NOT EXISTS child_id UUID REFERENCES public.children(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS completion_status TEXT NOT NULL DEFAULT 'not_started',
    ADD COLUMN IF NOT EXISTS viewed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

UPDATE public.paperwork_assignment_recipients
SET user_id = parent_id
WHERE user_id IS NULL AND parent_id IS NOT NULL;

-- user_id is canonical. Repair any pre-existing disagreement before enforcing
-- the invariant so legacy parent_id callers cannot create two identities.
UPDATE public.paperwork_assignment_recipients
SET parent_id = user_id
WHERE user_id IS NOT NULL
  AND parent_id IS DISTINCT FROM user_id;

ALTER TABLE public.paperwork_assignment_recipients
    ALTER COLUMN user_id SET NOT NULL,
    DROP CONSTRAINT IF EXISTS paperwork_assignment_recipients_user_identity_check,
    ADD CONSTRAINT paperwork_assignment_recipients_user_identity_check CHECK (parent_id = user_id);

CREATE OR REPLACE FUNCTION public.normalize_paperwork_recipient_user()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    NEW.user_id := COALESCE(NEW.user_id, NEW.parent_id);
    IF NEW.user_id IS NULL THEN RAISE EXCEPTION 'A paperwork recipient is required'; END IF;
    NEW.parent_id := NEW.user_id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS normalize_paperwork_recipient_user_trigger ON public.paperwork_assignment_recipients;
CREATE TRIGGER normalize_paperwork_recipient_user_trigger
BEFORE INSERT OR UPDATE ON public.paperwork_assignment_recipients
FOR EACH ROW EXECUTE FUNCTION public.normalize_paperwork_recipient_user();

-- 2. Update can_access_school_private_file to support canonical user_id alongside parent_id
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
    ELSIF category = 'document_submissions' THEN
        record_uuid := parts[4]::UUID;
        RETURN public.can_submit_onboarding_requirement(record_uuid, user_uuid)
            OR public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director'])
            OR EXISTS (
                SELECT 1
                FROM public.onboarding_template_requirements req
                JOIN public.onboarding_templates t ON t.id = req.template_id
                JOIN public.onboarding_requirement_instances inst ON inst.template_requirement_id = req.id
                WHERE req.id = record_uuid
                  AND t.school_id = school_uuid
                  AND inst.assignment_id IS NOT NULL
                  AND public.can_view_assignment(inst.assignment_id, user_uuid)
            );
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

-- 3. Repair can_write_school_private_file by joining onboarding_templates for school_id
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
    ELSIF category = 'document_submissions' THEN
        IF array_length(parts, 1) < 5 THEN RETURN FALSE; END IF;
        record_uuid := parts[4]::UUID;
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director'])
            OR public.can_submit_onboarding_requirement(record_uuid, user_uuid)
            OR EXISTS (
                SELECT 1
                FROM public.onboarding_template_requirements req
                JOIN public.onboarding_templates t ON t.id = req.template_id
                JOIN public.onboarding_requirement_instances inst ON inst.template_requirement_id = req.id
                WHERE req.id = record_uuid
                  AND t.school_id = school_uuid
                  AND inst.assignment_id IS NOT NULL
                  AND public.can_submit_assignment(inst.assignment_id, user_uuid)
            );
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

-- A reviewer may act only on the latest pending attempt while the request is
-- active. This prevents stale screens or crafted RPC calls from overwriting a
-- newer decision and from reopening an archived request.
CREATE OR REPLACE FUNCTION public.review_paperwork_submission_v2(
    input_submission_id UUID,
    input_decision TEXT,
    input_message TEXT DEFAULT NULL
)
RETURNS SETOF public.paperwork_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    saved public.paperwork_submissions%ROWTYPE;
    selected_submission public.paperwork_submissions%ROWTYPE;
    request public.paperwork_assignments%ROWTYPE;
    latest_submission_id UUID;
BEGIN
    SELECT * INTO selected_submission
    FROM public.paperwork_submissions
    WHERE id = input_submission_id
    FOR UPDATE;

    SELECT * INTO request
    FROM public.paperwork_assignments
    WHERE id = selected_submission.assignment_id
    FOR UPDATE;

    IF selected_submission.id IS NULL
       OR request.id IS NULL
       OR request.status NOT IN ('published', 'closed')
       OR selected_submission.status NOT IN ('submitted', 'resubmitted')
       OR NOT public.can_manage_paperwork_assignment(request.id, actor)
       OR selected_submission.submitted_by = actor THEN
        RAISE EXCEPTION 'You cannot review this paperwork submission';
    END IF;

    SELECT submission.id INTO latest_submission_id
    FROM public.paperwork_submissions submission
    WHERE submission.assignment_id = selected_submission.assignment_id
      AND submission.submitted_by = selected_submission.submitted_by
    ORDER BY submission.attempt_number DESC, submission.submitted_at DESC NULLS LAST, submission.id DESC
    LIMIT 1;

    IF latest_submission_id IS DISTINCT FROM selected_submission.id THEN
        RAISE EXCEPTION 'Only the latest paperwork submission can be reviewed';
    END IF;
    IF input_decision NOT IN ('accepted', 'changes_requested') THEN
        RAISE EXCEPTION 'Paperwork review decision is invalid';
    END IF;
    IF input_decision = 'changes_requested'
       AND NULLIF(btrim(COALESCE(input_message, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Explain the requested changes';
    END IF;

    UPDATE public.paperwork_submissions
    SET status = input_decision,
        reviewer_message = NULLIF(btrim(COALESCE(input_message, '')), ''),
        reviewed_by = actor,
        reviewed_at = NOW()
    WHERE id = selected_submission.id
    RETURNING * INTO saved;

    UPDATE public.paperwork_assignment_recipients
    SET completion_status = input_decision,
        completed_at = CASE WHEN input_decision = 'accepted' THEN NOW() ELSE NULL END
    WHERE assignment_id = saved.assignment_id
      AND user_id = saved.submitted_by;

    RETURN QUERY SELECT * FROM public.paperwork_submissions WHERE id = saved.id;
END;
$$;

-- 4. Ensure recipient SELECT RLS accommodates both user_id and parent_id
DROP POLICY IF EXISTS "Users view paperwork recipients" ON public.paperwork_assignment_recipients;
DROP POLICY IF EXISTS "Users can view paperwork recipients" ON public.paperwork_assignment_recipients;
CREATE POLICY "Users view paperwork recipients" ON public.paperwork_assignment_recipients FOR SELECT
USING (
    user_id = auth.uid()
    OR parent_id = auth.uid()
    OR public.can_manage_paperwork_assignment(assignment_id, auth.uid())
);

-- 5. Bump schema version to 20260915140000
CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT 20260915140000::BIGINT;
$$;
