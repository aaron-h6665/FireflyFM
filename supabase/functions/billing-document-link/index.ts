import {
  adminRows,
  assertUUID,
  authenticatedUser,
  BillingError,
  errorResponse,
  json,
  requirePost,
  stripeRequest,
} from "../_shared/billing.ts"

type RequestBody = { invoiceId?: string; kind?: "pay" | "invoicePDF" | "receipt" }
type InvoiceRow = {
  id: string
  school_id: string
  parent_user_id: string
  stripe_invoice_id: string
}
type AccountRow = { stripe_account_id: string }

Deno.serve(async (request) => {
  try {
    requirePost(request)
    const user = await authenticatedUser(request)
    const body = await request.json() as RequestBody
    assertUUID(body.invoiceId, "invoiceId")
    if (!body.kind || !["pay", "invoicePDF", "receipt"].includes(body.kind)) {
      throw new BillingError("A valid link kind is required")
    }
    const invoices = await adminRows<InvoiceRow>(
      `billing_invoices?select=id,school_id,parent_user_id,stripe_invoice_id&id=eq.${body.invoiceId}&limit=1`,
    )
    const invoice = invoices[0]
    if (!invoice) throw new BillingError("Invoice not found", 404)
    if (invoice.parent_user_id !== user.id) throw new BillingError("This invoice belongs to another payer", 403)
    const membership = await adminRows<{ id: string }>(
      `school_memberships?select=id&school_id=eq.${invoice.school_id}&user_id=eq.${user.id}`
        + "&role=eq.parent&active=eq.true&access_state=eq.full&limit=1",
    )
    if (membership.length === 0) throw new BillingError("Active parent access is required", 403)
    const accounts = await adminRows<AccountRow>(
      `school_payment_accounts?select=stripe_account_id&school_id=eq.${invoice.school_id}&limit=1`,
    )
    if (!accounts[0]?.stripe_account_id) throw new BillingError("School billing is unavailable", 409)

    const stripeInvoice = await stripeRequest<{
      hosted_invoice_url?: string | null
      invoice_pdf?: string | null
    }>("GET", `invoices/${encodeURIComponent(invoice.stripe_invoice_id)}`, {}, accounts[0].stripe_account_id)
    const url = body.kind === "invoicePDF" ? stripeInvoice.invoice_pdf : stripeInvoice.hosted_invoice_url
    if (!url) throw new BillingError("This document is not available yet", 409)
    return json({ url })
  } catch (error) {
    return errorResponse(error)
  }
})
