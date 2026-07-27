-- Chat-first privacy, automatic room lifecycle, and director vacancy rules.

ALTER TABLE public.schools
    ADD COLUMN IF NOT EXISTS family_chat_teacher_scope TEXT NOT NULL DEFAULT 'all_school_teachers';
ALTER TABLE public.schools
    DROP CONSTRAINT IF EXISTS schools_family_chat_teacher_scope_check;
ALTER TABLE public.schools
    ADD CONSTRAINT schools_family_chat_teacher_scope_check
    CHECK (family_chat_teacher_scope IN ('all_school_teachers', 'assigned_teachers'));

ALTER TABLE public.chat_rooms
    ADD COLUMN IF NOT EXISTS subject_child_id UUID REFERENCES public.children(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS system_managed BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS archive_reason TEXT,
    ADD COLUMN IF NOT EXISTS retention_until TIMESTAMPTZ;
ALTER TABLE public.chat_rooms DROP CONSTRAINT IF EXISTS chat_rooms_room_type_check;
UPDATE public.chat_rooms
SET room_type = 'custom'
WHERE room_type IS NULL OR room_type IN ('public', 'private', 'director_managed');
ALTER TABLE public.chat_rooms
    ALTER COLUMN room_type SET DEFAULT 'custom',
    ALTER COLUMN room_type SET NOT NULL,
    ADD CONSTRAINT chat_rooms_room_type_check
    CHECK (room_type IN ('child_family', 'school_group', 'custom'));

ALTER TABLE public.chat_participants
    ADD COLUMN IF NOT EXISTS membership_source TEXT NOT NULL DEFAULT 'manual';
ALTER TABLE public.chat_participants
    DROP CONSTRAINT IF EXISTS chat_participants_membership_source_check;
ALTER TABLE public.chat_participants
    ADD CONSTRAINT chat_participants_membership_source_check
    CHECK (membership_source IN ('manual', 'guardian', 'teacher', 'director', 'school'));

ALTER TABLE public.chat_participant_audit
    ALTER COLUMN acted_by DROP NOT NULL;

ALTER TABLE public.messages
    ADD COLUMN IF NOT EXISTS entry_kind TEXT NOT NULL DEFAULT 'message',
    ADD COLUMN IF NOT EXISTS structured_source_type TEXT,
    ADD COLUMN IF NOT EXISTS structured_source_id UUID,
    ADD COLUMN IF NOT EXISTS audio_duration_seconds DOUBLE PRECISION;
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_entry_kind_check;
ALTER TABLE public.messages
    ADD CONSTRAINT messages_entry_kind_check
    CHECK (entry_kind IN ('message', 'care_event', 'family_request', 'goal_update'));
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_structured_source_check;
ALTER TABLE public.messages
    ADD CONSTRAINT messages_structured_source_check CHECK (
        (entry_kind = 'message' AND structured_source_type IS NULL AND structured_source_id IS NULL)
        OR
        (entry_kind <> 'message' AND structured_source_type IS NOT NULL AND structured_source_id IS NOT NULL)
    );
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_audio_duration_check;
ALTER TABLE public.messages
    ADD CONSTRAINT messages_audio_duration_check
    CHECK (audio_duration_seconds IS NULL OR audio_duration_seconds >= 0);

CREATE TABLE IF NOT EXISTS public.chat_message_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
    room_id UUID NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
    normalized_url TEXT NOT NULL,
    display_url TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (message_id, normalized_url)
);
ALTER TABLE public.chat_message_links ENABLE ROW LEVEL SECURITY;

CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_rooms_one_active_child_family
    ON public.chat_rooms(school_id, subject_child_id)
    WHERE room_type = 'child_family' AND deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_rooms_one_school_group
    ON public.chat_rooms(school_id)
    WHERE room_type = 'school_group' AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_chat_rooms_subject_child
    ON public.chat_rooms(subject_child_id)
    WHERE subject_child_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_message_links_room_created
    ON public.chat_message_links(room_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_room_attachment_created
    ON public.messages(room_id, attachment_type, created_at DESC)
    WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_messages_structured_source
    ON public.messages(structured_source_type, structured_source_id)
    WHERE structured_source_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_one_structured_timeline_entry
    ON public.messages(structured_source_type, structured_source_id)
    WHERE structured_source_id IS NOT NULL;

-- Resolve legacy duplicate active directors deterministically before adding the
-- invariant. The newest membership stays active and every automatic vacancy is
-- preserved in the workflow audit trail.
WITH ranked AS (
    SELECT membership.id,
           row_number() OVER (
               PARTITION BY membership.school_id
               ORDER BY membership.joined_at DESC NULLS LAST,
                        membership.created_at DESC NULLS LAST,
                        membership.id DESC
           ) AS position
    FROM public.school_memberships membership
    WHERE membership.active = TRUE
      AND membership.role = 'school_director'
), deactivated AS (
    UPDATE public.school_memberships membership
    SET active = FALSE
    FROM ranked
    WHERE membership.id = ranked.id
      AND ranked.position > 1
    RETURNING membership.id, membership.school_id, membership.user_id
)
INSERT INTO public.workflow_audit_events (
    school_id, actor_id, event_type, source_type, source_id, metadata
)
SELECT school_id, NULL, 'director_membership_deduplicated',
       'school_membership', id, jsonb_build_object('user_id', user_id)
FROM deactivated;

CREATE UNIQUE INDEX IF NOT EXISTS idx_school_memberships_one_active_director
    ON public.school_memberships(school_id)
    WHERE active = TRUE AND role = 'school_director';

WITH ranked AS (
    SELECT invite.id,
           row_number() OVER (
               PARTITION BY invite.school_id
               ORDER BY invite.created_at DESC, invite.id DESC
           ) AS position
    FROM public.role_invites invite
    WHERE invite.role = 'school_director'
      AND invite.status = 'pending'
)
UPDATE public.role_invites invite
SET status = 'revoked', token = NULL, token_hash = NULL
FROM ranked
WHERE invite.id = ranked.id
  AND ranked.position > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_role_invites_one_pending_director
    ON public.role_invites(school_id)
    WHERE role = 'school_director' AND status = 'pending';

CREATE OR REPLACE FUNCTION public.guard_school_director_invite()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.role = 'school_director' AND NEW.status = 'pending' THEN
        IF EXISTS (
            SELECT 1
            FROM public.school_memberships membership
            WHERE membership.school_id = NEW.school_id
              AND membership.active = TRUE
              AND membership.role = 'school_director'
        ) THEN
            RAISE EXCEPTION 'Vacate the current school director before sending a replacement invitation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_school_director_invite_trigger ON public.role_invites;
CREATE TRIGGER guard_school_director_invite_trigger
    BEFORE INSERT OR UPDATE OF school_id, role, status
    ON public.role_invites
    FOR EACH ROW EXECUTE FUNCTION public.guard_school_director_invite();

CREATE OR REPLACE FUNCTION public.cancel_school_director_invite(input_invite_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    invite_record public.role_invites%ROWTYPE;
BEGIN
    IF actor IS NULL OR NOT public.is_hq_director(actor) THEN
        RAISE EXCEPTION 'Only a headquarter director can cancel a director invitation';
    END IF;

    SELECT * INTO invite_record
    FROM public.role_invites
    WHERE id = input_invite_id
      AND role = 'school_director'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Director invitation not found';
    END IF;
    IF invite_record.status <> 'pending' THEN
        RAISE EXCEPTION 'Only a pending director invitation can be cancelled';
    END IF;

    UPDATE public.role_invites
    SET status = 'revoked', token = NULL, token_hash = NULL
    WHERE id = input_invite_id;

    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id, metadata
    ) VALUES (
        invite_record.school_id, actor, 'director_invite_cancelled',
        'role_invite', invite_record.id,
        jsonb_build_object('email', invite_record.email)
    );
END;
$$;

-- HQ is an administrative role, not an implicit participant in private child
-- records. Keep staff access school-scoped and explicit.
CREATE OR REPLACE FUNCTION public.can_staff_access_child(
    child_uuid UUID,
    user_uuid UUID,
    allowed_roles TEXT[]
)
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
         AND membership.access_state = 'full'
        WHERE child.id = child_uuid
          AND membership.role = ANY(allowed_roles)
          AND membership.role IN ('teacher', 'school_director')
    );
