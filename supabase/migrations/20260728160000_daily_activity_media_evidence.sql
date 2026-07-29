-- Link child-scoped chat media to structured daily activities without copying
-- the attachment or creating a second timeline message. The activity remains
-- the reporting source of truth and the original chat message remains the
-- evidence source visible to the family.
BEGIN;

ALTER TABLE public.child_care_events
    ADD COLUMN IF NOT EXISTS source_message_id UUID,
    ADD COLUMN IF NOT EXISTS developmental_domains TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    ADD COLUMN IF NOT EXISTS report_highlight BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.messages
    ADD COLUMN IF NOT EXISTS linked_care_event_id UUID;

ALTER TABLE public.child_care_events
    DROP CONSTRAINT IF EXISTS child_care_events_source_message_id_fkey;
ALTER TABLE public.child_care_events
    ADD CONSTRAINT child_care_events_source_message_id_fkey
    FOREIGN KEY (source_message_id) REFERENCES public.messages(id) ON DELETE SET NULL;

ALTER TABLE public.messages
    DROP CONSTRAINT IF EXISTS messages_linked_care_event_id_fkey;
ALTER TABLE public.messages
    ADD CONSTRAINT messages_linked_care_event_id_fkey
    FOREIGN KEY (linked_care_event_id) REFERENCES public.child_care_events(id) ON DELETE SET NULL;

ALTER TABLE public.child_care_events
    DROP CONSTRAINT IF EXISTS child_care_events_developmental_domains_check;
ALTER TABLE public.child_care_events
    ADD CONSTRAINT child_care_events_developmental_domains_check CHECK (
        developmental_domains <@ ARRAY[
            'communication_language', 'social_emotional', 'cognitive',
            'physical_motor', 'creative', 'independence_self_care'
        ]::TEXT[]
    );

CREATE UNIQUE INDEX IF NOT EXISTS idx_child_care_events_source_message
    ON public.child_care_events(source_message_id)
    WHERE source_message_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_linked_care_event
    ON public.messages(linked_care_event_id)
    WHERE linked_care_event_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_child_care_events_report_evidence
    ON public.child_care_events(child_id, report_highlight, occurred_at DESC);

