BEGIN;

-- FireflyFM keeps a non-sensitive projection of Stripe billing state. Stripe
-- remains authoritative and every mutation is performed by an Edge Function
-- after it validates the caller or a signed Stripe webhook.

CREATE TABLE IF NOT EXISTS public.school_payment_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL UNIQUE REFERENCES public.schools(id) ON DELETE CASCADE,
    stripe_account_id TEXT UNIQUE,
    status TEXT NOT NULL DEFAULT 'not_started'
        CHECK (status IN ('not_started', 'onboarding', 'restricted', 'ready', 'disabled')),
    details_submitted BOOLEAN NOT NULL DEFAULT FALSE,
    charges_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    payouts_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    sandbox BOOLEAN NOT NULL DEFAULT TRUE,
    live_payments_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    requirements_due_count INTEGER NOT NULL DEFAULT 0 CHECK (requirements_due_count >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.billing_customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    parent_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    stripe_customer_id TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (school_id, parent_user_id),
    UNIQUE (school_id, stripe_customer_id)
);

CREATE TABLE IF NOT EXISTS public.billing_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    parent_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    child_id UUID REFERENCES public.children(id) ON DELETE SET NULL,
    stripe_subscription_id TEXT UNIQUE,
    cadence TEXT NOT NULL CHECK (cadence IN ('weekly', 'biweekly', 'monthly')),
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'paused', 'canceled', 'completed')),
    description TEXT NOT NULL,
    days_until_due INTEGER NOT NULL DEFAULT 7 CHECK (days_until_due BETWEEN 1 AND 90),
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.billing_invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    parent_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    child_id UUID REFERENCES public.children(id) ON DELETE SET NULL,
    schedule_id UUID REFERENCES public.billing_schedules(id) ON DELETE SET NULL,
    stripe_invoice_id TEXT NOT NULL UNIQUE,
    stripe_customer_id TEXT NOT NULL,
    invoice_number TEXT,
    description TEXT NOT NULL,
    currency TEXT NOT NULL DEFAULT 'USD' CHECK (currency = 'USD'),
    amount_due_cents BIGINT NOT NULL DEFAULT 0 CHECK (amount_due_cents >= 0),
    amount_paid_cents BIGINT NOT NULL DEFAULT 0 CHECK (amount_paid_cents >= 0),
    amount_remaining_cents BIGINT NOT NULL DEFAULT 0 CHECK (amount_remaining_cents >= 0),
    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'open', 'paid', 'void', 'uncollectible')),
    payment_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (payment_status IN ('pending', 'processing', 'succeeded', 'failed', 'refunded', 'disputed')),
    due_at TIMESTAMPTZ,
    period_start TIMESTAMPTZ,
    period_end TIMESTAMPTZ,
    sent_at TIMESTAMPTZ,
    paid_at TIMESTAMPTZ,
    voided_at TIMESTAMPTZ,
    provider_created_at TIMESTAMPTZ,
    provider_updated_at TIMESTAMPTZ,
    last_synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.billing_invoice_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID NOT NULL REFERENCES public.billing_invoices(id) ON DELETE CASCADE,
    stripe_invoice_item_id TEXT,
    description TEXT NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity BETWEEN 1 AND 1000),
    unit_amount_cents BIGINT NOT NULL CHECK (unit_amount_cents BETWEEN 1 AND 100000000),
    amount_cents BIGINT NOT NULL CHECK (amount_cents BETWEEN 1 AND 100000000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (invoice_id, stripe_invoice_item_id)
);

CREATE TABLE IF NOT EXISTS public.billing_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID REFERENCES public.billing_invoices(id) ON DELETE SET NULL,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    parent_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    stripe_payment_intent_id TEXT NOT NULL UNIQUE,
    stripe_charge_id TEXT,
    amount_cents BIGINT NOT NULL DEFAULT 0 CHECK (amount_cents >= 0),
    currency TEXT NOT NULL DEFAULT 'USD' CHECK (currency = 'USD'),
    status TEXT NOT NULL
        CHECK (status IN ('pending', 'processing', 'succeeded', 'failed', 'refunded', 'disputed')),
    payment_method_type TEXT,
    failure_code TEXT,
    provider_created_at TIMESTAMPTZ,
    provider_updated_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.billing_provider_events (
    stripe_event_id TEXT PRIMARY KEY,
    stripe_account_id TEXT,
    event_type TEXT NOT NULL,
    livemode BOOLEAN NOT NULL DEFAULT FALSE,
    provider_created_at TIMESTAMPTZ,
    payload_sha256 TEXT NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ,
    processing_error TEXT
);

