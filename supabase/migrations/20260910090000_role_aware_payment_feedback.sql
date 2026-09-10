-- Keep payment feedback and receipts accurate across the full onboarding
-- hierarchy: school directors review parent/teacher payments and HQ reviews
-- school-director onboarding payments.

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
    payer_message TEXT;
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

    payer_message := CASE
        WHEN invoice_record.payer_role = 'school_director'
             AND invoice_record.onboarding_requirement_instance_id IS NOT NULL
             AND input_decision = 'approved'
            THEN 'FireflyFM HQ has verified the payment. Your receipt is now available in FireflyFM.'
        WHEN invoice_record.payer_role = 'school_director'
             AND invoice_record.onboarding_requirement_instance_id IS NOT NULL
            THEN 'Open the invoice to read FireflyFM HQ feedback. Do not send another payment just to correct a reference.'
        WHEN input_decision = 'approved'
            THEN 'Your school director has verified the payment. Your receipt is now available in FireflyFM.'
        ELSE 'Open the invoice to read feedback from your school director. Do not send another payment just to correct a reference.'
    END;

    PERFORM public.notify_zelle_recipients(
        invoice_record.school_id, ARRAY[invoice_record.payer_user_id],
        CASE WHEN input_decision = 'approved' THEN 'Payment approved' ELSE 'Payment update requested' END,
        payer_message,
        invoice_record.id, 'zelle:invoice:' || submission_record.id::TEXT || ':decision:' || input_decision, actor
    );
    RETURN QUERY SELECT * FROM public.zelle_invoices WHERE id = invoice_record.id;
END;
$$;

REVOKE ALL ON FUNCTION public.review_zelle_payment(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_zelle_payment(UUID, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260910090000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
