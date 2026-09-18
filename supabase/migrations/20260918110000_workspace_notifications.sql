-- Keep Paperwork and Google Form notifications tied to the exact record that
-- changed. Payment notifications already use the same invoice-specific model.

CREATE OR REPLACE FUNCTION public.create_workspace_notification(
    input_school_id UUID,
    input_title TEXT,
    input_body TEXT,
    input_category TEXT,
    input_source_type TEXT,
    input_source_id UUID,
    input_recipient_ids UUID[],
    input_dedupe_key TEXT,
    input_actor_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    notification_uuid UUID;
BEGIN
    IF input_source_id IS NULL
       OR NULLIF(btrim(COALESCE(input_dedupe_key, '')), '') IS NULL
       OR COALESCE(cardinality(input_recipient_ids), 0) = 0 THEN
        RETURN;
    END IF;

    INSERT INTO public.notifications (
        school_id, title, body, category, source_type, source_id,
        created_by, dedupe_key
    ) VALUES (
        input_school_id, input_title, input_body, input_category,
        input_source_type, input_source_id, input_actor_id, input_dedupe_key
    )
    ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL
    DO UPDATE SET title = EXCLUDED.title, body = EXCLUDED.body
    RETURNING id INTO notification_uuid;

    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT notification_uuid, recipient_id
    FROM unnest(input_recipient_ids) AS recipient(recipient_id)
    WHERE recipient_id IS NOT NULL
    ON CONFLICT DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.create_workspace_notification(
    UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID[], TEXT, UUID
) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.notify_paperwork_published()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    request_record public.paperwork_assignments%ROWTYPE;
    recipients UUID[];
BEGIN
    IF NEW.event_type <> 'published' THEN
        RETURN NEW;
    END IF;

    SELECT * INTO request_record
    FROM public.paperwork_assignments
    WHERE id = NEW.request_id;

    SELECT COALESCE(array_agg(DISTINCT recipient.user_id), ARRAY[]::UUID[])
    INTO recipients
    FROM public.paperwork_assignment_recipients recipient
    WHERE recipient.assignment_id = NEW.request_id;

    PERFORM public.create_workspace_notification(
        NEW.school_id,
        'New paperwork',
        request_record.title,
        'paperwork_due',
        'paperwork_request',
        NEW.request_id,
        recipients,
        'paperwork:request:' || NEW.request_id::TEXT || ':published',
        NEW.actor_id
    );
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_paperwork_published() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS notify_paperwork_published_trigger ON public.paperwork_events;
CREATE TRIGGER notify_paperwork_published_trigger
AFTER INSERT ON public.paperwork_events
FOR EACH ROW EXECUTE FUNCTION public.notify_paperwork_published();

CREATE OR REPLACE FUNCTION public.notify_paperwork_submission_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    request_title TEXT;
    reviewers UUID[];
BEGIN
    SELECT assignment.title INTO request_title
    FROM public.paperwork_assignments assignment
    WHERE assignment.id = NEW.assignment_id;

    IF TG_OP = 'INSERT' AND NEW.status IN ('submitted', 'resubmitted') THEN
        SELECT COALESCE(array_agg(DISTINCT membership.user_id), ARRAY[]::UUID[])
        INTO reviewers
        FROM public.school_memberships membership
        WHERE membership.school_id = NEW.school_id
          AND membership.active
          AND membership.access_state = 'full'
          AND membership.role IN ('school_director', 'hq_director')
          AND membership.user_id <> NEW.submitted_by;

        PERFORM public.create_workspace_notification(
            NEW.school_id,
            'Paperwork needs review',
            COALESCE(request_title, 'A paperwork submission is ready for review.'),
            'paperwork_review',
            'paperwork_submission',
            NEW.id,
            reviewers,
            'paperwork:submission:' || NEW.id::TEXT || ':review',
            NEW.submitted_by
        );
    ELSIF TG_OP = 'UPDATE'
          AND NEW.status IS DISTINCT FROM OLD.status
          AND NEW.status IN ('accepted', 'changes_requested') THEN
        PERFORM public.create_workspace_notification(
            NEW.school_id,
            CASE WHEN NEW.status = 'accepted' THEN 'Paperwork approved' ELSE 'Paperwork changes requested' END,
            CASE WHEN NEW.status = 'accepted'
                 THEN COALESCE(request_title, 'Your paperwork was approved.')
                 ELSE COALESCE(NULLIF(btrim(NEW.reviewer_message), ''), 'Open Paperwork to review the requested changes.')
            END,
            'paperwork_reviewed',
            'paperwork_submission',
            NEW.id,
            ARRAY[NEW.submitted_by],
            'paperwork:submission:' || NEW.id::TEXT || ':decision:' || NEW.status,
            NEW.reviewed_by
        );
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_paperwork_submission_change() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS notify_paperwork_submission_change_trigger ON public.paperwork_submissions;
CREATE TRIGGER notify_paperwork_submission_change_trigger
AFTER INSERT OR UPDATE OF status ON public.paperwork_submissions
FOR EACH ROW EXECUTE FUNCTION public.notify_paperwork_submission_change();

CREATE OR REPLACE FUNCTION public.notify_google_form_import_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    form_title TEXT;
    recipient UUID := NEW.submitted_by;
    reviewers UUID[];
BEGIN
    SELECT connection.form_title INTO form_title
    FROM public.google_form_connections connection
    WHERE connection.id = NEW.connection_id;

    IF recipient IS NULL AND NEW.membership_id IS NOT NULL THEN
        SELECT membership.user_id INTO recipient
        FROM public.school_memberships membership
        WHERE membership.id = NEW.membership_id;
    END IF;

    IF NEW.status IN ('pending_review', 'ambiguous', 'error')
       AND (TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status) THEN
        SELECT COALESCE(array_agg(DISTINCT membership.user_id), ARRAY[]::UUID[])
        INTO reviewers
        FROM public.school_memberships membership
        WHERE membership.school_id = NEW.school_id
          AND membership.active
          AND membership.access_state = 'full'
          AND membership.role = 'school_director'
          AND membership.user_id IS DISTINCT FROM recipient;

        PERFORM public.create_workspace_notification(
            NEW.school_id,
            'Form response needs review',
            COALESCE(form_title, 'A Google Form response is ready for review.'),
            'google_form_response',
            'google_form_import',
            NEW.id,
            reviewers,
            'paperwork:form:' || NEW.id::TEXT || ':review:' || NEW.status,
            recipient
        );
    ELSIF TG_OP = 'UPDATE'
          AND NEW.status IS DISTINCT FROM OLD.status
          AND NEW.status IN ('approved', 'rejected', 'changes_requested') THEN
        PERFORM public.create_workspace_notification(
            NEW.school_id,
            CASE
                WHEN NEW.status = 'approved' THEN 'Form response approved'
                WHEN NEW.status = 'changes_requested' THEN 'Form changes requested'
                ELSE 'Form response not approved'
            END,
            CASE
                WHEN NEW.status = 'approved' THEN COALESCE(form_title, 'Your Form response was approved.')
                ELSE COALESCE(NULLIF(btrim(NEW.review_note), ''), 'Open Paperwork to review the response update.')
            END,
            'google_form_response',
            'google_form_import',
            NEW.id,
            ARRAY[recipient],
            'paperwork:form:' || NEW.id::TEXT || ':decision:' || NEW.status,
            NEW.reviewed_by
        );
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_google_form_import_change() FROM PUBLIC, anon, authenticated;
-- Supersede the earlier review-only trigger so one status change creates one
-- notification record and the same trigger can also notify the respondent.
DROP TRIGGER IF EXISTS notify_google_form_import_reviewers ON public.google_form_imports;
DROP TRIGGER IF EXISTS notify_google_form_import_change_trigger ON public.google_form_imports;
CREATE TRIGGER notify_google_form_import_change_trigger
AFTER INSERT OR UPDATE OF status ON public.google_form_imports
FOR EACH ROW EXECUTE FUNCTION public.notify_google_form_import_change();

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
AS $$ SELECT 20260918110000::BIGINT $$;

NOTIFY pgrst, 'reload schema';