CREATE TABLE IF NOT EXISTS public.billing_audit_log (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    school_id UUID REFERENCES public.schools(id) ON DELETE SET NULL,
    actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT,
    stripe_event_id TEXT REFERENCES public.billing_provider_events(stripe_event_id) ON DELETE SET NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_billing_invoices_parent
    ON public.billing_invoices(parent_user_id, due_at DESC);
CREATE INDEX IF NOT EXISTS idx_billing_invoices_school
    ON public.billing_invoices(school_id, status, due_at DESC);
CREATE INDEX IF NOT EXISTS idx_billing_payments_school
    ON public.billing_payments(school_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_billing_schedules_school
    ON public.billing_schedules(school_id, status);
CREATE INDEX IF NOT EXISTS idx_billing_audit_school
    ON public.billing_audit_log(school_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.billing_is_hq_director(user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.school_memberships membership
        WHERE membership.user_id = user_uuid
          AND membership.role = 'hq_director'
          AND membership.active = TRUE
          AND membership.access_state = 'full'
    );
$$;

CREATE OR REPLACE FUNCTION public.billing_is_school_director(school_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.school_memberships membership
        WHERE membership.school_id = school_uuid
          AND membership.user_id = user_uuid
          AND membership.role = 'school_director'
          AND membership.active = TRUE
          AND membership.access_state = 'full'
    );
$$;

CREATE OR REPLACE FUNCTION public.billing_is_named_parent(school_uuid UUID, parent_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT parent_uuid = user_uuid
       AND EXISTS (
            SELECT 1 FROM public.school_memberships membership
            WHERE membership.school_id = school_uuid
              AND membership.user_id = user_uuid
              AND membership.role = 'parent'
              AND membership.active = TRUE
              AND membership.access_state = 'full'
       );
$$;

REVOKE ALL ON FUNCTION public.billing_is_hq_director(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.billing_is_school_director(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.billing_is_named_parent(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.billing_is_hq_director(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.billing_is_school_director(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.billing_is_named_parent(UUID, UUID, UUID) TO authenticated, service_role;

ALTER TABLE public.school_payment_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_invoice_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_provider_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Billing staff can view school payment accounts"
    ON public.school_payment_accounts FOR SELECT
    USING (
        public.billing_is_school_director(school_id, auth.uid())
        OR public.billing_is_hq_director(auth.uid())
    );

CREATE POLICY "Billing participants can view customer mappings"
    ON public.billing_customers FOR SELECT
    USING (
        public.billing_is_named_parent(school_id, parent_user_id, auth.uid())
        OR public.billing_is_school_director(school_id, auth.uid())
        OR public.billing_is_hq_director(auth.uid())
    );

CREATE POLICY "Billing participants can view schedules"
    ON public.billing_schedules FOR SELECT
    USING (
        public.billing_is_named_parent(school_id, parent_user_id, auth.uid())
        OR public.billing_is_school_director(school_id, auth.uid())
        OR public.billing_is_hq_director(auth.uid())
    );

CREATE POLICY "Billing participants can view invoices"
    ON public.billing_invoices FOR SELECT
    USING (
        public.billing_is_named_parent(school_id, parent_user_id, auth.uid())
        OR public.billing_is_school_director(school_id, auth.uid())
        OR public.billing_is_hq_director(auth.uid())
    );

CREATE POLICY "Billing participants can view invoice items"
    ON public.billing_invoice_items FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.billing_invoices invoice
            WHERE invoice.id = billing_invoice_items.invoice_id
              AND (
                  public.billing_is_named_parent(invoice.school_id, invoice.parent_user_id, auth.uid())
                  OR public.billing_is_school_director(invoice.school_id, auth.uid())
                  OR public.billing_is_hq_director(auth.uid())
              )
        )
    );

CREATE POLICY "Billing participants can view payments"
    ON public.billing_payments FOR SELECT
    USING (
        public.billing_is_named_parent(school_id, parent_user_id, auth.uid())
        OR public.billing_is_school_director(school_id, auth.uid())
        OR public.billing_is_hq_director(auth.uid())
    );

CREATE POLICY "Billing staff can view audit history"
    ON public.billing_audit_log FOR SELECT
    USING (
        public.billing_is_school_director(school_id, auth.uid())
        OR public.billing_is_hq_director(auth.uid())
    );

-- No authenticated INSERT/UPDATE/DELETE policies are intentionally defined.
-- Provider event rows are service-only and never visible through PostgREST.
REVOKE ALL ON public.billing_provider_events FROM anon, authenticated;
GRANT SELECT ON public.school_payment_accounts, public.billing_customers,
    public.billing_schedules, public.billing_invoices, public.billing_invoice_items,
    public.billing_payments, public.billing_audit_log TO authenticated;
GRANT ALL ON public.school_payment_accounts, public.billing_customers,
    public.billing_schedules, public.billing_invoices, public.billing_invoice_items,
    public.billing_payments, public.billing_provider_events, public.billing_audit_log TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.billing_audit_log_id_seq TO service_role;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260807090000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
