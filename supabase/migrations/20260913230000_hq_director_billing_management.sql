-- Migration: 20260913230000_hq_director_billing_management.sql
-- Allow HQ directors to issue invoices and review payments across any school in the organization.

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
    IF NOT FOUND THEN RETURN FALSE; END IF;

    IF COALESCE(invoice_record.onboarding_requirement_instance_id, invoice_record.original_onboarding_requirement_id) IS NOT NULL THEN
        SELECT templates.target_role INTO target_role
        FROM public.onboarding_requirement_instances requirement_instance
        JOIN public.onboarding_instances onboarding_instance
          ON onboarding_instance.id = requirement_instance.onboarding_instance_id
        JOIN public.onboarding_templates templates ON templates.id = onboarding_instance.template_id
        WHERE requirement_instance.id = COALESCE(invoice_record.onboarding_requirement_instance_id, invoice_record.original_onboarding_requirement_id);
        RETURN public.is_onboarding_template_manager(invoice_record.school_id, target_role, user_uuid);
    END IF;

    RETURN public.has_direct_school_role(invoice_record.school_id, user_uuid, ARRAY['school_director'])
        OR public.is_hq_director(user_uuid);
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
    IF NOT (
        public.has_direct_school_role(input_school_id, actor, ARRAY['school_director'])
        OR public.is_hq_director(actor)
    ) THEN
        RAISE EXCEPTION 'Only an approved school director or HQ director can issue an invoice';
    END IF;
    IF COALESCE(input_idempotency_key, '') !~ '^.{8,180}$' THEN
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

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT 20260913230000::BIGINT;
$$;
