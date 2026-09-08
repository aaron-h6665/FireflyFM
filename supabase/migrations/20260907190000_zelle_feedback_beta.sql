BEGIN;

-- Demo support is installed separately, only in the dedicated local project.
CREATE FUNCTION public.zelle_is_demo_environment() RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$ SELECT FALSE $$;
REVOKE ALL ON FUNCTION public.zelle_is_demo_environment() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.zelle_is_demo_environment() TO authenticated;

ALTER TABLE public.zelle_invoices
    ADD COLUMN recipient_snapshot JSONB,
    ADD COLUMN original_onboarding_requirement_id UUID REFERENCES public.onboarding_requirement_instances(id),
    ADD COLUMN is_demo BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN replaces_invoice_id UUID UNIQUE REFERENCES public.zelle_invoices(id);
UPDATE public.zelle_invoices invoice SET recipient_snapshot = jsonb_build_object(
    'display_name', profile.recipient_display_name, 'type', profile.recipient_type,
    'value', profile.recipient_value, 'memo', profile.memo_prefix || '-' || invoice.invoice_number,
    'instructions', profile.payment_instructions, 'legacy_backfill', TRUE
) FROM public.school_zelle_profiles profile WHERE profile.school_id = invoice.school_id;

CREATE FUNCTION public.zelle_snapshot_recipient() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE profile public.school_zelle_profiles%ROWTYPE;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.recipient_snapshot IS DISTINCT FROM OLD.recipient_snapshot
           OR NEW.is_demo IS DISTINCT FROM OLD.is_demo THEN
            RAISE EXCEPTION 'Invoice recipient and environment are immutable';
        END IF;
        RETURN NEW;
    END IF;
    SELECT * INTO profile FROM public.school_zelle_profiles WHERE school_id = NEW.school_id AND active;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active recipient instructions are required'; END IF;
    NEW.recipient_snapshot := jsonb_build_object('display_name', profile.recipient_display_name,
        'type', profile.recipient_type, 'value', profile.recipient_value,
        'memo', profile.memo_prefix || '-' || NEW.invoice_number, 'instructions', profile.payment_instructions);
    NEW.is_demo := public.zelle_is_demo_environment();
    RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.zelle_snapshot_recipient() FROM PUBLIC;
CREATE TRIGGER zelle_snapshot_recipient BEFORE INSERT OR UPDATE ON public.zelle_invoices
FOR EACH ROW EXECUTE FUNCTION public.zelle_snapshot_recipient();

-- One reference belongs to one invoice; attempts on that invoice remain append-only.
CREATE TABLE public.zelle_reference_claims (
    school_id UUID NOT NULL REFERENCES public.schools(id),
    reference TEXT NOT NULL,
    invoice_id UUID NOT NULL REFERENCES public.zelle_invoices(id),
    PRIMARY KEY (school_id, reference)
);
INSERT INTO public.zelle_reference_claims SELECT DISTINCT school_id, upper(confirmation_reference), invoice_id
FROM public.zelle_payment_submissions;
ALTER TABLE public.zelle_reference_claims ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.zelle_reference_claims FROM PUBLIC, anon, authenticated;
DROP INDEX public.uq_zelle_submission_school_confirmation;
CREATE FUNCTION public.zelle_claim_reference() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE claimed UUID;
BEGIN
    NEW.confirmation_reference := upper(NEW.confirmation_reference);
    INSERT INTO public.zelle_reference_claims VALUES (NEW.school_id, NEW.confirmation_reference, NEW.invoice_id)
    ON CONFLICT (school_id, reference) DO UPDATE SET reference = EXCLUDED.reference
    RETURNING invoice_id INTO claimed;
    IF claimed <> NEW.invoice_id THEN
        RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'This reference belongs to another invoice';
    END IF;
    RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.zelle_claim_reference() FROM PUBLIC;
CREATE TRIGGER zelle_claim_reference BEFORE INSERT ON public.zelle_payment_submissions
FOR EACH ROW EXECUTE FUNCTION public.zelle_claim_reference();

