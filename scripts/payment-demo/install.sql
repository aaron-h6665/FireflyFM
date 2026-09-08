-- Only prepare.sh installs this file in its explicitly named local container.
BEGIN;
CREATE OR REPLACE FUNCTION public.zelle_is_demo_environment() RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$ SELECT TRUE $$;
CREATE TABLE IF NOT EXISTS public.zelle_demo_transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID NOT NULL REFERENCES public.zelle_invoices(id),
    reference TEXT NOT NULL UNIQUE,
    amount_cents BIGINT NOT NULL,
    recipient TEXT NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    received BOOLEAN NOT NULL,
    scenario TEXT NOT NULL CHECK (scenario IN ('matching','missing','wrong_amount'))
);
ALTER TABLE public.zelle_demo_transfers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.zelle_demo_transfers FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.zelle_demo_transfers TO authenticated;
DROP POLICY IF EXISTS demo_transfer_participants ON public.zelle_demo_transfers;
CREATE POLICY demo_transfer_participants ON public.zelle_demo_transfers FOR SELECT TO authenticated
USING (public.zelle_can_view_invoice(invoice_id, auth.uid()));
CREATE OR REPLACE FUNCTION public.create_zelle_demo_transfer(input_invoice_id UUID, input_scenario TEXT)
RETURNS SETOF public.zelle_demo_transfers LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE invoice public.zelle_invoices%ROWTYPE; transfer_id UUID;
BEGIN
    SELECT * INTO invoice FROM public.zelle_invoices WHERE id = input_invoice_id FOR UPDATE;
    IF NOT FOUND OR NOT invoice.is_demo OR NOT public.zelle_is_active_payer(invoice.school_id, invoice.payer_user_id, auth.uid())
       OR invoice.status NOT IN ('open','rejected') THEN RAISE EXCEPTION 'Demo payer access required'; END IF;
    IF input_scenario IS NULL OR input_scenario NOT IN ('matching','missing','wrong_amount') THEN
        RAISE EXCEPTION 'Invalid scenario'; END IF;
    INSERT INTO public.zelle_demo_transfers(invoice_id, reference, amount_cents, recipient, received, scenario)
    VALUES (invoice.id, 'TEST-' || upper(replace(gen_random_uuid()::TEXT, '-', '')),
        CASE WHEN input_scenario = 'wrong_amount' THEN invoice.amount_due_cents - 1 ELSE invoice.amount_due_cents END,
        invoice.recipient_snapshot->>'value', input_scenario <> 'missing', input_scenario) RETURNING id INTO transfer_id;
    RETURN QUERY SELECT * FROM public.zelle_demo_transfers WHERE id = transfer_id;
END; $$;
REVOKE ALL ON FUNCTION public.create_zelle_demo_transfer(UUID,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_zelle_demo_transfer(UUID,TEXT) TO authenticated;
-- Server enforces bank matching even if the demo UI is bypassed.
CREATE OR REPLACE FUNCTION public.verify_zelle_demo_approval() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NEW.status = 'approved' AND OLD.status <> 'approved' AND NOT EXISTS (
        SELECT 1 FROM public.zelle_demo_transfers transfer
        JOIN public.zelle_invoices invoice ON invoice.id = transfer.invoice_id
        WHERE transfer.invoice_id = NEW.invoice_id AND transfer.reference = NEW.confirmation_reference
          AND transfer.received AND transfer.amount_cents = invoice.amount_due_cents
          AND transfer.recipient = invoice.recipient_snapshot->>'value' AND invoice.is_demo
    ) THEN RAISE EXCEPTION 'No matching received demo transfer. Request an update instead.'; END IF;
    RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.verify_zelle_demo_approval() FROM PUBLIC;
DROP TRIGGER IF EXISTS verify_zelle_demo_approval ON public.zelle_payment_submissions;
CREATE TRIGGER verify_zelle_demo_approval BEFORE UPDATE ON public.zelle_payment_submissions
FOR EACH ROW EXECUTE FUNCTION public.verify_zelle_demo_approval();
COMMIT;
