BEGIN;

-- Zelle does not provide FireflyFM with a public payment-confirmation API.
-- This schema therefore records a payer's claim and requires the authorised
-- enrolment reviewer to confirm the transfer in the school's bank experience.
-- It deliberately has no fields for bank credentials, account numbers, Zelle
-- tokens, screenshots, or unredacted banking records.

CREATE SEQUENCE IF NOT EXISTS public.zelle_invoice_number_seq;

CREATE TABLE IF NOT EXISTS public.school_zelle_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL UNIQUE REFERENCES public.schools(id) ON DELETE CASCADE,
    recipient_display_name TEXT NOT NULL CHECK (char_length(btrim(recipient_display_name)) BETWEEN 2 AND 120),
    recipient_type TEXT NOT NULL CHECK (recipient_type IN ('email', 'mobile')),
    recipient_value TEXT NOT NULL CHECK (char_length(btrim(recipient_value)) BETWEEN 4 AND 180),
    memo_prefix TEXT NOT NULL DEFAULT 'FF' CHECK (memo_prefix ~ '^[A-Za-z0-9-]{2,16}$'),
    payment_instructions TEXT CHECK (char_length(payment_instructions) <= 500),
    active BOOLEAN NOT NULL DEFAULT FALSE,
    beta_simulation_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.zelle_invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    payer_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    payer_role TEXT NOT NULL CHECK (payer_role IN ('parent', 'teacher', 'school_director')),
    child_id UUID REFERENCES public.children(id) ON DELETE SET NULL,
    onboarding_requirement_instance_id UUID UNIQUE REFERENCES public.onboarding_requirement_instances(id) ON DELETE RESTRICT,
    invoice_number TEXT NOT NULL UNIQUE DEFAULT ('ZL-' || lpad(nextval('public.zelle_invoice_number_seq')::TEXT, 8, '0')),
    description TEXT NOT NULL CHECK (char_length(btrim(description)) BETWEEN 2 AND 240),
    currency TEXT NOT NULL DEFAULT 'USD' CHECK (currency = 'USD'),
    amount_due_cents BIGINT NOT NULL CHECK (amount_due_cents BETWEEN 50 AND 100000000),
    amount_paid_cents BIGINT NOT NULL DEFAULT 0 CHECK (amount_paid_cents >= 0),
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN (
        'draft', 'open', 'payment_submitted', 'under_review', 'paid', 'rejected', 'void', 'expired'
    )),
    due_at TIMESTAMPTZ,
    issued_at TIMESTAMPTZ,
    paid_at TIMESTAMPTZ,
    voided_at TIMESTAMPTZ,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (amount_paid_cents <= amount_due_cents)
);

CREATE TABLE IF NOT EXISTS public.zelle_invoice_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID NOT NULL REFERENCES public.zelle_invoices(id) ON DELETE CASCADE,
    description TEXT NOT NULL CHECK (char_length(btrim(description)) BETWEEN 2 AND 240),
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity BETWEEN 1 AND 100),
    unit_amount_cents BIGINT NOT NULL CHECK (unit_amount_cents BETWEEN 50 AND 100000000),
    amount_cents BIGINT NOT NULL CHECK (amount_cents BETWEEN 50 AND 100000000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (amount_cents = quantity * unit_amount_cents)
);

CREATE TABLE IF NOT EXISTS public.zelle_payment_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID NOT NULL REFERENCES public.zelle_invoices(id) ON DELETE RESTRICT,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    payer_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    amount_cents BIGINT NOT NULL CHECK (amount_cents BETWEEN 50 AND 100000000),
    sent_at TIMESTAMPTZ NOT NULL,
    confirmation_reference TEXT NOT NULL CHECK (confirmation_reference ~ '^[A-Za-z0-9-]{4,64}$'),
    status TEXT NOT NULL DEFAULT 'submitted' CHECK (status IN ('submitted', 'under_review', 'approved', 'rejected')),
    reviewer_note TEXT CHECK (char_length(reviewer_note) <= 500),
    reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    idempotency_key TEXT NOT NULL CHECK (char_length(idempotency_key) BETWEEN 8 AND 180),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (invoice_id, payer_user_id, idempotency_key)
);

