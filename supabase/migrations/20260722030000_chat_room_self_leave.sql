-- Allow invited teachers and parents to leave director-managed rooms while
-- preserving immediate access revocation and participant audit history.

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
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO room_record
    FROM public.chat_rooms
    WHERE id = input_room_id AND deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Chat room was not found';
    END IF;

    SELECT membership.role INTO actor_role
    FROM public.school_memberships membership
    WHERE membership.school_id = room_record.school_id
      AND membership.user_id = actor
      AND membership.active = TRUE
      AND membership.role IN ('parent', 'teacher')
    ORDER BY CASE membership.role WHEN 'teacher' THEN 0 ELSE 1 END
    LIMIT 1;

    IF actor_role IS NULL THEN
        RAISE EXCEPTION 'Only parent and teacher participants can leave a room';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.chat_participants participant
        WHERE participant.room_id = input_room_id
          AND participant.user_id = actor
    ) THEN
        RAISE EXCEPTION 'You are not a participant in this room';
    END IF;

    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    ) VALUES (
        input_room_id, room_record.school_id, actor, 'removed', actor
    );

    DELETE FROM public.chat_participants participant
    WHERE participant.room_id = input_room_id
      AND participant.user_id = actor;

    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id,
        metadata
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
        'A parent or teacher left this group chat.',
        'chat_participant_left',
        'chat_room',
        input_room_id,
        director_ids,
        'chat:participant:left:' || workflow_event_id::TEXT,
        'routine',
        jsonb_build_object('type', 'chat_room', 'id', input_room_id),
        actor
    );
END;
$$;

REVOKE ALL ON FUNCTION public.leave_managed_chat_room(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leave_managed_chat_room(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260722030000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