$$;

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
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.sync_child_family_room(input_child_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    child_record public.children%ROWTYPE;
    room_record public.chat_rooms%ROWTYPE;
    expected_ids UUID[] := ARRAY[]::UUID[];
    archive_ids UUID[] := ARRAY[]::UUID[];
    has_full_guardian BOOLEAN := FALSE;
BEGIN
    PERFORM set_config('firefly.system_room_sync', 'on', TRUE);
    PERFORM pg_advisory_xact_lock(hashtextextended('child-family-room:' || input_child_id::TEXT, 0));

    SELECT * INTO child_record
    FROM public.children
    WHERE id = input_child_id;
    IF NOT FOUND THEN
        PERFORM set_config('firefly.system_room_sync', 'off', TRUE);
        RETURN NULL;
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM public.child_guardians guardian
        JOIN public.school_memberships membership
          ON membership.school_id = child_record.school_id
         AND membership.user_id = guardian.guardian_id
         AND membership.active = TRUE
         AND membership.access_state = 'full'
         AND membership.role = 'parent'
        WHERE guardian.child_id = child_record.id
          AND guardian.verification_status = 'verified'
          AND guardian.ended_at IS NULL
    ) INTO has_full_guardian;

    SELECT * INTO room_record
    FROM public.chat_rooms room
    WHERE room.school_id = child_record.school_id
      AND room.subject_child_id = child_record.id
      AND room.room_type = 'child_family'
      AND room.deleted_at IS NULL
    FOR UPDATE;

    IF child_record.active = TRUE AND has_full_guardian THEN
        IF NOT FOUND THEN
            INSERT INTO public.chat_rooms (
                name, description, invite_hash, school_id, room_type,
                subject_child_id, system_managed, created_by,
                created_at, updated_at
            ) VALUES (
                btrim(child_record.first_name || ' ' || child_record.last_name) || ' • Family Team',
                'Private updates, care, and family requests for ' || btrim(child_record.first_name || ' ' || child_record.last_name),
                NULL, child_record.school_id, 'child_family',
                child_record.id, TRUE, NULL, NOW(), NOW()
            ) RETURNING * INTO room_record;
        ELSE
            UPDATE public.chat_rooms
            SET name = btrim(child_record.first_name || ' ' || child_record.last_name) || ' • Family Team',
                description = 'Private updates, care, and family requests for ' || btrim(child_record.first_name || ' ' || child_record.last_name),
                system_managed = TRUE,
                archived_at = NULL,
                archive_reason = NULL,
                retention_until = NULL,
                updated_at = NOW()
            WHERE id = room_record.id
            RETURNING * INTO room_record;
        END IF;

        WITH expected AS (
            SELECT guardian.guardian_id AS user_id, 'member'::TEXT AS participant_role,
                   'guardian'::TEXT AS membership_source, 1 AS priority
            FROM public.child_guardians guardian
            JOIN public.school_memberships membership
              ON membership.school_id = child_record.school_id
             AND membership.user_id = guardian.guardian_id
             AND membership.active = TRUE
             AND membership.access_state = 'full'
             AND membership.role = 'parent'
            WHERE guardian.child_id = child_record.id
              AND guardian.verification_status = 'verified'
              AND guardian.ended_at IS NULL
            UNION ALL
            SELECT membership.user_id, 'owner', 'director', 2
            FROM public.school_memberships membership
            WHERE membership.school_id = child_record.school_id
              AND membership.active = TRUE
              AND membership.access_state = 'full'
              AND membership.role = 'school_director'
            UNION ALL
            SELECT membership.user_id, 'member', 'teacher', 3
            FROM public.school_memberships membership
            WHERE membership.school_id = child_record.school_id
              AND membership.active = TRUE
              AND membership.access_state = 'full'
              AND membership.role = 'teacher'
              AND (
                  (SELECT school.family_chat_teacher_scope FROM public.schools school WHERE school.id = child_record.school_id) = 'all_school_teachers'
                  OR EXISTS (
                      SELECT 1
                      FROM public.classroom_children classroom_child
                      JOIN public.classroom_teachers classroom_teacher
                        ON classroom_teacher.classroom_id = classroom_child.classroom_id
                      WHERE classroom_child.child_id = child_record.id
                        AND classroom_teacher.teacher_id = membership.user_id
                  )
              )
        ), deduplicated AS (
            SELECT DISTINCT ON (user_id) user_id, participant_role, membership_source
            FROM expected
            ORDER BY user_id, priority
        )
        SELECT COALESCE(array_agg(user_id), ARRAY[]::UUID[])
        INTO expected_ids
        FROM deduplicated;

        INSERT INTO public.chat_participant_audit (
            room_id, school_id, user_id, action, acted_by
        )
        SELECT room_record.id, child_record.school_id, expected_id, 'added', NULL
        FROM unnest(expected_ids) expected_id
        WHERE NOT EXISTS (
            SELECT 1 FROM public.chat_participants participant
            WHERE participant.room_id = room_record.id
              AND participant.user_id = expected_id
        );

        WITH expected AS (
            SELECT guardian.guardian_id AS user_id, 'member'::TEXT AS participant_role,
                   'guardian'::TEXT AS membership_source, 1 AS priority
            FROM public.child_guardians guardian
            JOIN public.school_memberships membership
              ON membership.school_id = child_record.school_id
             AND membership.user_id = guardian.guardian_id
             AND membership.active = TRUE
             AND membership.access_state = 'full'
             AND membership.role = 'parent'
            WHERE guardian.child_id = child_record.id
              AND guardian.verification_status = 'verified'
              AND guardian.ended_at IS NULL
            UNION ALL
            SELECT membership.user_id, 'owner', 'director', 2
            FROM public.school_memberships membership
            WHERE membership.school_id = child_record.school_id
              AND membership.active = TRUE
              AND membership.access_state = 'full'
              AND membership.role = 'school_director'
            UNION ALL
            SELECT membership.user_id, 'member', 'teacher', 3
            FROM public.school_memberships membership
            WHERE membership.school_id = child_record.school_id
              AND membership.active = TRUE
              AND membership.access_state = 'full'
              AND membership.role = 'teacher'
              AND (
                  (SELECT school.family_chat_teacher_scope FROM public.schools school WHERE school.id = child_record.school_id) = 'all_school_teachers'
                  OR EXISTS (
                      SELECT 1
                      FROM public.classroom_children classroom_child
                      JOIN public.classroom_teachers classroom_teacher
                        ON classroom_teacher.classroom_id = classroom_child.classroom_id
                      WHERE classroom_child.child_id = child_record.id
                        AND classroom_teacher.teacher_id = membership.user_id
                  )
              )
        ), deduplicated AS (
            SELECT DISTINCT ON (user_id) user_id, participant_role, membership_source
            FROM expected
            ORDER BY user_id, priority
        )
        INSERT INTO public.chat_participants (
            room_id, user_id, role, membership_source
        )
        SELECT room_record.id, user_id, participant_role, membership_source
        FROM deduplicated
        ON CONFLICT (room_id, user_id) DO UPDATE
        SET role = EXCLUDED.role,
            membership_source = EXCLUDED.membership_source;

        INSERT INTO public.chat_participant_audit (
            room_id, school_id, user_id, action, acted_by
        )
        SELECT room_record.id, child_record.school_id, participant.user_id, 'removed', NULL
        FROM public.chat_participants participant
        WHERE participant.room_id = room_record.id
          AND NOT (participant.user_id = ANY(expected_ids));

        DELETE FROM public.chat_participants participant
        WHERE participant.room_id = room_record.id
          AND NOT (participant.user_id = ANY(expected_ids));
    ELSIF FOUND THEN
        UPDATE public.chat_rooms
        SET archived_at = COALESCE(archived_at, NOW()),
            archive_reason = CASE
                WHEN child_record.active = FALSE THEN 'child_left_school'
                ELSE 'no_full_access_guardian'
            END,
            retention_until = CASE
                WHEN child_record.active = FALSE THEN COALESCE(retention_until, NOW() + INTERVAL '90 days')
                ELSE NULL
            END,
            updated_at = NOW()
        WHERE id = room_record.id
        RETURNING * INTO room_record;

        SELECT COALESCE(array_agg(allowed.user_id), ARRAY[]::UUID[])
        INTO archive_ids
        FROM (
            SELECT guardian.guardian_id AS user_id
            FROM public.child_guardians guardian
            WHERE guardian.child_id = child_record.id
              AND guardian.verification_status = 'verified'
              AND guardian.ended_at IS NULL
            UNION
            SELECT membership.user_id
            FROM public.school_memberships membership
            WHERE membership.school_id = child_record.school_id
              AND membership.active = TRUE
              AND membership.access_state = 'full'
              AND membership.role = 'school_director'
        ) allowed;

        INSERT INTO public.chat_participant_audit (
            room_id, school_id, user_id, action, acted_by
        )
        SELECT room_record.id, child_record.school_id, participant.user_id, 'removed', NULL
        FROM public.chat_participants participant
        WHERE participant.room_id = room_record.id
          AND NOT (participant.user_id = ANY(archive_ids));

        DELETE FROM public.chat_participants participant
        WHERE participant.room_id = room_record.id
          AND NOT (participant.user_id = ANY(archive_ids));
    END IF;

    PERFORM set_config('firefly.system_room_sync', 'off', TRUE);
    RETURN room_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_school_communication_rooms(input_school_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    school_record public.schools%ROWTYPE;
    room_record public.chat_rooms%ROWTYPE;
    expected_ids UUID[] := ARRAY[]::UUID[];
    child_id UUID;
BEGIN
    PERFORM set_config('firefly.system_room_sync', 'on', TRUE);
    PERFORM pg_advisory_xact_lock(hashtextextended('school-community-room:' || input_school_id::TEXT, 0));

    SELECT * INTO school_record
    FROM public.schools
    WHERE id = input_school_id;
    IF NOT FOUND THEN
        PERFORM set_config('firefly.system_room_sync', 'off', TRUE);
        RETURN;
    END IF;

    SELECT * INTO room_record
    FROM public.chat_rooms room
    WHERE room.school_id = input_school_id
      AND room.room_type = 'school_group'
      AND room.deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        INSERT INTO public.chat_rooms (
            name, description, invite_hash, school_id, room_type,
            system_managed, created_by, created_at, updated_at
        ) VALUES (
            school_record.name || ' • School Community',
            'School-wide announcements and conversation',
            NULL, school_record.id, 'school_group', TRUE, NULL, NOW(), NOW()
        ) RETURNING * INTO room_record;
    ELSE
        UPDATE public.chat_rooms
        SET name = school_record.name || ' • School Community',
            description = 'School-wide announcements and conversation',
            system_managed = TRUE,
            archived_at = NULL,
            archive_reason = NULL,
            retention_until = NULL,
            updated_at = NOW()
        WHERE id = room_record.id
        RETURNING * INTO room_record;
    END IF;

    SELECT COALESCE(array_agg(membership.user_id), ARRAY[]::UUID[])
    INTO expected_ids
    FROM public.school_memberships membership
    WHERE membership.school_id = input_school_id
      AND membership.active = TRUE
      AND membership.access_state = 'full'
      AND membership.role IN ('parent', 'teacher', 'school_director');

    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    )
    SELECT room_record.id, school_record.id, expected_id, 'added', NULL
    FROM unnest(expected_ids) expected_id
    WHERE NOT EXISTS (
        SELECT 1 FROM public.chat_participants participant
        WHERE participant.room_id = room_record.id
          AND participant.user_id = expected_id
    );

    INSERT INTO public.chat_participants (
        room_id, user_id, role, membership_source
    )
    SELECT room_record.id,
           membership.user_id,
           CASE WHEN membership.role = 'school_director' THEN 'owner' ELSE 'member' END,
           CASE WHEN membership.role = 'school_director' THEN 'director' ELSE 'school' END
    FROM public.school_memberships membership
    WHERE membership.school_id = input_school_id
      AND membership.active = TRUE
      AND membership.access_state = 'full'
      AND membership.role IN ('parent', 'teacher', 'school_director')
    ON CONFLICT (room_id, user_id) DO UPDATE
    SET role = EXCLUDED.role,
        membership_source = EXCLUDED.membership_source;

    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    )
    SELECT room_record.id, school_record.id, participant.user_id, 'removed', NULL
    FROM public.chat_participants participant
    WHERE participant.room_id = room_record.id
      AND NOT (participant.user_id = ANY(expected_ids));

    DELETE FROM public.chat_participants participant
    WHERE participant.room_id = room_record.id
      AND NOT (participant.user_id = ANY(expected_ids));

    FOR child_id IN
        SELECT child.id FROM public.children child WHERE child.school_id = input_school_id
    LOOP
        PERFORM public.sync_child_family_room(child_id);
    END LOOP;
    PERFORM set_config('firefly.system_room_sync', 'off', TRUE);
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_chat_rooms_for_membership_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.sync_school_communication_rooms(OLD.school_id);
    ELSE
        PERFORM public.sync_school_communication_rooms(NEW.school_id);
        IF TG_OP = 'UPDATE' AND OLD.school_id IS DISTINCT FROM NEW.school_id THEN
            PERFORM public.sync_school_communication_rooms(OLD.school_id);
        END IF;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS sync_chat_rooms_for_membership_trigger ON public.school_memberships;
