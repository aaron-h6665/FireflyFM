-- HQ collects director fees independently of each school's receiving settings.
BEGIN;
CREATE TABLE public.hq_zelle_profile (
    id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK(id),
    recipient_display_name TEXT NOT NULL CHECK(length(btrim(recipient_display_name)) BETWEEN 2 AND 120),
    recipient_type TEXT NOT NULL CHECK(recipient_type IN ('email','mobile')),
    recipient_value TEXT NOT NULL CHECK(length(btrim(recipient_value)) BETWEEN 4 AND 180),
    memo_prefix TEXT NOT NULL DEFAULT 'HQ' CHECK(memo_prefix ~ '^[A-Za-z0-9-]{2,16}$'),
    payment_instructions TEXT CHECK(length(payment_instructions) <= 500),
    active BOOLEAN NOT NULL DEFAULT FALSE,
    updated_by UUID REFERENCES auth.users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.hq_zelle_profile ENABLE ROW LEVEL SECURITY;
CREATE POLICY "HQ receiving settings" ON public.hq_zelle_profile FOR SELECT TO authenticated USING(public.is_hq_director(auth.uid()));
GRANT SELECT ON public.hq_zelle_profile TO authenticated;
GRANT ALL ON public.hq_zelle_profile TO service_role;
CREATE FUNCTION public.save_hq_zelle_profile(input_display_name TEXT, input_type TEXT, input_value TEXT,
    input_memo_prefix TEXT, input_instructions TEXT, input_active BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT public.is_hq_director(auth.uid()) THEN RAISE EXCEPTION 'HQ access required'; END IF;
    IF (input_type = 'email' AND btrim(input_value) !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$')
       OR (input_type = 'mobile' AND length(regexp_replace(input_value, '[^0-9]', '', 'g')) NOT BETWEEN 10 AND 15) THEN
        RAISE EXCEPTION 'Enter a valid Zelle email address or mobile number';
    END IF;
    INSERT INTO public.hq_zelle_profile(id, recipient_display_name, recipient_type, recipient_value, memo_prefix, payment_instructions, active, updated_by)
    VALUES(TRUE, btrim(input_display_name), input_type, btrim(input_value), upper(btrim(input_memo_prefix)), input_instructions, input_active, auth.uid())
    ON CONFLICT(id) DO UPDATE SET recipient_display_name = EXCLUDED.recipient_display_name,
        recipient_type = EXCLUDED.recipient_type, recipient_value = EXCLUDED.recipient_value,
        memo_prefix = EXCLUDED.memo_prefix, payment_instructions = EXCLUDED.payment_instructions,
        active = EXCLUDED.active, updated_by = auth.uid(), updated_at = now();
END; $$;
REVOKE ALL ON FUNCTION public.save_hq_zelle_profile(TEXT,TEXT,TEXT,TEXT,TEXT,BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_hq_zelle_profile(TEXT,TEXT,TEXT,TEXT,TEXT,BOOLEAN) TO authenticated;

ALTER TABLE public.zelle_invoices ADD COLUMN recipient_owner TEXT NOT NULL DEFAULT 'school'
    CHECK(recipient_owner IN ('school','hq'));
CREATE OR REPLACE FUNCTION public.zelle_snapshot_recipient() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE profile RECORD;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.recipient_snapshot IS DISTINCT FROM OLD.recipient_snapshot
           OR NEW.recipient_owner IS DISTINCT FROM OLD.recipient_owner
           OR NEW.is_demo IS DISTINCT FROM OLD.is_demo THEN
            RAISE EXCEPTION 'Invoice recipient and environment are immutable'; END IF;
        RETURN NEW;
    END IF;
    IF NEW.payer_role = 'school_director' THEN
        SELECT recipient_display_name, recipient_type, recipient_value, memo_prefix, payment_instructions
        INTO profile FROM public.hq_zelle_profile WHERE id AND active;
        NEW.recipient_owner := 'hq';
    ELSE
        SELECT recipient_display_name, recipient_type, recipient_value, memo_prefix, payment_instructions
        INTO profile FROM public.school_zelle_profiles WHERE school_id = NEW.school_id AND active;
        NEW.recipient_owner := 'school';
    END IF;
    IF NOT FOUND THEN RAISE EXCEPTION 'Activate the receiving organization Zelle settings before issuing this invoice'; END IF;
    NEW.recipient_snapshot := jsonb_build_object('display_name', profile.recipient_display_name,
        'type', profile.recipient_type, 'value', profile.recipient_value,
        'memo', profile.memo_prefix || '-' || NEW.invoice_number, 'instructions', profile.payment_instructions);
    NEW.is_demo := public.zelle_is_demo_environment();
    RETURN NEW;
END; $$;

-- A receiving account can span schools; retain the old claims for old clients/history.
CREATE TABLE public.zelle_account_reference_claims (
    account_key TEXT NOT NULL, reference TEXT NOT NULL,
    invoice_id UUID NOT NULL REFERENCES public.zelle_invoices(id) ON DELETE CASCADE,
    PRIMARY KEY(account_key, reference, invoice_id)
);
ALTER TABLE public.zelle_account_reference_claims ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.zelle_account_reference_claims FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.zelle_account_reference_claims TO service_role;
CREATE FUNCTION public.zelle_recipient_account_key(snapshot JSONB) RETURNS TEXT
LANGUAGE sql IMMUTABLE SET search_path = public AS $$
    SELECT snapshot->>'type' || ':' || CASE WHEN snapshot->>'type' = 'mobile'
        THEN CASE WHEN length(regexp_replace(snapshot->>'value', '[^0-9]', '', 'g')) = 10
            THEN '1' || regexp_replace(snapshot->>'value', '[^0-9]', '', 'g')
            ELSE regexp_replace(snapshot->>'value', '[^0-9]', '', 'g') END
        ELSE lower(btrim(snapshot->>'value')) END;
$$;
INSERT INTO public.zelle_account_reference_claims
SELECT DISTINCT public.zelle_recipient_account_key(i.recipient_snapshot), upper(s.confirmation_reference), i.id
FROM public.zelle_payment_submissions s JOIN public.zelle_invoices i ON i.id = s.invoice_id
WHERE public.zelle_recipient_account_key(i.recipient_snapshot) IS NOT NULL;
CREATE OR REPLACE FUNCTION public.zelle_claim_reference() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE account TEXT;
BEGIN
    NEW.confirmation_reference := upper(btrim(NEW.confirmation_reference));
    SELECT public.zelle_recipient_account_key(recipient_snapshot) INTO account FROM public.zelle_invoices WHERE id = NEW.invoice_id;
    IF account IS NULL THEN RAISE EXCEPTION 'Invoice receiving instructions are unavailable'; END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(account || ':' || NEW.confirmation_reference, 0));
    IF EXISTS(SELECT 1 FROM public.zelle_account_reference_claims c
        WHERE c.account_key = account AND c.reference = NEW.confirmation_reference AND c.invoice_id <> NEW.invoice_id) THEN
        RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'This reference belongs to another invoice for this recipient';
    END IF;
    INSERT INTO public.zelle_account_reference_claims VALUES(account, NEW.confirmation_reference, NEW.invoice_id) ON CONFLICT DO NOTHING;
    RETURN NEW;
END; $$;
CREATE OR REPLACE FUNCTION public.create_zelle_onboarding_invoice(
    input_requirement_instance_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    requirement_instance public.onboarding_requirement_instances%ROWTYPE;
    requirement_record public.onboarding_template_requirements%ROWTYPE;
    membership_record public.school_memberships%ROWTYPE;
    invoice_uuid UUID;
    due_timestamp TIMESTAMPTZ;
BEGIN
    SELECT * INTO requirement_instance
    FROM public.onboarding_requirement_instances WHERE id = input_requirement_instance_id;
    SELECT * INTO requirement_record
    FROM public.onboarding_template_requirements WHERE id = requirement_instance.template_requirement_id;
    SELECT memberships.* INTO membership_record
    FROM public.onboarding_instances instance
    JOIN public.school_memberships memberships ON memberships.id = instance.membership_id
    WHERE instance.id = requirement_instance.onboarding_instance_id;
    IF requirement_instance.id IS NULL OR requirement_record.requirement_type <> 'payment'
       OR membership_record.id IS NULL THEN
        RAISE EXCEPTION 'Payment requirement could not be instantiated';
    END IF;
    SELECT id INTO invoice_uuid FROM public.zelle_invoices
    WHERE onboarding_requirement_instance_id = input_requirement_instance_id;
    IF FOUND THEN RETURN invoice_uuid; END IF;
    -- The snapshot trigger validates the appropriate school or HQ receiving profile.
    due_timestamp := NOW() + make_interval(days => COALESCE(requirement_record.payment_due_days, 7));
    INSERT INTO public.zelle_invoices (
        school_id, payer_user_id, payer_role, onboarding_requirement_instance_id,
        description, amount_due_cents, status, due_at, issued_at, created_by
    ) VALUES (
        membership_record.school_id, membership_record.user_id, membership_record.role,
        requirement_instance.id, requirement_record.title, requirement_record.payment_amount_cents,
        'open', due_timestamp, NOW(), NULL
    ) ON CONFLICT (onboarding_requirement_instance_id) DO UPDATE
        SET updated_at = public.zelle_invoices.updated_at
    RETURNING id INTO invoice_uuid;
    INSERT INTO public.zelle_invoice_items (invoice_id, description, quantity, unit_amount_cents, amount_cents)
    SELECT invoice_uuid, requirement_record.title, 1, requirement_record.payment_amount_cents,
           requirement_record.payment_amount_cents
    WHERE NOT EXISTS (SELECT 1 FROM public.zelle_invoice_items WHERE invoice_id = invoice_uuid);

    INSERT INTO public.zelle_billing_audit_log (school_id, action, entity_type, entity_id, metadata)
    VALUES (membership_record.school_id, 'onboarding_invoice_issued', 'invoice', invoice_uuid,
            jsonb_build_object('onboarding_requirement_instance_id', requirement_instance.id));
    PERFORM public.notify_zelle_recipients(
        membership_record.school_id, ARRAY[membership_record.user_id], 'Onboarding payment ready',
        'Complete your Zelle payment step and submit the confirmation reference for review.',
        invoice_uuid, 'zelle:invoice:' || invoice_uuid::TEXT || ':payer', NULL
    );
    RETURN invoice_uuid;
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
       AND NOT (
           (NEW.target_role = 'school_director' AND EXISTS(SELECT 1 FROM public.hq_zelle_profile WHERE id AND active))
           OR (NEW.target_role <> 'school_director' AND EXISTS(SELECT 1 FROM public.school_zelle_profiles profile WHERE profile.school_id = NEW.school_id AND profile.active))
       ) THEN
        RAISE EXCEPTION 'Activate Zelle recipient instructions before publishing a template with a payment step';
    END IF;
    RETURN NEW;
END;
$$;


CREATE OR REPLACE FUNCTION public.get_firefly_schema_version() RETURNS BIGINT
LANGUAGE sql STABLE AS $$ SELECT 20260918091000::BIGINT $$;
COMMIT;
