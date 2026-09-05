-- Forms may be connected even when they are not a complete child-intake Form.
-- Keep the warning as connection metadata so directors can arrange and repair
-- Forms without turning the setup screen into a mapping editor.

ALTER TABLE public.google_form_connections
    ADD COLUMN IF NOT EXISTS setup_warning TEXT;

CREATE OR REPLACE FUNCTION public.upsert_google_form_connection_v2(
    input_school_id UUID,
    input_credential_id UUID,
    input_form_role TEXT,
    input_form_key TEXT,
    input_form_id TEXT,
    input_form_url TEXT,
    input_form_title TEXT,
    input_google_account_email TEXT,
    input_is_required BOOLEAN,
    input_display_order INTEGER,
    input_form_snapshot JSONB,
    input_mappings JSONB,
    input_template_requirement_id UUID DEFAULT NULL
)
RETURNS SETOF public.google_form_connections
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    saved public.google_form_connections%ROWTYPE;
    mapping JSONB;
    credential_school UUID;
    resolved_requirement_id UUID;
BEGIN
    IF actor IS NULL OR NOT public.has_school_role(input_school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can connect an onboarding Google Form';
    END IF;
    IF input_form_role NOT IN ('parent', 'teacher') OR NULLIF(btrim(input_form_id), '') IS NULL
       OR input_form_url !~* '^https://docs\\.google\\.com/forms/' THEN
        RAISE EXCEPTION 'A valid authorized Google Form is required';
    END IF;
    SELECT school_id INTO credential_school FROM public.google_oauth_credentials
    WHERE id = input_credential_id AND status = 'connected';
    IF credential_school IS DISTINCT FROM input_school_id THEN
        RAISE EXCEPTION 'The selected Google account is not connected to this school';
    END IF;
    IF jsonb_typeof(input_mappings) <> 'array' THEN RAISE EXCEPTION 'Automatic Form mappings are invalid'; END IF;

    INSERT INTO public.google_form_connections (
        school_id, credential_id, form_role, form_key, form_id, form_url, form_title,
        google_account_email, credential_secret_ref, created_by, status, setup_warning, is_required,
        display_order, form_snapshot, updated_at
    ) VALUES (
        input_school_id, input_credential_id, input_form_role,
        COALESCE(NULLIF(btrim(input_form_key), ''), input_form_id), btrim(input_form_id),
        btrim(input_form_url), NULLIF(btrim(input_form_title), ''),
        NULLIF(lower(btrim(input_google_account_email)), ''), NULL, actor, 'connected',
        NULLIF(btrim(COALESCE(input_form_snapshot ->> 'setup_warning', '')), ''),
        COALESCE(input_is_required, TRUE), GREATEST(COALESCE(input_display_order, 0), 0),
        COALESCE(input_form_snapshot, '{}'::JSONB), NOW()
    ) ON CONFLICT (school_id, form_role, form_key) DO UPDATE SET
        credential_id = EXCLUDED.credential_id, form_id = EXCLUDED.form_id,
        form_url = EXCLUDED.form_url, form_title = EXCLUDED.form_title,
        google_account_email = EXCLUDED.google_account_email, credential_secret_ref = NULL,
        status = 'connected', setup_warning = EXCLUDED.setup_warning, is_required = EXCLUDED.is_required,
        display_order = EXCLUDED.display_order, form_snapshot = EXCLUDED.form_snapshot,
        last_error = NULL, updated_at = NOW()
    RETURNING * INTO saved;

    DELETE FROM public.google_form_question_mappings WHERE connection_id = saved.id;
    FOR mapping IN SELECT value FROM jsonb_array_elements(input_mappings) LOOP
        IF NULLIF(btrim(mapping ->> 'question_id'), '') IS NULL
           OR NULLIF(btrim(mapping ->> 'field_key'), '') IS NULL THEN
            RAISE EXCEPTION 'Each automatic Form mapping needs a question and field key';
        END IF;
        INSERT INTO public.google_form_question_mappings (
            connection_id, question_id, question_title, field_key, required, active, prefill_parameter, updated_at
        ) VALUES (
            saved.id, btrim(mapping ->> 'question_id'), COALESCE(NULLIF(btrim(mapping ->> 'question_title'), ''), btrim(mapping ->> 'question_id')),
            btrim(mapping ->> 'field_key'), COALESCE((mapping ->> 'required')::BOOLEAN, FALSE),
            COALESCE((mapping ->> 'active')::BOOLEAN, TRUE), NULLIF(btrim(mapping ->> 'prefill_parameter'), ''), NOW()
        );
    END LOOP;

    IF input_template_requirement_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.onboarding_template_requirements requirement
            JOIN public.onboarding_templates template ON template.id = requirement.template_id
            WHERE requirement.id = input_template_requirement_id
              AND template.school_id = input_school_id AND template.target_role = input_form_role
        ) THEN RAISE EXCEPTION 'The selected onboarding step does not belong to this Form role'; END IF;
        resolved_requirement_id := input_template_requirement_id;
    ELSE
        SELECT onboarding_template_requirement_id INTO resolved_requirement_id
        FROM public.google_form_requirement_bindings
        WHERE connection_id = saved.id;

        IF resolved_requirement_id IS NULL THEN
            SELECT requirement.id INTO resolved_requirement_id
            FROM public.onboarding_template_requirements requirement
            JOIN public.onboarding_templates template ON template.id = requirement.template_id
            WHERE template.school_id = input_school_id
              AND template.target_role = input_form_role
              AND NOT EXISTS (
                  SELECT 1
                  FROM public.google_form_requirement_bindings binding
                  JOIN public.google_form_connections connection ON connection.id = binding.connection_id
                  WHERE binding.onboarding_template_requirement_id = requirement.id
                    AND connection.school_id = input_school_id
                    AND connection.form_role = input_form_role
                    AND connection.id <> saved.id
                    AND connection.status <> 'disconnected'
              )
            ORDER BY requirement.position, requirement.created_at
            LIMIT 1;
        END IF;
    END IF;

    IF COALESCE(input_is_required, TRUE) THEN
        IF resolved_requirement_id IS NULL THEN
            RAISE EXCEPTION 'Add an onboarding step before connecting this Form. FireflyFM will automatically assign the next available step.';
        END IF;
        INSERT INTO public.google_form_requirement_bindings (
            connection_id, onboarding_template_requirement_id, published_snapshot, updated_at
        ) VALUES (saved.id, resolved_requirement_id,
                  jsonb_build_object('form', COALESCE(input_form_snapshot, '{}'::JSONB), 'mappings', input_mappings), NOW())
        ON CONFLICT (connection_id) DO UPDATE SET
            onboarding_template_requirement_id = EXCLUDED.onboarding_template_requirement_id,
            published_snapshot = EXCLUDED.published_snapshot, updated_at = NOW();
    ELSE
        DELETE FROM public.google_form_requirement_bindings WHERE connection_id = saved.id;
    END IF;
    RETURN NEXT saved;
END;
$$;