CREATE TRIGGER sync_chat_rooms_for_membership_trigger
    AFTER INSERT OR UPDATE OF school_id, role, active, access_state OR DELETE
    ON public.school_memberships
    FOR EACH ROW EXECUTE FUNCTION public.sync_chat_rooms_for_membership_change();

CREATE OR REPLACE FUNCTION public.sync_chat_room_for_child_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP <> 'DELETE' THEN
        PERFORM public.sync_child_family_room(NEW.id);
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS sync_chat_room_for_child_trigger ON public.children;
CREATE TRIGGER sync_chat_room_for_child_trigger
    AFTER INSERT OR UPDATE OF school_id, first_name, last_name, active
    ON public.children
    FOR EACH ROW EXECUTE FUNCTION public.sync_chat_room_for_child_change();

CREATE OR REPLACE FUNCTION public.sync_chat_room_for_guardian_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.sync_child_family_room(OLD.child_id);
    ELSE
        PERFORM public.sync_child_family_room(NEW.child_id);
        IF TG_OP = 'UPDATE' AND OLD.child_id IS DISTINCT FROM NEW.child_id THEN
            PERFORM public.sync_child_family_room(OLD.child_id);
        END IF;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS sync_chat_room_for_guardian_trigger ON public.child_guardians;
CREATE TRIGGER sync_chat_room_for_guardian_trigger
    AFTER INSERT OR UPDATE OF child_id, guardian_id, verification_status, ended_at OR DELETE
    ON public.child_guardians
    FOR EACH ROW EXECUTE FUNCTION public.sync_chat_room_for_guardian_change();

