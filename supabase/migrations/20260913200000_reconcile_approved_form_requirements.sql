-- An approved parent Form can create or match a child while satisfying a
-- member-scoped onboarding requirement. Resolve requirement evidence by the
-- template's declared scope, not merely by whether the approved import has a
-- child_id. Stable requirement keys also let an in-flight response follow a
-- recipient onto the current published template version.

CREATE OR REPLACE FUNCTION public.reconcile_google_form_import_requirement(input_import_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    form_import public.google_form_imports%ROWTYPE;
    snapshot_requirement_id UUID;
    requirement_instance_id UUID;
    requirement_status TEXT;
BEGIN
    SELECT * INTO form_import
    FROM public.google_form_imports
    WHERE id = input_import_id
      AND status = 'approved';

    IF NOT FOUND OR form_import.membership_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT NULLIF(session.connection_snapshot ->> 'requirement_id', '')::UUID
    INTO snapshot_requirement_id
    FROM public.google_form_submission_sessions session
    WHERE session.id = form_import.submission_session_id;

    IF snapshot_requirement_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT requirement_instance.id, requirement_instance.status
    INTO requirement_instance_id, requirement_status
    FROM public.onboarding_instances instance
    JOIN public.onboarding_requirement_instances requirement_instance
      ON requirement_instance.onboarding_instance_id = instance.id
    JOIN public.onboarding_template_requirements current_requirement
      ON current_requirement.id = requirement_instance.template_requirement_id
     AND current_requirement.template_id = instance.template_id
    JOIN public.onboarding_template_requirements snapshot_requirement
      ON snapshot_requirement.id = snapshot_requirement_id
    WHERE instance.membership_id = form_import.membership_id
      AND instance.status IN ('in_progress', 'complete')
      AND (
          current_requirement.id = snapshot_requirement.id
          OR (
              current_requirement.requirement_key = snapshot_requirement.requirement_key
              AND current_requirement.requirement_type = snapshot_requirement.requirement_type
              AND current_requirement.subject_scope = snapshot_requirement.subject_scope
          )
      )
      AND (
          (current_requirement.subject_scope = 'member' AND requirement_instance.child_id IS NULL)
          OR (
              current_requirement.subject_scope = 'child'
              AND form_import.child_id IS NOT NULL
              AND requirement_instance.child_id = form_import.child_id
          )
      )
    ORDER BY
        (current_requirement.id = snapshot_requirement.id) DESC,
        instance.started_at DESC
    LIMIT 1
    FOR UPDATE OF requirement_instance;

    IF requirement_instance_id IS NULL THEN
        RETURN NULL;
    END IF;

    IF requirement_status <> 'waived' THEN
        UPDATE public.onboarding_requirement_instances
        SET status = 'approved',
            completed_at = COALESCE(completed_at, NOW())
        WHERE id = requirement_instance_id;

        IF form_import.reviewed_by IS NOT NULL THEN
            INSERT INTO public.google_form_requirement_evidence (
                import_id, requirement_instance_id, approved_by
            ) VALUES (
                form_import.id, requirement_instance_id, form_import.reviewed_by
            )
            ON CONFLICT DO NOTHING;
        END IF;
    END IF;

    PERFORM public.refresh_onboarding_access(form_import.membership_id);
    RETURN requirement_instance_id;
END;
$$;

REVOKE ALL ON FUNCTION public.reconcile_google_form_import_requirement(UUID)
FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.reconcile_approved_google_form_import_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.status = 'approved'
       AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'approved') THEN
        PERFORM public.reconcile_google_form_import_requirement(NEW.id);
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.reconcile_approved_google_form_import_trigger()
FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS reconcile_approved_google_form_import
ON public.google_form_imports;
CREATE TRIGGER reconcile_approved_google_form_import
AFTER INSERT OR UPDATE OF status ON public.google_form_imports
FOR EACH ROW EXECUTE FUNCTION public.reconcile_approved_google_form_import_trigger();

-- Repair approved imports whose earlier approval did not attach requirement
-- evidence, including member-scoped parent Forms that also created a child.
DO $$
DECLARE
    import_record RECORD;
BEGIN
    FOR import_record IN
        SELECT form_import.id
        FROM public.google_form_imports form_import
        WHERE form_import.status = 'approved'
          AND form_import.membership_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM public.google_form_requirement_evidence evidence
              WHERE evidence.import_id = form_import.id
          )
    LOOP
        PERFORM public.reconcile_google_form_import_requirement(import_record.id);
    END LOOP;
END;
$$;

NOTIFY pgrst, 'reload schema';
