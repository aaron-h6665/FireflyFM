BEGIN;

-- Publishing a template updates every active membership with onboarding still
-- in progress, including access-gated members. Stable requirement_key values carry matching work
-- forward. Removed or structurally changed steps stop blocking access but stay
-- attached to the historical invoice/assignment records for audit purposes.
CREATE OR REPLACE FUNCTION public.apply_published_onboarding_template_to_membership(
    input_template_id UUID,
    input_membership_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    template_record public.onboarding_templates%ROWTYPE;
    membership_record public.school_memberships%ROWTYPE;
    instance_record public.onboarding_instances%ROWTYPE;
    retired_record RECORD;
    mapped_record RECORD;
    requirement_record public.onboarding_template_requirements%ROWTYPE;
    child_record RECORD;
    has_child BOOLEAN;
BEGIN
    SELECT * INTO template_record
    FROM public.onboarding_templates
    WHERE id = input_template_id AND status = 'published';

    SELECT * INTO membership_record
    FROM public.school_memberships
    WHERE id = input_membership_id
      AND active = TRUE
      AND (
          access_state = 'onboarding'
          OR EXISTS (
              SELECT 1 FROM public.onboarding_instances active_instance
              WHERE active_instance.membership_id = input_membership_id
                AND active_instance.status = 'in_progress'
          )
      );

    IF template_record.id IS NULL OR membership_record.id IS NULL
       OR membership_record.school_id <> template_record.school_id
       OR membership_record.role <> template_record.target_role THEN
        RAISE EXCEPTION 'The published onboarding template does not match this active membership';
    END IF;
    IF NOT public.is_onboarding_template_manager(
        template_record.school_id, template_record.target_role, actor
    ) THEN
        RAISE EXCEPTION 'You cannot apply this onboarding template';
    END IF;

    SELECT * INTO instance_record
    FROM public.onboarding_instances
    WHERE membership_id = membership_record.id AND status = 'in_progress'
    ORDER BY started_at DESC
    LIMIT 1
    FOR UPDATE;

    IF instance_record.id IS NULL THEN
        RETURN public.instantiate_onboarding_for_membership(membership_record.id);
    END IF;
    IF instance_record.template_id = template_record.id THEN
        PERFORM public.refresh_onboarding_access(membership_record.id);
        RETURN instance_record.id;
    END IF;

    -- Retire removed requirements and type/scope changes. They remain in the
    -- audit graph but no longer appear in the current template or block access.
    FOR retired_record IN
        SELECT requirement_instance.id AS requirement_instance_id,
               requirement_instance.assignment_id,
               requirement_instance.status,
               old_requirement.requirement_type
        FROM public.onboarding_requirement_instances requirement_instance
        JOIN public.onboarding_template_requirements old_requirement
          ON old_requirement.id = requirement_instance.template_requirement_id
        WHERE requirement_instance.onboarding_instance_id = instance_record.id
          AND old_requirement.template_id = instance_record.template_id
          AND NOT EXISTS (
              SELECT 1
              FROM public.onboarding_template_requirements new_requirement
              WHERE new_requirement.template_id = template_record.id
                AND new_requirement.requirement_key = old_requirement.requirement_key
                AND new_requirement.requirement_type = old_requirement.requirement_type
                AND new_requirement.subject_scope = old_requirement.subject_scope
          )
    LOOP
        IF retired_record.assignment_id IS NOT NULL THEN
            UPDATE public.assignments
            SET status = 'archived', updated_at = NOW()
            WHERE id = retired_record.assignment_id AND status <> 'archived';
        END IF;

        IF retired_record.requirement_type = 'payment' THEN
            UPDATE public.zelle_invoices
            SET status = 'void', voided_at = COALESCE(voided_at, NOW()), updated_at = NOW()
            WHERE onboarding_requirement_instance_id = retired_record.requirement_instance_id
              AND status IN ('draft', 'open', 'rejected', 'expired');
        END IF;

        UPDATE public.onboarding_requirement_instances
        SET status = CASE
                WHEN status IN ('approved', 'waived') THEN status
                ELSE 'waived'
            END,
            waived_by = CASE
                WHEN status IN ('approved', 'waived') THEN waived_by
                ELSE actor
            END,
            waiver_reason = CASE
                WHEN status IN ('approved', 'waived') THEN waiver_reason
                ELSE 'Removed by a published onboarding update'
            END,
            completed_at = COALESCE(completed_at, NOW())
        WHERE id = retired_record.requirement_instance_id;
    END LOOP;

    -- Carry matching work to the new version. Approved and waived results stay
    -- complete; unfinished assignments receive the latest title and materials.
    FOR mapped_record IN
        SELECT requirement_instance.id AS requirement_instance_id,
               requirement_instance.assignment_id,
               requirement_instance.status,
               new_requirement.id AS new_requirement_id,
               new_requirement.requirement_type,
               new_requirement.title,
               new_requirement.description,
               new_requirement.payment_amount_cents,
               new_requirement.payment_due_days
        FROM public.onboarding_requirement_instances requirement_instance
        JOIN public.onboarding_template_requirements old_requirement
          ON old_requirement.id = requirement_instance.template_requirement_id
        JOIN public.onboarding_template_requirements new_requirement
          ON new_requirement.template_id = template_record.id
         AND new_requirement.requirement_key = old_requirement.requirement_key
         AND new_requirement.requirement_type = old_requirement.requirement_type
         AND new_requirement.subject_scope = old_requirement.subject_scope
        WHERE requirement_instance.onboarding_instance_id = instance_record.id
          AND old_requirement.template_id = instance_record.template_id
    LOOP
        UPDATE public.onboarding_requirement_instances
        SET template_requirement_id = mapped_record.new_requirement_id
        WHERE id = mapped_record.requirement_instance_id;

        IF mapped_record.assignment_id IS NOT NULL
           AND mapped_record.status NOT IN ('approved', 'waived') THEN
            UPDATE public.assignments
            SET title = mapped_record.title,
                description = mapped_record.description,
                updated_at = NOW()
            WHERE id = mapped_record.assignment_id;

            DELETE FROM public.assignment_materials
            WHERE assignment_id = mapped_record.assignment_id;
            INSERT INTO public.assignment_materials (
                assignment_id, material_type, title, private_file_path, file_name, content_type
            )
            SELECT mapped_record.assignment_id, 'file', attachment.file_name,
                   attachment.private_file_path, attachment.file_name, attachment.content_type
            FROM public.onboarding_template_attachments attachment
            WHERE attachment.requirement_id = mapped_record.new_requirement_id
            ORDER BY attachment.position;
        END IF;

        -- An untouched invoice can safely receive the newly published amount
        -- and due period. Once a payer has submitted anything, keep that invoice
        -- immutable so a template edit can never imply a second bank transfer.
        IF mapped_record.requirement_type = 'payment' THEN
            UPDATE public.zelle_invoices
            SET description = mapped_record.title,
                amount_due_cents = mapped_record.payment_amount_cents,
                due_at = NOW() + make_interval(days => COALESCE(mapped_record.payment_due_days, 7)),
                updated_at = NOW()
            WHERE onboarding_requirement_instance_id = mapped_record.requirement_instance_id
              AND status IN ('draft', 'open');

            DELETE FROM public.zelle_invoice_items item
            USING public.zelle_invoices invoice
            WHERE item.invoice_id = invoice.id
              AND invoice.onboarding_requirement_instance_id = mapped_record.requirement_instance_id
              AND invoice.status IN ('draft', 'open');
            INSERT INTO public.zelle_invoice_items (
                invoice_id, description, quantity, unit_amount_cents, amount_cents
            )
            SELECT invoice.id, mapped_record.title, 1,
                   mapped_record.payment_amount_cents, mapped_record.payment_amount_cents
            FROM public.zelle_invoices invoice
            WHERE invoice.onboarding_requirement_instance_id = mapped_record.requirement_instance_id
              AND invoice.status IN ('draft', 'open');
        END IF;
    END LOOP;

    UPDATE public.onboarding_instances
    SET template_id = template_record.id, status = 'in_progress', completed_at = NULL
    WHERE id = instance_record.id;

    -- Instantiate requirements that were newly added or structurally changed.
    FOR requirement_record IN
        SELECT *
        FROM public.onboarding_template_requirements requirement
        WHERE requirement.template_id = template_record.id
          AND NOT EXISTS (
              SELECT 1
              FROM public.onboarding_requirement_instances requirement_instance
              WHERE requirement_instance.onboarding_instance_id = instance_record.id
                AND requirement_instance.template_requirement_id = requirement.id
          )
        ORDER BY requirement.position
    LOOP
        IF requirement_record.requirement_type = 'payment'
           AND membership_record.role = 'parent'
           AND NOT membership_record.is_onboarding_payment_payer THEN
            CONTINUE;
        END IF;

        IF requirement_record.subject_scope = 'member' THEN
            PERFORM public.create_onboarding_assignment(
                instance_record.id, requirement_record.id, NULL
            );
        ELSE
            has_child := FALSE;
            FOR child_record IN
                SELECT child.id
                FROM public.children child
                JOIN public.child_guardians guardian ON guardian.child_id = child.id
                WHERE guardian.guardian_id = membership_record.user_id
                  AND child.school_id = membership_record.school_id
                  AND child.active = TRUE
            LOOP
                has_child := TRUE;
                PERFORM public.create_onboarding_assignment(
                    instance_record.id, requirement_record.id, child_record.id
                );
            END LOOP;
            IF NOT has_child THEN
                INSERT INTO public.onboarding_requirement_instances (
                    onboarding_instance_id, template_requirement_id, status
                ) VALUES (instance_record.id, requirement_record.id, 'not_started');
            END IF;
        END IF;
    END LOOP;

    PERFORM public.refresh_onboarding_access(membership_record.id);
    RETURN instance_record.id;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_published_onboarding_template_to_membership(UUID, UUID)
FROM PUBLIC, anon, authenticated;

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

    UPDATE public.onboarding_templates
    SET status = 'archived', archived_at = NOW(), updated_at = NOW()
    WHERE school_id = template_record.school_id
      AND target_role = template_record.target_role
      AND status = 'published';
    UPDATE public.onboarding_templates
    SET status = 'published', published_at = NOW(), archived_at = NULL, updated_at = NOW()
    WHERE id = input_template_id
    RETURNING * INTO template_record;

    PERFORM public.apply_published_onboarding_template_to_membership(
        template_record.id, membership.id
    )
    FROM public.school_memberships membership
    WHERE membership.school_id = template_record.school_id
      AND membership.role = template_record.target_role
      AND membership.active = TRUE
      AND (
          membership.access_state = 'onboarding'
          OR EXISTS (
              SELECT 1 FROM public.onboarding_instances active_instance
              WHERE active_instance.membership_id = membership.id
                AND active_instance.status = 'in_progress'
          )
      );

    RETURN QUERY SELECT * FROM public.onboarding_templates WHERE id = template_record.id;
END;
$$;

-- Historical requirements remain linked for audit, but recipient dashboards
-- display only the requirements that belong to the currently assigned version.
DROP FUNCTION IF EXISTS public.fetch_my_parent_onboarding_timeline(UUID);
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
    JOIN public.onboarding_template_requirements requirement
      ON requirement.id = instance_requirement.template_requirement_id
     AND requirement.template_id = instance.template_id
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

DROP FUNCTION IF EXISTS public.fetch_my_onboarding_dashboard(UUID);
CREATE FUNCTION public.fetch_my_onboarding_dashboard(input_school_id UUID)
RETURNS TABLE (
    requirement_instance_id UUID, assignment_id UUID, child_id UUID, requirement_type TEXT,
    zelle_invoice_id UUID, zelle_invoice_status TEXT, zelle_amount_due_cents BIGINT,
    title TEXT, description TEXT, subject_scope TEXT, "position" INTEGER, status TEXT,
    material_count BIGINT, child_first_name TEXT, child_last_name TEXT, reviewer_label TEXT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT requirement_instances.id, requirement_instances.assignment_id, requirement_instances.child_id,
        requirements.requirement_type, invoice.id, invoice.status, invoice.amount_due_cents,
        requirements.title, requirements.description, requirements.subject_scope, requirements.position,
        requirement_instances.status,
        COALESCE((SELECT COUNT(*) FROM public.assignment_materials materials WHERE materials.assignment_id = requirement_instances.assignment_id), 0),
        children.first_name, children.last_name,
        CASE templates.target_role WHEN 'school_director' THEN 'Reviewed by FireflyFM HQ' ELSE 'Reviewed by your school director' END
    FROM public.onboarding_instances instances
    JOIN public.school_memberships memberships ON memberships.id = instances.membership_id
    JOIN public.onboarding_templates templates ON templates.id = instances.template_id
    JOIN public.onboarding_requirement_instances requirement_instances ON requirement_instances.onboarding_instance_id = instances.id
    JOIN public.onboarding_template_requirements requirements
      ON requirements.id = requirement_instances.template_requirement_id
     AND requirements.template_id = instances.template_id
    LEFT JOIN public.zelle_invoices invoice ON invoice.onboarding_requirement_instance_id = requirement_instances.id
    LEFT JOIN public.children children ON children.id = requirement_instances.child_id
    WHERE memberships.user_id = auth.uid() AND memberships.school_id = input_school_id
      AND memberships.active = TRUE AND instances.status IN ('in_progress', 'complete')
    ORDER BY requirements.position, children.first_name, children.last_name;
$$;

REVOKE ALL ON FUNCTION public.fetch_my_parent_onboarding_timeline(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fetch_my_onboarding_dashboard(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fetch_my_parent_onboarding_timeline(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_onboarding_dashboard(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260910100000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
