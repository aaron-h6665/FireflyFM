BEGIN;
-- Creator identity alone must never give an onboarding recipient management
-- rights. Reuse the role-aware policy for both lifecycle and content mutations.
CREATE OR REPLACE FUNCTION public.set_assignment_status(
    input_assignment_id UUID,
    input_status TEXT
)
RETURNS SETOF public.assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    assignment_record public.assignments%ROWTYPE;
    previous_status TEXT;
    event_name TEXT;
    notification_id UUID;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF input_status IS NULL OR input_status NOT IN ('published', 'closed', 'archived') THEN
        RAISE EXCEPTION 'Status must be published, closed, or archived';
    END IF;
    SELECT * INTO assignment_record FROM public.assignments
    WHERE id = input_assignment_id FOR UPDATE;
    IF NOT FOUND OR NOT public.can_manage_assignment(input_assignment_id, actor) THEN
        RAISE EXCEPTION 'You cannot manage this assignment';
    END IF;
    IF assignment_record.status = input_status THEN
        RETURN QUERY SELECT * FROM public.assignments WHERE id = input_assignment_id; RETURN;
    END IF;
    previous_status := assignment_record.status;
    IF previous_status = 'archived' AND input_status <> 'closed' THEN
        RAISE EXCEPTION 'Archived assignments must be restored to closed';
    END IF;
    IF previous_status = 'closed' AND input_status = 'archived' THEN event_name := 'archived';
    ELSIF previous_status = 'closed' AND input_status = 'published' THEN event_name := 'reopened';
    ELSIF previous_status = 'archived' AND input_status = 'closed' THEN event_name := 'restored';
    ELSE event_name := input_status; END IF;

    UPDATE public.assignments
    SET status = input_status,
        publish_at = CASE WHEN input_status = 'published' THEN COALESCE(publish_at, NOW()) ELSE publish_at END,
        updated_at = NOW()
    WHERE id = input_assignment_id RETURNING * INTO assignment_record;

    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type, metadata)
    VALUES (assignment_record.id, assignment_record.school_id, actor, event_name,
            jsonb_build_object('previous_status', previous_status, 'new_status', input_status));

    INSERT INTO public.notifications (
        school_id, title, body, category, source_type, source_id, created_by, dedupe_key
    ) VALUES (
        assignment_record.school_id, assignment_record.title,
        CASE event_name
            WHEN 'closed' THEN 'This assignment is now closed and read-only.'
            WHEN 'reopened' THEN 'This assignment has reopened.'
            WHEN 'archived' THEN 'This assignment was archived.'
            WHEN 'restored' THEN 'This assignment was restored as closed.'
            ELSE 'This assignment is now available.'
        END,
        'assignment_lifecycle', 'assignment', assignment_record.id, actor,
        'assignment:lifecycle:' || gen_random_uuid()::TEXT
    ) RETURNING id INTO notification_id;
    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT notification_id, recipient.user_id FROM public.assignment_recipients recipient
    WHERE recipient.assignment_id = assignment_record.id ON CONFLICT DO NOTHING;

    RETURN QUERY SELECT * FROM public.assignments WHERE id = assignment_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_assignment_v2(
    input_assignment_id UUID,
    input_title TEXT,
    input_description TEXT DEFAULT NULL,
    input_due_at TIMESTAMPTZ DEFAULT NULL,
    input_allow_resubmission BOOLEAN DEFAULT TRUE,
    input_materials JSONB DEFAULT '[]'::JSONB
)
RETURNS SETOF public.assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    assignment_record public.assignments%ROWTYPE;
    material JSONB;
    material_url TEXT;
    material_path TEXT;
    expected_prefix TEXT;
    revision_id UUID;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF NULLIF(btrim(COALESCE(input_title, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Assignment title is required';
    END IF;
    IF jsonb_typeof(COALESCE(input_materials, '[]'::JSONB)) <> 'array' THEN
        RAISE EXCEPTION 'Assignment materials must be a JSON array';
    END IF;

    SELECT * INTO assignment_record FROM public.assignments
    WHERE id = input_assignment_id FOR UPDATE;
    IF NOT FOUND OR NOT public.can_manage_assignment(input_assignment_id, actor) THEN
        RAISE EXCEPTION 'Only the assignment creator can edit this assignment';
    END IF;
    IF assignment_record.status = 'archived' THEN
        RAISE EXCEPTION 'Archived assignments cannot be edited';
    END IF;
    IF input_due_at IS NOT NULL
       AND input_due_at <= COALESCE(assignment_record.publish_at, assignment_record.created_at, NOW()) THEN
        RAISE EXCEPTION 'The due date must be after the assignment is published';
    END IF;

    expected_prefix := 'schools/' || assignment_record.school_id::TEXT
        || '/assignments/' || assignment_record.id::TEXT || '/materials/';

    FOR material IN SELECT * FROM jsonb_array_elements(COALESCE(input_materials, '[]'::JSONB)) LOOP
        IF COALESCE(material->>'material_type', '') NOT IN ('article', 'link', 'image', 'video', 'file', 'mixed') THEN
            RAISE EXCEPTION 'Material type is invalid';
        END IF;
        material_url := NULLIF(btrim(COALESCE(material->>'url', '')), '');
        material_path := NULLIF(btrim(COALESCE(material->>'private_file_path', '')), '');
        IF material_url IS NOT NULL AND material_url !~* '^https?://' THEN
            RAISE EXCEPTION 'Material links must use http or https';
        END IF;
        IF material_path IS NOT NULL AND LOWER(material_path) NOT LIKE LOWER(expected_prefix) || '%'
           AND NOT EXISTS (
               SELECT 1 FROM public.assignment_materials existing
               WHERE existing.assignment_id = input_assignment_id
                 AND existing.private_file_path = material_path
           ) THEN
            RAISE EXCEPTION 'Assignment material path is invalid';
        END IF;
        IF material_url IS NULL AND material_path IS NULL THEN
            RAISE EXCEPTION 'A material must include a link or private file';
        END IF;
    END LOOP;

    UPDATE public.assignments
    SET title = btrim(input_title),
        description = NULLIF(btrim(COALESCE(input_description, '')), ''),
        due_at = input_due_at,
        allow_resubmission = COALESCE(input_allow_resubmission, TRUE),
        updated_at = NOW()
    WHERE id = input_assignment_id
    RETURNING * INTO assignment_record;

    DELETE FROM public.assignment_materials WHERE assignment_id = input_assignment_id;
    FOR material IN SELECT * FROM jsonb_array_elements(COALESCE(input_materials, '[]'::JSONB)) LOOP
        INSERT INTO public.assignment_materials (
            assignment_id, material_type, title, url, private_file_path,
            file_name, content_type
        ) VALUES (
            input_assignment_id,
            material->>'material_type',
            NULLIF(btrim(COALESCE(material->>'title', '')), ''),
            NULLIF(btrim(COALESCE(material->>'url', '')), ''),
            NULLIF(btrim(COALESCE(material->>'private_file_path', '')), ''),
            NULLIF(btrim(COALESCE(material->>'file_name', '')), ''),
            NULLIF(btrim(COALESCE(material->>'content_type', '')), '')
        );
    END LOOP;

    revision_id := public.snapshot_assignment_revision(input_assignment_id, actor);

    INSERT INTO public.assignment_events (
        assignment_id, school_id, actor_id, event_type, metadata
    ) VALUES (
        assignment_record.id, assignment_record.school_id, actor, 'edited',
        jsonb_build_object(
            'allow_resubmission', assignment_record.allow_resubmission,
            'due_at', assignment_record.due_at,
            'revision_id', revision_id,
            'material_count', jsonb_array_length(COALESCE(input_materials, '[]'::JSONB))
        )
    );

    RETURN QUERY SELECT * FROM public.assignments WHERE id = input_assignment_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version() RETURNS BIGINT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260907200000::BIGINT; $$;
NOTIFY pgrst, 'reload schema';
COMMIT;