CREATE OR REPLACE FUNCTION public.zelle_can_review_invoice(invoice_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    invoice_record public.zelle_invoices%ROWTYPE;
    target_role TEXT;
BEGIN
    SELECT * INTO invoice_record FROM public.zelle_invoices WHERE id = invoice_uuid;
    IF NOT FOUND OR invoice_record.payer_user_id = user_uuid THEN RETURN FALSE; END IF;

    IF COALESCE(invoice_record.onboarding_requirement_instance_id, invoice_record.original_onboarding_requirement_id) IS NOT NULL THEN
        SELECT templates.target_role INTO target_role
        FROM public.onboarding_requirement_instances requirement_instance
        JOIN public.onboarding_instances onboarding_instance
          ON onboarding_instance.id = requirement_instance.onboarding_instance_id
        JOIN public.onboarding_templates templates ON templates.id = onboarding_instance.template_id
        WHERE requirement_instance.id = COALESCE(invoice_record.onboarding_requirement_instance_id, invoice_record.original_onboarding_requirement_id);
        RETURN public.is_onboarding_template_manager(invoice_record.school_id, target_role, user_uuid);
    END IF;

    RETURN public.has_direct_school_role(invoice_record.school_id, user_uuid, ARRAY['school_director']);
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
    IF input_amount_cents IS NULL OR input_sent_at IS NULL THEN RAISE EXCEPTION 'Amount and sent time are required'; END IF;
    IF NOT invoice_record.is_demo AND upper(input_confirmation_reference) LIKE 'TEST-%' THEN
        RAISE EXCEPTION 'Test references require the isolated demo environment';
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
          AND existing.invoice_id <> input_invoice_id
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
        invoice_record.id, 'zelle:invoice:' || submission_record.id::TEXT || ':review', actor
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
    WHERE id = input_submission_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment submission not found'; END IF;

    SELECT * INTO invoice_record FROM public.zelle_invoices
    WHERE id = submission_record.invoice_id FOR UPDATE;
    IF NOT FOUND OR NOT public.zelle_can_review_invoice(invoice_record.id, actor) THEN
        RAISE EXCEPTION 'You are not authorised to review this payment';
    END IF;
    SELECT * INTO submission_record FROM public.zelle_payment_submissions WHERE id = input_submission_id FOR UPDATE;
    IF input_decision IS NULL THEN RAISE EXCEPTION 'A decision is required'; END IF;
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
             ELSE 'Open the invoice to read the school feedback. Do not send another payment just to correct a reference.' END,
        invoice_record.id, 'zelle:invoice:' || submission_record.id::TEXT || ':decision:' || input_decision, actor
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
        SET status = 'not_started', waived_by = NULL, waiver_reason = NULL, completed_at = NULL
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


CREATE FUNCTION public.replace_zelle_invoice(input_invoice_id UUID, input_reason TEXT)
RETURNS SETOF public.zelle_invoices LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE old_invoice public.zelle_invoices%ROWTYPE; new_id UUID; requirement_id UUID;
BEGIN
    SELECT * INTO old_invoice FROM public.zelle_invoices WHERE id = input_invoice_id FOR UPDATE;
    IF NOT FOUND OR NOT public.zelle_can_review_invoice(input_invoice_id, auth.uid()) THEN
        RAISE EXCEPTION 'You cannot replace this invoice'; END IF;
    IF NULLIF(btrim(input_reason), '') IS NULL OR length(input_reason) > 450 THEN
        RAISE EXCEPTION 'A replacement reason is required (maximum 450 characters)'; END IF;
    SELECT id INTO new_id FROM public.zelle_invoices WHERE replaces_invoice_id = input_invoice_id;
    IF FOUND THEN RETURN QUERY SELECT * FROM public.zelle_invoices WHERE id = new_id; RETURN; END IF;
    IF old_invoice.status <> 'void' THEN RAISE EXCEPTION 'Void the invoice before replacing it'; END IF;
    requirement_id := old_invoice.onboarding_requirement_instance_id;
    IF requirement_id IS NOT NULL THEN
        PERFORM 1 FROM public.onboarding_requirement_instances
        WHERE id = requirement_id AND status NOT IN ('approved', 'waived') FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'This requirement is already complete'; END IF;
        UPDATE public.zelle_invoices SET original_onboarding_requirement_id = requirement_id, onboarding_requirement_instance_id = NULL WHERE id = input_invoice_id;
    END IF;
    INSERT INTO public.zelle_invoices (school_id, payer_user_id, payer_role, child_id,
        onboarding_requirement_instance_id, description, amount_due_cents, status, due_at, issued_at,
        created_by, replaces_invoice_id)
    VALUES (old_invoice.school_id, old_invoice.payer_user_id, old_invoice.payer_role, old_invoice.child_id,
        requirement_id, old_invoice.description, old_invoice.amount_due_cents, 'open', NOW() + INTERVAL '7 days',
        NOW(), auth.uid(), input_invoice_id) RETURNING id INTO new_id;
    INSERT INTO public.zelle_invoice_items (invoice_id, description, quantity, unit_amount_cents, amount_cents)
    SELECT new_id, description, quantity, unit_amount_cents, amount_cents
    FROM public.zelle_invoice_items WHERE invoice_id = input_invoice_id;
    INSERT INTO public.zelle_billing_audit_log (school_id, actor_id, action, entity_type, entity_id, metadata)
    VALUES (old_invoice.school_id, auth.uid(), 'invoice_replaced', 'invoice', input_invoice_id,
        jsonb_build_object('replacement_id', new_id, 'requirement_id', requirement_id, 'reason', btrim(input_reason)));
    PERFORM public.notify_zelle_recipients(old_invoice.school_id, ARRAY[old_invoice.payer_user_id],
        'Replacement invoice ready', 'Open Payments to review the replacement invoice.', new_id,
        'zelle:replacement:' || new_id::TEXT, auth.uid());
    RETURN QUERY SELECT * FROM public.zelle_invoices WHERE id = new_id;
END; $$;

CREATE FUNCTION public.waive_zelle_requirement(input_invoice_id UUID, input_reason TEXT)
RETURNS SETOF public.zelle_invoices LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE invoice public.zelle_invoices%ROWTYPE; membership_uuid UUID;
BEGIN
    SELECT * INTO invoice FROM public.zelle_invoices WHERE id = input_invoice_id FOR UPDATE;
    IF NOT FOUND OR NOT public.zelle_can_review_invoice(input_invoice_id, auth.uid())
       OR invoice.onboarding_requirement_instance_id IS NULL THEN
        RAISE EXCEPTION 'You cannot waive this payment requirement'; END IF;
    IF NULLIF(btrim(input_reason), '') IS NULL OR length(input_reason) > 450 THEN
        RAISE EXCEPTION 'A waiver reason is required (maximum 450 characters)'; END IF;
    IF invoice.status = 'paid' THEN RAISE EXCEPTION 'Paid requirements cannot be waived'; END IF;
    IF invoice.status <> 'void' THEN PERFORM public.void_zelle_invoice(input_invoice_id, input_reason); END IF;
    UPDATE public.onboarding_requirement_instances SET status = 'waived', waived_by = auth.uid(),
        waiver_reason = btrim(input_reason), completed_at = NOW()
    WHERE id = invoice.onboarding_requirement_instance_id;
    SELECT instance.membership_id INTO membership_uuid FROM public.onboarding_instances instance
    JOIN public.onboarding_requirement_instances requirement ON requirement.onboarding_instance_id = instance.id
    WHERE requirement.id = invoice.onboarding_requirement_instance_id;
    PERFORM public.refresh_onboarding_access(membership_uuid);
    INSERT INTO public.zelle_billing_audit_log(school_id, actor_id, action, entity_type, entity_id, metadata)
    VALUES(invoice.school_id, auth.uid(), 'payment_requirement_waived', 'onboarding_requirement',
        invoice.onboarding_requirement_instance_id, jsonb_build_object('reason', btrim(input_reason)));
    PERFORM public.notify_zelle_recipients(invoice.school_id, ARRAY[invoice.payer_user_id],
        'Payment requirement waived', 'The school waived this requirement. No payment receipt was issued.',
        invoice.id, 'zelle:waiver:' || invoice.id::TEXT, auth.uid());
    RETURN QUERY SELECT * FROM public.zelle_invoices WHERE id = input_invoice_id;
END; $$;
REVOKE ALL ON FUNCTION public.replace_zelle_invoice(UUID,TEXT), public.waive_zelle_requirement(UUID,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.replace_zelle_invoice(UUID,TEXT), public.waive_zelle_requirement(UUID,TEXT) TO authenticated;

-- Guidance alone never enables simulation on a normal deployment.
UPDATE public.school_zelle_profiles SET beta_simulation_enabled = FALSE;
ALTER TABLE public.school_zelle_profiles ALTER COLUMN beta_simulation_enabled SET DEFAULT FALSE;
CREATE OR REPLACE FUNCTION public.get_firefly_schema_version() RETURNS BIGINT
LANGUAGE sql IMMUTABLE AS $$ SELECT 20260907190000::BIGINT $$;
-- A classroom teacher receives one readiness label, never financial details.
CREATE FUNCTION public.fetch_child_enrollment_readiness(input_child_id UUID) RETURNS TEXT
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE school_uuid UUID;
BEGIN
    SELECT school_id INTO school_uuid FROM public.children WHERE id = input_child_id;
    IF school_uuid IS NULL OR NOT public.has_direct_school_role(school_uuid, auth.uid(), ARRAY['teacher'])
       OR NOT public.is_classroom_teacher_for_child(input_child_id, auth.uid()) THEN
        RAISE EXCEPTION 'Assigned teacher access required'; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.child_guardians WHERE child_id = input_child_id AND verification_status = 'verified') THEN
        RETURN 'School review needed'; END IF;
    IF EXISTS (
        SELECT 1 FROM public.child_guardians guardian
        JOIN public.school_memberships membership ON membership.user_id = guardian.guardian_id
        WHERE guardian.child_id = input_child_id AND guardian.verification_status = 'verified'
          AND membership.school_id = school_uuid AND membership.active AND membership.access_state = 'full'
    ) THEN RETURN 'Enrollment ready'; END IF;
    RETURN 'School review needed';
END; $$;
REVOKE ALL ON FUNCTION public.fetch_child_enrollment_readiness(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fetch_child_enrollment_readiness(UUID) TO authenticated;

COMMIT;
