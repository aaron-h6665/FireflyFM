import {
  adminRequest,
  adminRows,
  assertIdempotencyKey,
  assertUUID,
  authenticatedUser,
  BillingError,
  errorResponse,
  json,
  requireLiveBillingAssurance,
  requirePost,
  requireSchoolDirector,
  stripeRequest,
} from "../_shared/billing.ts"

type RequestBody = {
  invoiceId?: string
  action?: "send" | "resend" | "void"
  idempotencyKey?: string
}
type InvoiceRow = {
  id: string
  school_id: string
  stripe_invoice_id: string
  status: string
}
type AccountRow = { stripe_account_id: string }

Deno.serve(async (request) => {
  try {
    requirePost(request)
    const user = await authenticatedUser(request)
    const body = await request.json() as RequestBody
    assertUUID(body.invoiceId, "invoiceId")
    assertIdempotencyKey(body.idempotencyKey)
    if (!body.action || !["send", "resend", "void"].includes(body.action)) {
      throw new BillingError("A valid invoice action is required")
    }
    const invoices = await adminRows<InvoiceRow>(
      `billing_invoices?select=id,school_id,stripe_invoice_id,status&id=eq.${body.invoiceId}&limit=1`,
    )
    const invoice = invoices[0]
    if (!invoice) throw new BillingError("Invoice not found", 404)
    await requireSchoolDirector(invoice.school_id, user.id)
    await requireLiveBillingAssurance(user)
    if (body.action === "void" && invoice.status !== "open") {
      throw new BillingError("Only an open invoice can be voided", 409)
    }
    if ((body.action === "send" || body.action === "resend") && invoice.status !== "open") {
      throw new BillingError("Only an open invoice can be sent", 409)
    }
    const accounts = await adminRows<AccountRow>(
      `school_payment_accounts?select=stripe_account_id&school_id=eq.${invoice.school_id}&limit=1`,
    )
    if (!accounts[0]?.stripe_account_id) throw new BillingError("School billing is unavailable", 409)
    const endpoint = body.action === "void"
      ? `invoices/${encodeURIComponent(invoice.stripe_invoice_id)}/void`
      : `invoices/${encodeURIComponent(invoice.stripe_invoice_id)}/send`
    const result = await stripeRequest<Record<string, unknown> & { status?: string }>(
      "POST",
      endpoint,
      {},
      accounts[0].stripe_account_id,
      body.idempotencyKey,
    )
    await adminRequest("billing_audit_log", {
      method: "POST",
      body: JSON.stringify({
        school_id: invoice.school_id,
        actor_id: user.id,
        action: `invoice_${body.action}`,
        entity_type: "billing_invoice",
        entity_id: invoice.id,
      }),
    })
    return json({ invoiceId: invoice.id, status: result.status ?? invoice.status })
  } catch (error) {
    return errorResponse(error)
  }
})
