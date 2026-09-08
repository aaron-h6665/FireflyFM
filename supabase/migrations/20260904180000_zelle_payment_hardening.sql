BEGIN;

-- A payment step is valid only when its amount is explicit. PostgreSQL CHECK
-- constraints accept NULL/unknown expressions unless nullability is stated.
ALTER TABLE public.onboarding_template_requirements
    DROP CONSTRAINT IF EXISTS onboarding_template_payment_configuration_check;
ALTER TABLE public.onboarding_template_requirements
    ADD CONSTRAINT onboarding_template_payment_configuration_check CHECK (
        requirement_type <> 'payment'
        OR (
            subject_scope = 'member'
            AND payment_amount_cents IS NOT NULL
            AND payment_amount_cents BETWEEN 50 AND 100000000
            AND COALESCE(payment_due_days, 7) BETWEEN 1 AND 90
            AND blocks_access = TRUE
        )
    );

-- A bank confirmation reference may identify only one claimed transfer within
-- a school. This prevents the same transfer from being credited twice.
CREATE UNIQUE INDEX IF NOT EXISTS uq_zelle_submission_school_confirmation
    ON public.zelle_payment_submissions (school_id, upper(confirmation_reference));
CREATE UNIQUE INDEX IF NOT EXISTS uq_zelle_invoice_issue_idempotency
    ON public.zelle_billing_audit_log (school_id, action)
    WHERE action LIKE 'invoice_issue:%';

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
    old_requirement RECORD;
    new_requirement_id UUID;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF input_target_role NOT IN ('parent', 'teacher', 'school_director') THEN
        RAISE EXCEPTION 'Unsupported onboarding role';
    END IF;
    IF NOT public.is_onboarding_template_manager(input_school_id, input_target_role, actor) THEN
        RAISE EXCEPTION 'You cannot manage this onboarding template';
    END IF;

    SELECT * INTO existing_draft
    FROM public.onboarding_templates
    WHERE school_id = input_school_id AND target_role = input_target_role AND status = 'draft'
    LIMIT 1;
    IF FOUND THEN
        RETURN QUERY SELECT * FROM public.onboarding_templates WHERE id = existing_draft.id;
        RETURN;
    END IF;

    SELECT * INTO published_template
    FROM public.onboarding_templates
    WHERE school_id = input_school_id AND target_role = input_target_role AND status = 'published'
    ORDER BY version DESC LIMIT 1;

    INSERT INTO public.onboarding_templates (school_id, target_role, name, version, status, created_by)
    VALUES (
        input_school_id,
        input_target_role,
        CASE input_target_role
            WHEN 'school_director' THEN 'School Director Onboarding'
            WHEN 'parent' THEN 'Parent Onboarding'
            ELSE 'Teacher Onboarding'
        END,
        (SELECT COALESCE(MAX(existing.version), 0) + 1
         FROM public.onboarding_templates existing
         WHERE existing.school_id = input_school_id AND existing.target_role = input_target_role),
        'draft',
        actor
    ) RETURNING * INTO created_draft;

    IF published_template.id IS NOT NULL THEN
        FOR old_requirement IN
            SELECT * FROM public.onboarding_template_requirements
            WHERE template_id = published_template.id ORDER BY position
        LOOP
            INSERT INTO public.onboarding_template_requirements (
                template_id, requirement_key, position, requirement_type, title,
                description, subject_scope, blocks_access, child_record_binding,
                payment_amount_cents, payment_due_days
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
        END LOOP;
    END IF;

    RETURN QUERY SELECT * FROM public.onboarding_templates WHERE id = created_draft.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.save_onboarding_template_requirement_v2(
    input_template_id UUID,
    input_requirement_id UUID DEFAULT NULL,
    input_title TEXT DEFAULT NULL,
    input_description TEXT DEFAULT NULL,
    input_subject_scope TEXT DEFAULT 'member',
    input_position INTEGER DEFAULT 0,
    input_attachments JSONB DEFAULT '[]'::JSONB,
    input_blocks_access BOOLEAN DEFAULT TRUE,
    input_child_record_binding TEXT DEFAULT 'none',
    input_requirement_type TEXT DEFAULT 'document',
    input_payment_amount_cents BIGINT DEFAULT NULL,
    input_payment_due_days INTEGER DEFAULT NULL
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
    SELECT * INTO template_record FROM public.onboarding_templates WHERE id = input_template_id;
    IF NOT FOUND OR template_record.status <> 'draft'
       OR NOT public.is_onboarding_template_manager(template_record.school_id, template_record.target_role, actor) THEN
        RAISE EXCEPTION 'Requirements can only be changed by a manager in a draft template';
    END IF;
    IF NULLIF(btrim(COALESCE(input_title, '')), '') IS NULL THEN RAISE EXCEPTION 'A requirement title is required'; END IF;
    IF input_requirement_type NOT IN ('document', 'acknowledgement', 'payment') THEN RAISE EXCEPTION 'Requirement type is invalid'; END IF;
    IF input_subject_scope NOT IN ('member', 'child')
       OR (input_subject_scope = 'child' AND template_record.target_role <> 'parent') THEN
        RAISE EXCEPTION 'Child requirements are available only for parent templates';
    END IF;
    IF input_child_record_binding NOT IN (
        'none', 'child_document', 'immunization_record', 'medical_clearance',
        'medication_authorization', 'emergency_information', 'consent'
    ) OR (input_child_record_binding <> 'none' AND input_subject_scope <> 'child') THEN
        RAISE EXCEPTION 'The child record binding is invalid for this requirement';
    END IF;
    IF input_requirement_type = 'payment' AND (
        input_subject_scope <> 'member'
        OR input_payment_amount_cents IS NULL
        OR input_payment_amount_cents NOT BETWEEN 50 AND 100000000
        OR COALESCE(input_payment_due_days, 7) NOT BETWEEN 1 AND 90
        OR COALESCE(input_blocks_access, TRUE) <> TRUE
        OR jsonb_array_length(COALESCE(input_attachments, '[]'::JSONB)) <> 0
    ) THEN
        RAISE EXCEPTION 'Payment requirements are blocking, member-scoped, need an amount and due period, and cannot include paperwork';
    END IF;

    IF input_requirement_id IS NULL THEN
        INSERT INTO public.onboarding_template_requirements (
            template_id, position, requirement_type, title, description, subject_scope,
            blocks_access, child_record_binding, payment_amount_cents, payment_due_days
        ) VALUES (
            template_record.id, GREATEST(COALESCE(input_position, 0), 0), input_requirement_type,
            btrim(input_title), NULLIF(btrim(COALESCE(input_description, '')), ''), input_subject_scope,
            CASE WHEN input_requirement_type = 'payment' THEN TRUE ELSE COALESCE(input_blocks_access, TRUE) END,
            input_child_record_binding,
            CASE WHEN input_requirement_type = 'payment' THEN input_payment_amount_cents ELSE NULL END,
            CASE WHEN input_requirement_type = 'payment' THEN COALESCE(input_payment_due_days, 7) ELSE NULL END
        ) RETURNING * INTO saved_requirement;
    ELSE
        UPDATE public.onboarding_template_requirements
        SET title = btrim(input_title),
            description = NULLIF(btrim(COALESCE(input_description, '')), ''),
            requirement_type = input_requirement_type,
            subject_scope = input_subject_scope,
            blocks_access = CASE WHEN input_requirement_type = 'payment' THEN TRUE ELSE COALESCE(input_blocks_access, TRUE) END,
            child_record_binding = input_child_record_binding,
            payment_amount_cents = CASE WHEN input_requirement_type = 'payment' THEN input_payment_amount_cents ELSE NULL END,
            payment_due_days = CASE WHEN input_requirement_type = 'payment' THEN COALESCE(input_payment_due_days, 7) ELSE NULL END,
            updated_at = NOW()
        WHERE id = input_requirement_id AND template_id = template_record.id
        RETURNING * INTO saved_requirement;
        IF saved_requirement.id IS NULL THEN RAISE EXCEPTION 'Requirement not found in this draft'; END IF;
    END IF;

    DELETE FROM public.onboarding_template_attachments WHERE requirement_id = saved_requirement.id;
    IF input_requirement_type <> 'payment' THEN
        INSERT INTO public.onboarding_template_attachments (
            requirement_id, position, private_file_path, file_name, content_type
        )
        SELECT saved_requirement.id, attachment.ordinality::INTEGER - 1,
               attachment.value->>'private_file_path', attachment.value->>'file_name',
               NULLIF(attachment.value->>'content_type', '')
        FROM jsonb_array_elements(COALESCE(input_attachments, '[]'::JSONB))
             WITH ORDINALITY AS attachment(value, ordinality)
        WHERE NULLIF(attachment.value->>'private_file_path', '') IS NOT NULL
          AND NULLIF(attachment.value->>'file_name', '') IS NOT NULL;
    END IF;
    RETURN QUERY SELECT * FROM public.onboarding_template_requirements WHERE id = saved_requirement.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.require_active_zelle_profile_for_payment_template()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.status = 'published' AND OLD.status IS DISTINCT FROM 'published'
       AND EXISTS (
           SELECT 1 FROM public.onboarding_template_requirements requirement
           WHERE requirement.template_id = NEW.id
             AND requirement.requirement_type = 'payment'
             AND (
                 requirement.subject_scope <> 'member'
                 OR requirement.payment_amount_cents IS NULL
                 OR requirement.payment_amount_cents NOT BETWEEN 50 AND 100000000
                 OR COALESCE(requirement.payment_due_days, 7) NOT BETWEEN 1 AND 90
                 OR requirement.blocks_access <> TRUE
             )
       ) THEN
        RAISE EXCEPTION 'Every payment step needs a valid amount, due period, and blocking member scope';
    END IF;
    IF NEW.status = 'published' AND OLD.status IS DISTINCT FROM 'published'
       AND EXISTS (
           SELECT 1 FROM public.onboarding_template_requirements requirement
           WHERE requirement.template_id = NEW.id AND requirement.requirement_type = 'payment'
       )
       AND NOT EXISTS (
           SELECT 1 FROM public.school_zelle_profiles profile
           WHERE profile.school_id = NEW.school_id AND profile.active = TRUE
       ) THEN
        RAISE EXCEPTION 'Activate Zelle recipient instructions before publishing a template with a payment step';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.issue_zelle_invoice(
    input_school_id UUID,
    input_payer_user_id UUID,
    input_child_id UUID DEFAULT NULL,
    input_description TEXT DEFAULT NULL,
    input_due_at TIMESTAMPTZ DEFAULT NULL,
    input_items JSONB DEFAULT '[]'::JSONB,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.zelle_invoices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    invoice_uuid UUID;
    total_cents BIGINT;
    item RECORD;
BEGIN
    IF NOT public.has_direct_school_role(input_school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only an approved school director can issue an invoice';
    END IF;
    IF COALESCE(input_idempotency_key, '') !~ '^.{8,80}$' THEN
        RAISE EXCEPTION 'A valid idempotency key is required';
    END IF;
    PERFORM pg_advisory_xact_lock(
        hashtextextended(input_school_id::TEXT || ':' || input_idempotency_key, 0)
    );
    IF EXISTS (
        SELECT 1 FROM public.zelle_billing_audit_log audit
        WHERE audit.school_id = input_school_id AND audit.action = 'invoice_issue:' || input_idempotency_key
    ) THEN
        RETURN QUERY
        SELECT invoice.* FROM public.zelle_invoices invoice
        JOIN public.zelle_billing_audit_log audit ON audit.entity_id = invoice.id
        WHERE audit.school_id = input_school_id AND audit.action = 'invoice_issue:' || input_idempotency_key
        LIMIT 1;
        RETURN;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.school_zelle_profiles profile
        WHERE profile.school_id = input_school_id AND profile.active = TRUE
    ) THEN
        RAISE EXCEPTION 'Activate this school''s Zelle recipient instructions before issuing an invoice';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.school_memberships membership
        WHERE membership.school_id = input_school_id AND membership.user_id = input_payer_user_id
          AND membership.role = 'parent' AND membership.active = TRUE AND membership.access_state = 'full'
    ) THEN
        RAISE EXCEPTION 'Invoices can only be issued to an approved parent in this school';
    END IF;
    IF input_child_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.children child
        JOIN public.child_guardians guardian ON guardian.child_id = child.id
        WHERE child.id = input_child_id AND child.school_id = input_school_id
          AND guardian.guardian_id = input_payer_user_id
          AND guardian.verification_status = 'verified'
    ) THEN
        RAISE EXCEPTION 'The selected child is not linked to this verified parent';
    END IF;
    IF jsonb_typeof(COALESCE(input_items, '[]'::JSONB)) <> 'array'
       OR jsonb_array_length(COALESCE(input_items, '[]'::JSONB)) NOT BETWEEN 1 AND 20 THEN
        RAISE EXCEPTION 'Add between one and twenty invoice items';
    END IF;
    SELECT COALESCE(SUM((entry.value->>'quantity')::BIGINT * (entry.value->>'unit_amount_cents')::BIGINT), 0)
    INTO total_cents FROM jsonb_array_elements(input_items) AS entry(value);
    IF total_cents NOT BETWEEN 50 AND 100000000 THEN RAISE EXCEPTION 'Invoice total is invalid'; END IF;

    INSERT INTO public.zelle_invoices (
        school_id, payer_user_id, payer_role, child_id, description,
        amount_due_cents, status, due_at, issued_at, created_by
    ) VALUES (
        input_school_id, input_payer_user_id, 'parent', input_child_id,
        COALESCE(NULLIF(btrim(input_description), ''), 'School invoice'),
        total_cents, 'open', input_due_at, NOW(), actor
    ) RETURNING id INTO invoice_uuid;
    FOR item IN SELECT entry.value AS payload FROM jsonb_array_elements(input_items) AS entry(value) LOOP
        IF NULLIF(btrim(item.payload->>'description'), '') IS NULL
           OR COALESCE((item.payload->>'quantity')::INTEGER, 0) NOT BETWEEN 1 AND 100
           OR COALESCE((item.payload->>'unit_amount_cents')::BIGINT, 0) NOT BETWEEN 50 AND 100000000 THEN
            RAISE EXCEPTION 'Each invoice item needs a description, quantity, and amount';
        END IF;
        INSERT INTO public.zelle_invoice_items (invoice_id, description, quantity, unit_amount_cents, amount_cents)
        VALUES (
            invoice_uuid, btrim(item.payload->>'description'), (item.payload->>'quantity')::INTEGER,
            (item.payload->>'unit_amount_cents')::BIGINT,
            (item.payload->>'quantity')::BIGINT * (item.payload->>'unit_amount_cents')::BIGINT
        );
    END LOOP;
    INSERT INTO public.zelle_billing_audit_log (school_id, actor_id, action, entity_type, entity_id)
    VALUES (input_school_id, actor, 'invoice_issue:' || input_idempotency_key, 'invoice', invoice_uuid);
    PERFORM public.notify_zelle_recipients(
        input_school_id, ARRAY[input_payer_user_id], 'New school invoice',
        'A Zelle invoice is ready for your review and payment submission.', invoice_uuid,
        'zelle:invoice:' || invoice_uuid::TEXT || ':payer', actor
    );
    RETURN QUERY SELECT * FROM public.zelle_invoices WHERE id = invoice_uuid;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_zelle_payment(
    input_invoice_id UUID,
    input_amount_cents BIGINT,
    input_sent_at TIMESTAMPTZ,
    input_confirmation_reference TEXT,
    input_idempotency_key TEXT
)
RETURNS SETOF public.zelle_payment_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    invoice_record public.zelle_invoices%ROWTYPE;
    submission_record public.zelle_payment_submissions%ROWTYPE;
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

    IF invoice_record.status NOT IN ('open', 'rejected') THEN
        RAISE EXCEPTION 'This invoice cannot accept a new payment submission';
    END IF;
    IF input_amount_cents <> invoice_record.amount_due_cents THEN
        RAISE EXCEPTION 'This beta requires the full invoice amount in one payment';
    END IF;
    IF input_sent_at > NOW() + INTERVAL '15 minutes' OR input_sent_at < NOW() - INTERVAL '180 days'
       OR COALESCE(input_confirmation_reference, '') !~ '^[A-Za-z0-9-]{4,64}$'
       OR COALESCE(input_idempotency_key, '') !~ '^.{8,180}$' THEN
        RAISE EXCEPTION 'The payment submission is invalid';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.zelle_payment_submissions existing
        WHERE existing.school_id = invoice_record.school_id
          AND upper(existing.confirmation_reference) = upper(input_confirmation_reference)
    ) THEN
        RAISE EXCEPTION 'This confirmation reference has already been used for this school';
    END IF;

    INSERT INTO public.zelle_payment_submissions (
        invoice_id, school_id, payer_user_id, amount_cents, sent_at, confirmation_reference, idempotency_key
    ) VALUES (
        invoice_record.id, invoice_record.school_id, actor, input_amount_cents,
        input_sent_at, upper(input_confirmation_reference), input_idempotency_key
    ) RETURNING * INTO submission_record;
    UPDATE public.zelle_invoices SET status = 'payment_submitted', updated_at = NOW()
    WHERE id = invoice_record.id;
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
        invoice_record.id, 'zelle:invoice:' || invoice_record.id::TEXT || ':review', actor
    );
    RETURN QUERY SELECT * FROM public.zelle_payment_submissions WHERE id = submission_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_zelle_payment(
    input_submission_id UUID,
    input_decision TEXT,
    input_reviewer_note TEXT DEFAULT NULL
)
RETURNS SETOF public.zelle_invoices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    submission_record public.zelle_payment_submissions%ROWTYPE;
    invoice_record public.zelle_invoices%ROWTYPE;
    membership_uuid UUID;
