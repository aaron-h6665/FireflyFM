-- Parent onboarding is one ordered timeline. Forms and an optional payment
-- share the template requirement order, while each Form keeps its immutable
-- response mapping and each invoice remains manually reviewed.

ALTER TABLE public.role_invites
    ADD COLUMN IF NOT EXISTS is_onboarding_payment_payer BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE public.school_memberships
    ADD COLUMN IF NOT EXISTS is_onboarding_payment_payer BOOLEAN NOT NULL DEFAULT FALSE;

-- Only responses submitted after a Form was assigned to this timeline version
-- may be considered. Reusing the same Google Form must not re-import an old
-- response into a later parent cohort.
ALTER TABLE public.google_form_connections
    ADD COLUMN IF NOT EXISTS response_min_created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

UPDATE public.google_form_connections
SET response_min_created_at = COALESCE(last_synced_at, created_at, NOW())
WHERE response_min_created_at IS NULL;

-- Replace the four-argument version so the director can name the payer while
-- inviting a guardian. The invitation flow is the family boundary: invite a
-- second guardian with this flag off, so they receive Forms but no invoice.
DROP FUNCTION IF EXISTS public.create_member_role_invite(UUID, TEXT, TEXT, TEXT);
CREATE FUNCTION public.create_member_role_invite(
    input_school_id UUID,
    input_email TEXT,
    input_display_name TEXT,
    input_role TEXT,
    input_is_payment_payer BOOLEAN DEFAULT NULL
)
RETURNS SETOF public.role_invites
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    normalized_email TEXT := lower(NULLIF(BTRIM(input_email), ''));
    created_invite public.role_invites%ROWTYPE;
    raw_invite_token TEXT := encode(extensions.gen_random_bytes(32), 'hex');
    payer BOOLEAN := FALSE;
BEGIN
    IF input_role NOT IN ('parent', 'teacher') THEN RAISE EXCEPTION 'Only parent and teacher invitations are supported here'; END IF;
    IF normalized_email IS NULL OR POSITION('@' IN normalized_email) <= 1 THEN RAISE EXCEPTION 'A valid email is required'; END IF;
    IF NOT public.has_direct_school_role(input_school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only an approved school director can invite parents or teachers';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.onboarding_templates
        WHERE school_id = input_school_id AND target_role = input_role AND status = 'published'
    ) THEN
        RAISE EXCEPTION 'Publish the % onboarding template before inviting people', input_role;
    END IF;

    IF input_role = 'parent' THEN
        payer := COALESCE(input_is_payment_payer, TRUE);
    END IF;

    UPDATE public.role_invites SET status = 'revoked'
    WHERE school_id = input_school_id AND lower(email) = normalized_email AND role = input_role AND status = 'pending';
    INSERT INTO public.role_invites (
        school_id, email, display_name, role, invited_by, token, token_hash, is_onboarding_payment_payer
    ) VALUES (
        input_school_id, normalized_email, NULLIF(BTRIM(COALESCE(input_display_name, '')), ''),
        input_role, actor, NULL, encode(extensions.digest(raw_invite_token, 'sha256'), 'hex'), payer
    ) RETURNING * INTO created_invite;
    created_invite.token := raw_invite_token;
    RETURN NEXT created_invite;
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_role_invite(invite_token TEXT)
RETURNS SETOF public.school_memberships
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    invite_record public.role_invites%ROWTYPE;
    joining_user UUID := auth.uid();
    joining_email TEXT := lower(COALESCE(auth.jwt()->>'email', ''));
