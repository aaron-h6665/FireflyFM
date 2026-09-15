-- Migration: 20260914190000_hq_custom_chat_rooms.sql
-- Description: HQ Director cross-school custom chat rooms, parent privacy opt-in invites,
-- audit schema relaxation, and portfolio directory retrieval.

-- 1. Update chat_rooms room_type check to include 'hq_custom'
ALTER TABLE public.chat_rooms DROP CONSTRAINT IF EXISTS chat_rooms_room_type_check;
ALTER TABLE public.chat_rooms
    ADD CONSTRAINT chat_rooms_room_type_check
    CHECK (room_type IN ('child_family', 'school_group', 'custom', 'hq_custom'));

-- 2. Relax school_id NOT NULL constraint on audit tables for cross-school/HQ events
ALTER TABLE public.chat_participant_audit ALTER COLUMN school_id DROP NOT NULL;
ALTER TABLE public.workflow_audit_events ALTER COLUMN school_id DROP NOT NULL;

-- 3. Update is_chat_room_member to support hq_custom rooms and gate 'invited' role
CREATE OR REPLACE FUNCTION public.is_chat_room_member(room_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.chat_participants participant
        JOIN public.chat_rooms room ON room.id = participant.room_id
        WHERE participant.room_id = room_uuid
          AND participant.user_id = user_uuid
          AND room.deleted_at IS NULL
          AND participant.role != 'invited'
          AND (
              public.has_direct_school_role(
                  room.school_id,
                  user_uuid,
                  ARRAY['parent', 'teacher', 'school_director']
              )
              OR (
                  room.room_type = 'child_family'
                  AND room.archived_at IS NOT NULL
                  AND room.retention_until > NOW()
                  AND participant.membership_source = 'guardian'
              )
              OR (
                  room.room_type = 'hq_custom'
                  AND (
                      public.is_hq_director(user_uuid)
                      OR EXISTS (
                          SELECT 1
                          FROM public.school_memberships membership
                          WHERE membership.user_id = user_uuid
                            AND membership.active = TRUE
                            AND membership.access_state = 'full'
                      )
                  )
              )
          )
    );
$$;

-- 4. Update can_manage_chat_room for HQ custom rooms
CREATE OR REPLACE FUNCTION public.can_manage_chat_room(room_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.chat_rooms
        WHERE id = room_uuid
          AND (
              public.has_direct_school_role(school_id, user_uuid, ARRAY['school_director'])
              OR (
                  room_type = 'hq_custom'
                  AND public.is_hq_director(user_uuid)
              )
          )
    );
$$;

-- 5. Update RLS on chat_rooms so invited members can read room metadata for accept/decline
DROP POLICY IF EXISTS "Room participants can view rooms" ON public.chat_rooms;
CREATE POLICY "Room participants can view rooms"
    ON public.chat_rooms FOR SELECT
    USING (
        deleted_at IS NULL AND (
            public.is_chat_room_member(id, auth.uid())
            OR (
                room_type = 'hq_custom'
                AND EXISTS (
                    SELECT 1 FROM public.chat_participants cp
                    WHERE cp.room_id = chat_rooms.id AND cp.user_id = auth.uid()
                )
            )
        )
    );

