-- Notify each newly added HQ chat participant, including participants added
-- after room creation. Notifications remain school-scoped for delivery/RLS,
-- while routing to the cross-school room itself.

CREATE OR REPLACE FUNCTION public.notify_hq_chat_participant_added()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    room_record public.chat_rooms%ROWTYPE;
    notification_school_id UUID;
    actor UUID;
BEGIN
    SELECT * INTO room_record
    FROM public.chat_rooms
    WHERE id = NEW.room_id;

    IF NOT FOUND OR room_record.room_type <> 'hq_custom' THEN
        RETURN NEW;
    END IF;

    actor := COALESCE(auth.uid(), room_record.created_by);
    IF NEW.user_id = actor THEN
        RETURN NEW;
    END IF;

    SELECT membership.school_id INTO notification_school_id
    FROM public.school_memberships membership
    WHERE membership.user_id = NEW.user_id
      AND membership.active = TRUE
      AND (
          membership.role = 'hq_director'
          OR (
              membership.access_state = 'full'
              AND membership.role IN ('parent', 'teacher', 'school_director')
          )
      )
    ORDER BY (membership.role = 'hq_director') DESC, membership.created_at DESC
    LIMIT 1;

    IF notification_school_id IS NULL THEN
        RETURN NEW;
    END IF;

    PERFORM public.enqueue_workflow_notification(
        notification_school_id,
        'Added to ' || room_record.name,
        'An HQ director added you to a group chat.',
        'chat_invitation',
        'chat_room',
        room_record.id,
        ARRAY[NEW.user_id],
        'hq-chat:participant:added:' || room_record.id::TEXT || ':' || NEW.user_id::TEXT,
        'routine',
        jsonb_build_object('type', 'chat_room', 'id', room_record.id),
        actor
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_hq_chat_participant_added_trigger
ON public.chat_participants;

CREATE TRIGGER notify_hq_chat_participant_added_trigger
AFTER INSERT ON public.chat_participants
FOR EACH ROW
EXECUTE FUNCTION public.notify_hq_chat_participant_added();

REVOKE ALL ON FUNCTION public.notify_hq_chat_participant_added() FROM PUBLIC;