BEGIN
    IF joining_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF joining_email = '' THEN RAISE EXCEPTION 'Your account email could not be verified'; END IF;
    SELECT * INTO invite_record FROM public.role_invites
    WHERE token_hash = encode(extensions.digest(NULLIF(btrim(invite_token), ''), 'sha256'), 'hex')
      AND status = 'pending' AND (expires_at IS NULL OR expires_at > NOW())
    LIMIT 1 FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Invalid or expired invite link'; END IF;
    IF lower(invite_record.email) <> joining_email THEN RAISE EXCEPTION 'This invite belongs to a different email account'; END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.onboarding_templates template
        WHERE template.school_id = invite_record.school_id AND template.target_role = invite_record.role AND template.status = 'published'
    ) THEN RAISE EXCEPTION 'The onboarding template for this invitation is not published yet'; END IF;

    INSERT INTO public.school_memberships (school_id, user_id, role, active, joined_at, is_onboarding_payment_payer)
    VALUES (invite_record.school_id, joining_user, invite_record.role, TRUE, NOW(),
            invite_record.role = 'parent' AND invite_record.is_onboarding_payment_payer)
    ON CONFLICT (school_id, user_id) DO UPDATE
    SET active = TRUE, role = EXCLUDED.role, joined_at = NOW(),
        is_onboarding_payment_payer = EXCLUDED.is_onboarding_payment_payer;

    IF invite_record.child_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM public.children child WHERE child.id = invite_record.child_id AND child.school_id = invite_record.school_id AND child.active) THEN
            RAISE EXCEPTION 'The invited child is no longer active';
        END IF;
        INSERT INTO public.child_guardians (child_id, guardian_id, relationship, verification_status, verified_by, verified_at, ended_at)
        VALUES (invite_record.child_id, joining_user, COALESCE(invite_record.guardian_relationship, 'Parent'), 'verified', invite_record.invited_by, NOW(), NULL)
        ON CONFLICT (child_id, guardian_id) DO UPDATE
        SET relationship = EXCLUDED.relationship, verification_status = 'verified', verified_by = EXCLUDED.verified_by, verified_at = NOW(), ended_at = NULL;
        PERFORM public.instantiate_child_onboarding(invite_record.child_id, joining_user);
    END IF;
    UPDATE public.role_invites SET status = 'accepted', accepted_by = joining_user, accepted_at = NOW(), token = NULL WHERE id = invite_record.id;
    IF invite_record.display_name IS NOT NULL THEN
        INSERT INTO public.profiles (id, display_name) VALUES (joining_user, invite_record.display_name)
        ON CONFLICT (id) DO UPDATE SET display_name = COALESCE(NULLIF(public.profiles.display_name, ''), EXCLUDED.display_name), updated_at = NOW();
    END IF;
    RETURN QUERY SELECT * FROM public.school_memberships WHERE school_id = invite_record.school_id AND user_id = joining_user;
END;
$$;

