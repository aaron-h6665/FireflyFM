BEGIN;

-- Daily activity options now follow the classroom feed vocabulary used by
-- modern childcare tools while preserving all existing Firefly event values.
ALTER TABLE public.child_care_events
    DROP CONSTRAINT IF EXISTS child_care_events_event_type_check;

ALTER TABLE public.child_care_events
    ADD CONSTRAINT child_care_events_event_type_check CHECK (event_type IN (
        'meal', 'bottle', 'nap', 'potty', 'diaper', 'medication',
        'health_check', 'activity', 'observation', 'kudos', 'incident',
        'note', 'photo'
    ));

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
    IF input_event_type NOT IN (
        'meal', 'bottle', 'nap', 'potty', 'diaper', 'medication',
        'health_check', 'activity', 'observation', 'kudos', 'incident',
        'note', 'photo'
    ) THEN
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

    IF input_visibility = 'parent' AND input_event_type IN ('medication', 'health_check', 'incident') THEN
        SELECT array_agg(guardian.guardian_id) INTO guardian_ids
        FROM public.child_guardians guardian
        WHERE guardian.child_id = input_child_id
          AND guardian.verification_status = 'verified' AND guardian.ended_at IS NULL;
        PERFORM public.enqueue_workflow_notification(
            child_record.school_id,
            CASE
                WHEN input_event_type = 'medication' THEN 'Medication administered'
                WHEN input_event_type = 'incident' THEN 'Incident update'
                ELSE 'Health update'
            END,
            child_record.first_name || ' has a new ' || replace(input_event_type, '_', ' ') || ' update.',
            'care_' || input_event_type, 'child_care_event', saved_event.id,
            guardian_ids, 'care:' || input_event_type || ':' || saved_event.id::TEXT,
            CASE WHEN input_event_type IN ('health_check', 'incident') THEN 'urgent' ELSE 'important' END,
            jsonb_build_object('type', 'child_care_event', 'id', saved_event.id, 'child_id', input_child_id), actor
        );
    END IF;
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
    VALUES (child_record.school_id, actor, 'recorded', 'child_care_event', saved_event.id);
    RETURN QUERY SELECT * FROM public.child_care_events WHERE id = saved_event.id;
END;
$$;

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
            WHEN 'activity' THEN 'Learning activity'
            WHEN 'observation' THEN 'Child observation'
            WHEN 'kudos' THEN 'Kudos and milestone'
            WHEN 'incident' THEN 'Incident update'
            WHEN 'photo' THEN 'Photo update'
            ELSE 'Care note'
        END;
        source_label := source_label || COALESCE(
            ' — ' || NULLIF(concat_ws(
                ' • ',
                NULLIF(NEW.details->>'summary', ''),
                NULLIF(NEW.details->>'amount', ''),
                NULLIF(NEW.details->>'outcome', ''),
                NULLIF(NEW.details->>'dosage_given', '')
            ), ''),
            ''
        );
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
        source_label := source_label || COALESCE(' — ' || NULLIF(NEW.details->>'message', ''), '');
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

COMMIT;