CREATE TABLE IF NOT EXISTS public.zelle_billing_audit_log (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    school_id UUID REFERENCES public.schools(id) ON DELETE SET NULL,
    actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL CHECK (char_length(action) BETWEEN 2 AND 100),
    entity_type TEXT NOT NULL CHECK (entity_type IN ('profile', 'invoice', 'submission', 'onboarding_requirement')),
    entity_id UUID,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB CHECK (jsonb_typeof(metadata) = 'object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_zelle_invoices_school_status_due
    ON public.zelle_invoices(school_id, status, due_at DESC);
CREATE INDEX IF NOT EXISTS idx_zelle_invoices_payer
    ON public.zelle_invoices(payer_user_id, due_at DESC);
CREATE INDEX IF NOT EXISTS idx_zelle_submissions_invoice
    ON public.zelle_payment_submissions(invoice_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_zelle_audit_school
    ON public.zelle_billing_audit_log(school_id, created_at DESC);

-- Payment requirements are member-scoped deliberately. A school chooses the
-- financially responsible invitee; a child-scoped payment would otherwise
-- create duplicate deposit requests for each guardian.
ALTER TABLE public.onboarding_template_requirements
    ADD COLUMN IF NOT EXISTS payment_amount_cents BIGINT,
    ADD COLUMN IF NOT EXISTS payment_due_days INTEGER;
ALTER TABLE public.onboarding_template_requirements
    DROP CONSTRAINT IF EXISTS onboarding_template_payment_configuration_check;
ALTER TABLE public.onboarding_template_requirements
    ADD CONSTRAINT onboarding_template_payment_configuration_check CHECK (
        requirement_type <> 'payment'
        OR (
            subject_scope = 'member'
            AND payment_amount_cents BETWEEN 50 AND 100000000
            AND COALESCE(payment_due_days, 7) BETWEEN 1 AND 90
            AND blocks_access = TRUE
        )
    );

CREATE OR REPLACE FUNCTION public.zelle_is_active_payer(
    school_uuid UUID,
    payer_uuid UUID,
    user_uuid UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT payer_uuid = user_uuid
       AND EXISTS (
            SELECT 1
            FROM public.school_memberships membership
            WHERE membership.school_id = school_uuid
              AND membership.user_id = user_uuid
              AND membership.role IN ('parent', 'teacher', 'school_director')
              AND membership.active = TRUE
       );
$$;

CREATE OR REPLACE FUNCTION public.zelle_can_manage_profile(school_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.is_hq_director(user_uuid)
        OR public.has_direct_school_role(school_uuid, user_uuid, ARRAY['school_director']);
$$;

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

    IF invoice_record.onboarding_requirement_instance_id IS NOT NULL THEN
        SELECT templates.target_role INTO target_role
        FROM public.onboarding_requirement_instances requirement_instance
        JOIN public.onboarding_instances onboarding_instance
          ON onboarding_instance.id = requirement_instance.onboarding_instance_id
        JOIN public.onboarding_templates templates ON templates.id = onboarding_instance.template_id
        WHERE requirement_instance.id = invoice_record.onboarding_requirement_instance_id;
        RETURN public.is_onboarding_template_manager(invoice_record.school_id, target_role, user_uuid);
    END IF;

    RETURN public.has_direct_school_role(invoice_record.school_id, user_uuid, ARRAY['school_director']);
END;
$$;

CREATE OR REPLACE FUNCTION public.zelle_can_view_invoice(invoice_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.zelle_invoices invoice
        WHERE invoice.id = invoice_uuid
          AND (
              public.zelle_is_active_payer(invoice.school_id, invoice.payer_user_id, user_uuid)
              OR public.zelle_can_review_invoice(invoice.id, user_uuid)
              OR public.is_hq_director(user_uuid)
          )
    );
$$;

REVOKE ALL ON FUNCTION public.zelle_is_active_payer(UUID, UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.zelle_can_manage_profile(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.zelle_can_review_invoice(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.zelle_can_view_invoice(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.zelle_is_active_payer(UUID, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.zelle_can_manage_profile(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.zelle_can_review_invoice(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.zelle_can_view_invoice(UUID, UUID) TO authenticated;

ALTER TABLE public.school_zelle_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.zelle_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.zelle_invoice_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.zelle_payment_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.zelle_billing_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Zelle participants can view recipient instructions"
    ON public.school_zelle_profiles FOR SELECT TO authenticated
    USING (
        public.zelle_can_manage_profile(school_id, auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.zelle_invoices invoice
            WHERE invoice.school_id = school_zelle_profiles.school_id
              AND public.zelle_is_active_payer(invoice.school_id, invoice.payer_user_id, auth.uid())
        )
    );

CREATE POLICY "Zelle participants can view invoices"
    ON public.zelle_invoices FOR SELECT TO authenticated
    USING (public.zelle_can_view_invoice(id, auth.uid()));

CREATE POLICY "Zelle participants can view invoice items"
    ON public.zelle_invoice_items FOR SELECT TO authenticated
    USING (public.zelle_can_view_invoice(invoice_id, auth.uid()));

CREATE POLICY "Zelle participants can view payment submissions"
    ON public.zelle_payment_submissions FOR SELECT TO authenticated
    USING (public.zelle_can_view_invoice(invoice_id, auth.uid()));

CREATE POLICY "Only invoice reviewers can view Zelle audit history"
    ON public.zelle_billing_audit_log FOR SELECT TO authenticated
    USING (
        public.is_hq_director(auth.uid())
        OR public.has_direct_school_role(school_id, auth.uid(), ARRAY['school_director'])
    );

REVOKE ALL ON public.school_zelle_profiles, public.zelle_invoices,
    public.zelle_invoice_items, public.zelle_payment_submissions,
    public.zelle_billing_audit_log FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
    ON public.school_zelle_profiles, public.zelle_invoices,
    public.zelle_invoice_items, public.zelle_payment_submissions,
    public.zelle_billing_audit_log FROM authenticated;
GRANT SELECT ON public.school_zelle_profiles, public.zelle_invoices,
    public.zelle_invoice_items, public.zelle_payment_submissions,
    public.zelle_billing_audit_log TO authenticated;
GRANT ALL ON public.school_zelle_profiles, public.zelle_invoices,
    public.zelle_invoice_items, public.zelle_payment_submissions,
    public.zelle_billing_audit_log TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.zelle_invoice_number_seq,
    public.zelle_billing_audit_log_id_seq TO service_role;

CREATE OR REPLACE FUNCTION public.save_school_zelle_profile(
    input_school_id UUID,
    input_recipient_display_name TEXT,
    input_recipient_type TEXT,
    input_recipient_value TEXT,
    input_memo_prefix TEXT DEFAULT 'FF',
    input_payment_instructions TEXT DEFAULT NULL,
    input_active BOOLEAN DEFAULT FALSE,
    input_beta_simulation_enabled BOOLEAN DEFAULT TRUE
)
RETURNS SETOF public.school_zelle_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    saved_profile public.school_zelle_profiles%ROWTYPE;
BEGIN
    IF NOT public.zelle_can_manage_profile(input_school_id, actor) THEN
        RAISE EXCEPTION 'Only HQ or an approved school director can manage Zelle instructions';
    END IF;
    IF input_recipient_type NOT IN ('email', 'mobile') THEN RAISE EXCEPTION 'Recipient type must be email or mobile'; END IF;
    IF NULLIF(btrim(input_recipient_display_name), '') IS NULL
       OR NULLIF(btrim(input_recipient_value), '') IS NULL
       OR COALESCE(input_memo_prefix, '') !~ '^[A-Za-z0-9-]{2,16}$' THEN
        RAISE EXCEPTION 'Recipient instructions are invalid';
    END IF;

    INSERT INTO public.school_zelle_profiles (
        school_id, recipient_display_name, recipient_type, recipient_value,
        memo_prefix, payment_instructions, active, beta_simulation_enabled,
        created_by, updated_by
    ) VALUES (
        input_school_id, btrim(input_recipient_display_name), input_recipient_type,
        btrim(input_recipient_value), upper(input_memo_prefix),
        NULLIF(btrim(COALESCE(input_payment_instructions, '')), ''),
        COALESCE(input_active, FALSE), COALESCE(input_beta_simulation_enabled, TRUE), actor, actor
    ) ON CONFLICT (school_id) DO UPDATE SET
        recipient_display_name = EXCLUDED.recipient_display_name,
        recipient_type = EXCLUDED.recipient_type,
        recipient_value = EXCLUDED.recipient_value,
        memo_prefix = EXCLUDED.memo_prefix,
        payment_instructions = EXCLUDED.payment_instructions,
        active = EXCLUDED.active,
        beta_simulation_enabled = EXCLUDED.beta_simulation_enabled,
        updated_by = actor,
        updated_at = NOW()
    RETURNING * INTO saved_profile;

    INSERT INTO public.zelle_billing_audit_log (school_id, actor_id, action, entity_type, entity_id, metadata)
    VALUES (input_school_id, actor, 'profile_saved', 'profile', saved_profile.id,
            jsonb_build_object('active', saved_profile.active, 'recipient_type', saved_profile.recipient_type,
                               'beta_simulation_enabled', saved_profile.beta_simulation_enabled));
    RETURN QUERY SELECT * FROM public.school_zelle_profiles WHERE id = saved_profile.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_zelle_recipients(
    input_school_id UUID,
    input_recipient_ids UUID[],
    input_title TEXT,
    input_body TEXT,
    input_source_id UUID,
    input_dedupe_key TEXT,
    input_actor_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE notification_uuid UUID;
BEGIN
    IF COALESCE(array_length(input_recipient_ids, 1), 0) = 0 THEN RETURN; END IF;
    INSERT INTO public.notifications (school_id, title, body, category, source_type, source_id, created_by, dedupe_key)
    VALUES (input_school_id, input_title, input_body, 'zelle_payment', 'zelle_invoice', input_source_id,
            input_actor_id, input_dedupe_key)
    ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL
    DO UPDATE SET title = EXCLUDED.title, body = EXCLUDED.body
    RETURNING id INTO notification_uuid;
    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT notification_uuid, recipient_id
    FROM unnest(input_recipient_ids) AS recipient_id
    ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.zelle_invoice_reviewers(input_invoice_id UUID)
RETURNS UUID[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(array_agg(DISTINCT membership.user_id), ARRAY[]::UUID[])
    FROM public.zelle_invoices invoice
    LEFT JOIN public.onboarding_requirement_instances requirement_instance
      ON requirement_instance.id = invoice.onboarding_requirement_instance_id
    LEFT JOIN public.onboarding_instances onboarding_instance
      ON onboarding_instance.id = requirement_instance.onboarding_instance_id
    LEFT JOIN public.onboarding_templates template ON template.id = onboarding_instance.template_id
    JOIN public.school_memberships membership ON membership.active = TRUE AND membership.access_state = 'full'
    WHERE invoice.id = input_invoice_id
      AND (
          (template.target_role = 'school_director' AND membership.role = 'hq_director')
          OR (template.target_role IN ('parent', 'teacher')
              AND membership.school_id = invoice.school_id AND membership.role = 'school_director')
          OR (invoice.onboarding_requirement_instance_id IS NULL
              AND membership.school_id = invoice.school_id AND membership.role = 'school_director')
      );
$$;

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
    IF NOT EXISTS (
        SELECT 1 FROM public.school_zelle_profiles profile
        WHERE profile.school_id = membership_record.school_id AND profile.active = TRUE
    ) THEN
        RAISE EXCEPTION 'Activate this school''s Zelle recipient instructions before assigning a payment requirement';
    END IF;
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
    IF COALESCE(input_idempotency_key, '') !~ '^.{8,180}$' THEN RAISE EXCEPTION 'A valid idempotency key is required'; END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.school_memberships membership
        WHERE membership.school_id = input_school_id AND membership.user_id = input_payer_user_id
          AND membership.role = 'parent' AND membership.active = TRUE AND membership.access_state = 'full'
    ) THEN RAISE EXCEPTION 'Invoices can only be issued to an approved parent in this school'; END IF;
    IF input_child_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.children child
        JOIN public.child_guardians guardian ON guardian.child_id = child.id
        WHERE child.id = input_child_id AND child.school_id = input_school_id
          AND guardian.guardian_id = input_payer_user_id
    ) THEN RAISE EXCEPTION 'The selected child is not linked to this parent'; END IF;
    IF jsonb_typeof(COALESCE(input_items, '[]'::JSONB)) <> 'array' THEN
        RAISE EXCEPTION 'Invoice items must be a list';
    END IF;
    IF jsonb_array_length(COALESCE(input_items, '[]'::JSONB)) NOT BETWEEN 1 AND 20 THEN
        RAISE EXCEPTION 'Add between one and twenty invoice items';
    END IF;
    SELECT COALESCE(SUM((entry.value->>'quantity')::BIGINT * (entry.value->>'unit_amount_cents')::BIGINT), 0)
    INTO total_cents FROM jsonb_array_elements(input_items) AS entry(value);
    IF total_cents NOT BETWEEN 50 AND 100000000 THEN RAISE EXCEPTION 'Invoice total is invalid'; END IF;
    IF EXISTS (
        SELECT 1 FROM public.zelle_billing_audit_log audit
        WHERE audit.school_id = input_school_id AND audit.action = 'invoice_issue:' || input_idempotency_key
    ) THEN
        RETURN QUERY SELECT invoice.* FROM public.zelle_invoices invoice
        JOIN public.zelle_billing_audit_log audit ON audit.entity_id = invoice.id
        WHERE audit.school_id = input_school_id AND audit.action = 'invoice_issue:' || input_idempotency_key LIMIT 1;
        RETURN;
    END IF;
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
        VALUES (invoice_uuid, btrim(item.payload->>'description'), (item.payload->>'quantity')::INTEGER,
                (item.payload->>'unit_amount_cents')::BIGINT,
                (item.payload->>'quantity')::BIGINT * (item.payload->>'unit_amount_cents')::BIGINT);
    END LOOP;
    INSERT INTO public.zelle_billing_audit_log (school_id, actor_id, action, entity_type, entity_id)
    VALUES (input_school_id, actor, 'invoice_issue:' || input_idempotency_key, 'invoice', invoice_uuid);
    PERFORM public.notify_zelle_recipients(input_school_id, ARRAY[input_payer_user_id], 'New school invoice',
        'A Zelle invoice is ready for your review and payment submission.', invoice_uuid,
        'zelle:invoice:' || invoice_uuid::TEXT || ':payer', actor);
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
    IF invoice_record.status NOT IN ('open', 'rejected') THEN RAISE EXCEPTION 'This invoice cannot accept a new payment submission'; END IF;
    IF input_amount_cents <> invoice_record.amount_due_cents THEN
        RAISE EXCEPTION 'This beta requires the full invoice amount in one payment';
    END IF;
    IF input_sent_at > NOW() + INTERVAL '15 minutes' OR input_sent_at < NOW() - INTERVAL '180 days'
       OR COALESCE(input_confirmation_reference, '') !~ '^[A-Za-z0-9-]{4,64}$'
       OR COALESCE(input_idempotency_key, '') !~ '^.{8,180}$' THEN
        RAISE EXCEPTION 'The payment submission is invalid';
    END IF;
    SELECT * INTO submission_record FROM public.zelle_payment_submissions
    WHERE invoice_id = input_invoice_id AND payer_user_id = actor AND idempotency_key = input_idempotency_key;
    IF FOUND THEN RETURN QUERY SELECT * FROM public.zelle_payment_submissions WHERE id = submission_record.id; RETURN; END IF;
    INSERT INTO public.zelle_payment_submissions (
        invoice_id, school_id, payer_user_id, amount_cents, sent_at, confirmation_reference, idempotency_key
    ) VALUES (
        invoice_record.id, invoice_record.school_id, actor, input_amount_cents,
        input_sent_at, upper(input_confirmation_reference), input_idempotency_key
    ) RETURNING * INTO submission_record;
    UPDATE public.zelle_invoices SET status = 'payment_submitted', updated_at = NOW() WHERE id = invoice_record.id;
    IF invoice_record.onboarding_requirement_instance_id IS NOT NULL THEN
        UPDATE public.onboarding_requirement_instances SET status = 'in_review'
        WHERE id = invoice_record.onboarding_requirement_instance_id;
    END IF;
    INSERT INTO public.zelle_billing_audit_log (school_id, actor_id, action, entity_type, entity_id, metadata)
    VALUES (invoice_record.school_id, actor, 'payment_submitted', 'submission', submission_record.id,
            jsonb_build_object('invoice_id', invoice_record.id, 'amount_cents', input_amount_cents));
    PERFORM public.notify_zelle_recipients(invoice_record.school_id, public.zelle_invoice_reviewers(invoice_record.id),
        'Zelle payment needs review', 'A payer submitted a Zelle confirmation reference. Verify it in the school bank before approving.',
        invoice_record.id, 'zelle:invoice:' || invoice_record.id::TEXT || ':review', actor);
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
    SELECT * INTO submission_record FROM public.zelle_payment_submissions WHERE id = input_submission_id FOR UPDATE;
    SELECT * INTO invoice_record FROM public.zelle_invoices WHERE id = submission_record.invoice_id FOR UPDATE;
    IF NOT FOUND OR NOT public.zelle_can_review_invoice(invoice_record.id, actor) THEN
        RAISE EXCEPTION 'You are not authorised to review this payment';
    END IF;
    IF submission_record.status NOT IN ('submitted', 'under_review') OR input_decision NOT IN ('approved', 'rejected') THEN
        RAISE EXCEPTION 'This payment submission cannot be reviewed';
    END IF;
    IF input_decision = 'rejected' AND NULLIF(btrim(COALESCE(input_reviewer_note, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Explain what the payer should correct before rejecting a payment';
    END IF;
    UPDATE public.zelle_payment_submissions
    SET status = input_decision, reviewer_note = NULLIF(btrim(COALESCE(input_reviewer_note, '')), ''),
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
    VALUES (invoice_record.school_id, actor, 'payment_' || input_decision, 'submission', submission_record.id,
            jsonb_build_object('invoice_id', invoice_record.id));
    PERFORM public.notify_zelle_recipients(invoice_record.school_id, ARRAY[invoice_record.payer_user_id],
        CASE WHEN input_decision = 'approved' THEN 'Payment approved' ELSE 'Payment update requested' END,
        CASE WHEN input_decision = 'approved' THEN 'Your school has verified the payment. Your receipt is now available in FireflyFM.'
             ELSE COALESCE(NULLIF(btrim(input_reviewer_note), ''), 'Please submit a new payment confirmation reference.') END,
        invoice_record.id, 'zelle:invoice:' || invoice_record.id::TEXT || ':decision:' || input_decision, actor);
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
BEGIN
    SELECT * INTO invoice_record FROM public.zelle_invoices WHERE id = input_invoice_id FOR UPDATE;
    IF NOT FOUND OR NOT public.zelle_can_review_invoice(invoice_record.id, actor) THEN RAISE EXCEPTION 'You cannot void this invoice'; END IF;
    IF invoice_record.status IN ('paid', 'void') THEN RAISE EXCEPTION 'Paid or already void invoices cannot be voided'; END IF;
    IF NULLIF(btrim(COALESCE(input_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'A void reason is required'; END IF;
    UPDATE public.zelle_invoices SET status = 'void', voided_at = NOW(), updated_at = NOW() WHERE id = invoice_record.id
    RETURNING * INTO invoice_record;
    IF invoice_record.onboarding_requirement_instance_id IS NOT NULL THEN
        UPDATE public.onboarding_requirement_instances
        SET status = 'waived', waived_by = actor, waiver_reason = btrim(input_reason), completed_at = NOW()
        WHERE id = invoice_record.onboarding_requirement_instance_id;
    END IF;
    INSERT INTO public.zelle_billing_audit_log (school_id, actor_id, action, entity_type, entity_id, metadata)
    VALUES (invoice_record.school_id, actor, 'invoice_voided', 'invoice', invoice_record.id,
            jsonb_build_object('reason', btrim(input_reason)));
    PERFORM public.notify_zelle_recipients(invoice_record.school_id, ARRAY[invoice_record.payer_user_id],
        'Invoice voided', 'This invoice is no longer payable. Contact your school if you have questions.', invoice_record.id,
        'zelle:invoice:' || invoice_record.id::TEXT || ':void', actor);
    RETURN QUERY SELECT * FROM public.zelle_invoices WHERE id = invoice_record.id;
END;
$$;

-- Payment is a native onboarding step, never a Google Form field. Existing
-- document and acknowledgement assignment behaviour remains unchanged.
CREATE OR REPLACE FUNCTION public.create_onboarding_assignment(
    input_instance_id UUID,
    input_template_requirement_id UUID,
    input_child_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    instance_record RECORD;
    requirement_record public.onboarding_template_requirements%ROWTYPE;
    assignment_uuid UUID;
    notification_uuid UUID;
    shared_status TEXT;
    requirement_instance_uuid UUID;
BEGIN
    SELECT instances.*, memberships.user_id, memberships.role, templates.created_by
    INTO instance_record
    FROM public.onboarding_instances instances
    JOIN public.school_memberships memberships ON memberships.id = instances.membership_id
    JOIN public.onboarding_templates templates ON templates.id = instances.template_id
    WHERE instances.id = input_instance_id;
    SELECT * INTO requirement_record FROM public.onboarding_template_requirements
    WHERE id = input_template_requirement_id AND template_id = instance_record.template_id;
    IF instance_record.id IS NULL OR requirement_record.id IS NULL THEN RAISE EXCEPTION 'Onboarding requirement could not be instantiated'; END IF;
    IF requirement_record.requirement_type = 'payment' THEN
        IF input_child_id IS NOT NULL THEN RAISE EXCEPTION 'Payment requirements must be member-scoped'; END IF;
        INSERT INTO public.onboarding_requirement_instances (onboarding_instance_id, template_requirement_id, status)
        VALUES (input_instance_id, requirement_record.id, 'not_started')
        ON CONFLICT (onboarding_instance_id, template_requirement_id) WHERE child_id IS NULL
        DO UPDATE SET status = public.onboarding_requirement_instances.status
        RETURNING id INTO requirement_instance_uuid;
        RETURN public.create_zelle_onboarding_invoice(requirement_instance_uuid);
    END IF;
    IF input_child_id IS NOT NULL THEN
        SELECT requirement_instances.assignment_id, requirement_instances.status INTO assignment_uuid, shared_status
        FROM public.onboarding_requirement_instances requirement_instances
        JOIN public.onboarding_instances existing_instances ON existing_instances.id = requirement_instances.onboarding_instance_id
        JOIN public.onboarding_template_requirements existing_requirements ON existing_requirements.id = requirement_instances.template_requirement_id
        WHERE existing_instances.school_id = instance_record.school_id
          AND existing_requirements.requirement_key = requirement_record.requirement_key
          AND requirement_instances.child_id = input_child_id AND requirement_instances.assignment_id IS NOT NULL
        ORDER BY requirement_instances.created_at LIMIT 1;
        IF assignment_uuid IS NOT NULL THEN
            INSERT INTO public.onboarding_requirement_instances (onboarding_instance_id, template_requirement_id, assignment_id, child_id, status, completed_at)
            VALUES (input_instance_id, requirement_record.id, assignment_uuid, input_child_id, shared_status,
                    CASE WHEN shared_status IN ('approved', 'waived') THEN NOW() ELSE NULL END)
            ON CONFLICT DO NOTHING;
            INSERT INTO public.assignment_recipients (assignment_id, user_id, role_at_assignment, child_id, completion_status)
            VALUES (assignment_uuid, instance_record.user_id, instance_record.role, input_child_id,
                    CASE shared_status WHEN 'approved' THEN 'accepted' WHEN 'waived' THEN 'excused'
                         WHEN 'in_review' THEN 'submitted' WHEN 'changes_requested' THEN 'changes_requested'
                         WHEN 'overdue' THEN 'overdue' WHEN 'in_progress' THEN 'read' ELSE 'not_started' END)
            ON CONFLICT DO NOTHING;
            RETURN assignment_uuid;
        END IF;
    END IF;
    INSERT INTO public.assignments (school_id, child_id, title, description, category, audience_role, assigned_by, status, visibility, requires_review, allow_resubmission, publish_at)
    VALUES (instance_record.school_id, input_child_id, requirement_record.title, requirement_record.description,
            'onboarding', instance_record.role, instance_record.created_by, 'published', 'assigned', TRUE, TRUE, NOW())
    RETURNING id INTO assignment_uuid;
    IF input_child_id IS NULL THEN
        INSERT INTO public.assignment_recipients (assignment_id, user_id, role_at_assignment, child_id, completion_status)
        VALUES (assignment_uuid, instance_record.user_id, instance_record.role, NULL, 'not_started');
    ELSE
        INSERT INTO public.assignment_recipients (assignment_id, user_id, role_at_assignment, child_id, completion_status)
        SELECT assignment_uuid, memberships.user_id, memberships.role, input_child_id, 'not_started'
        FROM public.child_guardians guardians
        JOIN public.school_memberships memberships ON memberships.user_id = guardians.guardian_id
            AND memberships.school_id = instance_record.school_id AND memberships.role = 'parent' AND memberships.active = TRUE
        WHERE guardians.child_id = input_child_id ON CONFLICT DO NOTHING;
    END IF;
    INSERT INTO public.assignment_materials (assignment_id, material_type, title, private_file_path, file_name, content_type)
    SELECT assignment_uuid, 'file', file_name, private_file_path, file_name, content_type
    FROM public.onboarding_template_attachments WHERE requirement_id = requirement_record.id ORDER BY position;
    INSERT INTO public.onboarding_requirement_instances (onboarding_instance_id, template_requirement_id, assignment_id, child_id, status)
    VALUES (input_instance_id, requirement_record.id, assignment_uuid, input_child_id, 'not_started');
    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type)
    VALUES (assignment_uuid, instance_record.school_id, instance_record.created_by, 'published');
    INSERT INTO public.notifications (school_id, title, body, category, source_type, source_id, created_by, dedupe_key)
    VALUES (instance_record.school_id, requirement_record.title, COALESCE(requirement_record.description, 'A new onboarding requirement is ready.'),
            'assignment_assigned', 'assignment', assignment_uuid, instance_record.created_by,
            'onboarding:assignment:' || assignment_uuid::TEXT) RETURNING id INTO notification_uuid;
    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT notification_uuid, recipients.user_id FROM public.assignment_recipients recipients
    WHERE recipients.assignment_id = assignment_uuid ON CONFLICT DO NOTHING;
    RETURN assignment_uuid;
END;
$$;

-- The payment-aware signature adds three arguments. Drop the older overload
-- first so PostgREST has one unambiguous validation path for every template
-- save, including ordinary document and acknowledgement requirements.
DROP FUNCTION IF EXISTS public.save_onboarding_template_requirement_v2(
    UUID, UUID, TEXT, TEXT, TEXT, INTEGER, JSONB, BOOLEAN, TEXT
);

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
DECLARE actor UUID := auth.uid(); template_record public.onboarding_templates%ROWTYPE; saved_requirement public.onboarding_template_requirements%ROWTYPE;
BEGIN
    SELECT * INTO template_record FROM public.onboarding_templates WHERE id = input_template_id;
    IF NOT FOUND OR template_record.status <> 'draft' OR NOT public.is_onboarding_template_manager(template_record.school_id, template_record.target_role, actor) THEN
        RAISE EXCEPTION 'Requirements can only be changed by a manager in a draft template';
    END IF;
    IF NULLIF(btrim(COALESCE(input_title, '')), '') IS NULL THEN RAISE EXCEPTION 'A requirement title is required'; END IF;
    IF input_requirement_type NOT IN ('document', 'acknowledgement', 'payment') THEN RAISE EXCEPTION 'Requirement type is invalid'; END IF;
    IF input_subject_scope NOT IN ('member', 'child') OR (input_subject_scope = 'child' AND template_record.target_role <> 'parent') THEN RAISE EXCEPTION 'Child requirements are available only for parent templates'; END IF;
    IF input_child_record_binding NOT IN ('none', 'child_document', 'immunization_record', 'medical_clearance', 'medication_authorization', 'emergency_information', 'consent')
       OR (input_child_record_binding <> 'none' AND input_subject_scope <> 'child') THEN RAISE EXCEPTION 'The child record binding is invalid for this requirement'; END IF;
    IF input_requirement_type = 'payment' AND (
        input_subject_scope <> 'member' OR input_payment_amount_cents NOT BETWEEN 50 AND 100000000
        OR COALESCE(input_payment_due_days, 7) NOT BETWEEN 1 AND 90
        OR COALESCE(input_blocks_access, TRUE) <> TRUE OR jsonb_array_length(COALESCE(input_attachments, '[]'::JSONB)) <> 0
    ) THEN RAISE EXCEPTION 'Payment requirements are blocking, member-scoped, need an amount and due period, and cannot include paperwork'; END IF;
    IF input_requirement_id IS NULL THEN
        INSERT INTO public.onboarding_template_requirements (template_id, position, requirement_type, title, description, subject_scope, blocks_access, child_record_binding, payment_amount_cents, payment_due_days)
        VALUES (template_record.id, GREATEST(COALESCE(input_position, 0), 0), input_requirement_type, btrim(input_title),
                NULLIF(btrim(COALESCE(input_description, '')), ''), input_subject_scope,
                CASE WHEN input_requirement_type = 'payment' THEN TRUE ELSE COALESCE(input_blocks_access, TRUE) END,
                input_child_record_binding,
                CASE WHEN input_requirement_type = 'payment' THEN input_payment_amount_cents ELSE NULL END,
                CASE WHEN input_requirement_type = 'payment' THEN COALESCE(input_payment_due_days, 7) ELSE NULL END)
        RETURNING * INTO saved_requirement;
    ELSE
        UPDATE public.onboarding_template_requirements
        SET title = btrim(input_title), description = NULLIF(btrim(COALESCE(input_description, '')), ''),
            requirement_type = input_requirement_type, subject_scope = input_subject_scope,
            blocks_access = CASE WHEN input_requirement_type = 'payment' THEN TRUE ELSE COALESCE(input_blocks_access, TRUE) END,
            child_record_binding = input_child_record_binding,
            payment_amount_cents = CASE WHEN input_requirement_type = 'payment' THEN input_payment_amount_cents ELSE NULL END,
            payment_due_days = CASE WHEN input_requirement_type = 'payment' THEN COALESCE(input_payment_due_days, 7) ELSE NULL END,
            updated_at = NOW()
        WHERE id = input_requirement_id AND template_id = template_record.id RETURNING * INTO saved_requirement;
        IF saved_requirement.id IS NULL THEN RAISE EXCEPTION 'Requirement not found in this draft'; END IF;
    END IF;
    DELETE FROM public.onboarding_template_attachments WHERE requirement_id = saved_requirement.id;
    IF input_requirement_type <> 'payment' THEN
        INSERT INTO public.onboarding_template_attachments (requirement_id, position, private_file_path, file_name, content_type)
        SELECT saved_requirement.id, attachment.ordinality::INTEGER - 1, attachment.value->>'private_file_path', attachment.value->>'file_name', NULLIF(attachment.value->>'content_type', '')
        FROM jsonb_array_elements(COALESCE(input_attachments, '[]'::JSONB)) WITH ORDINALITY AS attachment(value, ordinality)
        WHERE NULLIF(attachment.value->>'private_file_path', '') IS NOT NULL AND NULLIF(attachment.value->>'file_name', '') IS NOT NULL;
    END IF;
    RETURN QUERY SELECT * FROM public.onboarding_template_requirements WHERE id = saved_requirement.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.require_active_zelle_profile_for_payment_template()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NEW.status = 'published' AND OLD.status IS DISTINCT FROM 'published'
       AND EXISTS (SELECT 1 FROM public.onboarding_template_requirements requirement WHERE requirement.template_id = NEW.id AND requirement.requirement_type = 'payment')
       AND NOT EXISTS (SELECT 1 FROM public.school_zelle_profiles profile WHERE profile.school_id = NEW.school_id AND profile.active = TRUE) THEN
        RAISE EXCEPTION 'Activate Zelle recipient instructions before publishing a template with a payment step';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS require_active_zelle_profile_for_payment_template_trigger ON public.onboarding_templates;
CREATE TRIGGER require_active_zelle_profile_for_payment_template_trigger
    BEFORE UPDATE OF status ON public.onboarding_templates
    FOR EACH ROW EXECUTE FUNCTION public.require_active_zelle_profile_for_payment_template();

-- PostgreSQL cannot replace a function when its RETURNS TABLE row type changes.
-- This dashboard gains billing columns, so remove the old RPC signature first.
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
    JOIN public.onboarding_template_requirements requirements ON requirements.id = requirement_instances.template_requirement_id
    LEFT JOIN public.zelle_invoices invoice ON invoice.onboarding_requirement_instance_id = requirement_instances.id
    LEFT JOIN public.children children ON children.id = requirement_instances.child_id
    WHERE memberships.user_id = auth.uid() AND memberships.school_id = input_school_id
      AND memberships.active = TRUE AND instances.status IN ('in_progress', 'complete')
    ORDER BY requirements.position, children.first_name, children.last_name;
$$;

REVOKE ALL ON FUNCTION public.save_school_zelle_profile(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.issue_zelle_invoice(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, JSONB, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.submit_zelle_payment(UUID, BIGINT, TIMESTAMPTZ, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.review_zelle_payment(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.void_zelle_invoice(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_zelle_onboarding_invoice(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.zelle_invoice_reviewers(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notify_zelle_recipients(UUID, UUID[], TEXT, TEXT, UUID, TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fetch_my_onboarding_dashboard(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_school_zelle_profile(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.issue_zelle_invoice(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_zelle_payment(UUID, BIGINT, TIMESTAMPTZ, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_zelle_payment(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.void_zelle_invoice(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_onboarding_dashboard(UUID) TO authenticated;

-- Keep legacy Stripe records immutable for audit/history, but disable any old
-- account so no new Stripe charge can be started after this migration.
UPDATE public.school_payment_accounts
SET status = 'disabled', charges_enabled = FALSE, payouts_enabled = FALSE,
    live_payments_enabled = FALSE, updated_at = NOW()
WHERE status <> 'disabled';
COMMENT ON TABLE public.school_payment_accounts IS 'Legacy Stripe history only. New billing uses school_zelle_profiles and zelle_* tables.';

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260904150100::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