BEGIN
    SELECT * INTO submission_record FROM public.zelle_payment_submissions
    WHERE id = input_submission_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment submission not found'; END IF;

    SELECT * INTO invoice_record FROM public.zelle_invoices
    WHERE id = submission_record.invoice_id FOR UPDATE;
    IF NOT FOUND OR NOT public.zelle_can_review_invoice(invoice_record.id, actor) THEN
        RAISE EXCEPTION 'You are not authorised to review this payment';
    END IF;
    IF invoice_record.status NOT IN ('payment_submitted', 'under_review')
       OR submission_record.status NOT IN ('submitted', 'under_review')
       OR input_decision NOT IN ('approved', 'rejected') THEN
        RAISE EXCEPTION 'This payment submission cannot be reviewed';
    END IF;
    IF input_decision = 'rejected' AND NULLIF(btrim(COALESCE(input_reviewer_note, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Explain what the payer should correct before rejecting a payment';
    END IF;
    IF char_length(COALESCE(input_reviewer_note, '')) > 500 THEN
        RAISE EXCEPTION 'The reviewer note is too long';
    END IF;

    UPDATE public.zelle_payment_submissions
    SET status = input_decision,
        reviewer_note = NULLIF(btrim(COALESCE(input_reviewer_note, '')), ''),
        reviewed_by = actor, reviewed_at = NOW(), updated_at = NOW()
    WHERE id = submission_record.id;
    UPDATE public.zelle_invoices
    SET status = CASE WHEN input_decision = 'approved' THEN 'paid' ELSE 'rejected' END,
        amount_paid_cents = CASE WHEN input_decision = 'approved' THEN amount_due_cents ELSE 0 END,
        paid_at = CASE WHEN input_decision = 'approved' THEN NOW() ELSE NULL END,
        updated_at = NOW()
    WHERE id = invoice_record.id
    RETURNING * INTO invoice_record;

    IF invoice_record.onboarding_requirement_instance_id IS NOT NULL THEN
        UPDATE public.onboarding_requirement_instances
        SET status = CASE WHEN input_decision = 'approved' THEN 'approved' ELSE 'changes_requested' END,
            completed_at = CASE WHEN input_decision = 'approved' THEN NOW() ELSE NULL END
        WHERE id = invoice_record.onboarding_requirement_instance_id;
        SELECT instance.membership_id INTO membership_uuid
        FROM public.onboarding_requirement_instances requirement_instance
        JOIN public.onboarding_instances instance ON instance.id = requirement_instance.onboarding_instance_id
        WHERE requirement_instance.id = invoice_record.onboarding_requirement_instance_id;
        PERFORM public.refresh_onboarding_access(membership_uuid);
    END IF;

    INSERT INTO public.zelle_billing_audit_log (school_id, actor_id, action, entity_type, entity_id, metadata)
    VALUES (
        invoice_record.school_id, actor, 'payment_' || input_decision, 'submission', submission_record.id,
        jsonb_build_object('invoice_id', invoice_record.id)
    );
    PERFORM public.notify_zelle_recipients(
        invoice_record.school_id, ARRAY[invoice_record.payer_user_id],
        CASE WHEN input_decision = 'approved' THEN 'Payment approved' ELSE 'Payment update requested' END,
        CASE WHEN input_decision = 'approved'
             THEN 'Your school has verified the payment. Your receipt is now available in FireflyFM.'
             ELSE COALESCE(NULLIF(btrim(input_reviewer_note), ''), 'Please submit a new payment confirmation reference.') END,
        invoice_record.id, 'zelle:invoice:' || invoice_record.id::TEXT || ':decision:' || input_decision, actor
    );
    RETURN QUERY SELECT * FROM public.zelle_invoices WHERE id = invoice_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.void_zelle_invoice(input_invoice_id UUID, input_reason TEXT)
RETURNS SETOF public.zelle_invoices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    invoice_record public.zelle_invoices%ROWTYPE;
    membership_uuid UUID;
BEGIN
    SELECT * INTO invoice_record FROM public.zelle_invoices WHERE id = input_invoice_id FOR UPDATE;
    IF NOT FOUND OR NOT public.zelle_can_review_invoice(invoice_record.id, actor) THEN
        RAISE EXCEPTION 'You cannot void this invoice';
    END IF;
    IF invoice_record.status IN ('paid', 'void') THEN
        RAISE EXCEPTION 'Paid or already void invoices cannot be voided';
    END IF;
    IF NULLIF(btrim(COALESCE(input_reason, '')), '') IS NULL
       OR char_length(btrim(input_reason)) > 450 THEN
        RAISE EXCEPTION 'A void reason between 1 and 450 characters is required';
    END IF;

    UPDATE public.zelle_payment_submissions
    SET status = 'rejected', reviewer_note = 'Invoice voided: ' || btrim(input_reason),
        reviewed_by = actor, reviewed_at = NOW(), updated_at = NOW()
    WHERE invoice_id = invoice_record.id AND status IN ('submitted', 'under_review');
    UPDATE public.zelle_invoices
    SET status = 'void', amount_paid_cents = 0, paid_at = NULL,
        voided_at = NOW(), updated_at = NOW()
    WHERE id = invoice_record.id
    RETURNING * INTO invoice_record;

    IF invoice_record.onboarding_requirement_instance_id IS NOT NULL THEN
        UPDATE public.onboarding_requirement_instances
        SET status = 'waived', waived_by = actor, waiver_reason = btrim(input_reason), completed_at = NOW()
        WHERE id = invoice_record.onboarding_requirement_instance_id;
        SELECT instance.membership_id INTO membership_uuid
        FROM public.onboarding_requirement_instances requirement_instance
        JOIN public.onboarding_instances instance ON instance.id = requirement_instance.onboarding_instance_id
        WHERE requirement_instance.id = invoice_record.onboarding_requirement_instance_id;
        PERFORM public.refresh_onboarding_access(membership_uuid);
    END IF;

    INSERT INTO public.zelle_billing_audit_log (school_id, actor_id, action, entity_type, entity_id, metadata)
    VALUES (
        invoice_record.school_id, actor, 'invoice_voided', 'invoice', invoice_record.id,
        jsonb_build_object('reason', btrim(input_reason))
    );
    PERFORM public.notify_zelle_recipients(
        invoice_record.school_id, ARRAY[invoice_record.payer_user_id],
        'Invoice voided', 'This invoice is no longer payable. Contact your school if you have questions.',
        invoice_record.id, 'zelle:invoice:' || invoice_record.id::TEXT || ':void', actor
    );
    RETURN QUERY SELECT * FROM public.zelle_invoices WHERE id = invoice_record.id;
END;
$$;

-- archive_and_delete_school writes its recovery record immediately before it
-- deletes the school. Merge the Zelle ledger into that record, then remove the
-- FK rows in a deterministic order. A direct delete without an archive is
-- refused whenever payment data exists.
CREATE OR REPLACE FUNCTION public.archive_zelle_before_school_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    backup_uuid UUID;
BEGIN
    IF EXISTS (SELECT 1 FROM public.school_zelle_profiles WHERE school_id = OLD.id)
       OR EXISTS (SELECT 1 FROM public.zelle_invoices WHERE school_id = OLD.id)
       OR EXISTS (SELECT 1 FROM public.zelle_payment_submissions WHERE school_id = OLD.id)
       OR EXISTS (SELECT 1 FROM public.zelle_billing_audit_log WHERE school_id = OLD.id) THEN
        SELECT id INTO backup_uuid
        FROM public.school_deletion_backups
        WHERE school_id = OLD.id
          AND deleted_by IS NOT DISTINCT FROM auth.uid()
          AND deleted_at >= NOW() - INTERVAL '5 minutes'
        ORDER BY deleted_at DESC
        LIMIT 1
        FOR UPDATE;
        IF backup_uuid IS NULL THEN
            RAISE EXCEPTION 'Payment records require archive_and_delete_school before this school can be deleted';
        END IF;

        UPDATE public.school_deletion_backups
        SET backup_payload = backup_payload || jsonb_build_object(
            'school_zelle_profiles', COALESCE((
                SELECT jsonb_agg(to_jsonb(profile)) FROM public.school_zelle_profiles profile
                WHERE profile.school_id = OLD.id
            ), '[]'::JSONB),
            'zelle_invoices', COALESCE((
                SELECT jsonb_agg(to_jsonb(invoice)) FROM public.zelle_invoices invoice
                WHERE invoice.school_id = OLD.id
            ), '[]'::JSONB),
            'zelle_invoice_items', COALESCE((
                SELECT jsonb_agg(to_jsonb(item)) FROM public.zelle_invoice_items item
                JOIN public.zelle_invoices invoice ON invoice.id = item.invoice_id
                WHERE invoice.school_id = OLD.id
            ), '[]'::JSONB),
            'zelle_payment_submissions', COALESCE((
                SELECT jsonb_agg(to_jsonb(submission)) FROM public.zelle_payment_submissions submission
                WHERE submission.school_id = OLD.id
            ), '[]'::JSONB),
            'zelle_billing_audit_log', COALESCE((
                SELECT jsonb_agg(to_jsonb(audit)) FROM public.zelle_billing_audit_log audit
                WHERE audit.school_id = OLD.id
            ), '[]'::JSONB)
        )
        WHERE id = backup_uuid;

        DELETE FROM public.zelle_payment_submissions WHERE school_id = OLD.id;
        DELETE FROM public.zelle_invoice_items
        WHERE invoice_id IN (SELECT id FROM public.zelle_invoices WHERE school_id = OLD.id);
        DELETE FROM public.zelle_invoices WHERE school_id = OLD.id;
        DELETE FROM public.school_zelle_profiles WHERE school_id = OLD.id;
    END IF;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS archive_zelle_before_school_delete_trigger ON public.schools;
CREATE TRIGGER archive_zelle_before_school_delete_trigger
    BEFORE DELETE ON public.schools
    FOR EACH ROW EXECUTE FUNCTION public.archive_zelle_before_school_delete();

-- This helper is invoked only by trusted onboarding functions. It performs no
-- actor authorization of its own and must never be exposed as an API RPC.
REVOKE ALL ON FUNCTION public.create_onboarding_assignment(UUID, UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.archive_zelle_before_school_delete() FROM PUBLIC, anon, authenticated;

-- These onboarding/Form functions return columns whose names intentionally
-- match underlying table columns. Add a compile-time PL/pgSQL directive to the
-- existing definitions so approved Form intake and director participant
-- updates cannot fail on the default ambiguity check. CREATE OR REPLACE keeps
-- the established owner, signature, and grants intact.
DO $migration$
DECLARE
    function_signature TEXT;
    function_definition TEXT;
    rewritten_definition TEXT;
BEGIN
    FOREACH function_signature IN ARRAY ARRAY[
        'public.begin_google_form_submission(uuid)',
        'public.approve_google_form_child_intake(uuid,text,uuid,text)',
        'public.set_director_chat_participants(uuid,uuid[])'
    ] LOOP
        SELECT pg_get_functiondef(function_signature::regprocedure)
        INTO function_definition;
        rewritten_definition := replace(
            function_definition,
            E'AS $function$\n',
            E'AS $function$\n#variable_conflict use_column\n'
        );
        IF rewritten_definition = function_definition THEN
            RAISE EXCEPTION 'Could not harden function definition for %', function_signature;
        END IF;
        EXECUTE rewritten_definition;
    END LOOP;
END;
$migration$;

-- pgcrypto lives in Supabase's trusted extensions schema; name it explicitly
-- in the function search path so digest() resolves consistently.
ALTER FUNCTION public.begin_google_form_submission(UUID)
    SET search_path = public, extensions;
ALTER FUNCTION public.ingest_google_form_import(UUID)
    SET search_path = public, extensions;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260904180000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