CREATE TABLE IF NOT EXISTS public.child_care_event_revisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.child_care_events(id) ON DELETE RESTRICT,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
    corrected_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    reason TEXT NOT NULL CHECK (NULLIF(btrim(reason), '') IS NOT NULL),
    previous_snapshot JSONB NOT NULL CHECK (jsonb_typeof(previous_snapshot) = 'object'),
    revised_snapshot JSONB NOT NULL CHECK (jsonb_typeof(revised_snapshot) = 'object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.child_care_event_revisions ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_child_care_event_revisions_event_created
    ON public.child_care_event_revisions(event_id, created_at DESC);

DROP POLICY IF EXISTS "Authorized staff can view care event revisions" ON public.child_care_event_revisions;
CREATE POLICY "Authorized staff can view care event revisions"
    ON public.child_care_event_revisions FOR SELECT
    USING (public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director']));

CREATE OR REPLACE FUNCTION public.record_child_care_event_v2(
    input_child_id UUID,
    input_event_type TEXT,
    input_occurred_at TIMESTAMPTZ,
    input_details JSONB,
    input_visibility TEXT,
    input_medication_task_id UUID DEFAULT NULL,
    input_idempotency_key TEXT DEFAULT NULL,
    input_source_message_id UUID DEFAULT NULL,
    input_developmental_domains TEXT[] DEFAULT ARRAY[]::TEXT[],
    input_report_highlight BOOLEAN DEFAULT FALSE
)
RETURNS SETOF public.child_care_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    child_record public.children%ROWTYPE;
    message_record public.messages%ROWTYPE;
    room_record public.chat_rooms%ROWTYPE;
    saved_event public.child_care_events%ROWTYPE;
    guardian_ids UUID[];
    normalized_domains TEXT[] := COALESCE(input_developmental_domains, ARRAY[]::TEXT[]);
BEGIN
    SELECT * INTO child_record
    FROM public.children
    WHERE id = input_child_id AND active = TRUE;
    IF NOT FOUND OR NOT public.can_staff_access_child(input_child_id, actor, ARRAY['teacher', 'school_director']) THEN
        RAISE EXCEPTION 'You cannot record care for this child';
    END IF;
    IF input_event_type NOT IN (
        'meal', 'bottle', 'nap', 'potty', 'diaper', 'medication',
        'health_check', 'activity', 'observation', 'kudos', 'incident',
        'note', 'photo'
    ) THEN RAISE EXCEPTION 'Invalid care event type'; END IF;
    IF input_visibility NOT IN ('parent', 'staff_only') THEN RAISE EXCEPTION 'Invalid visibility'; END IF;
    IF jsonb_typeof(COALESCE(input_details, '{}'::JSONB)) <> 'object' THEN RAISE EXCEPTION 'Details must be an object'; END IF;
    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN RAISE EXCEPTION 'An idempotency key is required'; END IF;
    IF NOT normalized_domains <@ ARRAY[
        'communication_language', 'social_emotional', 'cognitive',
        'physical_motor', 'creative', 'independence_self_care'
    ]::TEXT[] THEN RAISE EXCEPTION 'Invalid developmental domain'; END IF;

    IF input_source_message_id IS NOT NULL THEN
        SELECT message.* INTO message_record
        FROM public.messages message
        WHERE message.id = input_source_message_id;
        IF NOT FOUND OR message_record.is_deleted
           OR (message_record.media_path IS NULL AND message_record.media_url IS NULL
               AND message_record.audio_path IS NULL AND message_record.audio_url IS NULL) THEN
            RAISE EXCEPTION 'The source media message is unavailable';
        END IF;
        SELECT * INTO room_record FROM public.chat_rooms WHERE id = message_record.room_id;
        IF NOT FOUND OR room_record.room_type <> 'child_family'
           OR room_record.subject_child_id IS DISTINCT FROM input_child_id
           OR room_record.deleted_at IS NOT NULL OR room_record.archived_at IS NOT NULL
           OR NOT public.is_chat_room_member(room_record.id, actor) THEN
            RAISE EXCEPTION 'The source message is not in this child family room';
        END IF;
        IF message_record.sender_id <> actor
           AND NOT public.has_school_role(child_record.school_id, actor, ARRAY['school_director']) THEN
            RAISE EXCEPTION 'Only the sender or school director can label this media';
        END IF;
        IF input_visibility <> 'parent' THEN
            RAISE EXCEPTION 'Family chat media can only be linked to a parent-visible activity';
        END IF;
    END IF;

    IF input_event_type = 'photo' AND (
        NULLIF(btrim(COALESCE(input_details->>'photo_path', '')), '') IS NULL
        OR input_details->>'photo_path' NOT LIKE (
            'schools/' || child_record.school_id::TEXT || '/care_events/' || input_child_id::TEXT
            || '/' || input_visibility || '/' || actor::TEXT || '/%'
        )
    ) THEN RAISE EXCEPTION 'Photo care events require a private photo uploaded by the recording staff member'; END IF;

    INSERT INTO public.child_care_events (
        school_id, child_id, event_type, occurred_at, details, visibility,
        recorded_by, source_medication_task_id, idempotency_key,
        source_message_id, developmental_domains, report_highlight
    ) VALUES (
        child_record.school_id, input_child_id, input_event_type,
        COALESCE(input_occurred_at, NOW()), COALESCE(input_details, '{}'::JSONB),
        input_visibility, actor, input_medication_task_id, btrim(input_idempotency_key),
        input_source_message_id, normalized_domains, COALESCE(input_report_highlight, FALSE)
    )
    ON CONFLICT (recorded_by, idempotency_key)
    DO UPDATE SET idempotency_key = EXCLUDED.idempotency_key
    RETURNING * INTO saved_event;

    IF saved_event.child_id IS DISTINCT FROM input_child_id
       OR saved_event.event_type IS DISTINCT FROM input_event_type
       OR saved_event.source_message_id IS DISTINCT FROM input_source_message_id THEN
        RAISE EXCEPTION 'The idempotency key was already used for a different care event';
    END IF;

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
    VALUES (
        child_record.school_id, actor,
        CASE WHEN input_source_message_id IS NULL THEN 'recorded' ELSE 'recorded_from_chat_media' END,
        'child_care_event', saved_event.id
    );
    RETURN QUERY SELECT * FROM public.child_care_events WHERE id = saved_event.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.label_chat_message_as_activity(
    input_message_id UUID,
    input_event_type TEXT,
    input_summary TEXT DEFAULT NULL,
    input_developmental_domains TEXT[] DEFAULT ARRAY[]::TEXT[],
    input_report_highlight BOOLEAN DEFAULT TRUE,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.child_care_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    message_record public.messages%ROWTYPE;
    room_record public.chat_rooms%ROWTYPE;
    existing_event public.child_care_events%ROWTYPE;
    details JSONB;
BEGIN
    IF input_event_type NOT IN ('activity', 'observation', 'kudos', 'note') THEN
        RAISE EXCEPTION 'Chat media can only be labeled as a learning activity, observation, milestone, or note';
    END IF;
    SELECT * INTO message_record FROM public.messages WHERE id = input_message_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'The source media message is unavailable'; END IF;
    SELECT * INTO room_record FROM public.chat_rooms WHERE id = message_record.room_id;
    IF NOT FOUND OR room_record.room_type <> 'child_family'
       OR room_record.subject_child_id IS NULL
       OR room_record.deleted_at IS NOT NULL OR room_record.archived_at IS NOT NULL
       OR NOT public.is_chat_room_member(room_record.id, actor)
       OR NOT public.can_staff_access_child(
           room_record.subject_child_id, actor, ARRAY['teacher', 'school_director']
       ) THEN
        RAISE EXCEPTION 'The source message is not in a child family room';
    END IF;
    IF message_record.sender_id <> actor
       AND NOT public.has_school_role(room_record.school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only the sender or school director can label this media';
    END IF;
    IF message_record.linked_care_event_id IS NOT NULL THEN
        RETURN QUERY SELECT * FROM public.child_care_events WHERE id = message_record.linked_care_event_id;
        RETURN;
    END IF;
    details := jsonb_strip_nulls(jsonb_build_object(
        'summary', NULLIF(btrim(COALESCE(input_summary, '')), ''),
        'attachment_name', message_record.attachment_name,
        'media_kind', CASE
            WHEN message_record.audio_path IS NOT NULL OR message_record.audio_url IS NOT NULL THEN 'audio'
            WHEN COALESCE(message_record.attachment_type, '') LIKE 'video/%' THEN 'video'
            ELSE 'photo'
        END
    ));
    SELECT * INTO existing_event
    FROM public.record_child_care_event_v2(
        room_record.subject_child_id, input_event_type, message_record.created_at,
        details, 'parent', NULL, input_idempotency_key, input_message_id,
        input_developmental_domains, input_report_highlight
    ) LIMIT 1;
    RETURN QUERY SELECT * FROM public.child_care_events WHERE id = existing_event.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.correct_linked_child_activity(
    input_event_id UUID,
    input_event_type TEXT,
    input_summary TEXT DEFAULT NULL,
    input_developmental_domains TEXT[] DEFAULT ARRAY[]::TEXT[],
    input_report_highlight BOOLEAN DEFAULT TRUE,
    input_reason TEXT DEFAULT 'Updated linked activity label'
)
RETURNS SETOF public.child_care_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    event_record public.child_care_events%ROWTYPE;
    previous_snapshot JSONB;
    revised_details JSONB;
    normalized_domains TEXT[] := COALESCE(input_developmental_domains, ARRAY[]::TEXT[]);
BEGIN
    SELECT * INTO event_record FROM public.child_care_events WHERE id = input_event_id FOR UPDATE;
    IF NOT FOUND OR event_record.source_message_id IS NULL THEN
        RAISE EXCEPTION 'The linked daily activity was not found';
    END IF;
    IF NOT public.can_staff_access_child(
        event_record.child_id, actor, ARRAY['teacher', 'school_director']
    ) THEN
        RAISE EXCEPTION 'You cannot correct care for this child';
    END IF;
    IF event_record.recorded_by <> actor
       AND NOT public.has_school_role(event_record.school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only the recorder or school director can correct this activity';
    END IF;
    IF input_event_type NOT IN ('activity', 'observation', 'kudos', 'note') THEN
        RAISE EXCEPTION 'Invalid linked activity type';
    END IF;
    IF NOT normalized_domains <@ ARRAY[
        'communication_language', 'social_emotional', 'cognitive',
        'physical_motor', 'creative', 'independence_self_care'
    ]::TEXT[] THEN RAISE EXCEPTION 'Invalid developmental domain'; END IF;
    IF NULLIF(btrim(COALESCE(input_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'A correction reason is required';
    END IF;

    previous_snapshot := to_jsonb(event_record);
    revised_details := (event_record.details - 'summary') || CASE
        WHEN NULLIF(btrim(COALESCE(input_summary, '')), '') IS NULL THEN '{}'::JSONB
        ELSE jsonb_build_object('summary', btrim(input_summary))
    END;
    UPDATE public.child_care_events
    SET event_type = input_event_type,
        details = revised_details,
        developmental_domains = normalized_domains,
        report_highlight = COALESCE(input_report_highlight, FALSE)
    WHERE id = input_event_id
    RETURNING * INTO event_record;

    INSERT INTO public.child_care_event_revisions (
        event_id, school_id, child_id, corrected_by, reason,
        previous_snapshot, revised_snapshot
    ) VALUES (
        event_record.id, event_record.school_id, event_record.child_id, actor,
        btrim(input_reason), previous_snapshot, to_jsonb(event_record)
    );
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
    VALUES (event_record.school_id, actor, 'corrected', 'child_care_event', event_record.id);
    RETURN QUERY SELECT * FROM public.child_care_events WHERE id = event_record.id;
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
        IF NEW.source_message_id IS NOT NULL THEN
            UPDATE public.messages
            SET linked_care_event_id = NEW.id
            WHERE id = NEW.source_message_id;
            RETURN NEW;
        END IF;
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
                ' • ', NULLIF(NEW.details->>'summary', ''),
                NULLIF(NEW.details->>'amount', ''), NULLIF(NEW.details->>'outcome', ''),
                NULLIF(NEW.details->>'dosage_given', '')
            ), ''), ''
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
      AND room.deleted_at IS NULL AND room.archived_at IS NULL
    LIMIT 1;
    IF target_room_id IS NULL THEN RETURN NEW; END IF;

    INSERT INTO public.messages (
        room_id, school_id, sender_id, text, entry_kind,
        structured_source_type, structured_source_id, created_at, is_deleted
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

CREATE OR REPLACE FUNCTION public.guard_linked_activity_message_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF OLD.linked_care_event_id IS NOT NULL
       AND OLD.is_deleted = FALSE AND NEW.is_deleted = TRUE THEN
        RAISE EXCEPTION 'A message saved to the daily log cannot be deleted';
    END IF;
    IF OLD.linked_care_event_id IS NOT NULL
       AND NEW.linked_care_event_id IS DISTINCT FROM OLD.linked_care_event_id THEN
        RAISE EXCEPTION 'A daily log evidence link cannot be changed';
    END IF;
    IF OLD.linked_care_event_id IS NOT NULL AND (
        NEW.room_id IS DISTINCT FROM OLD.room_id
        OR NEW.school_id IS DISTINCT FROM OLD.school_id
        OR NEW.sender_id IS DISTINCT FROM OLD.sender_id
        OR NEW.created_at IS DISTINCT FROM OLD.created_at
        OR NEW.media_path IS DISTINCT FROM OLD.media_path
        OR NEW.media_url IS DISTINCT FROM OLD.media_url
        OR NEW.audio_path IS DISTINCT FROM OLD.audio_path
        OR NEW.audio_url IS DISTINCT FROM OLD.audio_url
        OR NEW.attachment_type IS DISTINCT FROM OLD.attachment_type
        OR NEW.attachment_name IS DISTINCT FROM OLD.attachment_name
        OR NEW.attachment_size IS DISTINCT FROM OLD.attachment_size
    ) THEN
        RAISE EXCEPTION 'Daily log evidence cannot be altered';
    END IF;
    IF OLD.linked_care_event_id IS NULL AND NEW.linked_care_event_id IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM public.child_care_events event
           WHERE event.id = NEW.linked_care_event_id
             AND event.source_message_id = OLD.id
       ) THEN
        RAISE EXCEPTION 'The daily log evidence link is invalid';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS guard_linked_activity_message_deletion_trigger ON public.messages;
DROP TRIGGER IF EXISTS guard_linked_activity_message_mutation_trigger ON public.messages;
CREATE TRIGGER guard_linked_activity_message_mutation_trigger
    BEFORE UPDATE ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.guard_linked_activity_message_mutation();

REVOKE ALL ON FUNCTION public.record_child_care_event_v2(UUID, TEXT, TIMESTAMPTZ, JSONB, TEXT, UUID, TEXT, UUID, TEXT[], BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.label_chat_message_as_activity(UUID, TEXT, TEXT, TEXT[], BOOLEAN, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.correct_linked_child_activity(UUID, TEXT, TEXT, TEXT[], BOOLEAN, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_child_care_event_v2(UUID, TEXT, TIMESTAMPTZ, JSONB, TEXT, UUID, TEXT, UUID, TEXT[], BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.label_chat_message_as_activity(UUID, TEXT, TEXT, TEXT[], BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.correct_linked_child_activity(UUID, TEXT, TEXT, TEXT[], BOOLEAN, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260728160000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
