-- School-level child access, verified guardian connections, structured care,
-- transactional notifications, and director-managed group chat.

ALTER TABLE public.children
    DROP CONSTRAINT IF EXISTS children_birthdate_required;
ALTER TABLE public.children
    ADD CONSTRAINT children_birthdate_required CHECK (birthdate IS NOT NULL) NOT VALID;

ALTER TABLE public.child_guardians
    ADD COLUMN IF NOT EXISTS verification_status TEXT NOT NULL DEFAULT 'verified',
    ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS ended_at TIMESTAMPTZ;
ALTER TABLE public.child_guardians
    DROP CONSTRAINT IF EXISTS child_guardians_verification_status_check;
ALTER TABLE public.child_guardians
    ADD CONSTRAINT child_guardians_verification_status_check
    CHECK (verification_status IN ('pending', 'verified', 'revoked'));
UPDATE public.child_guardians
SET verified_at = COALESCE(verified_at, created_at)
WHERE verification_status = 'verified';

ALTER TABLE public.role_invites
    ADD COLUMN IF NOT EXISTS child_id UUID REFERENCES public.children(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS guardian_relationship TEXT;

ALTER TABLE public.onboarding_template_requirements
    ADD COLUMN IF NOT EXISTS blocks_access BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS child_record_binding TEXT NOT NULL DEFAULT 'none';
ALTER TABLE public.onboarding_template_requirements
    DROP CONSTRAINT IF EXISTS onboarding_template_requirements_child_record_binding_check;
ALTER TABLE public.onboarding_template_requirements
    ADD CONSTRAINT onboarding_template_requirements_child_record_binding_check
    CHECK (child_record_binding IN (
        'none', 'child_document', 'immunization_record', 'medical_clearance',
        'medication_authorization', 'emergency_information', 'consent'
    ));
ALTER TABLE public.onboarding_template_requirements
    DROP CONSTRAINT IF EXISTS onboarding_template_requirements_binding_scope_check;
ALTER TABLE public.onboarding_template_requirements
    ADD CONSTRAINT onboarding_template_requirements_binding_scope_check
    CHECK (child_record_binding = 'none' OR subject_scope = 'child');

CREATE OR REPLACE FUNCTION public.enforce_onboarding_requirement_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE source_requirement public.onboarding_template_requirements%ROWTYPE;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT * INTO source_requirement
        FROM public.onboarding_template_requirements existing
        WHERE existing.requirement_key = NEW.requirement_key
          AND existing.template_id <> NEW.template_id
        ORDER BY existing.created_at DESC LIMIT 1;
        IF FOUND THEN
            NEW.blocks_access := source_requirement.blocks_access;
            NEW.child_record_binding := source_requirement.child_record_binding;
        END IF;
    END IF;
    IF NEW.position = 0 THEN NEW.blocks_access := TRUE; END IF;
    IF NEW.subject_scope <> 'child' THEN NEW.child_record_binding := 'none'; END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS enforce_onboarding_requirement_rules_trigger ON public.onboarding_template_requirements;
CREATE TRIGGER enforce_onboarding_requirement_rules_trigger
    BEFORE INSERT OR UPDATE ON public.onboarding_template_requirements
    FOR EACH ROW EXECUTE FUNCTION public.enforce_onboarding_requirement_rules();

ALTER TABLE public.assignment_submissions
    ADD COLUMN IF NOT EXISTS structured_payload JSONB NOT NULL DEFAULT '{}'::JSONB;

ALTER TABLE public.child_documents
    ADD COLUMN IF NOT EXISTS source_assignment_submission_id UUID REFERENCES public.assignment_submissions(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS source_attachment_id UUID REFERENCES public.assignment_submission_attachments(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS expires_on DATE;
CREATE UNIQUE INDEX IF NOT EXISTS idx_child_documents_source_submission
    ON public.child_documents(source_assignment_submission_id)
    WHERE source_assignment_submission_id IS NOT NULL;

ALTER TABLE public.medication_instructions
    ADD COLUMN IF NOT EXISTS source_assignment_submission_id UUID REFERENCES public.assignment_submissions(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ;
CREATE UNIQUE INDEX IF NOT EXISTS idx_medication_instructions_source_submission
    ON public.medication_instructions(source_assignment_submission_id)
    WHERE source_assignment_submission_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.child_connection_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    requested_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    legal_first_name TEXT NOT NULL CHECK (btrim(legal_first_name) <> ''),
    legal_last_name TEXT NOT NULL CHECK (btrim(legal_last_name) <> ''),
    birthdate DATE NOT NULL CHECK (birthdate <= CURRENT_DATE),
    relationship TEXT NOT NULL CHECK (btrim(relationship) <> ''),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    matched_child_id UUID REFERENCES public.children(id) ON DELETE RESTRICT,
    reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    review_note TEXT,
    idempotency_key TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (requested_by, idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_child_connection_requests_school_status
    ON public.child_connection_requests(school_id, status, created_at);

CREATE TABLE IF NOT EXISTS public.child_profile_change_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
    requested_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    proposed_changes JSONB NOT NULL CHECK (jsonb_typeof(proposed_changes) = 'object'),
    reason TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'withdrawn')),
    reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    review_note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.attendance_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
    attendance_date DATE NOT NULL DEFAULT CURRENT_DATE,
    state TEXT NOT NULL DEFAULT 'present' CHECK (state IN ('expected', 'present', 'checked_out', 'absent', 'needs_attention')),
    checked_in_at TIMESTAMPTZ,
    checked_out_at TIMESTAMPTZ,
    checked_in_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    checked_out_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    notes TEXT,
    idempotency_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (checked_out_at IS NULL OR (checked_in_at IS NOT NULL AND checked_out_at >= checked_in_at))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_one_open_session
    ON public.attendance_sessions(child_id) WHERE checked_in_at IS NOT NULL AND checked_out_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_idempotency
    ON public.attendance_sessions(school_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_attendance_school_date
    ON public.attendance_sessions(school_id, attendance_date, state);

CREATE TABLE IF NOT EXISTS public.attendance_corrections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attendance_session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE RESTRICT,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    corrected_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    reason TEXT NOT NULL CHECK (btrim(reason) <> ''),
    before_values JSONB NOT NULL,
    after_values JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.child_care_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN (
        'meal', 'bottle', 'nap', 'potty', 'diaper', 'medication',
        'health_check', 'activity', 'note', 'photo'
    )),
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    details JSONB NOT NULL DEFAULT '{}'::JSONB CHECK (jsonb_typeof(details) = 'object'),
    visibility TEXT NOT NULL DEFAULT 'parent' CHECK (visibility IN ('parent', 'staff_only')),
    recorded_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    source_medication_task_id UUID REFERENCES public.medication_tasks(id) ON DELETE RESTRICT,
    idempotency_key TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (recorded_by, idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_child_care_events_child_occurred
    ON public.child_care_events(child_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS public.family_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
    requested_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    request_type TEXT NOT NULL CHECK (request_type IN ('absence', 'pickup_change', 'medication', 'general')),
    details JSONB NOT NULL DEFAULT '{}'::JSONB CHECK (jsonb_typeof(details) = 'object'),
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'acknowledged', 'completed', 'cancelled')),
    handled_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    handled_at TIMESTAMPTZ,
    idempotency_key TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (requested_by, idempotency_key)
);

ALTER TABLE public.notifications
    ADD COLUMN IF NOT EXISTS priority TEXT NOT NULL DEFAULT 'routine',
    ADD COLUMN IF NOT EXISTS route JSONB NOT NULL DEFAULT '{}'::JSONB;
ALTER TABLE public.notifications
    DROP CONSTRAINT IF EXISTS notifications_priority_check;
ALTER TABLE public.notifications
    ADD CONSTRAINT notifications_priority_check CHECK (priority IN ('routine', 'important', 'urgent'));

ALTER TABLE public.notification_recipients
    ADD COLUMN IF NOT EXISTS delivery_state TEXT NOT NULL DEFAULT 'queued',
    ADD COLUMN IF NOT EXISTS attempt_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_error TEXT,
    ADD COLUMN IF NOT EXISTS opened_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS dismissed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS expired_at TIMESTAMPTZ;
ALTER TABLE public.notification_recipients
    DROP CONSTRAINT IF EXISTS notification_recipients_delivery_state_check;
ALTER TABLE public.notification_recipients
    ADD CONSTRAINT notification_recipients_delivery_state_check
    CHECK (delivery_state IN ('queued', 'delivered', 'opened', 'acknowledged', 'failed', 'dismissed', 'expired'));

CREATE TABLE IF NOT EXISTS public.notification_outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id UUID NOT NULL REFERENCES public.notifications(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    available_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    locked_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (notification_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.workflow_audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL,
    source_type TEXT NOT NULL,
    source_id UUID NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.chat_rooms
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.chat_rooms DROP CONSTRAINT IF EXISTS chat_rooms_room_type_check;
UPDATE public.chat_rooms SET room_type = 'director_managed' WHERE room_type IN ('public', 'private');
ALTER TABLE public.chat_rooms
    ADD CONSTRAINT chat_rooms_room_type_check CHECK (room_type = 'director_managed');
ALTER TABLE public.chat_rooms ALTER COLUMN room_type SET DEFAULT 'director_managed';
UPDATE public.chat_rooms SET invite_hash = NULL;

CREATE TABLE IF NOT EXISTS public.chat_participant_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES public.chat_rooms(id) ON DELETE RESTRICT,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    action TEXT NOT NULL CHECK (action IN ('added', 'removed')),
    acted_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.school_workflow_mutations (
    actor_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    operation TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    result_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (actor_id, operation, idempotency_key)
);

ALTER TABLE public.child_connection_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.child_profile_change_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_corrections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.child_care_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.family_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participant_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_workflow_mutations ENABLE ROW LEVEL SECURITY;

-- Classroom records remain for migration compatibility, but application access
-- is now based only on active school membership.
DROP TRIGGER IF EXISTS assign_child_to_default_classroom_trigger ON public.children;
REVOKE ALL ON FUNCTION public.create_child_for_current_parent(UUID, TEXT, TEXT, DATE) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_child_for_current_parent(UUID, TEXT, TEXT, DATE) FROM authenticated;
REVOKE ALL ON FUNCTION public.join_chat_room(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.join_chat_room(TEXT) FROM authenticated;
REVOKE ALL ON FUNCTION public.create_medication_instruction(UUID, UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_medication_instruction(UUID, UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ) FROM authenticated;
REVOKE ALL ON FUNCTION public.acknowledge_medication_task(UUID, TEXT, TEXT, TIMESTAMPTZ) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.acknowledge_medication_task(UUID, TEXT, TEXT, TIMESTAMPTZ) FROM authenticated;
REVOKE ALL ON FUNCTION public.escalate_missed_medication_tasks() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.escalate_missed_medication_tasks() FROM authenticated;

CREATE OR REPLACE FUNCTION public.is_classroom_teacher_for_child(child_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.children child
        JOIN public.school_memberships membership
          ON membership.school_id = child.school_id
         AND membership.user_id = user_uuid
         AND membership.active = TRUE
         AND membership.role = 'teacher'
        WHERE child.id = child_uuid
          AND child.active = TRUE
    );
$$;

CREATE OR REPLACE FUNCTION public.can_staff_access_child(child_uuid UUID, user_uuid UUID, allowed_roles TEXT[])
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.is_hq_director(user_uuid)
        OR EXISTS (
            SELECT 1
            FROM public.children child
            JOIN public.school_memberships membership
              ON membership.school_id = child.school_id
             AND membership.user_id = user_uuid
             AND membership.active = TRUE
            WHERE child.id = child_uuid
              AND membership.role = ANY(allowed_roles)
              AND membership.role IN ('teacher', 'school_director')
        );
$$;

-- Care photos use a purpose-specific private path so guardians can see only
-- parent-visible media and only school staff can upload it.
CREATE OR REPLACE FUNCTION public.can_access_child_care_file(object_name TEXT, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parts TEXT[];
    school_uuid UUID;
    child_uuid UUID;
    file_visibility TEXT;
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL THEN RETURN FALSE; END IF;
    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 7 OR parts[1] <> 'schools' OR parts[3] <> 'care_events' THEN RETURN FALSE; END IF;
    school_uuid := parts[2]::UUID;
    child_uuid := parts[4]::UUID;
    file_visibility := parts[5];
    IF file_visibility NOT IN ('parent', 'staff_only') THEN RETURN FALSE; END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.children child
        WHERE child.id = child_uuid AND child.school_id = school_uuid AND child.active = TRUE
    ) THEN RETURN FALSE; END IF;
    RETURN public.can_staff_access_child(child_uuid, user_uuid, ARRAY['teacher', 'school_director'])
        OR (file_visibility = 'parent' AND public.is_child_guardian(child_uuid, user_uuid));
EXCEPTION WHEN invalid_text_representation THEN RETURN FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_write_child_care_file(object_name TEXT, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parts TEXT[];
    school_uuid UUID;
    child_uuid UUID;
    owner_uuid UUID;
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL THEN RETURN FALSE; END IF;
    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 7 OR parts[1] <> 'schools' OR parts[3] <> 'care_events'
       OR parts[5] NOT IN ('parent', 'staff_only') THEN RETURN FALSE; END IF;
    school_uuid := parts[2]::UUID;
    child_uuid := parts[4]::UUID;
    owner_uuid := parts[6]::UUID;
    RETURN owner_uuid = user_uuid
       AND EXISTS (
            SELECT 1 FROM public.children child
            WHERE child.id = child_uuid AND child.school_id = school_uuid AND child.active = TRUE
       )
       AND public.can_staff_access_child(child_uuid, user_uuid, ARRAY['teacher', 'school_director']);
EXCEPTION WHEN invalid_text_representation THEN RETURN FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.can_access_child_care_file(TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_write_child_care_file(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_access_child_care_file(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_write_child_care_file(TEXT, UUID) TO authenticated;

DROP POLICY IF EXISTS "School private files are restricted" ON storage.objects;
CREATE POLICY "School private files are restricted"
    ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'school_private_files'
        AND (
            public.can_access_school_private_file(name, auth.uid())
            OR public.can_access_child_care_file(name, auth.uid())
        )
    );
DROP POLICY IF EXISTS "School members can upload private files" ON storage.objects;
CREATE POLICY "School members can upload private files"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'school_private_files'
        AND (
            public.can_write_school_private_file(name, auth.uid())
            OR public.can_write_child_care_file(name, auth.uid())
        )
    );
DROP POLICY IF EXISTS "School members can update private files" ON storage.objects;
CREATE POLICY "School members can update private files"
    ON storage.objects FOR UPDATE TO authenticated
    USING (
        bucket_id = 'school_private_files'
        AND (
            public.can_write_school_private_file(name, auth.uid())
            OR public.can_write_child_care_file(name, auth.uid())
        )
    )
    WITH CHECK (
        bucket_id = 'school_private_files'
        AND (
            public.can_write_school_private_file(name, auth.uid())
            OR public.can_write_child_care_file(name, auth.uid())
        )
    );
DROP POLICY IF EXISTS "School private file deletes are owner scoped" ON storage.objects;
CREATE POLICY "School private file deletes are owner scoped"
    ON storage.objects FOR DELETE TO authenticated
    USING (
        bucket_id = 'school_private_files'
        AND (
            public.can_delete_school_private_file(name, auth.uid())
            OR public.can_write_child_care_file(name, auth.uid())
        )
    );

CREATE OR REPLACE FUNCTION public.is_child_guardian(child_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.child_guardians guardian
        JOIN public.children child ON child.id = guardian.child_id
        JOIN public.school_memberships membership
          ON membership.school_id = child.school_id
         AND membership.user_id = guardian.guardian_id
         AND membership.active = TRUE
         AND membership.role = 'parent'
        WHERE guardian.child_id = child_uuid
          AND guardian.guardian_id = user_uuid
          AND guardian.verification_status = 'verified'
          AND guardian.ended_at IS NULL
    );
$$;

CREATE OR REPLACE FUNCTION public.enqueue_workflow_notification(
    input_school_id UUID,
    input_title TEXT,
    input_body TEXT,
    input_category TEXT,
    input_source_type TEXT,
    input_source_id UUID,
    input_recipient_ids UUID[],
    input_dedupe_key TEXT,
    input_priority TEXT DEFAULT 'routine',
    input_route JSONB DEFAULT '{}'::JSONB,
    input_actor_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    notification_uuid UUID;
    valid_recipient_ids UUID[];
BEGIN
    IF input_priority NOT IN ('routine', 'important', 'urgent') THEN
        RAISE EXCEPTION 'Invalid notification priority';
    END IF;
    IF NULLIF(btrim(COALESCE(input_dedupe_key, '')), '') IS NULL THEN
        RAISE EXCEPTION 'A notification deduplication key is required';
    END IF;

    SELECT array_agg(DISTINCT recipients.user_id) INTO valid_recipient_ids
    FROM unnest(COALESCE(input_recipient_ids, ARRAY[]::UUID[])) recipients(user_id)
    WHERE recipients.user_id IS NOT NULL
      AND EXISTS (
          SELECT 1 FROM public.school_memberships membership
          WHERE membership.school_id = input_school_id
            AND membership.user_id = recipients.user_id
            AND membership.active = TRUE
      );
    IF COALESCE(cardinality(valid_recipient_ids), 0) = 0 THEN RETURN NULL; END IF;

    INSERT INTO public.notifications (
        school_id, title, body, category, source_type, source_id,
        created_by, dedupe_key, priority, route
    ) VALUES (
        input_school_id, btrim(input_title), btrim(input_body), input_category,
        input_source_type, input_source_id, input_actor_id, input_dedupe_key,
        input_priority, COALESCE(input_route, '{}'::JSONB)
    )
    ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL
    DO UPDATE SET dedupe_key = EXCLUDED.dedupe_key
    RETURNING id INTO notification_uuid;

    INSERT INTO public.notification_recipients (notification_id, user_id, delivery_state)
    SELECT notification_uuid, recipients.user_id, 'queued'
    FROM unnest(valid_recipient_ids) recipients(user_id)
    ON CONFLICT (notification_id, user_id) DO NOTHING;

    INSERT INTO public.notification_outbox (notification_id, user_id, available_at)
    SELECT notification_uuid, recipients.user_id, availability.available_at
    FROM public.notification_recipients recipients
    CROSS JOIN LATERAL (
        SELECT public.notification_delivery_available_at(
            recipients.user_id, input_category, input_priority
        ) AS available_at
    ) availability
    WHERE recipients.notification_id = notification_uuid
      AND availability.available_at IS NOT NULL
    ON CONFLICT (notification_id, user_id) DO NOTHING;

    RETURN notification_uuid;
END;
$$;
REVOKE ALL ON FUNCTION public.enqueue_workflow_notification(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID[], TEXT, TEXT, JSONB, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enqueue_workflow_notification(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID[], TEXT, TEXT, JSONB, UUID) FROM authenticated;

CREATE OR REPLACE FUNCTION public.fetch_school_directory(input_school_id UUID)
RETURNS TABLE (
    user_id UUID,
    display_name TEXT,
    avatar_url TEXT,
    school_role TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL OR NOT (
        public.is_school_member(input_school_id, auth.uid())
        OR public.is_hq_director(auth.uid())
    ) THEN
        RAISE EXCEPTION 'School directory access denied';
    END IF;

    RETURN QUERY
    SELECT membership.user_id, profile.display_name, profile.avatar_url, membership.role
    FROM public.school_memberships membership
    JOIN public.profiles profile ON profile.id = membership.user_id
    WHERE membership.school_id = input_school_id
      AND membership.active = TRUE
      AND membership.role IN ('parent', 'teacher', 'school_director')
    ORDER BY
        CASE membership.role WHEN 'school_director' THEN 0 WHEN 'teacher' THEN 1 ELSE 2 END,
        lower(profile.display_name), membership.user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_child_connection_request(
    input_school_id UUID,
    input_legal_first_name TEXT,
    input_legal_last_name TEXT,
    input_birthdate DATE,
    input_relationship TEXT,
    input_idempotency_key TEXT
)
RETURNS SETOF public.child_connection_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    saved_request public.child_connection_requests%ROWTYPE;
    recipient_ids UUID[];
BEGIN
    IF actor IS NULL OR NOT EXISTS (
        SELECT 1
        FROM public.school_memberships membership
        WHERE membership.school_id = input_school_id
          AND membership.user_id = actor
          AND membership.active = TRUE
          AND membership.role = 'parent'
    ) THEN
        RAISE EXCEPTION 'Only active parents can request a child connection';
    END IF;
    IF input_birthdate IS NULL OR input_birthdate > CURRENT_DATE THEN
        RAISE EXCEPTION 'A valid birthdate is required';
    END IF;
    IF NULLIF(btrim(input_legal_first_name), '') IS NULL
       OR NULLIF(btrim(input_legal_last_name), '') IS NULL
       OR NULLIF(btrim(input_relationship), '') IS NULL
       OR NULLIF(btrim(input_idempotency_key), '') IS NULL THEN
        RAISE EXCEPTION 'Legal name, relationship, and idempotency key are required';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(actor::TEXT || ':child-connection:' || btrim(input_idempotency_key), 0));
    SELECT * INTO saved_request
    FROM public.child_connection_requests
    WHERE requested_by = actor AND idempotency_key = btrim(input_idempotency_key);

    IF saved_request.id IS NULL THEN
        INSERT INTO public.child_connection_requests (
            school_id, requested_by, legal_first_name, legal_last_name,
            birthdate, relationship, idempotency_key
        ) VALUES (
            input_school_id, actor, btrim(input_legal_first_name), btrim(input_legal_last_name),
            input_birthdate, btrim(input_relationship), btrim(input_idempotency_key)
        ) RETURNING * INTO saved_request;

        SELECT array_agg(membership.user_id) INTO recipient_ids
        FROM public.school_memberships membership
        WHERE membership.school_id = input_school_id
          AND membership.active = TRUE
          AND membership.role = 'school_director';

        PERFORM public.enqueue_workflow_notification(
            input_school_id,
            'Child connection request',
            btrim(input_legal_first_name) || ' ' || btrim(input_legal_last_name) || ' needs review.',
            'child_connection_request', 'child_connection_request', saved_request.id,
            recipient_ids, 'child-connection:requested:' || saved_request.id::TEXT,
            'important', jsonb_build_object('type', 'child_connection_request', 'id', saved_request.id), actor
        );
        INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
        VALUES (input_school_id, actor, 'requested', 'child_connection_request', saved_request.id);
    END IF;

    RETURN QUERY SELECT * FROM public.child_connection_requests WHERE id = saved_request.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_child_connection_request(
    input_request_id UUID,
    input_decision TEXT,
    input_matched_child_id UUID DEFAULT NULL,
    input_review_note TEXT DEFAULT NULL,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.child_connection_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    request_record public.child_connection_requests%ROWTYPE;
    child_uuid UUID;
BEGIN
    SELECT * INTO request_record
    FROM public.child_connection_requests
    WHERE id = input_request_id
    FOR UPDATE;
    IF NOT FOUND OR NOT (
        public.has_school_role(request_record.school_id, actor, ARRAY['school_director'])
        OR public.is_hq_director(actor)
    ) THEN
        RAISE EXCEPTION 'Only a director can review this request';
    END IF;
    IF input_decision NOT IN ('approved', 'rejected') THEN
        RAISE EXCEPTION 'Decision must be approved or rejected';
    END IF;
    IF request_record.status <> 'pending' THEN
        RETURN QUERY SELECT * FROM public.child_connection_requests WHERE id = request_record.id;
        RETURN;
    END IF;

    IF input_decision = 'approved' THEN
        IF input_matched_child_id IS NOT NULL THEN
            SELECT child.id INTO child_uuid
            FROM public.children child
            WHERE child.id = input_matched_child_id
              AND child.school_id = request_record.school_id
              AND child.active = TRUE;
            IF child_uuid IS NULL THEN RAISE EXCEPTION 'The selected child is not active at this school'; END IF;
        ELSE
            INSERT INTO public.children (school_id, first_name, last_name, birthdate, active)
            VALUES (
                request_record.school_id, request_record.legal_first_name,
                request_record.legal_last_name, request_record.birthdate, TRUE
            ) RETURNING id INTO child_uuid;
        END IF;

        INSERT INTO public.child_guardians (
            child_id, guardian_id, relationship, verification_status, verified_by, verified_at, ended_at
        ) VALUES (
            child_uuid, request_record.requested_by, request_record.relationship,
            'verified', actor, NOW(), NULL
        )
        ON CONFLICT (child_id, guardian_id) DO UPDATE
        SET relationship = EXCLUDED.relationship,
            verification_status = 'verified', verified_by = actor,
            verified_at = NOW(), ended_at = NULL;

        PERFORM public.instantiate_child_onboarding(child_uuid, request_record.requested_by);
    END IF;

    UPDATE public.child_connection_requests
    SET status = input_decision,
        matched_child_id = CASE WHEN input_decision = 'approved' THEN child_uuid ELSE NULL END,
        reviewed_by = actor,
        reviewed_at = NOW(),
        review_note = NULLIF(btrim(COALESCE(input_review_note, '')), ''),
        updated_at = NOW()
    WHERE id = request_record.id
    RETURNING * INTO request_record;

    PERFORM public.enqueue_workflow_notification(
        request_record.school_id,
        CASE WHEN input_decision = 'approved' THEN 'Child connection approved' ELSE 'Child connection update' END,
        CASE WHEN input_decision = 'approved'
            THEN request_record.legal_first_name || ' is now connected to your account.'
            ELSE 'Your child connection request was not approved.' END,
        'child_connection_decision', 'child_connection_request', request_record.id,
        ARRAY[request_record.requested_by],
        'child-connection:' || input_decision || ':' || request_record.id::TEXT,
        'important', jsonb_build_object('type', 'child_connection_request', 'id', request_record.id), actor
    );
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id, metadata)
    VALUES (
        request_record.school_id, actor, input_decision, 'child_connection_request', request_record.id,
        jsonb_build_object('child_id', child_uuid, 'note', input_review_note)
    );

    RETURN QUERY SELECT * FROM public.child_connection_requests WHERE id = request_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_child_guardian(input_child_id UUID, input_guardian_id UUID, input_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE actor UUID := auth.uid(); child_record public.children%ROWTYPE;
BEGIN
    SELECT * INTO child_record FROM public.children WHERE id = input_child_id;
    IF NOT FOUND OR NOT public.has_school_role(child_record.school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can revoke a guardian link';
    END IF;
    UPDATE public.child_guardians
    SET verification_status = 'revoked', ended_at = NOW()
    WHERE child_id = input_child_id AND guardian_id = input_guardian_id
      AND verification_status = 'verified' AND ended_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active guardian link not found'; END IF;
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id, metadata)
    VALUES (
        child_record.school_id, actor, 'guardian_revoked', 'child', input_child_id,
        jsonb_build_object('guardian_id', input_guardian_id, 'reason', input_reason)
    );
    PERFORM public.enqueue_workflow_notification(
        child_record.school_id, 'Child access removed',
        'A school director removed your access to ' || child_record.first_name || '''s profile.',
        'child_connection_removed', 'child', input_child_id, ARRAY[input_guardian_id],
        'guardian:revoked:' || input_child_id::TEXT || ':' || input_guardian_id::TEXT || ':' || extract(epoch from NOW())::BIGINT,
        'important', jsonb_build_object('type', 'child', 'id', input_child_id), actor
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_onboarding_access(input_membership_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    instance_record public.onboarding_instances%ROWTYPE;
    next_state TEXT;
BEGIN
    SELECT * INTO instance_record
    FROM public.onboarding_instances
    WHERE membership_id = input_membership_id
    ORDER BY started_at DESC
    LIMIT 1;
    IF NOT FOUND THEN
        RETURN (SELECT access_state FROM public.school_memberships WHERE id = input_membership_id);
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.onboarding_requirement_instances requirement_instance
        JOIN public.onboarding_template_requirements requirement
          ON requirement.id = requirement_instance.template_requirement_id
        WHERE requirement_instance.onboarding_instance_id = instance_record.id
          AND requirement.blocks_access = TRUE
          AND requirement_instance.status NOT IN ('approved', 'waived')
    ) THEN
        next_state := 'onboarding';
    ELSE
        next_state := 'full';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.onboarding_requirement_instances
        WHERE onboarding_instance_id = instance_record.id
          AND status NOT IN ('approved', 'waived')
    ) THEN
        UPDATE public.onboarding_instances
        SET status = 'complete', completed_at = COALESCE(completed_at, NOW())
        WHERE id = instance_record.id;
    END IF;

    UPDATE public.school_memberships SET access_state = next_state WHERE id = input_membership_id;
    RETURN next_state;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_child_guardian_invite(
    input_child_id UUID,
    input_email TEXT,
    input_display_name TEXT DEFAULT NULL,
    input_relationship TEXT DEFAULT 'Parent'
)
RETURNS TABLE (invite_id UUID, invite_token TEXT, expires_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    child_record public.children%ROWTYPE;
    raw_token TEXT := encode(extensions.gen_random_bytes(32), 'hex');
    saved_invite public.role_invites%ROWTYPE;
BEGIN
    SELECT * INTO child_record FROM public.children WHERE id = input_child_id AND active = TRUE;
    IF NOT FOUND OR NOT public.has_school_role(child_record.school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only the school director can invite a guardian';
    END IF;
    IF NULLIF(btrim(COALESCE(input_email, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Guardian email is required';
    END IF;

    INSERT INTO public.role_invites (
        school_id, email, display_name, role, token_hash, status, invited_by,
        expires_at, child_id, guardian_relationship
    ) VALUES (
        child_record.school_id, lower(btrim(input_email)), NULLIF(btrim(COALESCE(input_display_name, '')), ''),
        'parent', encode(extensions.digest(raw_token, 'sha256'), 'hex'), 'pending', actor,
        NOW() + INTERVAL '14 days', child_record.id, COALESCE(NULLIF(btrim(input_relationship), ''), 'Parent')
    ) RETURNING * INTO saved_invite;

    invite_id := saved_invite.id;
    invite_token := raw_token;
    expires_at := saved_invite.expires_at;
    RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_role_invite(invite_token TEXT)
RETURNS SETOF public.school_memberships
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    invite_record public.role_invites%ROWTYPE;
    joining_user UUID := auth.uid();
    joining_email TEXT := lower(COALESCE(auth.jwt()->>'email', ''));
BEGIN
    IF joining_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF joining_email = '' THEN RAISE EXCEPTION 'Your account email could not be verified'; END IF;

    SELECT * INTO invite_record
    FROM public.role_invites
    WHERE token_hash = encode(extensions.digest(NULLIF(btrim(invite_token), ''), 'sha256'), 'hex')
      AND status = 'pending'
      AND (expires_at IS NULL OR expires_at > NOW())
    LIMIT 1 FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Invalid or expired invite link'; END IF;
    IF lower(invite_record.email) <> joining_email THEN
        RAISE EXCEPTION 'This invite belongs to a different email account';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.onboarding_templates template
        WHERE template.school_id = invite_record.school_id
          AND template.target_role = invite_record.role
          AND template.status = 'published'
    ) THEN
        RAISE EXCEPTION 'The onboarding template for this invitation is not published yet';
    END IF;

    INSERT INTO public.school_memberships (school_id, user_id, role, active, joined_at)
    VALUES (invite_record.school_id, joining_user, invite_record.role, TRUE, NOW())
    ON CONFLICT (school_id, user_id)
    DO UPDATE SET active = TRUE, role = EXCLUDED.role, joined_at = NOW();

    IF invite_record.child_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.children child
            WHERE child.id = invite_record.child_id AND child.school_id = invite_record.school_id AND child.active = TRUE
        ) THEN
            RAISE EXCEPTION 'The invited child is no longer active';
        END IF;
        INSERT INTO public.child_guardians (
            child_id, guardian_id, relationship, verification_status,
            verified_by, verified_at, ended_at
        ) VALUES (
            invite_record.child_id, joining_user,
            COALESCE(invite_record.guardian_relationship, 'Parent'),
            'verified', invite_record.invited_by, NOW(), NULL
        )
        ON CONFLICT (child_id, guardian_id) DO UPDATE
        SET relationship = EXCLUDED.relationship,
            verification_status = 'verified', verified_by = EXCLUDED.verified_by,
            verified_at = NOW(), ended_at = NULL;
        PERFORM public.instantiate_child_onboarding(invite_record.child_id, joining_user);
    END IF;

    UPDATE public.role_invites
    SET status = 'accepted', accepted_by = joining_user, accepted_at = NOW(), token = NULL
    WHERE id = invite_record.id;

    IF invite_record.display_name IS NOT NULL THEN
        INSERT INTO public.profiles (id, display_name)
        VALUES (joining_user, invite_record.display_name)
        ON CONFLICT (id) DO UPDATE
        SET display_name = COALESCE(NULLIF(public.profiles.display_name, ''), EXCLUDED.display_name),
            updated_at = NOW();
    END IF;

    RETURN QUERY SELECT * FROM public.school_memberships
    WHERE school_id = invite_record.school_id AND user_id = joining_user;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_assignment_with_payload(
    input_assignment_id UUID,
    input_structured_payload JSONB DEFAULT '{}'::JSONB,
    input_feedback_text TEXT DEFAULT NULL,
    input_attachments JSONB DEFAULT '[]'::JSONB,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    saved_submission public.assignment_submissions%ROWTYPE;
BEGIN
    IF jsonb_typeof(COALESCE(input_structured_payload, '{}'::JSONB)) <> 'object' THEN
        RAISE EXCEPTION 'Structured answers must be a JSON object';
    END IF;
    SELECT * INTO saved_submission
    FROM public.submit_assignment_v2(
        input_assignment_id, input_feedback_text, input_attachments, input_idempotency_key
    );
    UPDATE public.assignment_submissions
    SET structured_payload = CASE
        WHEN structured_payload = '{}'::JSONB THEN COALESCE(input_structured_payload, '{}'::JSONB)
        ELSE structured_payload
    END
    WHERE id = saved_submission.id
    RETURNING * INTO saved_submission;
    RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = saved_submission.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fetch_assignment_child_binding(input_assignment_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE((
        SELECT requirement.child_record_binding
        FROM public.onboarding_requirement_instances instance
        JOIN public.onboarding_template_requirements requirement
          ON requirement.id = instance.template_requirement_id
        WHERE instance.assignment_id = input_assignment_id
          AND (
              public.is_assignment_recipient(input_assignment_id, auth.uid())
              OR public.can_review_assignment(input_assignment_id, auth.uid())
          )
        LIMIT 1
    ), 'none');
$$;

CREATE OR REPLACE FUNCTION public.save_onboarding_template_requirement_v2(
    input_template_id UUID,
    input_requirement_id UUID DEFAULT NULL,
    input_title TEXT DEFAULT NULL,
    input_description TEXT DEFAULT NULL,
    input_subject_scope TEXT DEFAULT 'member',
    input_position INTEGER DEFAULT 0,
    input_attachments JSONB DEFAULT '[]'::JSONB,
    input_blocks_access BOOLEAN DEFAULT TRUE,
    input_child_record_binding TEXT DEFAULT 'none'
)
RETURNS SETOF public.onboarding_template_requirements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    template_record public.onboarding_templates%ROWTYPE;
    saved_requirement public.onboarding_template_requirements%ROWTYPE;
BEGIN
    SELECT * INTO template_record FROM public.onboarding_templates WHERE id = input_template_id;
    IF NOT FOUND OR template_record.status <> 'draft'
       OR NOT public.is_onboarding_template_manager(template_record.school_id, template_record.target_role, actor) THEN
        RAISE EXCEPTION 'Requirements can only be changed by a manager in a draft template';
    END IF;
    IF NULLIF(btrim(COALESCE(input_title, '')), '') IS NULL THEN RAISE EXCEPTION 'A requirement title is required'; END IF;
    IF input_subject_scope NOT IN ('member', 'child')
       OR (input_subject_scope = 'child' AND template_record.target_role <> 'parent') THEN
        RAISE EXCEPTION 'Child requirements are available only for parent templates';
    END IF;
    IF input_child_record_binding NOT IN (
        'none', 'child_document', 'immunization_record', 'medical_clearance',
        'medication_authorization', 'emergency_information', 'consent'
    ) OR (input_child_record_binding <> 'none' AND input_subject_scope <> 'child') THEN
        RAISE EXCEPTION 'The child record binding is invalid for this requirement';
    END IF;

    IF input_requirement_id IS NULL THEN
        INSERT INTO public.onboarding_template_requirements (
            template_id, position, title, description, subject_scope, blocks_access, child_record_binding
        ) VALUES (
            template_record.id, GREATEST(COALESCE(input_position, 0), 0), btrim(input_title),
            NULLIF(btrim(COALESCE(input_description, '')), ''), input_subject_scope,
            COALESCE(input_blocks_access, TRUE), input_child_record_binding
        ) RETURNING * INTO saved_requirement;
    ELSE
        UPDATE public.onboarding_template_requirements
        SET title = btrim(input_title), description = NULLIF(btrim(COALESCE(input_description, '')), ''),
            subject_scope = input_subject_scope, blocks_access = COALESCE(input_blocks_access, TRUE),
            child_record_binding = input_child_record_binding, updated_at = NOW()
        WHERE id = input_requirement_id AND template_id = template_record.id
        RETURNING * INTO saved_requirement;
        IF saved_requirement.id IS NULL THEN RAISE EXCEPTION 'Requirement not found in this draft'; END IF;
    END IF;

    DELETE FROM public.onboarding_template_attachments WHERE requirement_id = saved_requirement.id;
    INSERT INTO public.onboarding_template_attachments (
        requirement_id, position, private_file_path, file_name, content_type
    )
    SELECT saved_requirement.id, attachment.ordinality::INTEGER - 1,
        attachment.value->>'private_file_path', attachment.value->>'file_name',
        NULLIF(attachment.value->>'content_type', '')
    FROM jsonb_array_elements(COALESCE(input_attachments, '[]'::JSONB))
      WITH ORDINALITY AS attachment(value, ordinality)
    WHERE NULLIF(attachment.value->>'private_file_path', '') IS NOT NULL
      AND NULLIF(attachment.value->>'file_name', '') IS NOT NULL;
    RETURN QUERY SELECT * FROM public.onboarding_template_requirements WHERE id = saved_requirement.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.bind_approved_child_submission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    binding TEXT;
    child_uuid UUID;
    assignment_record public.assignments%ROWTYPE;
    attachment_record public.assignment_submission_attachments%ROWTYPE;
    instruction_uuid UUID;
    scheduled_timestamp TIMESTAMPTZ;
BEGIN
    IF NEW.status <> 'accepted' OR OLD.status = 'accepted' THEN RETURN NEW; END IF;

    SELECT requirement.child_record_binding, requirement_instance.child_id
    INTO binding, child_uuid
    FROM public.onboarding_requirement_instances requirement_instance
    JOIN public.onboarding_template_requirements requirement
      ON requirement.id = requirement_instance.template_requirement_id
    WHERE requirement_instance.assignment_id = NEW.assignment_id
      AND requirement_instance.child_id IS NOT NULL
    LIMIT 1;
    IF binding IS NULL OR binding = 'none' THEN RETURN NEW; END IF;

    SELECT * INTO assignment_record FROM public.assignments WHERE id = NEW.assignment_id;
    SELECT * INTO attachment_record
    FROM public.assignment_submission_attachments
    WHERE submission_id = NEW.id
    ORDER BY created_at, id LIMIT 1;
    IF attachment_record.id IS NULL THEN
        RAISE EXCEPTION 'An approved child record submission must include evidence';
    END IF;

    IF binding = 'medication_authorization' THEN
        IF NULLIF(btrim(NEW.structured_payload->>'medication_name'), '') IS NULL
           OR NULLIF(btrim(NEW.structured_payload->>'scheduled_at'), '') IS NULL THEN
            RAISE EXCEPTION 'Medication name and schedule are required';
        END IF;
        scheduled_timestamp := (NEW.structured_payload->>'scheduled_at')::TIMESTAMPTZ;
        INSERT INTO public.medication_instructions (
            school_id, child_id, title, dosage, instructions, scheduled_at,
            repeat_rule, starts_on, ends_on, created_by, active,
            source_assignment_submission_id, verified_by, verified_at
        ) VALUES (
            NEW.school_id, child_uuid, btrim(NEW.structured_payload->>'medication_name'),
            NULLIF(btrim(NEW.structured_payload->>'dosage'), ''),
            NULLIF(btrim(NEW.structured_payload->>'instructions'), ''), scheduled_timestamp,
            NULLIF(btrim(NEW.structured_payload->>'repeat_rule'), ''),
            NULLIF(NEW.structured_payload->>'starts_on', '')::DATE,
            NULLIF(NEW.structured_payload->>'ends_on', '')::DATE,
            NEW.submitted_by, TRUE, NEW.id, NEW.reviewed_by, NEW.reviewed_at
        )
        ON CONFLICT (source_assignment_submission_id) WHERE source_assignment_submission_id IS NOT NULL
        DO UPDATE SET active = TRUE, verified_by = EXCLUDED.verified_by, verified_at = EXCLUDED.verified_at
        RETURNING id INTO instruction_uuid;

        INSERT INTO public.medication_tasks (school_id, child_id, instruction_id, due_at, status)
        SELECT NEW.school_id, child_uuid, instruction_uuid, scheduled_timestamp, 'pending'
        WHERE NOT EXISTS (
            SELECT 1 FROM public.medication_tasks task
            WHERE task.instruction_id = instruction_uuid AND task.due_at = scheduled_timestamp
        );
    ELSE
        INSERT INTO public.child_documents (
            school_id, child_id, title, document_type, file_name, file_path,
            uploaded_by, verification_status, reviewed_by, reviewed_at,
            source_assignment_submission_id, source_attachment_id, expires_on
        ) VALUES (
            NEW.school_id, child_uuid, assignment_record.title, binding,
            attachment_record.file_name, attachment_record.private_file_path,
            NEW.submitted_by, 'verified', NEW.reviewed_by, NEW.reviewed_at,
            NEW.id, attachment_record.id, NULLIF(NEW.structured_payload->>'expires_on', '')::DATE
        )
        ON CONFLICT (source_assignment_submission_id) WHERE source_assignment_submission_id IS NOT NULL
        DO UPDATE SET verification_status = 'verified', reviewed_by = EXCLUDED.reviewed_by,
            reviewed_at = EXCLUDED.reviewed_at, expires_on = EXCLUDED.expires_on;
    END IF;

    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id, metadata
    ) VALUES (
        NEW.school_id, NEW.reviewed_by, 'bound_record_created', 'assignment_submission', NEW.id,
        jsonb_build_object('binding', binding, 'child_id', child_uuid)
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS bind_approved_child_submission_trigger ON public.assignment_submissions;
CREATE TRIGGER bind_approved_child_submission_trigger
    AFTER UPDATE OF status ON public.assignment_submissions
    FOR EACH ROW EXECUTE FUNCTION public.bind_approved_child_submission();

CREATE OR REPLACE FUNCTION public.record_school_attendance(
    input_child_id UUID,
    input_action TEXT,
    input_occurred_at TIMESTAMPTZ DEFAULT NOW(),
    input_notes TEXT DEFAULT NULL,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.attendance_sessions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    child_record public.children%ROWTYPE;
    session_record public.attendance_sessions%ROWTYPE;
    guardian_ids UUID[];
    daily_summary TEXT;
BEGIN
    SELECT * INTO child_record FROM public.children WHERE id = input_child_id AND active = TRUE;
    IF NOT FOUND OR NOT (
        public.can_staff_access_child(input_child_id, actor, ARRAY['teacher', 'school_director'])
        OR public.is_hq_director(actor)
    ) THEN
        RAISE EXCEPTION 'You cannot record attendance for this child';
    END IF;
    IF input_action NOT IN ('check_in', 'check_out', 'expected', 'absent', 'needs_attention') THEN
        RAISE EXCEPTION 'Invalid attendance action';
    END IF;
    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN
        RAISE EXCEPTION 'An idempotency key is required';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(actor::TEXT || ':attendance:' || btrim(input_idempotency_key), 0));
    SELECT * INTO session_record
    FROM public.attendance_sessions
    WHERE school_id = child_record.school_id AND idempotency_key = btrim(input_idempotency_key);
    IF session_record.id IS NOT NULL THEN
        RETURN QUERY SELECT * FROM public.attendance_sessions WHERE id = session_record.id;
        RETURN;
    END IF;

    IF input_action = 'check_in' THEN
        IF EXISTS (
            SELECT 1 FROM public.attendance_sessions
            WHERE child_id = input_child_id AND checked_in_at IS NOT NULL AND checked_out_at IS NULL
        ) THEN RAISE EXCEPTION 'This child already has an open attendance session'; END IF;
        INSERT INTO public.attendance_sessions (
            school_id, child_id, attendance_date, state, checked_in_at,
            checked_in_by, notes, idempotency_key
        ) VALUES (
            child_record.school_id, input_child_id,
            (input_occurred_at AT TIME ZONE 'America/New_York')::DATE,
            'present', input_occurred_at, actor, NULLIF(btrim(COALESCE(input_notes, '')), ''),
            btrim(input_idempotency_key)
        ) RETURNING * INTO session_record;
    ELSIF input_action = 'check_out' THEN
        SELECT * INTO session_record
        FROM public.attendance_sessions
        WHERE child_id = input_child_id AND checked_in_at IS NOT NULL AND checked_out_at IS NULL
        ORDER BY checked_in_at DESC LIMIT 1 FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'No open attendance session exists'; END IF;
        IF input_occurred_at < session_record.checked_in_at THEN
            RAISE EXCEPTION 'Checkout cannot occur before check-in';
        END IF;
        UPDATE public.attendance_sessions
        SET state = 'checked_out', checked_out_at = input_occurred_at,
            checked_out_by = actor,
            notes = COALESCE(NULLIF(btrim(COALESCE(input_notes, '')), ''), notes),
            idempotency_key = btrim(input_idempotency_key), updated_at = NOW()
        WHERE id = session_record.id RETURNING * INTO session_record;
    ELSE
        INSERT INTO public.attendance_sessions (
            school_id, child_id, attendance_date, state, notes, idempotency_key
        ) VALUES (
            child_record.school_id, input_child_id,
            (input_occurred_at AT TIME ZONE 'America/New_York')::DATE,
            input_action, NULLIF(btrim(COALESCE(input_notes, '')), ''), btrim(input_idempotency_key)
        ) RETURNING * INTO session_record;
    END IF;

    SELECT array_agg(guardian.guardian_id) INTO guardian_ids
    FROM public.child_guardians guardian
    WHERE guardian.child_id = input_child_id
      AND guardian.verification_status = 'verified' AND guardian.ended_at IS NULL;

    IF input_action IN ('check_in', 'check_out') THEN
        PERFORM public.enqueue_workflow_notification(
            child_record.school_id,
            child_record.first_name || CASE WHEN input_action = 'check_in' THEN ' checked in' ELSE ' checked out' END,
            to_char(input_occurred_at AT TIME ZONE 'America/New_York', 'Mon FMDD at FMHH12:MI AM'),
            'attendance_' || input_action, 'attendance_session', session_record.id,
            guardian_ids, 'attendance:' || input_action || ':' || btrim(input_idempotency_key),
            'routine', jsonb_build_object('type', 'attendance_session', 'id', session_record.id, 'child_id', input_child_id), actor
        );
        IF input_action = 'check_out' THEN
            SELECT string_agg(summary.event_count::TEXT || ' ' || replace(summary.event_type, '_', ' '), ', ' ORDER BY summary.event_type)
            INTO daily_summary
            FROM (
                SELECT event.event_type, COUNT(*) AS event_count
                FROM public.child_care_events event
                WHERE event.child_id = input_child_id
                  AND event.visibility = 'parent'
                  AND (event.occurred_at AT TIME ZONE 'America/New_York')::DATE = session_record.attendance_date
                GROUP BY event.event_type
            ) summary;
            PERFORM public.enqueue_workflow_notification(
                child_record.school_id,
                child_record.first_name || '''s daily summary',
                COALESCE(daily_summary, 'No routine care updates were recorded today.'),
                'daily_care_summary', 'attendance_session', session_record.id,
                guardian_ids, 'daily-summary:' || session_record.id::TEXT,
                'routine', jsonb_build_object(
                    'type', 'child_feed', 'id', input_child_id, 'child_id', input_child_id,
                    'attendance_session_id', session_record.id, 'date', session_record.attendance_date
                ), actor
            );
        END IF;
    ELSIF input_action = 'needs_attention' THEN
        PERFORM public.enqueue_workflow_notification(
            child_record.school_id, 'Attendance needs attention',
            child_record.first_name || ' has an attendance record that needs review.',
            'attendance_exception', 'attendance_session', session_record.id,
            ARRAY(
                SELECT membership.user_id FROM public.school_memberships membership
                WHERE membership.school_id = child_record.school_id
                  AND membership.active = TRUE AND membership.role = 'school_director'
            ), 'attendance:exception:' || session_record.id::TEXT,
            'important', jsonb_build_object('type', 'attendance_session', 'id', session_record.id), actor
        );
    END IF;

    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
    VALUES (child_record.school_id, actor, input_action, 'attendance_session', session_record.id);
    RETURN QUERY SELECT * FROM public.attendance_sessions WHERE id = session_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.correct_attendance_session(
    input_session_id UUID,
    input_checked_in_at TIMESTAMPTZ,
    input_checked_out_at TIMESTAMPTZ,
    input_state TEXT,
    input_notes TEXT,
    input_reason TEXT
)
RETURNS SETOF public.attendance_sessions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    session_record public.attendance_sessions%ROWTYPE;
    before_record JSONB;
BEGIN
    SELECT * INTO session_record FROM public.attendance_sessions WHERE id = input_session_id FOR UPDATE;
    IF NOT FOUND OR NOT (
        public.has_school_role(session_record.school_id, actor, ARRAY['school_director'])
        OR public.is_hq_director(actor)
    ) THEN RAISE EXCEPTION 'Only a director can correct attendance'; END IF;
    IF NULLIF(btrim(COALESCE(input_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'A correction reason is required'; END IF;
    IF input_state NOT IN ('expected', 'present', 'checked_out', 'absent', 'needs_attention') THEN
        RAISE EXCEPTION 'Invalid attendance state';
    END IF;
    before_record := to_jsonb(session_record);
    UPDATE public.attendance_sessions
    SET checked_in_at = input_checked_in_at, checked_out_at = input_checked_out_at,
        state = input_state, notes = NULLIF(btrim(COALESCE(input_notes, '')), ''), updated_at = NOW()
    WHERE id = input_session_id RETURNING * INTO session_record;
    INSERT INTO public.attendance_corrections (
        attendance_session_id, school_id, corrected_by, reason, before_values, after_values
    ) VALUES (
        input_session_id, session_record.school_id, actor, btrim(input_reason),
        before_record, to_jsonb(session_record)
    );
    RETURN QUERY SELECT * FROM public.attendance_sessions WHERE id = input_session_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_child_care_event(
    input_child_id UUID,
    input_event_type TEXT,
    input_occurred_at TIMESTAMPTZ,
    input_details JSONB,
    input_visibility TEXT,
    input_medication_task_id UUID DEFAULT NULL,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.child_care_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    child_record public.children%ROWTYPE;
    saved_event public.child_care_events%ROWTYPE;
    guardian_ids UUID[];
BEGIN
    SELECT * INTO child_record FROM public.children WHERE id = input_child_id AND active = TRUE;
    IF NOT FOUND OR NOT public.can_staff_access_child(input_child_id, actor, ARRAY['teacher', 'school_director']) THEN
        RAISE EXCEPTION 'You cannot record care for this child';
    END IF;
    IF input_event_type NOT IN ('meal', 'bottle', 'nap', 'potty', 'diaper', 'medication', 'health_check', 'activity', 'note', 'photo') THEN
        RAISE EXCEPTION 'Invalid care event type';
    END IF;
    IF input_visibility NOT IN ('parent', 'staff_only') THEN RAISE EXCEPTION 'Invalid visibility'; END IF;
    IF jsonb_typeof(COALESCE(input_details, '{}'::JSONB)) <> 'object' THEN RAISE EXCEPTION 'Details must be an object'; END IF;
    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN RAISE EXCEPTION 'An idempotency key is required'; END IF;
    IF input_event_type = 'photo' AND (
        NULLIF(btrim(COALESCE(input_details->>'photo_path', '')), '') IS NULL
        OR input_details->>'photo_path' NOT LIKE (
            'schools/' || child_record.school_id::TEXT || '/care_events/' || input_child_id::TEXT
            || '/' || input_visibility || '/' || actor::TEXT || '/%'
        )
    ) THEN RAISE EXCEPTION 'Photo care events require a private photo uploaded by the recording staff member'; END IF;

    INSERT INTO public.child_care_events (
        school_id, child_id, event_type, occurred_at, details, visibility,
        recorded_by, source_medication_task_id, idempotency_key
    ) VALUES (
        child_record.school_id, input_child_id, input_event_type,
        COALESCE(input_occurred_at, NOW()), COALESCE(input_details, '{}'::JSONB),
        input_visibility, actor, input_medication_task_id, btrim(input_idempotency_key)
    )
    ON CONFLICT (recorded_by, idempotency_key) DO UPDATE SET idempotency_key = EXCLUDED.idempotency_key
    RETURNING * INTO saved_event;

    IF input_event_type = 'medication' THEN
        IF input_medication_task_id IS NULL OR NOT EXISTS (
            SELECT 1 FROM public.medication_tasks task
            JOIN public.medication_instructions instruction ON instruction.id = task.instruction_id
            WHERE task.id = input_medication_task_id
              AND task.child_id = input_child_id
              AND instruction.source_assignment_submission_id IS NOT NULL
        ) THEN RAISE EXCEPTION 'Medication care requires an approved authorization task'; END IF;
        UPDATE public.medication_tasks SET status = 'acknowledged' WHERE id = input_medication_task_id;
        INSERT INTO public.medication_acknowledgements (
            task_id, school_id, child_id, acknowledged_by, dosage_given, notes, given_at
        )
        SELECT input_medication_task_id, child_record.school_id, input_child_id, actor,
            NULLIF(input_details->>'dosage_given', ''), NULLIF(input_details->>'notes', ''), saved_event.occurred_at
        WHERE NOT EXISTS (
            SELECT 1 FROM public.medication_acknowledgements WHERE task_id = input_medication_task_id
        );
    END IF;

    IF input_visibility = 'parent' AND input_event_type IN ('medication', 'health_check') THEN
        SELECT array_agg(guardian.guardian_id) INTO guardian_ids
        FROM public.child_guardians guardian
        WHERE guardian.child_id = input_child_id
          AND guardian.verification_status = 'verified' AND guardian.ended_at IS NULL;
        PERFORM public.enqueue_workflow_notification(
            child_record.school_id,
            CASE WHEN input_event_type = 'medication' THEN 'Medication administered' ELSE 'Health update' END,
            child_record.first_name || ' has a new ' || replace(input_event_type, '_', ' ') || ' update.',
            'care_' || input_event_type, 'child_care_event', saved_event.id,
            guardian_ids, 'care:' || input_event_type || ':' || saved_event.id::TEXT,
            CASE WHEN input_event_type = 'health_check' THEN 'urgent' ELSE 'important' END,
            jsonb_build_object('type', 'child_care_event', 'id', saved_event.id, 'child_id', input_child_id), actor
        );
    END IF;
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
    VALUES (child_record.school_id, actor, 'recorded', 'child_care_event', saved_event.id);
    RETURN QUERY SELECT * FROM public.child_care_events WHERE id = saved_event.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_family_request(
    input_child_id UUID,
    input_request_type TEXT,
    input_details JSONB,
    input_idempotency_key TEXT
)
RETURNS SETOF public.family_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    child_record public.children%ROWTYPE;
    saved_request public.family_requests%ROWTYPE;
BEGIN
    SELECT * INTO child_record FROM public.children WHERE id = input_child_id AND active = TRUE;
    IF NOT FOUND OR NOT public.is_child_guardian(input_child_id, actor) THEN
        RAISE EXCEPTION 'Only a verified guardian can submit a family request';
    END IF;
    IF input_request_type NOT IN ('absence', 'pickup_change', 'medication', 'general') THEN RAISE EXCEPTION 'Invalid request type'; END IF;
    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN RAISE EXCEPTION 'An idempotency key is required'; END IF;

    INSERT INTO public.family_requests (
        school_id, child_id, requested_by, request_type, details, idempotency_key
    ) VALUES (
        child_record.school_id, input_child_id, actor, input_request_type,
        COALESCE(input_details, '{}'::JSONB), btrim(input_idempotency_key)
    )
    ON CONFLICT (requested_by, idempotency_key) DO UPDATE SET idempotency_key = EXCLUDED.idempotency_key
    RETURNING * INTO saved_request;

    PERFORM public.enqueue_workflow_notification(
        child_record.school_id, 'Family request: ' || replace(input_request_type, '_', ' '),
        child_record.first_name || ' has a new family request.',
        'family_request', 'family_request', saved_request.id,
        ARRAY(
            SELECT membership.user_id FROM public.school_memberships membership
            WHERE membership.school_id = child_record.school_id AND membership.active = TRUE
              AND membership.role IN ('teacher', 'school_director')
        ), 'family-request:' || saved_request.id::TEXT,
        CASE WHEN input_request_type IN ('pickup_change', 'medication') THEN 'important' ELSE 'routine' END,
        jsonb_build_object('type', 'family_request', 'id', saved_request.id, 'child_id', input_child_id), actor
    );
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
    VALUES (child_record.school_id, actor, 'submitted', 'family_request', saved_request.id);
    RETURN QUERY SELECT * FROM public.family_requests WHERE id = saved_request.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_family_request_status(
    input_request_id UUID,
    input_status TEXT
)
RETURNS SETOF public.family_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE actor UUID := auth.uid(); saved_request public.family_requests%ROWTYPE;
BEGIN
    SELECT * INTO saved_request FROM public.family_requests WHERE id = input_request_id FOR UPDATE;
    IF NOT FOUND OR NOT public.can_staff_access_child(saved_request.child_id, actor, ARRAY['teacher', 'school_director']) THEN
        RAISE EXCEPTION 'Only school staff can update a family request';
    END IF;
    IF input_status NOT IN ('acknowledged', 'completed') THEN RAISE EXCEPTION 'Invalid family request status'; END IF;
    UPDATE public.family_requests
    SET status = input_status, handled_by = actor, handled_at = NOW(), updated_at = NOW()
    WHERE id = input_request_id RETURNING * INTO saved_request;
    PERFORM public.enqueue_workflow_notification(
        saved_request.school_id, 'Family request ' || input_status,
        'Your ' || replace(saved_request.request_type, '_', ' ') || ' request was ' || input_status || '.',
        'family_request_' || input_status, 'family_request', saved_request.id,
        ARRAY[saved_request.requested_by], 'family-request:' || input_status || ':' || saved_request.id::TEXT,
        'routine', jsonb_build_object('type', 'family_request', 'id', saved_request.id, 'child_id', saved_request.child_id), actor
    );
    RETURN QUERY SELECT * FROM public.family_requests WHERE id = saved_request.id;
END;
$$;

CREATE TABLE IF NOT EXISTS public.notification_preferences (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    category TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    quiet_hours_start TIME,
    quiet_hours_end TIME,
    time_zone TEXT NOT NULL DEFAULT 'America/New_York',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, category),
    CHECK (category NOT IN ('medication', 'health', 'medication_missed', 'care_health_check') OR enabled = TRUE)
);
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.notification_delivery_available_at(
    input_user_id UUID,
    input_category TEXT,
    input_priority TEXT
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    preference public.notification_preferences%ROWTYPE;
    preference_category TEXT;
    local_now TIMESTAMP;
    local_date DATE;
    local_time TIME;
    next_delivery_local TIMESTAMP;
BEGIN
    preference_category := CASE
        WHEN input_category LIKE 'assignment_%' OR input_category LIKE 'onboarding_%' THEN 'assignments'
        WHEN input_category LIKE 'attendance_%' OR input_category = 'daily_care_summary' THEN 'attendance'
        WHEN input_category LIKE 'chat_%' THEN 'chat'
        WHEN input_category LIKE 'child_connection_%' THEN 'connections'
        WHEN input_category LIKE 'family_request%' THEN 'family_requests'
        WHEN input_category = 'school_announcement' THEN 'announcements'
        WHEN input_category LIKE 'medication_%' OR input_category = 'care_medication' THEN 'medication'
        WHEN input_category = 'care_health_check' THEN 'health'
        ELSE input_category
    END;
    SELECT * INTO preference FROM public.notification_preferences
    WHERE user_id = input_user_id AND category IN (input_category, preference_category)
    ORDER BY (category = input_category) DESC
    LIMIT 1;
    IF input_priority = 'urgent' OR input_category IN ('medication_missed', 'care_health_check') THEN RETURN NOW(); END IF;
    IF FOUND AND preference.enabled = FALSE THEN RETURN NULL; END IF;
    IF NOT FOUND OR preference.quiet_hours_start IS NULL OR preference.quiet_hours_end IS NULL THEN RETURN NOW(); END IF;

    local_now := NOW() AT TIME ZONE preference.time_zone;
    local_date := local_now::DATE;
    local_time := local_now::TIME;
    IF preference.quiet_hours_start < preference.quiet_hours_end THEN
        IF local_time >= preference.quiet_hours_start AND local_time < preference.quiet_hours_end THEN
            next_delivery_local := local_date + preference.quiet_hours_end;
        ELSE RETURN NOW(); END IF;
    ELSE
        IF local_time >= preference.quiet_hours_start THEN
            next_delivery_local := (local_date + 1) + preference.quiet_hours_end;
        ELSIF local_time < preference.quiet_hours_end THEN
            next_delivery_local := local_date + preference.quiet_hours_end;
        ELSE RETURN NOW(); END IF;
    END IF;
    RETURN next_delivery_local AT TIME ZONE preference.time_zone;
END;
$$;
REVOKE ALL ON FUNCTION public.notification_delivery_available_at(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notification_delivery_available_at(UUID, TEXT, TEXT) FROM authenticated;

CREATE OR REPLACE FUNCTION public.route_notification_recipient_to_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    notification_record public.notifications%ROWTYPE;
    delivery_time TIMESTAMPTZ;
BEGIN
    SELECT * INTO notification_record FROM public.notifications WHERE id = NEW.notification_id;
    delivery_time := public.notification_delivery_available_at(
        NEW.user_id, notification_record.category, notification_record.priority
    );
    IF delivery_time IS NULL THEN
        UPDATE public.notification_recipients
        SET delivery_state = 'expired', expired_at = NOW()
        WHERE notification_id = NEW.notification_id AND user_id = NEW.user_id;
    ELSE
        INSERT INTO public.notification_outbox (notification_id, user_id, available_at)
        VALUES (NEW.notification_id, NEW.user_id, delivery_time)
        ON CONFLICT (notification_id, user_id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS route_notification_recipient_to_outbox_trigger ON public.notification_recipients;
CREATE TRIGGER route_notification_recipient_to_outbox_trigger
    AFTER INSERT ON public.notification_recipients
    FOR EACH ROW EXECUTE FUNCTION public.route_notification_recipient_to_outbox();
REVOKE ALL ON FUNCTION public.route_notification_recipient_to_outbox() FROM PUBLIC, authenticated;

CREATE OR REPLACE FUNCTION public.process_due_medication_tasks()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    task_record RECORD;
    due_count INTEGER := 0;
    missed_count INTEGER := 0;
    staff_ids UUID[];
BEGIN
    IF COALESCE(auth.jwt()->>'role', '') <> 'service_role' THEN RAISE EXCEPTION 'Service role required'; END IF;

    FOR task_record IN
        UPDATE public.medication_tasks task
        SET status = 'due'
        FROM public.children child
        WHERE task.child_id = child.id
          AND task.status = 'pending'
          AND task.due_at <= NOW()
        RETURNING task.*, child.first_name
    LOOP
        SELECT array_agg(membership.user_id) INTO staff_ids
        FROM public.school_memberships membership
        WHERE membership.school_id = task_record.school_id
          AND membership.active = TRUE
          AND membership.role IN ('teacher', 'school_director');
        PERFORM public.enqueue_workflow_notification(
            task_record.school_id, 'Medication due',
            task_record.first_name || ' has medication due now.',
            'medication_due', 'medication_task', task_record.id, staff_ids,
            'medication:due:' || task_record.id::TEXT, 'important',
            jsonb_build_object('type', 'medication_task', 'id', task_record.id, 'child_id', task_record.child_id), NULL
        );
        due_count := due_count + 1;
    END LOOP;

    FOR task_record IN
        UPDATE public.medication_tasks task
        SET status = 'missed', escalated_at = NOW()
        FROM public.children child
        WHERE task.child_id = child.id
          AND task.status = 'due'
          AND task.due_at < NOW() - INTERVAL '15 minutes'
          AND NOT EXISTS (
              SELECT 1 FROM public.medication_acknowledgements acknowledgement
              WHERE acknowledgement.task_id = task.id
          )
        RETURNING task.*, child.first_name
    LOOP
        INSERT INTO public.medication_escalations (task_id, school_id, child_id, reason)
        VALUES (
            task_record.id, task_record.school_id, task_record.child_id,
            'Medication task was not acknowledged within 15 minutes'
        ) ON CONFLICT (task_id) DO NOTHING;
        SELECT array_agg(membership.user_id) INTO staff_ids
        FROM public.school_memberships membership
        WHERE membership.school_id = task_record.school_id
          AND membership.active = TRUE
          AND membership.role IN ('teacher', 'school_director');
        PERFORM public.enqueue_workflow_notification(
            task_record.school_id, 'Medication missed',
            task_record.first_name || '''s medication was not recorded within 15 minutes.',
            'medication_missed', 'medication_task', task_record.id, staff_ids,
            'medication:missed:' || task_record.id::TEXT, 'urgent',
            jsonb_build_object('type', 'medication_task', 'id', task_record.id, 'child_id', task_record.child_id), NULL
        );
        missed_count := missed_count + 1;
    END LOOP;
    RETURN jsonb_build_object('due', due_count, 'missed', missed_count);
END;
$$;
REVOKE ALL ON FUNCTION public.process_due_medication_tasks() FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.process_due_medication_tasks() TO service_role;

CREATE OR REPLACE FUNCTION public.claim_notification_outbox(input_limit INTEGER DEFAULT 100)
RETURNS SETOF public.notification_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF COALESCE(auth.jwt()->>'role', '') <> 'service_role' THEN RAISE EXCEPTION 'Service role required'; END IF;
    RETURN QUERY
    WITH candidates AS (
        SELECT outbox.id FROM public.notification_outbox outbox
        WHERE outbox.completed_at IS NULL AND outbox.available_at <= NOW()
          AND (outbox.locked_at IS NULL OR outbox.locked_at < NOW() - INTERVAL '5 minutes')
        ORDER BY outbox.available_at LIMIT LEAST(GREATEST(input_limit, 1), 500)
        FOR UPDATE SKIP LOCKED
    )
    UPDATE public.notification_outbox outbox
    SET locked_at = NOW(), attempt_count = outbox.attempt_count + 1
    FROM candidates WHERE outbox.id = candidates.id
    RETURNING outbox.*;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_notification_delivery(
    input_outbox_id UUID,
    input_succeeded BOOLEAN,
    input_error TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE outbox_record public.notification_outbox%ROWTYPE; next_delay INTERVAL;
BEGIN
    IF COALESCE(auth.jwt()->>'role', '') <> 'service_role' THEN RAISE EXCEPTION 'Service role required'; END IF;
    SELECT * INTO outbox_record FROM public.notification_outbox WHERE id = input_outbox_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Outbox item not found'; END IF;
    IF input_succeeded THEN
        UPDATE public.notification_outbox SET completed_at = NOW(), locked_at = NULL, last_error = NULL WHERE id = input_outbox_id;
        UPDATE public.notification_recipients
        SET delivered_at = COALESCE(delivered_at, NOW()), delivery_state = 'delivered',
            attempt_count = outbox_record.attempt_count, last_error = NULL
        WHERE notification_id = outbox_record.notification_id AND user_id = outbox_record.user_id;
    ELSIF outbox_record.attempt_count >= 8 THEN
        UPDATE public.notification_outbox
        SET completed_at = NOW(), locked_at = NULL, last_error = left(input_error, 1000)
        WHERE id = input_outbox_id;
        UPDATE public.notification_recipients
        SET delivery_state = 'expired', attempt_count = outbox_record.attempt_count,
            last_error = left(input_error, 1000), expired_at = NOW()
        WHERE notification_id = outbox_record.notification_id AND user_id = outbox_record.user_id;
    ELSE
        next_delay := make_interval(secs => LEAST(POWER(2, outbox_record.attempt_count)::INTEGER * 30, 21600));
        UPDATE public.notification_outbox
        SET locked_at = NULL, available_at = NOW() + next_delay, last_error = left(input_error, 1000)
        WHERE id = input_outbox_id;
        UPDATE public.notification_recipients
        SET delivery_state = 'failed', attempt_count = outbox_record.attempt_count, last_error = left(input_error, 1000)
        WHERE notification_id = outbox_record.notification_id AND user_id = outbox_record.user_id;
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_notification_outbox(INTEGER) FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION public.complete_notification_delivery(UUID, BOOLEAN, TEXT) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_notification_outbox(INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_notification_delivery(UUID, BOOLEAN, TEXT) TO service_role;

CREATE OR REPLACE FUNCTION public.create_school_announcement(
    input_school_id UUID,
    input_title TEXT,
    input_body TEXT,
    input_recipient_ids UUID[],
    input_idempotency_key TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    sanitized_recipients UUID[];
    notification_uuid UUID;
BEGIN
    IF NOT public.has_school_role(input_school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can send announcements';
    END IF;
    IF NULLIF(btrim(COALESCE(input_title, '')), '') IS NULL
       OR NULLIF(btrim(COALESCE(input_body, '')), '') IS NULL
       OR NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Title, message, and idempotency key are required';
    END IF;
    SELECT array_agg(membership.user_id) INTO sanitized_recipients
    FROM public.school_memberships membership
    WHERE membership.school_id = input_school_id
      AND membership.active = TRUE
      AND membership.role IN ('parent', 'teacher', 'school_director')
      AND membership.user_id = ANY(COALESCE(input_recipient_ids, ARRAY[]::UUID[]));
    notification_uuid := public.enqueue_workflow_notification(
        input_school_id, input_title, input_body, 'announcement', 'school', input_school_id,
        sanitized_recipients, 'announcement:' || actor::TEXT || ':' || btrim(input_idempotency_key),
        'important', jsonb_build_object('type', 'school_announcement', 'school_id', input_school_id), actor
    );
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
    VALUES (input_school_id, actor, 'announced', 'notification', notification_uuid);
    RETURN notification_uuid;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_transactional_notification(
    input_school_id UUID,
    input_title TEXT,
    input_body TEXT,
    input_category TEXT,
    input_source_type TEXT,
    input_source_id UUID,
    input_recipient_ids UUID[],
    input_idempotency_key TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE actor UUID := auth.uid();
BEGIN
    IF actor IS NULL OR NOT (
        public.has_school_role(input_school_id, actor, ARRAY['teacher', 'school_director'])
        OR public.is_hq_director(actor)
    ) THEN RAISE EXCEPTION 'Only school staff can create workflow notifications'; END IF;
    RETURN public.enqueue_workflow_notification(
        input_school_id, input_title, input_body, input_category,
        input_source_type, input_source_id, input_recipient_ids,
        'workflow:' || actor::TEXT || ':' || btrim(input_idempotency_key),
        'routine', jsonb_build_object('type', COALESCE(input_source_type, 'notification'), 'id', input_source_id), actor
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_director_chat_room(
    input_school_id UUID,
    input_name TEXT,
    input_description TEXT DEFAULT NULL,
    input_profile_image_url TEXT DEFAULT NULL,
    input_participant_ids UUID[] DEFAULT ARRAY[]::UUID[],
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.chat_rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    room_record public.chat_rooms%ROWTYPE;
    existing_result UUID;
    participant UUID;
BEGIN
    IF NOT public.has_school_role(input_school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can create rooms';
    END IF;
    IF NULLIF(btrim(COALESCE(input_name, '')), '') IS NULL
       OR NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Room name and idempotency key are required';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(actor::TEXT || ':chat-create:' || btrim(input_idempotency_key), 0));
    SELECT result_id INTO existing_result FROM public.school_workflow_mutations
    WHERE actor_id = actor AND operation = 'create_chat_room' AND idempotency_key = btrim(input_idempotency_key);
    IF existing_result IS NOT NULL THEN
        RETURN QUERY SELECT * FROM public.chat_rooms WHERE id = existing_result;
        RETURN;
    END IF;

    IF EXISTS (
        SELECT selected.user_id
        FROM unnest(COALESCE(input_participant_ids, ARRAY[]::UUID[])) selected(user_id)
        WHERE NOT EXISTS (
            SELECT 1 FROM public.school_memberships membership
            WHERE membership.school_id = input_school_id
              AND membership.user_id = selected.user_id
              AND membership.active = TRUE
              AND membership.role IN ('parent', 'teacher', 'school_director')
        )
    ) THEN RAISE EXCEPTION 'Every participant must be an active adult school member'; END IF;

    INSERT INTO public.chat_rooms (
        name, description, profile_image_url, invite_hash, room_type,
        created_by, school_id, created_at, updated_at
    ) VALUES (
        btrim(input_name), NULLIF(btrim(COALESCE(input_description, '')), ''),
        NULLIF(btrim(COALESCE(input_profile_image_url, '')), ''), NULL,
        'director_managed', actor, input_school_id, NOW(), NOW()
    ) RETURNING * INTO room_record;

    INSERT INTO public.chat_participants (room_id, user_id, role)
    VALUES (room_record.id, actor, 'owner')
    ON CONFLICT (room_id, user_id) DO UPDATE SET role = 'owner';
    INSERT INTO public.chat_participants (room_id, user_id, role)
    SELECT room_record.id, selected.user_id, CASE WHEN selected.user_id = actor THEN 'owner' ELSE 'member' END
    FROM (SELECT DISTINCT unnest(COALESCE(input_participant_ids, ARRAY[]::UUID[])) AS user_id) selected
    ON CONFLICT (room_id, user_id) DO NOTHING;

    INSERT INTO public.chat_participant_audit (room_id, school_id, user_id, action, acted_by)
    SELECT room_record.id, input_school_id, participant_row.user_id, 'added', actor
    FROM public.chat_participants participant_row WHERE participant_row.room_id = room_record.id;

    PERFORM public.enqueue_workflow_notification(
        input_school_id, 'Added to ' || room_record.name,
        'A school director added you to a group chat.',
        'chat_invitation', 'chat_room', room_record.id,
        ARRAY(
            SELECT row.user_id FROM public.chat_participants row
            WHERE row.room_id = room_record.id AND row.user_id <> actor
        ), 'chat:created:' || room_record.id::TEXT,
        'routine', jsonb_build_object('type', 'chat_room', 'id', room_record.id), actor
    );
    INSERT INTO public.school_workflow_mutations (actor_id, operation, idempotency_key, result_id)
    VALUES (actor, 'create_chat_room', btrim(input_idempotency_key), room_record.id);
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
    VALUES (input_school_id, actor, 'created', 'chat_room', room_record.id);
    RETURN QUERY SELECT * FROM public.chat_rooms WHERE id = room_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_director_chat_room(
    input_room_id UUID,
    input_name TEXT,
    input_description TEXT DEFAULT NULL,
    input_profile_image_url TEXT DEFAULT NULL,
    input_archived BOOLEAN DEFAULT FALSE
)
RETURNS SETOF public.chat_rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE room_record public.chat_rooms%ROWTYPE;
BEGIN
    SELECT * INTO room_record FROM public.chat_rooms WHERE id = input_room_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND OR NOT public.has_school_role(room_record.school_id, auth.uid(), ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can update this room';
    END IF;
    IF NULLIF(btrim(COALESCE(input_name, '')), '') IS NULL THEN RAISE EXCEPTION 'Room name is required'; END IF;
    UPDATE public.chat_rooms
    SET name = btrim(input_name), description = NULLIF(btrim(COALESCE(input_description, '')), ''),
        profile_image_url = NULLIF(btrim(COALESCE(input_profile_image_url, '')), ''),
        archived_at = CASE WHEN input_archived THEN COALESCE(archived_at, NOW()) ELSE NULL END,
        updated_at = NOW()
    WHERE id = input_room_id RETURNING * INTO room_record;
    RETURN QUERY SELECT * FROM public.chat_rooms WHERE id = room_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_director_chat_room_image_path(
    input_room_id UUID,
    input_profile_image_path TEXT
)
RETURNS SETOF public.chat_rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE room_record public.chat_rooms%ROWTYPE;
BEGIN
    SELECT * INTO room_record FROM public.chat_rooms WHERE id = input_room_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND OR NOT public.has_school_role(room_record.school_id, auth.uid(), ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can update this room image';
    END IF;
    UPDATE public.chat_rooms
    SET profile_image_path = NULLIF(btrim(COALESCE(input_profile_image_path, '')), ''), updated_at = NOW()
    WHERE id = input_room_id RETURNING * INTO room_record;
    RETURN QUERY SELECT * FROM public.chat_rooms WHERE id = room_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_director_chat_participants(
    input_room_id UUID,
    input_participant_ids UUID[]
)
RETURNS TABLE (room_id UUID, user_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    room_record public.chat_rooms%ROWTYPE;
    added_ids UUID[];
    removed_ids UUID[];
BEGIN
    SELECT * INTO room_record FROM public.chat_rooms WHERE id = input_room_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND OR NOT public.has_school_role(room_record.school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can manage room membership';
    END IF;
    IF EXISTS (
        SELECT selected.user_id FROM unnest(COALESCE(input_participant_ids, ARRAY[]::UUID[])) selected(user_id)
        WHERE NOT EXISTS (
            SELECT 1 FROM public.school_memberships membership
            WHERE membership.school_id = room_record.school_id
              AND membership.user_id = selected.user_id AND membership.active = TRUE
              AND membership.role IN ('parent', 'teacher', 'school_director')
        )
    ) THEN RAISE EXCEPTION 'Every participant must be an active adult school member'; END IF;

    INSERT INTO public.chat_participants (room_id, user_id, role)
    VALUES (input_room_id, actor, 'owner')
    ON CONFLICT ON CONSTRAINT chat_participants_pkey DO UPDATE SET role = 'owner';

    SELECT array_agg(existing.user_id) INTO removed_ids
    FROM public.chat_participants existing
    WHERE existing.room_id = input_room_id AND existing.user_id <> actor
      AND NOT (existing.user_id = ANY(COALESCE(input_participant_ids, ARRAY[]::UUID[])));
    SELECT array_agg(selected.user_id) INTO added_ids
    FROM (SELECT DISTINCT unnest(COALESCE(input_participant_ids, ARRAY[]::UUID[])) AS user_id) selected
    WHERE selected.user_id <> actor AND NOT EXISTS (
        SELECT 1 FROM public.chat_participants existing
        WHERE existing.room_id = input_room_id AND existing.user_id = selected.user_id
    );

    INSERT INTO public.chat_participant_audit (room_id, school_id, user_id, action, acted_by)
    SELECT input_room_id, room_record.school_id, removed.user_id, 'removed', actor
    FROM unnest(COALESCE(removed_ids, ARRAY[]::UUID[])) removed(user_id);
    DELETE FROM public.chat_participants existing
    WHERE existing.room_id = input_room_id AND existing.user_id <> actor
      AND existing.user_id = ANY(COALESCE(removed_ids, ARRAY[]::UUID[]));

    INSERT INTO public.chat_participants (room_id, user_id, role)
    SELECT input_room_id, added.user_id, 'member'
    FROM unnest(COALESCE(added_ids, ARRAY[]::UUID[])) added(user_id)
    ON CONFLICT ON CONSTRAINT chat_participants_pkey DO NOTHING;
    INSERT INTO public.chat_participant_audit (room_id, school_id, user_id, action, acted_by)
    SELECT input_room_id, room_record.school_id, added.user_id, 'added', actor
    FROM unnest(COALESCE(added_ids, ARRAY[]::UUID[])) added(user_id);

    PERFORM public.enqueue_workflow_notification(
        room_record.school_id, 'Added to ' || room_record.name,
        'A school director added you to a group chat.', 'chat_invitation', 'chat_room', input_room_id,
        added_ids, 'chat:participants:added:' || input_room_id::TEXT || ':' || md5(COALESCE(array_to_string(added_ids, ','), 'none')),
        'routine', jsonb_build_object('type', 'chat_room', 'id', input_room_id), actor
    );
    PERFORM public.enqueue_workflow_notification(
        room_record.school_id, 'Removed from ' || room_record.name,
        'A school director removed you from a group chat.', 'chat_removal', 'chat_room', input_room_id,
        removed_ids, 'chat:participants:removed:' || input_room_id::TEXT || ':' || md5(COALESCE(array_to_string(removed_ids, ','), 'none')),
        'routine', jsonb_build_object('type', 'chat_room', 'id', input_room_id), actor
    );
    RETURN QUERY SELECT participant.room_id, participant.user_id
    FROM public.chat_participants participant WHERE participant.room_id = input_room_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_director_chat_room(input_room_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE room_record public.chat_rooms%ROWTYPE;
BEGIN
    SELECT * INTO room_record FROM public.chat_rooms WHERE id = input_room_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND OR NOT public.has_school_role(room_record.school_id, auth.uid(), ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can delete this room';
    END IF;
    UPDATE public.chat_rooms SET deleted_at = NOW(), deleted_by = auth.uid(), archived_at = COALESCE(archived_at, NOW()), updated_at = NOW()
    WHERE id = input_room_id;
    INSERT INTO public.chat_participant_audit (room_id, school_id, user_id, action, acted_by)
    SELECT input_room_id, room_record.school_id, participant.user_id, 'removed', auth.uid()
    FROM public.chat_participants participant WHERE participant.room_id = input_room_id;
    DELETE FROM public.chat_participants WHERE room_id = input_room_id;
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
    VALUES (room_record.school_id, auth.uid(), 'soft_deleted', 'chat_room', input_room_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_chat_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE room_record public.chat_rooms%ROWTYPE;
BEGIN
    SELECT * INTO room_record FROM public.chat_rooms WHERE id = NEW.room_id;
    IF room_record.deleted_at IS NULL THEN
        PERFORM public.enqueue_workflow_notification(
            room_record.school_id, room_record.name, COALESCE(NULLIF(NEW.text, ''), 'New attachment'),
            'chat_message', 'chat_room', room_record.id,
            ARRAY(
                SELECT participant.user_id FROM public.chat_participants participant
                WHERE participant.room_id = room_record.id AND participant.user_id <> NEW.sender_id
                  AND participant.notifications_enabled = TRUE
            ), 'chat:message:' || NEW.id::TEXT,
            'routine', jsonb_build_object('type', 'chat_room', 'id', room_record.id, 'message_id', NEW.id), NEW.sender_id
        );
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS notify_chat_message_trigger ON public.messages;
CREATE TRIGGER notify_chat_message_trigger
    AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION public.notify_chat_message();

CREATE OR REPLACE FUNCTION public.guard_chat_participant_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.can_manage_chat_room(OLD.room_id, auth.uid()) AND (
        NEW.room_id <> OLD.room_id OR NEW.user_id <> OLD.user_id OR NEW.role <> OLD.role
    ) THEN
        RAISE EXCEPTION 'Members can only change their room notification setting';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS guard_chat_participant_update_trigger ON public.chat_participants;
CREATE TRIGGER guard_chat_participant_update_trigger
    BEFORE UPDATE ON public.chat_participants FOR EACH ROW EXECUTE FUNCTION public.guard_chat_participant_update();

DROP POLICY IF EXISTS "Authenticated users can view profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can view same-school adult profiles" ON public.profiles;
CREATE POLICY "Users can view same-school adult profiles"
    ON public.profiles FOR SELECT
    USING (
        id = auth.uid()
        OR public.is_hq_director(auth.uid())
        OR EXISTS (
            SELECT 1
            FROM public.school_memberships mine
            JOIN public.school_memberships theirs ON theirs.school_id = mine.school_id
            WHERE mine.user_id = auth.uid() AND mine.active = TRUE
              AND theirs.user_id = profiles.id AND theirs.active = TRUE
              AND theirs.role IN ('parent', 'teacher', 'school_director')
        )
    );

DROP POLICY IF EXISTS "Users can view rooms they are in" ON public.chat_rooms;
DROP POLICY IF EXISTS "Authenticated users can create rooms" ON public.chat_rooms;
DROP POLICY IF EXISTS "Room members can update rooms" ON public.chat_rooms;
DROP POLICY IF EXISTS "Room owners can delete rooms" ON public.chat_rooms;
CREATE POLICY "Participants can view active managed rooms"
    ON public.chat_rooms FOR SELECT
    USING (
        deleted_at IS NULL AND (
            public.is_chat_room_member(id, auth.uid())
            OR public.has_school_role(school_id, auth.uid(), ARRAY['school_director'])
        )
    );

DROP POLICY IF EXISTS "Users can view participants in their rooms" ON public.chat_participants;
DROP POLICY IF EXISTS "Room members can add participants" ON public.chat_participants;
DROP POLICY IF EXISTS "Users and owners can update participants" ON public.chat_participants;
DROP POLICY IF EXISTS "Users and owners can remove participants" ON public.chat_participants;
CREATE POLICY "Participants can view managed room membership"
    ON public.chat_participants FOR SELECT
    USING (public.is_chat_room_member(room_id, auth.uid()) OR public.can_manage_chat_room(room_id, auth.uid()));
CREATE POLICY "Participants can update their own mute setting"
    ON public.chat_participants FOR UPDATE
    USING (user_id = auth.uid() AND public.is_chat_room_member(room_id, auth.uid()))
    WITH CHECK (user_id = auth.uid() AND public.is_chat_room_member(room_id, auth.uid()));

DROP POLICY IF EXISTS "Users can view messages in their rooms" ON public.messages;
DROP POLICY IF EXISTS "Users can insert messages in their rooms" ON public.messages;
DROP POLICY IF EXISTS "Users can update their own messages" ON public.messages;
DROP POLICY IF EXISTS "Users can delete their own messages" ON public.messages;
CREATE POLICY "Managed room participants can view messages"
    ON public.messages FOR SELECT
    USING (
        (public.is_chat_room_member(room_id, auth.uid())
         OR public.has_school_role(school_id, auth.uid(), ARRAY['school_director']))
        AND EXISTS (SELECT 1 FROM public.chat_rooms room WHERE room.id = messages.room_id AND room.deleted_at IS NULL)
    );
CREATE POLICY "Managed room participants can send messages"
    ON public.messages FOR INSERT
    WITH CHECK (
        sender_id = auth.uid() AND public.is_chat_room_member(room_id, auth.uid())
        AND EXISTS (
            SELECT 1 FROM public.chat_rooms room
            WHERE room.id = messages.room_id AND room.deleted_at IS NULL AND room.archived_at IS NULL
        )
    );
CREATE POLICY "Senders can edit managed room messages"
    ON public.messages FOR UPDATE
    USING (sender_id = auth.uid() AND public.is_chat_room_member(room_id, auth.uid()))
    WITH CHECK (sender_id = auth.uid() AND public.is_chat_room_member(room_id, auth.uid()));
CREATE POLICY "Senders can delete managed room messages"
    ON public.messages FOR DELETE
    USING (sender_id = auth.uid() AND public.is_chat_room_member(room_id, auth.uid()));

CREATE POLICY "Users can view relevant connection requests"
    ON public.child_connection_requests FOR SELECT
    USING (
        requested_by = auth.uid()
        OR public.has_school_role(school_id, auth.uid(), ARRAY['school_director'])
        OR public.is_hq_director(auth.uid())
    );
DROP POLICY IF EXISTS "Directors can manage child guardians" ON public.child_guardians;
DROP POLICY IF EXISTS "Users can upload child documents" ON public.child_documents;
DROP POLICY IF EXISTS "Directors can review child documents" ON public.child_documents;
DROP POLICY IF EXISTS "Users can manage medication instructions" ON public.medication_instructions;
DROP POLICY IF EXISTS "Staff can update medication tasks" ON public.medication_tasks;
DROP POLICY IF EXISTS "Staff can create medication acknowledgements" ON public.medication_acknowledgements;
CREATE POLICY "Users can view relevant child profile changes"
    ON public.child_profile_change_requests FOR SELECT
    USING (
        requested_by = auth.uid() OR public.can_access_child(child_id, auth.uid())
    );
CREATE POLICY "Authorized adults can view attendance sessions"
    ON public.attendance_sessions FOR SELECT
    USING (public.can_access_child(child_id, auth.uid()));
CREATE POLICY "Directors can view attendance corrections"
    ON public.attendance_corrections FOR SELECT
    USING (
        public.has_school_role(school_id, auth.uid(), ARRAY['school_director'])
        OR public.is_hq_director(auth.uid())
    );
CREATE POLICY "Authorized adults can view care events"
    ON public.child_care_events FOR SELECT
    USING (
        public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director'])
        OR (visibility = 'parent' AND public.is_child_guardian(child_id, auth.uid()))
    );
CREATE POLICY "Families and staff can view family requests"
    ON public.family_requests FOR SELECT
    USING (
        requested_by = auth.uid()
        OR public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director'])
        OR public.is_hq_director(auth.uid())
    );
CREATE POLICY "Users manage their notification preferences"
    ON public.notification_preferences FOR ALL
    USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "Directors can view workflow audit"
    ON public.workflow_audit_events FOR SELECT
    USING (
        public.has_school_role(school_id, auth.uid(), ARRAY['school_director'])
        OR public.is_hq_director(auth.uid())
    );
CREATE POLICY "Directors can view chat participant audit"
    ON public.chat_participant_audit FOR SELECT
    USING (
        public.has_school_role(school_id, auth.uid(), ARRAY['school_director'])
        OR public.is_hq_director(auth.uid())
    );

-- Notifications are created only inside trusted workflow functions.
DROP POLICY IF EXISTS "School staff can create notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can create notification recipients" ON public.notification_recipients;

DROP FUNCTION IF EXISTS public.fetch_my_notifications(INTEGER);
CREATE FUNCTION public.fetch_my_notifications(input_limit INTEGER DEFAULT 100)
RETURNS TABLE (
    id UUID,
    school_id UUID,
    school_name TEXT,
    title TEXT,
    body TEXT,
    category TEXT,
    source_type TEXT,
    source_id UUID,
    created_by UUID,
    created_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    priority TEXT,
    route JSONB,
    delivery_state TEXT,
    attempt_count INTEGER,
    last_error TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT notification.id, notification.school_id, school.name,
        notification.title, notification.body, notification.category,
        notification.source_type, notification.source_id, notification.created_by,
        notification.created_at, recipient.read_at, notification.priority,
        notification.route, recipient.delivery_state, recipient.attempt_count, recipient.last_error
    FROM public.notification_recipients recipient
    JOIN public.notifications notification ON notification.id = recipient.notification_id
    JOIN public.schools school ON school.id = notification.school_id
    WHERE recipient.user_id = auth.uid()
      AND recipient.delivery_state NOT IN ('dismissed', 'expired')
    ORDER BY notification.created_at DESC
    LIMIT LEAST(GREATEST(COALESCE(input_limit, 100), 1), 200);
$$;

CREATE OR REPLACE FUNCTION public.mark_notification_read(input_notification_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.notification_recipients
    SET read_at = COALESCE(read_at, NOW()), opened_at = COALESCE(opened_at, NOW()),
        delivery_state = CASE WHEN delivery_state IN ('acknowledged', 'failed') THEN delivery_state ELSE 'opened' END
    WHERE notification_id = input_notification_id AND user_id = auth.uid()
      AND delivery_state NOT IN ('dismissed', 'expired');
    IF NOT FOUND THEN RAISE EXCEPTION 'Notification was not found for this user'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.acknowledge_notification(input_notification_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.notification_recipients
    SET acknowledged_at = COALESCE(acknowledged_at, NOW()), opened_at = COALESCE(opened_at, NOW()),
        read_at = COALESCE(read_at, NOW()), delivery_state = 'acknowledged'
    WHERE notification_id = input_notification_id AND user_id = auth.uid();
    IF NOT FOUND THEN RAISE EXCEPTION 'Notification was not found for this user'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.dismiss_notification(input_notification_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.notification_recipients
    SET dismissed_at = COALESCE(dismissed_at, NOW()), delivery_state = 'dismissed'
    WHERE notification_id = input_notification_id AND user_id = auth.uid();
    IF NOT FOUND THEN RAISE EXCEPTION 'Notification was not found for this user'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.clear_my_notifications()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE changed_count INTEGER;
BEGIN
    UPDATE public.notification_recipients
    SET dismissed_at = COALESCE(dismissed_at, NOW()), delivery_state = 'dismissed'
    WHERE user_id = auth.uid() AND delivery_state NOT IN ('dismissed', 'expired');
    GET DIAGNOSTICS changed_count = ROW_COUNT;
    RETURN changed_count;
END;
$$;

DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notification_recipients;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.attendance_sessions;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.child_care_events;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

REVOKE ALL ON FUNCTION public.fetch_school_directory(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.submit_child_connection_request(UUID, TEXT, TEXT, DATE, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.review_child_connection_request(UUID, TEXT, UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_child_guardian_invite(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.revoke_child_guardian(UUID, UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.submit_assignment_with_payload(UUID, JSONB, TEXT, JSONB, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fetch_assignment_child_binding(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.save_onboarding_template_requirement_v2(UUID, UUID, TEXT, TEXT, TEXT, INTEGER, JSONB, BOOLEAN, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_school_attendance(UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.correct_attendance_session(UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_child_care_event(UUID, TEXT, TIMESTAMPTZ, JSONB, TEXT, UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.submit_family_request(UUID, TEXT, JSONB, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_family_request_status(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_school_announcement(UUID, TEXT, TEXT, UUID[], TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_transactional_notification(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID[], TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_director_chat_room(UUID, TEXT, TEXT, TEXT, UUID[], TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_director_chat_room(UUID, TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_director_chat_room_image_path(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_director_chat_participants(UUID, UUID[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_director_chat_room(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.acknowledge_notification(UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fetch_school_directory(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_child_connection_request(UUID, TEXT, TEXT, DATE, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_child_connection_request(UUID, TEXT, UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_child_guardian_invite(UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_child_guardian(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_assignment_with_payload(UUID, JSONB, TEXT, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_assignment_child_binding(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_onboarding_template_requirement_v2(UUID, UUID, TEXT, TEXT, TEXT, INTEGER, JSONB, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_school_attendance(UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.correct_attendance_session(UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_child_care_event(UUID, TEXT, TIMESTAMPTZ, JSONB, TEXT, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_family_request(UUID, TEXT, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_family_request_status(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_school_announcement(UUID, TEXT, TEXT, UUID[], TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_transactional_notification(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID[], TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_director_chat_room(UUID, TEXT, TEXT, TEXT, UUID[], TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_director_chat_room(UUID, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_director_chat_room_image_path(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_director_chat_participants(UUID, UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_director_chat_room(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.acknowledge_notification(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260722010000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