-- 6. Update fetch_my_managed_chat_rooms to include cross-school HQ rooms
DROP FUNCTION IF EXISTS public.fetch_my_managed_chat_rooms(UUID);
CREATE OR REPLACE FUNCTION public.fetch_my_managed_chat_rooms(input_school_id UUID)
RETURNS TABLE (
    id UUID,
    name TEXT,
    description TEXT,
    profile_image_url TEXT,
    profile_image_path TEXT,
    school_id UUID,
    room_type TEXT,
    subject_child_id UUID,
    system_managed BOOLEAN,
    created_at TIMESTAMPTZ,
    created_by UUID,
    updated_at TIMESTAMPTZ,
    archived_at TIMESTAMPTZ,
    archive_reason TEXT,
    retention_until TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    participant_joined_at TIMESTAMPTZ,
    participant_last_read_at TIMESTAMPTZ,
    participant_notifications_enabled BOOLEAN,
    participant_role TEXT,
    participant_membership_source TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE actor UUID := auth.uid();
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'School chat access denied'; END IF;

    RETURN QUERY
    SELECT room.id, room.name, room.description, room.profile_image_url,
           room.profile_image_path, room.school_id, room.room_type,
           room.subject_child_id, room.system_managed, room.created_at,
           room.created_by, room.updated_at, room.archived_at,
           room.archive_reason, room.retention_until, room.deleted_at,
           participant.joined_at, participant.last_read_at,
           participant.notifications_enabled, participant.role,
           participant.membership_source
    FROM public.chat_rooms room
    JOIN public.chat_participants participant
      ON participant.room_id = room.id
     AND participant.user_id = actor
    WHERE (room.school_id = input_school_id OR room.school_id IS NULL OR room.room_type = 'hq_custom')
      AND room.deleted_at IS NULL
    ORDER BY room.archived_at NULLS FIRST,
             COALESCE(room.updated_at, room.created_at) DESC,
             room.id;
END;
$$;

REVOKE ALL ON FUNCTION public.fetch_my_managed_chat_rooms(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fetch_my_managed_chat_rooms(UUID) TO authenticated;

-- 7. RPC: create_hq_chat_room
CREATE OR REPLACE FUNCTION public.create_hq_chat_room(
    input_name TEXT,
    input_description TEXT DEFAULT NULL,
    input_profile_image_url TEXT DEFAULT NULL,
    input_participant_ids UUID[] DEFAULT '{}'::UUID[],
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.chat_rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    existing_result UUID;
    room_record public.chat_rooms%ROWTYPE;
BEGIN
    IF actor IS NULL OR NOT public.is_hq_director(actor) THEN
        RAISE EXCEPTION 'Only an HQ director can create an HQ custom chat room';
    END IF;
    IF NULLIF(btrim(COALESCE(input_name, '')), '') IS NULL
       OR NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Room name and idempotency key are required';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended(actor::TEXT || ':hq-chat-create:' || btrim(input_idempotency_key), 0)
    );
    SELECT result_id INTO existing_result
    FROM public.school_workflow_mutations
    WHERE actor_id = actor
      AND operation = 'create_hq_chat_room'
      AND idempotency_key = btrim(input_idempotency_key);
    IF existing_result IS NOT NULL THEN
        RETURN QUERY SELECT * FROM public.chat_rooms WHERE id = existing_result;
        RETURN;
    END IF;

    -- Validate all participants are active full-access adults or HQ directors
    IF EXISTS (
        SELECT selected.user_id
        FROM unnest(COALESCE(input_participant_ids, ARRAY[]::UUID[])) selected(user_id)
        WHERE NOT (
            public.is_hq_director(selected.user_id)
            OR EXISTS (
                SELECT 1
                FROM public.school_memberships membership
                WHERE membership.user_id = selected.user_id
                  AND membership.active = TRUE
                  AND membership.access_state = 'full'
                  AND membership.role IN ('parent', 'teacher', 'school_director')
            )
        )
    ) THEN
        RAISE EXCEPTION 'Every participant must be an active full-access adult member or HQ director';
    END IF;

    INSERT INTO public.chat_rooms (
        name, description, profile_image_url, invite_hash, room_type,
        system_managed, created_by, school_id, created_at, updated_at
    ) VALUES (
        btrim(input_name),
        NULLIF(btrim(COALESCE(input_description, '')), ''),
        NULLIF(btrim(COALESCE(input_profile_image_url, '')), ''),
        NULL, 'hq_custom', FALSE, actor, NULL, NOW(), NOW()
    ) RETURNING * INTO room_record;

    -- Creator is owner
    INSERT INTO public.chat_participants (
        room_id, user_id, role, membership_source
    ) VALUES (
        room_record.id, actor, 'owner', 'manual'
    ) ON CONFLICT (room_id, user_id) DO UPDATE
      SET role = 'owner', membership_source = 'manual';

    -- Other participants: Staff (HQ, director, teacher) are 'member', parents are 'invited'
    INSERT INTO public.chat_participants (
        room_id, user_id, role, membership_source
    )
    SELECT room_record.id, selected.user_id,
           CASE 
               WHEN selected.user_id = actor THEN 'owner'
               WHEN public.is_hq_director(selected.user_id) OR EXISTS (
                   SELECT 1 FROM public.school_memberships m
                   WHERE m.user_id = selected.user_id AND m.active = TRUE AND m.role IN ('teacher', 'school_director')
               ) THEN 'member'
               ELSE 'invited'
           END,
           'manual'
    FROM (
        SELECT DISTINCT unnest(COALESCE(input_participant_ids, ARRAY[]::UUID[])) AS user_id
    ) selected
    ON CONFLICT (room_id, user_id) DO NOTHING;

    -- Participant audit
    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    )
    SELECT room_record.id, NULL, participant.user_id, 'added', actor
    FROM public.chat_participants participant
    WHERE participant.room_id = room_record.id;

    -- Workflow mutations & audit
    INSERT INTO public.school_workflow_mutations (
        actor_id, operation, idempotency_key, result_id
    ) VALUES (
        actor, 'create_hq_chat_room', btrim(input_idempotency_key), room_record.id
    );

    RETURN QUERY SELECT * FROM public.chat_rooms WHERE id = room_record.id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_hq_chat_room(TEXT, TEXT, TEXT, UUID[], TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_hq_chat_room(TEXT, TEXT, TEXT, UUID[], TEXT) TO authenticated;

-- 8. RPC: respond_to_chat_invite
CREATE OR REPLACE FUNCTION public.respond_to_chat_invite(
    input_room_id UUID,
    input_accept BOOLEAN
)
RETURNS SETOF public.chat_rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    room_record public.chat_rooms%ROWTYPE;
    participant_record public.chat_participants%ROWTYPE;
BEGIN
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO room_record
    FROM public.chat_rooms
    WHERE id = input_room_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room not found';
    END IF;

    SELECT * INTO participant_record
    FROM public.chat_participants
    WHERE room_id = input_room_id AND user_id = actor;
    IF NOT FOUND OR participant_record.role != 'invited' THEN
        RAISE EXCEPTION 'No pending invitation found for this room';
    END IF;

    IF input_accept THEN
        UPDATE public.chat_participants
        SET role = 'member',
            joined_at = NOW()
        WHERE room_id = input_room_id AND user_id = actor;

        INSERT INTO public.chat_participant_audit (
            room_id, school_id, user_id, action, acted_by
        ) VALUES (
            input_room_id, room_record.school_id, actor, 'added', actor
        );

        RETURN QUERY SELECT * FROM public.chat_rooms WHERE id = room_record.id;
    ELSE
        DELETE FROM public.chat_participants
        WHERE room_id = input_room_id AND user_id = actor;

        INSERT INTO public.chat_participant_audit (
            room_id, school_id, user_id, action, acted_by
        ) VALUES (
            input_room_id, room_record.school_id, actor, 'removed', actor
        );

        RETURN;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.respond_to_chat_invite(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.respond_to_chat_invite(UUID, BOOLEAN) TO authenticated;

-- 9. RPC: fetch_hq_chat_directory
CREATE OR REPLACE FUNCTION public.fetch_hq_chat_directory(
    input_school_id UUID DEFAULT NULL,
    input_role TEXT DEFAULT NULL,
    input_query TEXT DEFAULT NULL
)
RETURNS TABLE (
    user_id UUID,
    display_name TEXT,
    avatar_url TEXT,
    role TEXT,
    school_id UUID,
    school_name TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    trimmed_query TEXT := NULLIF(btrim(COALESCE(input_query, '')), '');
BEGIN
    IF actor IS NULL OR NOT public.is_hq_director(actor) THEN
        RAISE EXCEPTION 'Only an HQ director can access the portfolio directory';
    END IF;

    RETURN QUERY
    WITH candidate_members AS (
        -- School-based members
        SELECT DISTINCT ON (membership.user_id, membership.school_id)
            membership.user_id,
            membership.role::TEXT AS member_role,
            membership.school_id,
            schools.name AS school_name
        FROM public.school_memberships membership
        JOIN public.schools schools ON schools.id = membership.school_id
        WHERE membership.active = TRUE
          AND membership.access_state = 'full'
          AND membership.role IN ('parent', 'teacher', 'school_director')
          AND (input_school_id IS NULL OR membership.school_id = input_school_id)
          AND (input_role IS NULL OR membership.role::TEXT = input_role)

        UNION ALL

        -- HQ directors
        SELECT DISTINCT ON (membership.user_id)
            membership.user_id,
            'hq_director' AS member_role,
            membership.school_id,
            COALESCE(schools.name, 'Headquarters') AS school_name
        FROM public.school_memberships membership
        LEFT JOIN public.schools schools ON schools.id = membership.school_id
        WHERE membership.active = TRUE
          AND membership.role = 'hq_director'
          AND (input_school_id IS NULL OR membership.school_id = input_school_id)
          AND (input_role IS NULL OR input_role = 'hq_director')
    )
    SELECT
        candidates.user_id,
        COALESCE(profiles.display_name, 'Member') AS display_name,
        profiles.avatar_url,
        candidates.member_role AS role,
        candidates.school_id,
        candidates.school_name
    FROM candidate_members candidates
    LEFT JOIN public.profiles profiles ON profiles.id = candidates.user_id
    WHERE candidates.user_id <> actor
      AND (
          trimmed_query IS NULL
          OR profiles.display_name ILIKE ('%' || trimmed_query || '%')
      )
    ORDER BY display_name ASC, school_name ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.fetch_hq_chat_directory(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fetch_hq_chat_directory(UUID, TEXT, TEXT) TO authenticated;

-- 10. Update update_director_chat_room to support HQ custom rooms
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
    SELECT * INTO room_record
    FROM public.chat_rooms
    WHERE id = input_room_id AND deleted_at IS NULL
    FOR UPDATE;
    IF NOT FOUND
       OR (
           NOT public.has_direct_school_role(room_record.school_id, auth.uid(), ARRAY['school_director'])
           AND NOT (room_record.room_type = 'hq_custom' AND public.is_hq_director(auth.uid()))
       ) THEN
        RAISE EXCEPTION 'Only an authorized director can update this room';
    END IF;
    IF room_record.system_managed THEN
        RAISE EXCEPTION 'This room is managed automatically';
    END IF;
    IF NULLIF(btrim(COALESCE(input_name, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Room name is required';
    END IF;

    UPDATE public.chat_rooms
    SET name = btrim(input_name),
        description = NULLIF(btrim(COALESCE(input_description, '')), ''),
        profile_image_url = NULLIF(btrim(COALESCE(input_profile_image_url, '')), ''),
        archived_at = CASE WHEN input_archived THEN COALESCE(archived_at, NOW()) ELSE NULL END,
        archive_reason = CASE WHEN input_archived THEN 'director_archived' ELSE NULL END,
        updated_at = NOW()
    WHERE id = input_room_id
    RETURNING * INTO room_record;
    RETURN QUERY SELECT * FROM public.chat_rooms WHERE id = room_record.id;
END;
$$;

-- 11. Update set_director_chat_participants to support HQ custom rooms
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
    selected_ids UUID[];
BEGIN
    SELECT * INTO room_record
    FROM public.chat_rooms
    WHERE id = input_room_id AND deleted_at IS NULL
    FOR UPDATE;
    IF NOT FOUND
       OR (
           NOT public.has_direct_school_role(room_record.school_id, actor, ARRAY['school_director'])
           AND NOT (room_record.room_type = 'hq_custom' AND public.is_hq_director(actor))
       ) THEN
        RAISE EXCEPTION 'Only an authorized director can manage room membership';
    END IF;
    IF room_record.system_managed THEN
        RAISE EXCEPTION 'Membership in this room is managed automatically';
    END IF;

    SELECT COALESCE(array_agg(DISTINCT value), ARRAY[]::UUID[])
    INTO selected_ids
    FROM unnest(COALESCE(input_participant_ids, ARRAY[]::UUID[]) || actor) value;

    IF room_record.room_type = 'hq_custom' THEN
        IF EXISTS (
            SELECT selected.user_id
            FROM unnest(selected_ids) selected(user_id)
            WHERE NOT (
                public.is_hq_director(selected.user_id)
                OR EXISTS (
                    SELECT 1
                    FROM public.school_memberships membership
                    WHERE membership.user_id = selected.user_id
                      AND membership.active = TRUE
                      AND membership.access_state = 'full'
                      AND membership.role IN ('parent', 'teacher', 'school_director')
                )
            )
        ) THEN
            RAISE EXCEPTION 'Every participant must be an active full-access adult member or HQ director';
        END IF;
    ELSE
        IF EXISTS (
            SELECT selected.user_id
            FROM unnest(selected_ids) selected(user_id)
            WHERE NOT EXISTS (
                SELECT 1
                FROM public.school_memberships membership
                WHERE membership.school_id = room_record.school_id
                  AND membership.user_id = selected.user_id
                  AND membership.active = TRUE
                  AND membership.access_state = 'full'
                  AND membership.role IN ('parent', 'teacher', 'school_director')
            )
        ) THEN
            RAISE EXCEPTION 'Every participant must be a full-access adult school member';
        END IF;
    END IF;

    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    )
    SELECT input_room_id, room_record.school_id, participant.user_id, 'removed', actor
    FROM public.chat_participants participant
    WHERE participant.room_id = input_room_id
      AND NOT (participant.user_id = ANY(selected_ids));

    DELETE FROM public.chat_participants participant
    WHERE participant.room_id = input_room_id
      AND NOT (participant.user_id = ANY(selected_ids));

    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    )
    SELECT input_room_id, room_record.school_id, selected.user_id, 'added', actor
    FROM unnest(selected_ids) selected(user_id)
    WHERE NOT EXISTS (
        SELECT 1 FROM public.chat_participants participant
        WHERE participant.room_id = input_room_id
          AND participant.user_id = selected.user_id
    );

    INSERT INTO public.chat_participants (
        room_id, user_id, role, membership_source
    )
    SELECT input_room_id, selected.user_id,
           CASE 
               WHEN selected.user_id = actor THEN 'owner'
               WHEN room_record.room_type = 'hq_custom' AND NOT (
                   public.is_hq_director(selected.user_id)
                   OR EXISTS (
                       SELECT 1 FROM public.school_memberships m
                       WHERE m.user_id = selected.user_id AND m.active = TRUE AND m.role IN ('teacher', 'school_director')
                   )
               ) THEN 'invited'
               ELSE 'member'
           END,
           'manual'
    FROM unnest(selected_ids) selected(user_id)
    ON CONFLICT ON CONSTRAINT chat_participants_pkey DO UPDATE
    SET membership_source = 'manual';

    RETURN QUERY
    SELECT participant.room_id, participant.user_id
    FROM public.chat_participants participant
    WHERE participant.room_id = input_room_id;
END;
$$;

-- 12. Update delete_director_chat_room to support HQ custom rooms
CREATE OR REPLACE FUNCTION public.delete_director_chat_room(input_room_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    room_record public.chat_rooms%ROWTYPE;
BEGIN
    SELECT * INTO room_record
    FROM public.chat_rooms
    WHERE id = input_room_id AND deleted_at IS NULL
    FOR UPDATE;
    IF NOT FOUND
       OR (
           NOT public.has_direct_school_role(room_record.school_id, actor, ARRAY['school_director'])
           AND NOT (room_record.room_type = 'hq_custom' AND public.is_hq_director(actor))
       ) THEN
        RAISE EXCEPTION 'Only an authorized director can delete this room';
    END IF;
    IF room_record.system_managed THEN
        RAISE EXCEPTION 'Membership in this room is managed automatically';
    END IF;

    UPDATE public.chat_rooms
    SET deleted_at = NOW(),
        deleted_by = actor,
        updated_at = NOW()
    WHERE id = input_room_id;

    DELETE FROM public.chat_participants WHERE room_id = input_room_id;

    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    ) VALUES (
        input_room_id, room_record.school_id, actor, 'removed', actor
    );
END;
$$;

-- 13. Update storage private file policies to allow hq_custom chat rooms and gate invited parents
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
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director'])
            OR EXISTS (
                SELECT 1
                FROM public.onboarding_template_requirements req
                JOIN public.onboarding_requirement_instances inst ON inst.template_requirement_id = req.id
                WHERE req.school_id = school_uuid
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

-- 14. Bump schema version to 20260914190000
CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT 20260914190000::BIGINT;
$$;