CREATE OR REPLACE FUNCTION public.instantiate_onboarding_for_membership(input_membership_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    membership_record public.school_memberships%ROWTYPE;
    template_record public.onboarding_templates%ROWTYPE;
    instance_uuid UUID;
    requirement_record public.onboarding_template_requirements%ROWTYPE;
    child_record RECORD;
    has_child BOOLEAN;
BEGIN
    SELECT * INTO membership_record FROM public.school_memberships WHERE id = input_membership_id AND active = TRUE;
    IF NOT FOUND OR membership_record.role = 'hq_director' THEN RETURN NULL; END IF;
    SELECT * INTO template_record FROM public.onboarding_templates
    WHERE school_id = membership_record.school_id AND target_role = membership_record.role AND status = 'published'
    ORDER BY version DESC LIMIT 1;
    IF NOT FOUND THEN
        UPDATE public.school_memberships SET access_state = 'onboarding' WHERE id = membership_record.id;
        RETURN NULL;
    END IF;
    SELECT id INTO instance_uuid FROM public.onboarding_instances
    WHERE membership_id = membership_record.id AND template_id = template_record.id;
    IF instance_uuid IS NOT NULL THEN
        PERFORM public.refresh_onboarding_access(membership_record.id);
        RETURN instance_uuid;
    END IF;
    INSERT INTO public.onboarding_instances (school_id, membership_id, template_id)
    VALUES (membership_record.school_id, membership_record.id, template_record.id)
    RETURNING id INTO instance_uuid;
    UPDATE public.school_memberships SET access_state = 'onboarding' WHERE id = membership_record.id;

    FOR requirement_record IN SELECT * FROM public.onboarding_template_requirements
                              WHERE template_id = template_record.id ORDER BY position LOOP
        -- Parent Forms are always assigned. A manual payment is assigned only
        -- to the one parent selected by the director for that family.
        IF requirement_record.requirement_type = 'payment'
           AND membership_record.role = 'parent'
           AND NOT membership_record.is_onboarding_payment_payer THEN
            CONTINUE;
        END IF;
        IF requirement_record.subject_scope = 'member' THEN
            PERFORM public.create_onboarding_assignment(instance_uuid, requirement_record.id, NULL);
        ELSE
            has_child := FALSE;
            FOR child_record IN
                SELECT children.id FROM public.children
                JOIN public.child_guardians guardians ON guardians.child_id = children.id
                WHERE guardians.guardian_id = membership_record.user_id
                  AND children.school_id = membership_record.school_id AND children.active
            LOOP
                has_child := TRUE;
                PERFORM public.create_onboarding_assignment(instance_uuid, requirement_record.id, child_record.id);
            END LOOP;
            IF NOT has_child THEN
                INSERT INTO public.onboarding_requirement_instances (onboarding_instance_id, template_requirement_id, status)
                VALUES (instance_uuid, requirement_record.id, 'not_started');
            END IF;
        END IF;
    END LOOP;
    PERFORM public.refresh_onboarding_access(membership_record.id);
    RETURN instance_uuid;
END;
$$;

-- Keep the Form display sequence synchronized with the timeline's only source
-- of order. The offset avoids transient unique-position conflicts.
CREATE OR REPLACE FUNCTION public.reorder_onboarding_template_requirements(
    input_template_id UUID,
    input_requirement_ids UUID[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    template_record public.onboarding_templates%ROWTYPE;
BEGIN
    SELECT * INTO template_record FROM public.onboarding_templates WHERE id = input_template_id;
    IF NOT FOUND OR template_record.status <> 'draft'
       OR NOT public.is_onboarding_template_manager(template_record.school_id, template_record.target_role, actor) THEN
        RAISE EXCEPTION 'You cannot reorder this template';
    END IF;
    IF COALESCE(array_length(input_requirement_ids, 1), 0) <>
       (SELECT COUNT(*) FROM public.onboarding_template_requirements WHERE template_id = input_template_id) THEN
        RAISE EXCEPTION 'The reordered timeline is incomplete';
    END IF;
    UPDATE public.onboarding_template_requirements SET position = position + 10000 WHERE template_id = input_template_id;
    UPDATE public.onboarding_template_requirements requirement
    SET position = ordered.ordinality::INTEGER - 1, updated_at = NOW()
    FROM unnest(input_requirement_ids) WITH ORDINALITY AS ordered(id, ordinality)
    WHERE requirement.id = ordered.id AND requirement.template_id = input_template_id;
    UPDATE public.google_form_connections connection
    SET display_order = requirement.position, updated_at = NOW()
    FROM public.google_form_requirement_bindings binding
    JOIN public.onboarding_template_requirements requirement ON requirement.id = binding.onboarding_template_requirement_id
    WHERE binding.connection_id = connection.id AND requirement.template_id = input_template_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.publish_onboarding_template(input_template_id UUID)
RETURNS SETOF public.onboarding_templates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    template_record public.onboarding_templates%ROWTYPE;
BEGIN
    SELECT * INTO template_record FROM public.onboarding_templates WHERE id = input_template_id;
    IF NOT FOUND OR template_record.status <> 'draft'
       OR NOT public.is_onboarding_template_manager(template_record.school_id, template_record.target_role, actor) THEN
        RAISE EXCEPTION 'You cannot publish this template';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.onboarding_template_requirements WHERE template_id = input_template_id) THEN
        RAISE EXCEPTION 'Add at least one requirement before publishing';
    END IF;
    IF template_record.target_role = 'parent' AND NOT EXISTS (
        SELECT 1 FROM public.google_form_requirement_bindings binding
        JOIN public.google_form_connections connection ON connection.id = binding.connection_id
        JOIN public.onboarding_template_requirements requirement ON requirement.id = binding.onboarding_template_requirement_id
        WHERE requirement.template_id = input_template_id AND connection.status = 'connected'
    ) THEN
        RAISE EXCEPTION 'Add at least one parent Form before publishing this timeline';
    END IF;
    UPDATE public.onboarding_templates SET status = 'archived', archived_at = NOW(), updated_at = NOW()
    WHERE school_id = template_record.school_id AND target_role = template_record.target_role AND status = 'published';
    UPDATE public.onboarding_templates SET status = 'published', published_at = NOW(), archived_at = NULL, updated_at = NOW()
    WHERE id = input_template_id RETURNING * INTO template_record;
    PERFORM public.instantiate_onboarding_for_membership(membership.id)
    FROM public.school_memberships membership
    WHERE membership.school_id = template_record.school_id AND membership.role = template_record.target_role
      AND membership.active AND membership.access_state = 'onboarding'
      AND NOT EXISTS (SELECT 1 FROM public.onboarding_instances instance WHERE instance.membership_id = membership.id);
    RETURN QUERY SELECT * FROM public.onboarding_templates WHERE id = template_record.id;
END;
$$;

CREATE FUNCTION public.fetch_parent_onboarding_timeline_editor(input_school_id UUID)
RETURNS TABLE (
    requirement_id UUID, step_position INTEGER, title TEXT, description TEXT, requirement_type TEXT,
    payment_amount_cents BIGINT, payment_due_days INTEGER, form_connection_id UUID, form_id TEXT,
    form_title TEXT, form_url TEXT, google_account_email TEXT, form_status TEXT, setup_warning TEXT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    WITH template AS (
        SELECT id FROM public.onboarding_templates
        WHERE school_id = input_school_id AND target_role = 'parent' AND status IN ('draft', 'published')
        ORDER BY (status = 'draft') DESC, version DESC LIMIT 1
    )
    SELECT requirement.id, requirement.position AS step_position, requirement.title, requirement.description, requirement.requirement_type,
           requirement.payment_amount_cents, requirement.payment_due_days, connection.id, connection.form_id, connection.form_title,
           connection.form_url, connection.google_account_email, connection.status, connection.setup_warning
    FROM public.onboarding_template_requirements requirement
    JOIN template ON template.id = requirement.template_id
    LEFT JOIN public.google_form_requirement_bindings binding ON binding.onboarding_template_requirement_id = requirement.id
    LEFT JOIN public.google_form_connections connection ON connection.id = binding.connection_id
    WHERE public.is_onboarding_template_manager(input_school_id, 'parent', auth.uid())
    ORDER BY requirement.position, requirement.created_at;
$$;

CREATE FUNCTION public.fetch_my_parent_onboarding_timeline(input_school_id UUID)
RETURNS TABLE (
    requirement_instance_id UUID, step_position INTEGER, title TEXT, requirement_type TEXT, status TEXT,
    step_kind TEXT, connection_id UUID, form_title TEXT, form_submission_status TEXT, form_review_note TEXT,
    zelle_invoice_id UUID, zelle_invoice_status TEXT, zelle_amount_due_cents BIGINT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT instance_requirement.id, requirement.position AS step_position, requirement.title, requirement.requirement_type,
           instance_requirement.status,
           CASE WHEN connection.id IS NOT NULL THEN 'form'
                WHEN requirement.requirement_type = 'payment' THEN 'payment' ELSE 'paperwork' END,
           connection.id, connection.form_title, form_import.status, form_import.review_note,
           invoice.id, invoice.status, invoice.amount_due_cents
    FROM public.onboarding_instances instance
    JOIN public.school_memberships membership ON membership.id = instance.membership_id
    JOIN public.onboarding_requirement_instances instance_requirement ON instance_requirement.onboarding_instance_id = instance.id
    JOIN public.onboarding_template_requirements requirement ON requirement.id = instance_requirement.template_requirement_id
    LEFT JOIN public.google_form_requirement_bindings binding ON binding.onboarding_template_requirement_id = requirement.id
    LEFT JOIN public.google_form_connections connection ON connection.id = binding.connection_id AND connection.status = 'connected'
    LEFT JOIN LATERAL (
        SELECT response.status, response.review_note FROM public.google_form_imports response
        WHERE response.connection_id = connection.id AND response.membership_id = membership.id
        ORDER BY response.response_submitted_at DESC NULLS LAST, response.created_at DESC LIMIT 1
    ) form_import ON TRUE
    LEFT JOIN public.zelle_invoices invoice ON invoice.onboarding_requirement_instance_id = instance_requirement.id
    WHERE membership.user_id = auth.uid() AND membership.school_id = input_school_id
      AND membership.role = 'parent' AND membership.active AND instance.status IN ('in_progress', 'complete')
    ORDER BY requirement.position, instance_requirement.created_at;
$$;

CREATE FUNCTION public.remove_parent_onboarding_timeline_step(input_requirement_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    requirement_record public.onboarding_template_requirements%ROWTYPE;
    bound_connection_id UUID;
BEGIN
    SELECT * INTO requirement_record FROM public.onboarding_template_requirements WHERE id = input_requirement_id;
    IF requirement_record.id IS NULL OR NOT public.is_onboarding_template_manager(
        (SELECT school_id FROM public.onboarding_templates WHERE id = requirement_record.template_id), 'parent', auth.uid()
    ) OR (SELECT status FROM public.onboarding_templates WHERE id = requirement_record.template_id) <> 'draft' THEN
        RAISE EXCEPTION 'Only a parent timeline draft can be changed';
    END IF;
    SELECT binding.connection_id INTO bound_connection_id FROM public.google_form_requirement_bindings binding
    WHERE binding.onboarding_template_requirement_id = input_requirement_id;
    IF bound_connection_id IS NOT NULL THEN
        UPDATE public.google_form_connections SET status = 'disconnected', updated_at = NOW() WHERE id = bound_connection_id;
        DELETE FROM public.google_form_requirement_bindings WHERE connection_id = bound_connection_id;
    END IF;
    DELETE FROM public.onboarding_template_requirements WHERE id = input_requirement_id;
    WITH ordered AS (
        SELECT id, row_number() OVER (ORDER BY position, created_at)::INTEGER - 1 AS next_position
        FROM public.onboarding_template_requirements WHERE template_id = requirement_record.template_id
    )
    UPDATE public.onboarding_template_requirements requirement SET position = ordered.next_position, updated_at = NOW()
    FROM ordered WHERE requirement.id = ordered.id;
END;
$$;

-- A published timeline is immutable. When a director starts the next draft,
-- copy each bound Form into a new connection keyed by its new requirement.
-- The previous connection, mapping, imports, and submission sessions remain
-- tied to the earlier template version.
CREATE OR REPLACE FUNCTION public.ensure_onboarding_template_draft(
    input_school_id UUID,
    input_target_role TEXT
)
RETURNS SETOF public.onboarding_templates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    existing_draft public.onboarding_templates%ROWTYPE;
    published_template public.onboarding_templates%ROWTYPE;
    created_draft public.onboarding_templates%ROWTYPE;
    old_requirement public.onboarding_template_requirements%ROWTYPE;
    new_requirement_id UUID;
    source_binding RECORD;
    new_connection_id UUID;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF input_target_role NOT IN ('parent', 'teacher', 'school_director') THEN
        RAISE EXCEPTION 'Unsupported onboarding role';
    END IF;
    IF NOT public.is_onboarding_template_manager(input_school_id, input_target_role, actor) THEN
        RAISE EXCEPTION 'You cannot manage this onboarding template';
    END IF;

    SELECT * INTO existing_draft FROM public.onboarding_templates
    WHERE school_id = input_school_id AND target_role = input_target_role AND status = 'draft'
    LIMIT 1;
    IF FOUND THEN
        RETURN QUERY SELECT * FROM public.onboarding_templates WHERE id = existing_draft.id;
        RETURN;
    END IF;

    SELECT * INTO published_template FROM public.onboarding_templates
    WHERE school_id = input_school_id AND target_role = input_target_role AND status = 'published'
    ORDER BY version DESC LIMIT 1;

    INSERT INTO public.onboarding_templates (school_id, target_role, name, version, status, created_by)
    VALUES (
        input_school_id, input_target_role,
        CASE input_target_role WHEN 'school_director' THEN 'School Director Onboarding'
            WHEN 'parent' THEN 'Parent Onboarding' ELSE 'Teacher Onboarding' END,
        (SELECT COALESCE(MAX(template.version), 0) + 1 FROM public.onboarding_templates template
         WHERE template.school_id = input_school_id AND template.target_role = input_target_role),
        'draft', actor
    ) RETURNING * INTO created_draft;

    IF published_template.id IS NOT NULL THEN
        FOR old_requirement IN
            SELECT * FROM public.onboarding_template_requirements
            WHERE template_id = published_template.id ORDER BY position
        LOOP
            INSERT INTO public.onboarding_template_requirements (
                template_id, requirement_key, position, requirement_type, title, description,
                subject_scope, blocks_access, child_record_binding, payment_amount_cents, payment_due_days
            ) VALUES (
                created_draft.id, old_requirement.requirement_key, old_requirement.position,
                old_requirement.requirement_type, old_requirement.title, old_requirement.description,
                old_requirement.subject_scope, old_requirement.blocks_access,
                old_requirement.child_record_binding, old_requirement.payment_amount_cents,
                old_requirement.payment_due_days
            ) RETURNING id INTO new_requirement_id;

            INSERT INTO public.onboarding_template_attachments (
                requirement_id, position, private_file_path, file_name, content_type
            )
            SELECT new_requirement_id, position, private_file_path, file_name, content_type
            FROM public.onboarding_template_attachments
            WHERE requirement_id = old_requirement.id ORDER BY position;

            IF input_target_role = 'parent' THEN
                SELECT binding.published_snapshot, connection.* INTO source_binding
                FROM public.google_form_requirement_bindings binding
                JOIN public.google_form_connections connection ON connection.id = binding.connection_id
                WHERE binding.onboarding_template_requirement_id = old_requirement.id;

                IF FOUND THEN
                    INSERT INTO public.google_form_connections (
                        school_id, credential_id, form_role, form_key, form_id, form_url, form_title,
                        google_account_email, credential_secret_ref, status, setup_warning, is_required,
                        display_order, form_snapshot, response_min_created_at, created_by, updated_at
                    ) VALUES (
                        source_binding.school_id, source_binding.credential_id, source_binding.form_role,
                        source_binding.form_id || ':' || new_requirement_id::TEXT,
                        source_binding.form_id, source_binding.form_url, source_binding.form_title,
                        source_binding.google_account_email, source_binding.credential_secret_ref,
                        source_binding.status, source_binding.setup_warning, source_binding.is_required,
                        old_requirement.position, source_binding.form_snapshot, NOW(), actor, NOW()
                    ) RETURNING id INTO new_connection_id;

                    INSERT INTO public.google_form_question_mappings (
                        connection_id, question_id, question_title, field_key, required, active,
                        prefill_parameter, updated_at
                    )
                    SELECT new_connection_id, question_id, question_title, field_key, required, active,
                           prefill_parameter, NOW()
                    FROM public.google_form_question_mappings
                    WHERE connection_id = source_binding.id;

                    INSERT INTO public.google_form_requirement_bindings (
                        connection_id, onboarding_template_requirement_id, published_snapshot, updated_at
                    ) VALUES (
                        new_connection_id, new_requirement_id,
                        source_binding.published_snapshot, NOW()
                    );
                END IF;
            END IF;
        END LOOP;
    END IF;

    RETURN QUERY SELECT * FROM public.onboarding_templates WHERE id = created_draft.id;
END;
$$;

-- A URL is not an authorization grant. A parent may start a Form only when it
-- belongs to their own onboarding instance and every earlier assigned timeline
-- requirement is complete. The server creates the fresh two-hour token here.
CREATE OR REPLACE FUNCTION public.begin_google_form_submission(input_connection_id UUID)
RETURNS TABLE (connection_id UUID, launch_url TEXT, expires_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    connection public.google_form_connections%ROWTYPE;
    membership public.school_memberships%ROWTYPE;
    reference_mapping public.google_form_question_mappings%ROWTYPE;
    raw_token TEXT := replace(gen_random_uuid()::TEXT, '-', '') || replace(gen_random_uuid()::TEXT, '-', '');
    snapshot JSONB;
    bound_requirement_id UUID;
    bound_position INTEGER;
    joiner TEXT;
    query_key TEXT;
BEGIN
    SELECT * INTO connection FROM public.google_form_connections WHERE id = input_connection_id AND status = 'connected';
    IF NOT FOUND THEN RAISE EXCEPTION 'This Form is not available'; END IF;
    SELECT * INTO membership FROM public.school_memberships
    WHERE school_id = connection.school_id AND user_id = actor AND active = TRUE AND role = connection.form_role;
    IF NOT FOUND THEN RAISE EXCEPTION 'This Form is not assigned to your role'; END IF;
    SELECT onboarding_template_requirement_id INTO bound_requirement_id
    FROM public.google_form_requirement_bindings binding
    WHERE binding.connection_id = connection.id;
    SELECT position INTO bound_position FROM public.onboarding_template_requirements WHERE id = bound_requirement_id;
    IF bound_requirement_id IS NULL OR bound_position IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.onboarding_requirement_instances requirement_instance
        JOIN public.onboarding_instances instance ON instance.id = requirement_instance.onboarding_instance_id
        WHERE instance.membership_id = membership.id
          AND requirement_instance.template_requirement_id = bound_requirement_id
    ) THEN
        RAISE EXCEPTION 'This Form is not assigned to your onboarding timeline';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.onboarding_requirement_instances earlier_instance
        JOIN public.onboarding_instances instance ON instance.id = earlier_instance.onboarding_instance_id
        JOIN public.onboarding_template_requirements earlier_requirement
          ON earlier_requirement.id = earlier_instance.template_requirement_id
        WHERE instance.membership_id = membership.id
          AND earlier_requirement.position < bound_position
          AND earlier_instance.status NOT IN ('approved', 'waived')
    ) THEN
        RAISE EXCEPTION 'Complete the earlier onboarding step first';
    END IF;
    SELECT * INTO reference_mapping FROM public.google_form_question_mappings mapping
    WHERE mapping.connection_id = connection.id
      AND mapping.field_key = 'submission_reference'
      AND mapping.active = TRUE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reconnect Google to finish setup'; END IF;

    SELECT jsonb_build_object('form_url', connection.form_url, 'form_role', connection.form_role,
        'requirement_id', bound_requirement_id,
        'mappings', COALESCE(jsonb_agg(jsonb_build_object(
            'question_id', mapping.question_id, 'question_title', mapping.question_title,
            'field_key', mapping.field_key, 'required', mapping.required, 'active', mapping.active,
            'prefill_parameter', mapping.prefill_parameter
        )), '[]'::JSONB))
    INTO snapshot
    FROM public.google_form_question_mappings mapping WHERE mapping.connection_id = connection.id;

    INSERT INTO public.google_form_submission_sessions (
        connection_id, school_id, membership_id, user_id, token_hash, connection_snapshot, expires_at
    ) VALUES (
        connection.id, connection.school_id, membership.id, actor, encode(extensions.digest(raw_token, 'sha256'), 'hex'),
        snapshot, NOW() + INTERVAL '2 hours'
    );
    joiner := CASE WHEN position('?' IN connection.form_url) > 0 THEN '&' ELSE '?' END;
    query_key := COALESCE(NULLIF(reference_mapping.prefill_parameter, ''), 'entry.' || reference_mapping.question_id);
    RETURN QUERY SELECT connection.id,
        connection.form_url || joiner || 'usp=pp_url&' || query_key || '=' || raw_token,
        NOW() + INTERVAL '2 hours';
END;
$$;

-- The payment card follows the same timeline rule even if a payer tries to
-- call the billing RPC directly rather than using the recipient screen.
CREATE OR REPLACE FUNCTION public.submit_zelle_payment(
    input_invoice_id UUID,
    input_amount_cents BIGINT,
    input_sent_at TIMESTAMPTZ,
    input_confirmation_reference TEXT,
    input_idempotency_key TEXT
)
RETURNS SETOF public.zelle_payment_submissions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    invoice_record public.zelle_invoices%ROWTYPE;
    submission_record public.zelle_payment_submissions%ROWTYPE;
    payment_position INTEGER;
BEGIN
    SELECT * INTO invoice_record FROM public.zelle_invoices WHERE id = input_invoice_id FOR UPDATE;
    IF NOT FOUND OR NOT public.zelle_is_active_payer(invoice_record.school_id, invoice_record.payer_user_id, actor) THEN
        RAISE EXCEPTION 'Only the named payer can submit this payment';
    END IF;
    SELECT * INTO submission_record FROM public.zelle_payment_submissions
    WHERE invoice_id = input_invoice_id AND payer_user_id = actor AND idempotency_key = input_idempotency_key;
    IF FOUND THEN
        RETURN QUERY SELECT * FROM public.zelle_payment_submissions WHERE id = submission_record.id;
        RETURN;
    END IF;
    IF invoice_record.onboarding_requirement_instance_id IS NOT NULL THEN
        SELECT requirement.position INTO payment_position
        FROM public.onboarding_requirement_instances payment_instance
        JOIN public.onboarding_instances instance ON instance.id = payment_instance.onboarding_instance_id
        JOIN public.onboarding_template_requirements requirement ON requirement.id = payment_instance.template_requirement_id
        WHERE payment_instance.id = invoice_record.onboarding_requirement_instance_id;
        IF EXISTS (
            SELECT 1 FROM public.onboarding_requirement_instances earlier_instance
            JOIN public.onboarding_instances instance ON instance.id = earlier_instance.onboarding_instance_id
            JOIN public.onboarding_template_requirements earlier_requirement
              ON earlier_requirement.id = earlier_instance.template_requirement_id
            WHERE instance.membership_id = (
                SELECT membership_id FROM public.onboarding_instances instance
                JOIN public.onboarding_requirement_instances payment_instance
                  ON payment_instance.onboarding_instance_id = instance.id
                WHERE payment_instance.id = invoice_record.onboarding_requirement_instance_id
            )
              AND earlier_requirement.position < payment_position
              AND earlier_instance.status NOT IN ('approved', 'waived')
        ) THEN
            RAISE EXCEPTION 'Complete the earlier onboarding step first';
        END IF;
    END IF;
    IF invoice_record.status NOT IN ('open', 'rejected') THEN RAISE EXCEPTION 'This invoice cannot accept a new payment submission'; END IF;
    IF input_amount_cents IS NULL OR input_sent_at IS NULL THEN RAISE EXCEPTION 'Amount and sent time are required'; END IF;
    IF NOT invoice_record.is_demo AND upper(input_confirmation_reference) LIKE 'TEST-%' THEN
        RAISE EXCEPTION 'Test references require the isolated demo environment';
    END IF;
    IF input_amount_cents <> invoice_record.amount_due_cents THEN RAISE EXCEPTION 'This beta requires the full invoice amount in one payment'; END IF;
    IF input_sent_at > NOW() + INTERVAL '15 minutes' OR input_sent_at < NOW() - INTERVAL '180 days'
       OR COALESCE(input_confirmation_reference, '') !~ '^[A-Za-z0-9-]{4,64}$'
       OR COALESCE(input_idempotency_key, '') !~ '^.{8,180}$' THEN
        RAISE EXCEPTION 'The payment submission is invalid';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.zelle_payment_submissions existing
        WHERE existing.school_id = invoice_record.school_id
          AND upper(existing.confirmation_reference) = upper(input_confirmation_reference)
          AND existing.invoice_id <> input_invoice_id
    ) THEN RAISE EXCEPTION 'This confirmation reference has already been used for this school'; END IF;

    INSERT INTO public.zelle_payment_submissions (
        invoice_id, school_id, payer_user_id, amount_cents, sent_at, confirmation_reference, idempotency_key
    ) VALUES (
        invoice_record.id, invoice_record.school_id, actor, input_amount_cents,
        input_sent_at, upper(input_confirmation_reference), input_idempotency_key
    ) RETURNING * INTO submission_record;
    UPDATE public.zelle_invoices SET status = 'payment_submitted', updated_at = NOW() WHERE id = invoice_record.id;
    IF invoice_record.onboarding_requirement_instance_id IS NOT NULL THEN
        UPDATE public.onboarding_requirement_instances SET status = 'in_review'
        WHERE id = invoice_record.onboarding_requirement_instance_id;
    END IF;
    INSERT INTO public.zelle_billing_audit_log (school_id, actor_id, action, entity_type, entity_id, metadata)
    VALUES (
        invoice_record.school_id, actor, 'payment_submitted', 'submission', submission_record.id,
        jsonb_build_object('invoice_id', invoice_record.id, 'amount_cents', input_amount_cents)
    );
    PERFORM public.notify_zelle_recipients(
        invoice_record.school_id, public.zelle_invoice_reviewers(invoice_record.id),
        'Zelle payment needs review',
        'A payer submitted a Zelle confirmation reference. Verify it in the school bank before approving.',
        invoice_record.id, 'zelle:invoice:' || submission_record.id::TEXT || ':review', actor
    );
    RETURN QUERY SELECT * FROM public.zelle_payment_submissions WHERE id = submission_record.id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_member_role_invite(UUID, TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fetch_parent_onboarding_timeline_editor(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fetch_my_parent_onboarding_timeline(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.remove_parent_onboarding_timeline_step(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_member_role_invite(UUID, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_parent_onboarding_timeline_editor(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_parent_onboarding_timeline(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_parent_onboarding_timeline_step(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260908090000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
