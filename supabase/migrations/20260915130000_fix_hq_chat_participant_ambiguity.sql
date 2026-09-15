-- The table-returning function exposes room_id/user_id as PL/pgSQL variables.
-- Referencing those names in an ON CONFLICT column list is therefore ambiguous.
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
        SELECT 1
        FROM public.chat_participants participant
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
                       SELECT 1
                       FROM public.school_memberships membership
                       WHERE membership.user_id = selected.user_id
                         AND membership.active = TRUE
                         AND membership.role IN ('teacher', 'school_director')
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

REVOKE ALL ON FUNCTION public.set_director_chat_participants(UUID, UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_director_chat_participants(UUID, UUID[]) TO authenticated;
