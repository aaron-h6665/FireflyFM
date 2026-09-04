-- Allow the author (or an authorized school director) to correct or remove
-- structured chat entries without widening ordinary message permissions.

CREATE OR REPLACE FUNCTION public.update_child_care_event_from_chat(
    input_event_id UUID,
    input_event_type TEXT,
    input_occurred_at TIMESTAMPTZ,
    input_details JSONB,
    input_developmental_domains TEXT[] DEFAULT ARRAY[]::TEXT[],
    input_report_highlight BOOLEAN DEFAULT FALSE
)
RETURNS SETOF public.child_care_events
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    event_record public.child_care_events%ROWTYPE;
    previous_snapshot JSONB;
BEGIN
    SELECT * INTO event_record FROM public.child_care_events
    WHERE id = input_event_id FOR UPDATE;
    IF NOT FOUND OR NOT public.can_staff_access_child(event_record.child_id, actor, ARRAY['teacher', 'school_director'])
       OR (event_record.recorded_by <> actor AND NOT public.has_school_role(event_record.school_id, actor, ARRAY['school_director'])) THEN
        RAISE EXCEPTION 'You cannot update this daily activity';
    END IF;
    IF input_event_type NOT IN ('meal', 'bottle', 'nap', 'potty', 'diaper', 'medication', 'health_check', 'activity', 'observation', 'kudos', 'incident', 'note', 'photo') THEN
        RAISE EXCEPTION 'Invalid care event type';
    END IF;
    IF jsonb_typeof(COALESCE(input_details, '{}'::JSONB)) <> 'object' THEN
        RAISE EXCEPTION 'Activity details must be an object';
    END IF;
    IF NOT COALESCE(input_developmental_domains, ARRAY[]::TEXT[]) <@ ARRAY['communication_language', 'social_emotional', 'cognitive', 'physical_motor', 'creative', 'independence_self_care']::TEXT[] THEN
        RAISE EXCEPTION 'Invalid developmental domain';
    END IF;
    previous_snapshot := to_jsonb(event_record);
    UPDATE public.child_care_events
    SET event_type = input_event_type,
        occurred_at = COALESCE(input_occurred_at, occurred_at),
        details = COALESCE(input_details, '{}'::JSONB),
        developmental_domains = COALESCE(input_developmental_domains, ARRAY[]::TEXT[]),
        report_highlight = COALESCE(input_report_highlight, FALSE)
    WHERE id = input_event_id
    RETURNING * INTO event_record;
    INSERT INTO public.child_care_event_revisions (event_id, school_id, child_id, corrected_by, reason, previous_snapshot, revised_snapshot)
    VALUES (event_record.id, event_record.school_id, event_record.child_id, actor, 'Updated from family chat', previous_snapshot, to_jsonb(event_record));
    UPDATE public.messages
    SET text = 'Activity update — ' || replace(event_record.event_type, '_', ' '), updated_at = NOW()
    WHERE (structured_source_type = 'child_care_events' AND structured_source_id = input_event_id)
       OR linked_care_event_id = input_event_id;
    RETURN QUERY SELECT * FROM public.child_care_events WHERE id = event_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_child_care_event_from_chat(input_event_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    event_record public.child_care_events%ROWTYPE;
BEGIN
    SELECT * INTO event_record FROM public.child_care_events WHERE id = input_event_id FOR UPDATE;
    IF NOT FOUND OR NOT public.can_staff_access_child(event_record.child_id, actor, ARRAY['teacher', 'school_director'])
       OR (event_record.recorded_by <> actor AND NOT public.has_school_role(event_record.school_id, actor, ARRAY['school_director'])) THEN
        RAISE EXCEPTION 'You cannot delete this daily activity';
    END IF;
    UPDATE public.messages SET linked_care_event_id = NULL WHERE linked_care_event_id = input_event_id;
    UPDATE public.messages
    SET text = 'Activity deleted', updated_at = NOW(), is_deleted = TRUE
    WHERE (structured_source_type = 'child_care_events' AND structured_source_id = input_event_id)
       OR linked_care_event_id = input_event_id;
    DELETE FROM public.child_care_event_revisions WHERE event_id = input_event_id;
    DELETE FROM public.child_care_events WHERE id = input_event_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_family_request_from_chat(
    input_request_id UUID,
    input_request_type TEXT,
    input_details JSONB
)
RETURNS SETOF public.family_requests
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    request_record public.family_requests%ROWTYPE;
BEGIN
    SELECT * INTO request_record FROM public.family_requests WHERE id = input_request_id FOR UPDATE;
    IF NOT FOUND OR (request_record.requested_by <> actor AND NOT public.has_school_role(request_record.school_id, actor, ARRAY['school_director'])) THEN
        RAISE EXCEPTION 'You cannot update this family request';
    END IF;
    IF input_request_type NOT IN ('absence', 'pickup_change', 'medication', 'general') OR jsonb_typeof(COALESCE(input_details, '{}'::JSONB)) <> 'object' THEN
        RAISE EXCEPTION 'Invalid family request';
    END IF;
    UPDATE public.family_requests SET request_type = input_request_type, details = COALESCE(input_details, '{}'::JSONB), updated_at = NOW()
    WHERE id = input_request_id RETURNING * INTO request_record;
    UPDATE public.messages
    SET text = 'Family request — ' || replace(request_record.request_type, '_', ' '), updated_at = NOW()
    WHERE structured_source_type = 'family_requests' AND structured_source_id = input_request_id;
    RETURN QUERY SELECT * FROM public.family_requests WHERE id = request_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_family_request_from_chat(input_event_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    request_record public.family_requests%ROWTYPE;
BEGIN
    SELECT * INTO request_record FROM public.family_requests WHERE id = input_event_id FOR UPDATE;
    IF NOT FOUND OR (request_record.requested_by <> actor AND NOT public.has_school_role(request_record.school_id, actor, ARRAY['school_director'])) THEN
        RAISE EXCEPTION 'You cannot delete this family request';
    END IF;
    UPDATE public.messages
    SET text = 'Family request deleted', updated_at = NOW(), is_deleted = TRUE
    WHERE structured_source_type = 'family_requests' AND structured_source_id = input_event_id;
    DELETE FROM public.family_requests WHERE id = input_event_id;
END;
$$;

REVOKE ALL ON FUNCTION public.update_child_care_event_from_chat(UUID, TEXT, TIMESTAMPTZ, JSONB, TEXT[], BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_child_care_event_from_chat(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_family_request_from_chat(UUID, TEXT, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_family_request_from_chat(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_child_care_event_from_chat(UUID, TEXT, TIMESTAMPTZ, JSONB, TEXT[], BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_child_care_event_from_chat(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_family_request_from_chat(UUID, TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_family_request_from_chat(UUID) TO authenticated;
