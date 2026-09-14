-- A reviewed Google Form import is immutable history. Completed onboarding
-- assignments are archived automatically so recipients and their role-aware
-- reviewers see them under Archived instead of Active paperwork.

ALTER FUNCTION public.approve_google_form_child_intake(UUID, TEXT, UUID, TEXT)
    RENAME TO apply_google_form_child_intake_review;

REVOKE ALL ON FUNCTION public.apply_google_form_child_intake_review(UUID, TEXT, UUID, TEXT)
FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.approve_google_form_child_intake(
    input_import_id UUID,
    input_decision TEXT,
    input_matched_child_id UUID DEFAULT NULL,
    input_review_note TEXT DEFAULT NULL
)
RETURNS TABLE (import_id UUID, child_id UUID, access_state TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    current_status TEXT;
BEGIN
    SELECT form_import.status
    INTO current_status
    FROM public.google_form_imports form_import
    WHERE form_import.id = input_import_id
      AND public.has_school_role(form_import.school_id, actor, ARRAY['school_director'])
    FOR UPDATE;

    IF current_status IS NULL THEN
        RAISE EXCEPTION 'Only a school director can review this Form response';
    END IF;
    IF current_status IN ('approved', 'rejected', 'changes_requested') THEN
        RAISE EXCEPTION 'This Form response has already been reviewed and archived';
    END IF;

    RETURN QUERY
    SELECT *
    FROM public.apply_google_form_child_intake_review(
        input_import_id,
        input_decision,
        input_matched_child_id,
        input_review_note
    );
END;
$$;

REVOKE ALL ON FUNCTION public.approve_google_form_child_intake(UUID, TEXT, UUID, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_google_form_child_intake(UUID, TEXT, UUID, TEXT)
TO authenticated;

CREATE OR REPLACE FUNCTION public.prevent_reviewed_google_form_import_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF OLD.status IN ('approved', 'rejected', 'changes_requested')
       AND NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION 'Reviewed Form responses are archived and cannot be changed';
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.prevent_reviewed_google_form_import_changes()
FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS prevent_reviewed_google_form_import_changes_trigger
ON public.google_form_imports;
CREATE TRIGGER prevent_reviewed_google_form_import_changes_trigger
BEFORE UPDATE OF status ON public.google_form_imports
FOR EACH ROW EXECUTE FUNCTION public.prevent_reviewed_google_form_import_changes();

CREATE OR REPLACE FUNCTION public.archive_completed_onboarding_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    archived_school_id UUID;
BEGIN
    IF NEW.completion_status NOT IN ('accepted', 'excused') THEN
        RETURN NEW;
    END IF;

    UPDATE public.assignments assignment
    SET status = 'archived', updated_at = NOW()
    WHERE assignment.id = NEW.assignment_id
      AND assignment.category = 'onboarding'
      AND assignment.status <> 'archived'
      AND NOT EXISTS (
          SELECT 1
          FROM public.assignment_recipients recipient
          WHERE recipient.assignment_id = assignment.id
            AND recipient.completion_status NOT IN ('accepted', 'excused')
      )
    RETURNING assignment.school_id INTO archived_school_id;

    IF archived_school_id IS NOT NULL THEN
        INSERT INTO public.assignment_events (
            assignment_id, school_id, actor_id, event_type, metadata
        ) VALUES (
            NEW.assignment_id,
            archived_school_id,
            auth.uid(),
            'archived',
            jsonb_build_object('reason', 'onboarding_completed')
        );
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.archive_completed_onboarding_assignment()
FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS archive_completed_onboarding_assignment_trigger
ON public.assignment_recipients;
CREATE TRIGGER archive_completed_onboarding_assignment_trigger
AFTER INSERT OR UPDATE OF completion_status ON public.assignment_recipients
FOR EACH ROW EXECUTE FUNCTION public.archive_completed_onboarding_assignment();

CREATE OR REPLACE FUNCTION public.sync_completed_onboarding_requirement_to_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.assignment_id IS NULL
       OR NEW.status NOT IN ('approved', 'waived')
       OR (TG_OP = 'UPDATE' AND NEW.status IS NOT DISTINCT FROM OLD.status) THEN
        RETURN NEW;
    END IF;

    UPDATE public.assignment_recipients recipient
    SET completion_status = CASE WHEN NEW.status = 'approved' THEN 'accepted' ELSE 'excused' END,
        completed_at = COALESCE(recipient.completed_at, NEW.completed_at, NOW())
    WHERE recipient.assignment_id = NEW.assignment_id
      AND recipient.completion_status IS DISTINCT FROM
          CASE WHEN NEW.status = 'approved' THEN 'accepted' ELSE 'excused' END;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_completed_onboarding_requirement_to_assignment()
FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS sync_completed_onboarding_requirement_to_assignment_trigger
ON public.onboarding_requirement_instances;
CREATE TRIGGER sync_completed_onboarding_requirement_to_assignment_trigger
AFTER INSERT OR UPDATE OF status ON public.onboarding_requirement_instances
FOR EACH ROW EXECUTE FUNCTION public.sync_completed_onboarding_requirement_to_assignment();

-- Bring previously completed requirements into the same terminal state. The
-- recipient trigger above archives an onboarding assignment only after every
-- recipient is accepted or excused.
UPDATE public.assignment_recipients recipient
SET completion_status = CASE
        WHEN EXISTS (
            SELECT 1 FROM public.onboarding_requirement_instances requirement
            WHERE requirement.assignment_id = recipient.assignment_id
              AND requirement.status = 'approved'
        ) THEN 'accepted'
        ELSE 'excused'
    END,
    completed_at = COALESCE(recipient.completed_at, NOW())
WHERE EXISTS (
    SELECT 1
    FROM public.onboarding_requirement_instances requirement
    WHERE requirement.assignment_id = recipient.assignment_id
      AND requirement.status IN ('approved', 'waived')
)
AND recipient.completion_status NOT IN ('accepted', 'excused');

UPDATE public.assignments assignment
SET status = 'archived', updated_at = NOW()
WHERE assignment.category = 'onboarding'
  AND assignment.status <> 'archived'
  AND EXISTS (
      SELECT 1 FROM public.assignment_recipients recipient
      WHERE recipient.assignment_id = assignment.id
  )
  AND NOT EXISTS (
      SELECT 1 FROM public.assignment_recipients recipient
      WHERE recipient.assignment_id = assignment.id
        AND recipient.completion_status NOT IN ('accepted', 'excused')
  );

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260913210000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
