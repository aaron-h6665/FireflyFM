-- Onboarding recipients may complete their checklist, but only the role's
-- onboarding manager may edit or change the lifecycle of checklist assignments.
BEGIN;

CREATE OR REPLACE FUNCTION public.can_manage_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignments assignments
        WHERE assignments.id = assignment_uuid
          AND (
              (
                  assignments.category <> 'onboarding'
                  AND assignments.assigned_by = user_uuid
              )
              OR EXISTS (
                  SELECT 1
                  FROM public.onboarding_requirement_instances requirement_instances
                  JOIN public.onboarding_instances instances
                    ON instances.id = requirement_instances.onboarding_instance_id
                  JOIN public.onboarding_templates templates
                    ON templates.id = instances.template_id
                  WHERE requirement_instances.assignment_id = assignments.id
                    AND public.is_onboarding_template_manager(
                        templates.school_id,
                        templates.target_role,
                        user_uuid
                    )
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260728140000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