CREATE OR REPLACE FUNCTION public.sync_chat_rooms_for_school_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.sync_school_communication_rooms(NEW.id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_chat_rooms_for_school_trigger ON public.schools;
CREATE TRIGGER sync_chat_rooms_for_school_trigger
    AFTER INSERT OR UPDATE OF name, family_chat_teacher_scope
    ON public.schools
    FOR EACH ROW EXECUTE FUNCTION public.sync_chat_rooms_for_school_change();

CREATE OR REPLACE FUNCTION public.sync_chat_rooms_for_classroom_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    changed_classroom_id UUID := COALESCE(NEW.classroom_id, OLD.classroom_id);
    child_id UUID;
BEGIN
    FOR child_id IN
        SELECT classroom_child.child_id
        FROM public.classroom_children classroom_child
        WHERE classroom_child.classroom_id = changed_classroom_id
    LOOP
        PERFORM public.sync_child_family_room(child_id);
    END LOOP;
    IF TG_TABLE_NAME = 'classroom_children' THEN
        PERFORM public.sync_child_family_room(COALESCE(NEW.child_id, OLD.child_id));
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS sync_chat_rooms_for_classroom_children_trigger ON public.classroom_children;
CREATE TRIGGER sync_chat_rooms_for_classroom_children_trigger
    AFTER INSERT OR UPDATE OR DELETE ON public.classroom_children
    FOR EACH ROW EXECUTE FUNCTION public.sync_chat_rooms_for_classroom_change();
DROP TRIGGER IF EXISTS sync_chat_rooms_for_classroom_teachers_trigger ON public.classroom_teachers;
CREATE TRIGGER sync_chat_rooms_for_classroom_teachers_trigger
    AFTER INSERT OR UPDATE OR DELETE ON public.classroom_teachers
    FOR EACH ROW EXECUTE FUNCTION public.sync_chat_rooms_for_classroom_change();

-- System rooms are server-owned. Custom rooms retain director editing and
-- participant self-leave behavior.
CREATE OR REPLACE FUNCTION public.guard_chat_participant_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    room_is_system_managed BOOLEAN;
BEGIN
    SELECT system_managed INTO room_is_system_managed
    FROM public.chat_rooms
    WHERE id = OLD.room_id;

    IF room_is_system_managed
       AND current_setting('firefly.system_room_sync', TRUE) IS DISTINCT FROM 'on'
       AND (
        NEW.room_id <> OLD.room_id
        OR NEW.user_id <> OLD.user_id
        OR NEW.role <> OLD.role
        OR NEW.membership_source <> OLD.membership_source
       ) THEN
        RAISE EXCEPTION 'Membership in this room is managed by the school lifecycle';
    END IF;

    IF NOT room_is_system_managed
       AND NOT public.can_manage_chat_room(OLD.room_id, auth.uid())
       AND (
           NEW.room_id <> OLD.room_id
           OR NEW.user_id <> OLD.user_id
           OR NEW.role <> OLD.role
           OR NEW.membership_source <> OLD.membership_source
       ) THEN
        RAISE EXCEPTION 'Members can only change their room notification setting';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.leave_managed_chat_room(input_room_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    room_record public.chat_rooms%ROWTYPE;
    actor_role TEXT;
    director_ids UUID[];
    workflow_event_id UUID;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    SELECT * INTO room_record
    FROM public.chat_rooms
    WHERE id = input_room_id AND deleted_at IS NULL
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Chat room was not found'; END IF;
    IF room_record.system_managed THEN
        RAISE EXCEPTION 'This room is created automatically and cannot be left manually';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.chat_participants
        WHERE room_id = input_room_id AND user_id = actor
    ) THEN RAISE EXCEPTION 'You are not a participant in this room'; END IF;

    SELECT membership.role INTO actor_role
    FROM public.school_memberships membership
    WHERE membership.school_id = room_record.school_id
      AND membership.user_id = actor
      AND membership.active = TRUE
      AND membership.role IN ('parent', 'teacher')
    ORDER BY CASE membership.role WHEN 'teacher' THEN 0 ELSE 1 END
    LIMIT 1;
    IF actor_role IS NULL THEN
        RAISE EXCEPTION 'Only parent and teacher participants can leave a custom room';
    END IF;

    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    ) VALUES (input_room_id, room_record.school_id, actor, 'removed', actor);
    DELETE FROM public.chat_participants
    WHERE room_id = input_room_id AND user_id = actor;

    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id, metadata
    ) VALUES (
        room_record.school_id, actor, 'participant_left', 'chat_room',
        input_room_id, jsonb_build_object('role', actor_role)
    ) RETURNING id INTO workflow_event_id;

    SELECT array_agg(membership.user_id) INTO director_ids
    FROM public.school_memberships membership
    WHERE membership.school_id = room_record.school_id
      AND membership.active = TRUE
      AND membership.role = 'school_director';

    PERFORM public.enqueue_workflow_notification(
        room_record.school_id,
        'A member left ' || room_record.name,
        'A parent or teacher left this custom group chat.',
        'chat_participant_left', 'chat_room', input_room_id, director_ids,
        'chat:participant:left:' || workflow_event_id::TEXT,
        'routine', jsonb_build_object('type', 'chat_room', 'id', input_room_id), actor
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
BEGIN
    IF NOT public.has_direct_school_role(input_school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can create rooms';
    END IF;
    IF NULLIF(btrim(COALESCE(input_name, '')), '') IS NULL
       OR NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Room name and idempotency key are required';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended(actor::TEXT || ':chat-create:' || btrim(input_idempotency_key), 0)
    );
    SELECT result_id INTO existing_result
    FROM public.school_workflow_mutations
    WHERE actor_id = actor
      AND operation = 'create_chat_room'
      AND idempotency_key = btrim(input_idempotency_key);
    IF existing_result IS NOT NULL THEN
        RETURN QUERY SELECT * FROM public.chat_rooms WHERE id = existing_result;
        RETURN;
    END IF;

    IF EXISTS (
        SELECT selected.user_id
        FROM unnest(COALESCE(input_participant_ids, ARRAY[]::UUID[])) selected(user_id)
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.school_memberships membership
            WHERE membership.school_id = input_school_id
              AND membership.user_id = selected.user_id
              AND membership.active = TRUE
              AND membership.access_state = 'full'
              AND membership.role IN ('parent', 'teacher', 'school_director')
        )
    ) THEN
        RAISE EXCEPTION 'Every participant must be a full-access adult school member';
    END IF;

    INSERT INTO public.chat_rooms (
        name, description, profile_image_url, invite_hash, room_type,
        system_managed, created_by, school_id, created_at, updated_at
    ) VALUES (
        btrim(input_name),
        NULLIF(btrim(COALESCE(input_description, '')), ''),
        NULLIF(btrim(COALESCE(input_profile_image_url, '')), ''),
        NULL, 'custom', FALSE, actor, input_school_id, NOW(), NOW()
    ) RETURNING * INTO room_record;

    INSERT INTO public.chat_participants (
        room_id, user_id, role, membership_source
    ) VALUES (
        room_record.id, actor, 'owner', 'manual'
    ) ON CONFLICT (room_id, user_id) DO UPDATE
      SET role = 'owner', membership_source = 'manual';

    INSERT INTO public.chat_participants (
        room_id, user_id, role, membership_source
    )
    SELECT room_record.id, selected.user_id,
           CASE WHEN selected.user_id = actor THEN 'owner' ELSE 'member' END,
           'manual'
    FROM (
        SELECT DISTINCT unnest(COALESCE(input_participant_ids, ARRAY[]::UUID[])) AS user_id
    ) selected
    ON CONFLICT (room_id, user_id) DO NOTHING;

    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    )
    SELECT room_record.id, input_school_id, participant.user_id, 'added', actor
    FROM public.chat_participants participant
    WHERE participant.room_id = room_record.id;

    INSERT INTO public.school_workflow_mutations (
        actor_id, operation, idempotency_key, result_id
    ) VALUES (
        actor, 'create_chat_room', btrim(input_idempotency_key), room_record.id
    );
    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id
    ) VALUES (
        input_school_id, actor, 'created', 'chat_room', room_record.id
    );
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
    SELECT * INTO room_record
    FROM public.chat_rooms
    WHERE id = input_room_id AND deleted_at IS NULL
    FOR UPDATE;
    IF NOT FOUND
       OR NOT public.has_direct_school_role(room_record.school_id, auth.uid(), ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can update this room';
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
    SELECT * INTO room_record
    FROM public.chat_rooms
    WHERE id = input_room_id AND deleted_at IS NULL
    FOR UPDATE;
    IF NOT FOUND
       OR NOT public.has_direct_school_role(room_record.school_id, auth.uid(), ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can update this room image';
    END IF;
    IF room_record.system_managed THEN
        RAISE EXCEPTION 'This room is managed automatically';
    END IF;
    UPDATE public.chat_rooms
    SET profile_image_path = NULLIF(btrim(COALESCE(input_profile_image_path, '')), ''),
        updated_at = NOW()
    WHERE id = input_room_id
    RETURNING * INTO room_record;
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
    selected_ids UUID[];
BEGIN
    SELECT * INTO room_record
    FROM public.chat_rooms
    WHERE id = input_room_id AND deleted_at IS NULL
    FOR UPDATE;
    IF NOT FOUND
       OR NOT public.has_direct_school_role(room_record.school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can manage room membership';
    END IF;
    IF room_record.system_managed THEN
        RAISE EXCEPTION 'Membership in this room is managed automatically';
    END IF;

    SELECT COALESCE(array_agg(DISTINCT value), ARRAY[]::UUID[])
    INTO selected_ids
    FROM unnest(COALESCE(input_participant_ids, ARRAY[]::UUID[]) || actor) value;

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
           CASE WHEN selected.user_id = actor THEN 'owner' ELSE 'member' END,
           'manual'
    FROM unnest(selected_ids) selected(user_id)
    ON CONFLICT (room_id, user_id) DO UPDATE
    SET role = EXCLUDED.role, membership_source = 'manual';

    RETURN QUERY
    SELECT participant.room_id, participant.user_id
    FROM public.chat_participants participant
    WHERE participant.room_id = input_room_id;
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
    SELECT * INTO room_record
    FROM public.chat_rooms
    WHERE id = input_room_id AND deleted_at IS NULL
    FOR UPDATE;
    IF NOT FOUND
       OR NOT public.has_direct_school_role(room_record.school_id, auth.uid(), ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can delete this room';
    END IF;
    IF room_record.system_managed THEN
        RAISE EXCEPTION 'This room is managed automatically and cannot be deleted';
    END IF;

    UPDATE public.chat_rooms
    SET deleted_at = NOW(), deleted_by = auth.uid(),
        archived_at = COALESCE(archived_at, NOW()),
        archive_reason = 'director_deleted', updated_at = NOW()
    WHERE id = input_room_id;

    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    )
    SELECT input_room_id, room_record.school_id, participant.user_id, 'removed', auth.uid()
    FROM public.chat_participants participant
    WHERE participant.room_id = input_room_id;
    DELETE FROM public.chat_participants WHERE room_id = input_room_id;

    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id
    ) VALUES (
        room_record.school_id, auth.uid(), 'soft_deleted', 'chat_room', input_room_id
    );
END;
$$;

DROP FUNCTION IF EXISTS public.fetch_my_managed_chat_rooms(UUID);
CREATE FUNCTION public.fetch_my_managed_chat_rooms(input_school_id UUID)
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
    WHERE room.school_id = input_school_id
      AND room.deleted_at IS NULL
      AND public.is_chat_room_member(room.id, actor)
    ORDER BY room.archived_at NULLS FIRST,
             COALESCE(room.updated_at, room.created_at) DESC,
             room.id;
END;
$$;

DROP POLICY IF EXISTS "Participants can view active managed rooms" ON public.chat_rooms;
DROP POLICY IF EXISTS "Room participants can view rooms" ON public.chat_rooms;
CREATE POLICY "Room participants can view rooms"
    ON public.chat_rooms FOR SELECT
    USING (deleted_at IS NULL AND public.is_chat_room_member(id, auth.uid()));

DROP POLICY IF EXISTS "Participants can view managed room membership" ON public.chat_participants;
DROP POLICY IF EXISTS "Room participants can view membership" ON public.chat_participants;
CREATE POLICY "Room participants can view membership"
    ON public.chat_participants FOR SELECT
    USING (public.is_chat_room_member(room_id, auth.uid()));

DROP POLICY IF EXISTS "Managed room participants can view messages" ON public.messages;
DROP POLICY IF EXISTS "Room participants can view messages" ON public.messages;
CREATE POLICY "Room participants can view messages"
    ON public.messages FOR SELECT
    USING (public.is_chat_room_member(room_id, auth.uid()));

DROP POLICY IF EXISTS "Room participants can view indexed links" ON public.chat_message_links;
CREATE POLICY "Room participants can view indexed links"
    ON public.chat_message_links FOR SELECT
    USING (public.is_chat_room_member(room_id, auth.uid()));

DROP POLICY IF EXISTS "Senders can edit managed room messages" ON public.messages;
CREATE POLICY "Senders can edit managed room messages"
    ON public.messages FOR UPDATE
    USING (
        entry_kind = 'message'
        AND sender_id = auth.uid()
        AND public.is_chat_room_member(room_id, auth.uid())
    )
    WITH CHECK (
        entry_kind = 'message'
        AND structured_source_type IS NULL
        AND structured_source_id IS NULL
        AND sender_id = auth.uid()
        AND public.is_chat_room_member(room_id, auth.uid())
    );

DROP POLICY IF EXISTS "Senders can delete managed room messages" ON public.messages;
CREATE POLICY "Senders can delete managed room messages"
    ON public.messages FOR DELETE
    USING (
        entry_kind = 'message'
        AND sender_id = auth.uid()
        AND public.is_chat_room_member(room_id, auth.uid())
    );

DROP POLICY IF EXISTS "Managed room participants can send messages" ON public.messages;
CREATE POLICY "Managed room participants can send messages"
    ON public.messages FOR INSERT
    WITH CHECK (
        entry_kind = 'message'
        AND structured_source_type IS NULL
        AND structured_source_id IS NULL
        AND sender_id = auth.uid()
        AND public.is_chat_room_member(room_id, auth.uid())
        AND EXISTS (
            SELECT 1
            FROM public.chat_rooms room
            WHERE room.id = messages.room_id
              AND room.deleted_at IS NULL
              AND room.archived_at IS NULL
        )
    );

DROP POLICY IF EXISTS "Families and staff can view family requests" ON public.family_requests;
CREATE POLICY "Families and staff can view family requests"
    ON public.family_requests FOR SELECT
    USING (
        requested_by = auth.uid()
        OR public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director'])
    );

CREATE OR REPLACE FUNCTION public.append_structured_child_timeline_entry()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    target_room_id UUID;
    source_kind TEXT;
    source_id UUID;
    source_school_id UUID;
    source_child_id UUID;
    source_sender_id UUID;
    source_created_at TIMESTAMPTZ;
    source_label TEXT;
BEGIN
    IF TG_TABLE_NAME = 'child_care_events' THEN
        IF NEW.visibility <> 'parent' THEN RETURN NEW; END IF;
        source_kind := 'care_event';
        source_id := NEW.id;
        source_school_id := NEW.school_id;
        source_child_id := NEW.child_id;
        source_sender_id := NEW.recorded_by;
        source_created_at := NEW.occurred_at;
        source_label := CASE NEW.event_type
            WHEN 'meal' THEN 'Meal update'
            WHEN 'bottle' THEN 'Bottle update'
            WHEN 'nap' THEN 'Nap update'
            WHEN 'potty' THEN 'Toileting update'
            WHEN 'diaper' THEN 'Diaper update'
            WHEN 'medication' THEN 'Medication administration'
            WHEN 'health_check' THEN 'Health observation'
            WHEN 'activity' THEN 'Activity update'
            WHEN 'photo' THEN 'Photo update'
            ELSE 'Care note'
        END;
    ELSIF TG_TABLE_NAME = 'family_requests' THEN
        source_kind := 'family_request';
        source_id := NEW.id;
        source_school_id := NEW.school_id;
        source_child_id := NEW.child_id;
        source_sender_id := NEW.requested_by;
        source_created_at := NEW.created_at;
        source_label := CASE NEW.request_type
            WHEN 'absence' THEN 'Absence request'
            WHEN 'pickup_change' THEN 'Pickup change request'
            WHEN 'medication' THEN 'Medication question'
            ELSE 'Family request'
        END;
    ELSE
        RETURN NEW;
    END IF;

    SELECT room.id INTO target_room_id
    FROM public.chat_rooms room
    WHERE room.school_id = source_school_id
      AND room.subject_child_id = source_child_id
      AND room.room_type = 'child_family'
      AND room.deleted_at IS NULL
      AND room.archived_at IS NULL
    LIMIT 1;

    IF target_room_id IS NULL THEN RETURN NEW; END IF;

    INSERT INTO public.messages (
        room_id, school_id, sender_id, text, entry_kind,
        structured_source_type, structured_source_id,
        created_at, is_deleted
    ) VALUES (
        target_room_id, source_school_id, source_sender_id, source_label,
        source_kind, TG_TABLE_NAME, source_id, source_created_at, FALSE
    )
    ON CONFLICT (structured_source_type, structured_source_id)
        WHERE structured_source_id IS NOT NULL
    DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS append_care_event_to_child_timeline_trigger ON public.child_care_events;
CREATE TRIGGER append_care_event_to_child_timeline_trigger
    AFTER INSERT ON public.child_care_events
    FOR EACH ROW EXECUTE FUNCTION public.append_structured_child_timeline_entry();

DROP TRIGGER IF EXISTS append_family_request_to_child_timeline_trigger ON public.family_requests;
CREATE TRIGGER append_family_request_to_child_timeline_trigger
    AFTER INSERT ON public.family_requests
    FOR EACH ROW EXECUTE FUNCTION public.append_structured_child_timeline_entry();

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
            room_record.school_id,
            room_record.name,
            COALESCE(
                NULLIF(NEW.text, ''),
                CASE
                    WHEN NEW.audio_path IS NOT NULL OR NEW.audio_url IS NOT NULL THEN 'Voice message'
                    WHEN NEW.entry_kind = 'care_event' THEN 'New care update'
                    WHEN NEW.entry_kind = 'family_request' THEN 'New family request'
                    WHEN NEW.entry_kind = 'goal_update' THEN 'New goal update'
                    ELSE 'New attachment'
                END
            ),
            'chat_message', 'chat_room', room_record.id,
            ARRAY(
                SELECT participant.user_id
                FROM public.chat_participants participant
                WHERE participant.room_id = room_record.id
                  AND participant.user_id <> NEW.sender_id
                  AND participant.notifications_enabled = TRUE
            ),
            'chat:message:' || NEW.id::TEXT,
            'routine',
            jsonb_build_object('type', 'chat_room', 'id', room_record.id, 'message_id', NEW.id),
            NEW.sender_id
        );
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_attendance_batch(
    input_child_ids UUID[],
    input_action TEXT,
    input_idempotency_key TEXT
)
RETURNS TABLE (
    child_id UUID,
    success BOOLEAN,
    session_id UUID,
    error_code TEXT,
    error_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    target_child_id UUID;
    saved_session_id UUID;
    caught_state TEXT;
    caught_message TEXT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF COALESCE(array_length(input_child_ids, 1), 0) = 0 THEN
        RAISE EXCEPTION 'Select at least one child';
    END IF;
    IF input_action NOT IN ('check_in', 'check_out', 'absent') THEN
        RAISE EXCEPTION 'Invalid batch attendance action';
    END IF;
    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN
        RAISE EXCEPTION 'An idempotency key is required';
    END IF;

    FOREACH target_child_id IN ARRAY input_child_ids LOOP
        BEGIN
            saved_session_id := NULL;
            SELECT session.id INTO saved_session_id
            FROM public.record_school_attendance(
                target_child_id,
                input_action,
                NOW(),
                NULL,
                btrim(input_idempotency_key) || ':' || target_child_id::TEXT
            ) session
            LIMIT 1;

            child_id := target_child_id;
            success := saved_session_id IS NOT NULL;
            session_id := saved_session_id;
            error_code := NULL;
            error_message := NULL;
            RETURN NEXT;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS
                caught_state = RETURNED_SQLSTATE,
                caught_message = MESSAGE_TEXT;
            child_id := target_child_id;
            success := FALSE;
            session_id := NULL;
            error_code := caught_state;
            error_message := caught_message;
            RETURN NEXT;
        END;
    END LOOP;
END;
$$;

-- Assignment revisions stay creator-owned. Recipients can only submit a new
-- attempt after the creator has enabled revisions and requested changes.
ALTER TABLE public.assignment_submissions
    ADD COLUMN IF NOT EXISTS score SMALLINT;

ALTER TABLE public.assignment_submissions
    DROP CONSTRAINT IF EXISTS assignment_submissions_score_check;
ALTER TABLE public.assignment_submissions
    ADD CONSTRAINT assignment_submissions_score_check
    CHECK (score IS NULL OR score BETWEEN 1 AND 10);

ALTER TABLE public.school_events
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS archived_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_school_events_active_school_start
    ON public.school_events(school_id, start_at)
    WHERE archived_at IS NULL;

DROP POLICY IF EXISTS "School members can view events" ON public.school_events;
CREATE POLICY "School members can view events"
    ON public.school_events FOR SELECT
    USING (
        (archived_at IS NULL AND public.is_school_member(school_id, auth.uid()))
        OR public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director'])
    );

CREATE OR REPLACE FUNCTION public.set_school_event_archived(
    input_event_id UUID,
    input_archived BOOLEAN
)
RETURNS SETOF public.school_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    event_record public.school_events%ROWTYPE;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

    SELECT * INTO event_record
    FROM public.school_events
    WHERE id = input_event_id
    FOR UPDATE;

    IF NOT FOUND OR NOT public.has_school_role(
        event_record.school_id,
        actor,
        ARRAY['teacher', 'school_director', 'hq_director']
    ) THEN
        RAISE EXCEPTION 'You cannot archive this event';
    END IF;

    UPDATE public.school_events
    SET archived_at = CASE WHEN input_archived THEN COALESCE(archived_at, NOW()) ELSE NULL END,
        archived_by = CASE WHEN input_archived THEN actor ELSE NULL END,
        updated_at = NOW()
    WHERE id = input_event_id
    RETURNING * INTO event_record;

    RETURN QUERY SELECT events.* FROM public.school_events events WHERE events.id = input_event_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_assignment_details(
    input_assignment_id UUID,
    input_title TEXT,
    input_description TEXT DEFAULT NULL,
    input_due_at TIMESTAMPTZ DEFAULT NULL,
    input_allow_resubmission BOOLEAN DEFAULT TRUE
)
RETURNS SETOF public.assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    assignment_record public.assignments%ROWTYPE;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF NULLIF(btrim(COALESCE(input_title, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Assignment title is required';
    END IF;

    SELECT * INTO assignment_record
    FROM public.assignments
    WHERE id = input_assignment_id
    FOR UPDATE;

    IF NOT FOUND OR assignment_record.assigned_by <> actor THEN
        RAISE EXCEPTION 'Only the assignment creator can edit this assignment';
    END IF;
    IF assignment_record.status = 'archived' THEN
        RAISE EXCEPTION 'Archived assignments cannot be edited';
    END IF;
    IF input_due_at IS NOT NULL
       AND input_due_at <= COALESCE(assignment_record.publish_at, assignment_record.created_at, NOW()) THEN
        RAISE EXCEPTION 'The due date must be after the assignment is published';
    END IF;

    UPDATE public.assignments
    SET title = btrim(input_title),
        description = NULLIF(btrim(COALESCE(input_description, '')), ''),
        due_at = input_due_at,
        allow_resubmission = COALESCE(input_allow_resubmission, TRUE),
        updated_at = NOW()
    WHERE id = input_assignment_id
    RETURNING * INTO assignment_record;

    INSERT INTO public.assignment_events (
        assignment_id, school_id, actor_id, event_type, metadata
    ) VALUES (
        assignment_record.id,
        assignment_record.school_id,
        actor,
        'edited',
        jsonb_build_object(
            'allow_resubmission', assignment_record.allow_resubmission,
            'due_at', assignment_record.due_at
        )
    );

    RETURN QUERY SELECT assignments.* FROM public.assignments WHERE id = input_assignment_id;
END;
$$;

DROP FUNCTION IF EXISTS public.review_assignment_submission_v2(UUID, TEXT, TEXT, TEXT);
CREATE FUNCTION public.review_assignment_submission_v2(
    input_submission_id UUID,
    input_status TEXT,
    input_reviewer_message TEXT DEFAULT NULL,
    input_idempotency_key TEXT DEFAULT NULL,
    input_score INTEGER DEFAULT NULL
)
RETURNS SETOF public.assignment_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    submission_record public.assignment_submissions%ROWTYPE;
    latest_submission_id UUID;
    assignment_record public.assignments%ROWTYPE;
    existing_result_id UUID;
    notification_id UUID;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF input_status NOT IN ('accepted', 'changes_requested') THEN
        RAISE EXCEPTION 'Review status must be accepted or changes_requested';
    END IF;
    IF input_score IS NOT NULL AND (input_score < 1 OR input_score > 10) THEN
        RAISE EXCEPTION 'Score must be between 1 and 10';
    END IF;
    IF input_status = 'changes_requested'
       AND NULLIF(btrim(COALESCE(input_reviewer_message, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Feedback is required when requesting changes';
    END IF;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended(
            actor::TEXT || ':review:' || btrim(input_idempotency_key), 0
        ));
        SELECT result_id INTO existing_result_id
        FROM public.assignment_mutation_requests
        WHERE actor_id = actor
          AND idempotency_key = btrim(input_idempotency_key)
          AND operation = 'review';
        IF existing_result_id IS NOT NULL THEN
            RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = existing_result_id;
            RETURN;
        END IF;
    END IF;

    SELECT * INTO submission_record
    FROM public.assignment_submissions
    WHERE id = input_submission_id
    FOR UPDATE;

    IF NOT FOUND OR NOT public.can_review_assignment_submission(input_submission_id, actor) THEN
        RAISE EXCEPTION 'Only the assignment creator can review this submission';
    END IF;

    SELECT id INTO latest_submission_id
    FROM public.assignment_submissions
    WHERE assignment_id = submission_record.assignment_id
      AND submitted_by = submission_record.submitted_by
    ORDER BY attempt_number DESC, submitted_at DESC
    LIMIT 1;

    IF latest_submission_id <> submission_record.id
       OR submission_record.status NOT IN ('submitted', 'resubmitted') THEN
        RAISE EXCEPTION 'Only the latest pending attempt can be reviewed';
    END IF;

    SELECT * INTO assignment_record
    FROM public.assignments
    WHERE id = submission_record.assignment_id;

    UPDATE public.assignment_submissions
    SET status = input_status,
        score = input_score,
        reviewer_message = NULLIF(btrim(COALESCE(input_reviewer_message, '')), ''),
        reviewed_by = actor,
        reviewed_at = NOW()
    WHERE id = submission_record.id
    RETURNING * INTO submission_record;

    UPDATE public.assignment_recipients
    SET completion_status = input_status,
        completed_at = CASE WHEN input_status = 'accepted' THEN NOW() ELSE NULL END
    WHERE assignment_id = assignment_record.id
      AND user_id = submission_record.submitted_by;

    IF NULLIF(btrim(COALESCE(input_reviewer_message, '')), '') IS NOT NULL THEN
        INSERT INTO public.assignment_feedback_messages (
            assignment_id, submission_id, school_id, sender_id, recipient_id, body
        ) VALUES (
            assignment_record.id, submission_record.id, assignment_record.school_id,
            actor, submission_record.submitted_by, btrim(input_reviewer_message)
        );
    END IF;

    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type, metadata)
    VALUES (
        assignment_record.id, assignment_record.school_id, actor, input_status,
        jsonb_build_object(
            'submission_id', submission_record.id,
            'recipient_id', submission_record.submitted_by,
            'attempt_number', submission_record.attempt_number,
            'score', input_score
        )
    );

    INSERT INTO public.notifications (
        school_id, title, body, category, source_type, source_id, created_by, dedupe_key
    ) VALUES (
        assignment_record.school_id,
        assignment_record.title,
        'Status: ' || initcap(replace(input_status, '_', ' '))
            || CASE WHEN input_score IS NULL THEN '' ELSE '. Score: ' || input_score::TEXT || '/10' END
            || COALESCE('. ' || NULLIF(btrim(input_reviewer_message), ''), '.'),
        'assignment_reviewed', 'assignment', assignment_record.id, actor,
        'assignment:review:' || submission_record.id::TEXT || ':' || input_status
    ) RETURNING id INTO notification_id;

    INSERT INTO public.notification_recipients (notification_id, user_id)
    VALUES (notification_id, submission_record.submitted_by)
    ON CONFLICT DO NOTHING;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        INSERT INTO public.assignment_mutation_requests (actor_id, idempotency_key, operation, result_id)
        VALUES (actor, btrim(input_idempotency_key), 'review', submission_record.id);
    END IF;

    RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = submission_record.id;
END;
$$;

-- Bring existing schools and eligible families into the chat-first lifecycle.
DO $$
DECLARE school_id UUID;
BEGIN
    FOR school_id IN SELECT id FROM public.schools LOOP
        PERFORM public.sync_school_communication_rooms(school_id);
    END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_school_director_invite(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sync_child_family_room(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sync_school_communication_rooms(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fetch_my_managed_chat_rooms(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_attendance_batch(UUID[], TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_assignment_details(UUID, TEXT, TEXT, TIMESTAMPTZ, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.review_assignment_submission_v2(UUID, TEXT, TEXT, TEXT, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_school_event_archived(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_school_director_invite(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_managed_chat_rooms(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_attendance_batch(UUID[], TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_assignment_details(UUID, TEXT, TEXT, TIMESTAMPTZ, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_assignment_submission_v2(UUID, TEXT, TEXT, TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_school_event_archived(UUID, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260727000000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
