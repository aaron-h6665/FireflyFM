-- Apply this focused repair when Add Requirement reports that the Supabase
-- schema cache is stale. Optional JSON keys may be omitted by older clients,
-- so every parameter after input_template_id has a database default.

CREATE OR REPLACE FUNCTION public.save_onboarding_template_requirement(
    input_template_id UUID,
    input_requirement_id UUID DEFAULT NULL,
    input_title TEXT DEFAULT NULL,
    input_description TEXT DEFAULT NULL,
    input_subject_scope TEXT DEFAULT 'member',
    input_position INTEGER DEFAULT 0,
    input_attachments JSONB DEFAULT '[]'::JSONB
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
    SELECT * INTO template_record
    FROM public.onboarding_templates
    WHERE id = input_template_id;

    IF NOT FOUND OR template_record.status <> 'draft' THEN
        RAISE EXCEPTION 'Requirements can only be changed in a draft template';
    END IF;
    IF NOT public.is_onboarding_template_manager(
        template_record.school_id,
        template_record.target_role,
        actor
    ) THEN
        RAISE EXCEPTION 'You cannot manage this onboarding template';
    END IF;
    IF NULLIF(BTRIM(COALESCE(input_title, '')), '') IS NULL THEN
        RAISE EXCEPTION 'A requirement title is required';
    END IF;
    IF input_subject_scope NOT IN ('member', 'child')
       OR (input_subject_scope = 'child' AND template_record.target_role <> 'parent') THEN
        RAISE EXCEPTION 'Child requirements are available only for parent templates';
    END IF;

    IF input_requirement_id IS NULL THEN
        INSERT INTO public.onboarding_template_requirements (
            template_id, position, title, description, subject_scope
        ) VALUES (
            template_record.id,
            GREATEST(COALESCE(input_position, 0), 0),
            BTRIM(input_title),
            NULLIF(BTRIM(COALESCE(input_description, '')), ''),
            input_subject_scope
        )
        RETURNING * INTO saved_requirement;
    ELSE
        UPDATE public.onboarding_template_requirements
        SET title = BTRIM(input_title),
            description = NULLIF(BTRIM(COALESCE(input_description, '')), ''),
            subject_scope = input_subject_scope,
            updated_at = NOW()
        WHERE id = input_requirement_id
          AND template_id = template_record.id
        RETURNING * INTO saved_requirement;

        IF saved_requirement.id IS NULL THEN
            RAISE EXCEPTION 'Requirement not found in this draft';
        END IF;
    END IF;

    DELETE FROM public.onboarding_template_attachments
    WHERE requirement_id = saved_requirement.id;

    INSERT INTO public.onboarding_template_attachments (
        requirement_id, position, private_file_path, file_name, content_type
    )
    SELECT
        saved_requirement.id,
        attachment.ordinality::INTEGER - 1,
        attachment.value->>'private_file_path',
        attachment.value->>'file_name',
        NULLIF(attachment.value->>'content_type', '')
    FROM jsonb_array_elements(
        COALESCE(input_attachments, '[]'::JSONB)
    ) WITH ORDINALITY AS attachment(value, ordinality)
    WHERE NULLIF(attachment.value->>'private_file_path', '') IS NOT NULL
      AND NULLIF(attachment.value->>'file_name', '') IS NOT NULL;

    RETURN QUERY
    SELECT *
    FROM public.onboarding_template_requirements
    WHERE id = saved_requirement.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_onboarding_template_requirement(
    UUID, UUID, TEXT, TEXT, TEXT, INTEGER, JSONB
) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Confirms Postgres recorded defaults for the optional RPC arguments.
SELECT
    proname,
    pronargdefaults
FROM pg_proc
WHERE oid = 'public.save_onboarding_template_requirement(uuid,uuid,text,text,text,integer,jsonb)'::regprocedure;
