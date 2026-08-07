import {
  adminRequest,
  adminRows,
  BillingError,
  environment,
  errorResponse,
  json,
  paymentStatusForInvoice,
  sha256,
  unixDate,
  verifyStripeSignature,
} from "../_shared/billing.ts"

type StripeEvent = {
  id: string
  account?: string
  type: string
  livemode: boolean
  created?: number
  data: { object: Record<string, unknown> }
}
type InvoiceProjection = {
  id: string
  school_id: string
  parent_user_id: string
  payment_status: string
}

Deno.serve(async (request) => {
  let eventID: string | undefined
  try {
    if (request.method !== "POST") throw new BillingError("Method not allowed", 405)
    const rawBody = await request.text()
    if (rawBody.length > 512 * 1024) throw new BillingError("Webhook is too large", 413)
    const env = environment()
    if (!env.webhookSecret) throw new Error("STRIPE_CONNECT_WEBHOOK_SECRET is required")
    const valid = await verifyStripeSignature(rawBody, request.headers.get("stripe-signature"), env.webhookSecret)
    if (!valid) throw new BillingError("Invalid Stripe signature", 400)
    const event = JSON.parse(rawBody) as StripeEvent
    if (!event.id || !event.type || !event.data?.object) throw new BillingError("Invalid Stripe event")
    eventID = event.id

    const inserted = await adminRequest<Array<{ stripe_event_id: string }>>(
      "billing_provider_events?on_conflict=stripe_event_id",
      {
        method: "POST",
        headers: { prefer: "resolution=ignore-duplicates,return=representation" },
        body: JSON.stringify({
          stripe_event_id: event.id,
          stripe_account_id: event.account ?? null,
          event_type: event.type,
          livemode: event.livemode,
          provider_created_at: unixDate(event.created),
          payload_sha256: await sha256(rawBody),
        }),
      },
    )
    if (inserted.length === 0) {
      const existing = await adminRows<{ processed_at: string | null; processing_error: string | null }>(
        `billing_provider_events?select=processed_at,processing_error&stripe_event_id=eq.${encodeURIComponent(event.id)}&limit=1`,
      )
      if (existing[0]?.processed_at && !existing[0]?.processing_error) return json({ received: true, duplicate: true })
    }

    await processEvent(event)
    await adminRequest(`billing_provider_events?stripe_event_id=eq.${encodeURIComponent(event.id)}`, {
      method: "PATCH",
      body: JSON.stringify({ processed_at: new Date().toISOString(), processing_error: null }),
    })
    return json({ received: true })
  } catch (error) {
    if (eventID) {
      await adminRequest(`billing_provider_events?stripe_event_id=eq.${encodeURIComponent(eventID)}`, {
        method: "PATCH",
        body: JSON.stringify({ processing_error: error instanceof Error ? error.message.slice(0, 500) : "Unknown error" }),
      }).catch(() => undefined)
    }
    return errorResponse(error)
  }
})

async function processEvent(event: StripeEvent) {
  const object = event.data.object
  if (event.type === "account.updated") {
    await syncAccount(object)
    return
  }
  if (event.type.startsWith("invoice.")) {
    const invoice = await syncInvoice(object, event.account, event.created)
    if (event.type === "invoice.paid") await notifyInvoice(invoice, "Invoice paid", "Your school payment was received.", event.id)
    if (event.type === "invoice.payment_failed") {
      await notifyInvoice(invoice, "Invoice payment failed", "Open Payments to review the invoice and try again.", event.id)
    }
    return
  }
  if (event.type.startsWith("payment_intent.")) {
    await syncPaymentIntent(object, event.account, event.created)
    return
  }
  if (event.type === "charge.refunded") {
    await syncChargeState(object, "refunded", event.created)
    return
  }
  if (event.type === "charge.dispute.created") {
    await syncChargeState(object, "disputed", event.created)
  }
}

async function syncAccount(object: Record<string, unknown>) {
  const accountID = String(object.id ?? "")
  if (!accountID) return
  const details = object.details_submitted === true
  const charges = object.charges_enabled === true
  const payouts = object.payouts_enabled === true
  const requirements = object.requirements as { currently_due?: unknown[]; disabled_reason?: string | null } | undefined
  const dueCount = requirements?.currently_due?.length ?? 0
  let status = details ? "restricted" : "onboarding"
  if (charges && payouts && dueCount === 0) status = "ready"
  if (requirements?.disabled_reason) status = "disabled"
  await adminRequest(`school_payment_accounts?stripe_account_id=eq.${encodeURIComponent(accountID)}`, {
    method: "PATCH",
    body: JSON.stringify({
      status,
      details_submitted: details,
      charges_enabled: charges,
      payouts_enabled: payouts,
      requirements_due_count: dueCount,
      updated_at: new Date().toISOString(),
    }),
  })
}

async function syncInvoice(
  object: Record<string, unknown>,
  connectedAccount: string | undefined,
  eventCreated: number | undefined,
): Promise<InvoiceProjection> {
  const stripeInvoiceID = String(object.id ?? "")
  const stripeCustomerID = idValue(object.customer)
  if (!stripeInvoiceID || !stripeCustomerID) throw new Error("Invoice event is missing identifiers")
  const account = await paymentAccount(connectedAccount)
  const existing = await adminRows<InvoiceProjection & { id: string }>(
    `billing_invoices?select=id,school_id,parent_user_id,payment_status&stripe_invoice_id=eq.${encodeURIComponent(stripeInvoiceID)}&limit=1`,
  )
  const metadata = (object.metadata ?? {}) as Record<string, string>
  const customers = await adminRows<{ parent_user_id: string }>(
    `billing_customers?select=parent_user_id&school_id=eq.${account.school_id}`
      + `&stripe_customer_id=eq.${encodeURIComponent(stripeCustomerID)}&limit=1`,
  )
  const subscriptionID = idValue(object.subscription)
  const schedules = subscriptionID
    ? await adminRows<{ id: string; parent_user_id: string; child_id: string | null }>(
      `billing_schedules?select=id,parent_user_id,child_id&stripe_subscription_id=eq.${encodeURIComponent(subscriptionID)}&limit=1`,
    )
    : []
  const parentID = existing[0]?.parent_user_id ?? customers[0]?.parent_user_id ?? schedules[0]?.parent_user_id ?? metadata.firefly_parent_user_id
  if (!parentID) throw new Error("Invoice payer mapping is missing")
  const status = normalizeInvoiceStatus(object.status)
  const priorPaymentStatus = existing[0]?.payment_status
  const derivedPaymentStatus = ["refunded", "disputed"].includes(priorPaymentStatus)
    ? priorPaymentStatus
    : paymentStatusForInvoice(status, object.amount_paid)
  const transitions = (object.status_transitions ?? {}) as Record<string, number>
  const localID = existing[0]?.id ?? validUUID(metadata.firefly_invoice_id) ?? crypto.randomUUID()
  const projection = {
    id: localID,
    school_id: account.school_id,
    parent_user_id: parentID,
    child_id: schedules[0]?.child_id ?? validUUID(metadata.firefly_child_id),
    schedule_id: schedules[0]?.id ?? null,
    stripe_invoice_id: stripeInvoiceID,
    stripe_customer_id: stripeCustomerID,
    invoice_number: typeof object.number === "string" ? object.number : null,
    description: typeof object.description === "string" && object.description.trim()
      ? object.description.trim().slice(0, 500)
      : "Childcare tuition and school fees",
    currency: String(object.currency ?? "usd").toUpperCase(),
    amount_due_cents: integer(object.amount_due),
    amount_paid_cents: integer(object.amount_paid),
    amount_remaining_cents: integer(object.amount_remaining),
    status,
    payment_status: derivedPaymentStatus,
    due_at: unixDate(object.due_date),
    period_start: unixDate(object.period_start),
    period_end: unixDate(object.period_end),
    sent_at: unixDate(transitions.finalized_at),
    paid_at: unixDate(transitions.paid_at),
    voided_at: unixDate(transitions.voided_at),
    provider_created_at: unixDate(object.created),
    provider_updated_at: unixDate(eventCreated) ?? new Date().toISOString(),
    last_synced_at: new Date().toISOString(),
  }
  const rows = await adminRequest<InvoiceProjection[]>("billing_invoices?on_conflict=stripe_invoice_id", {
    method: "POST",
    headers: { prefer: "resolution=merge-duplicates,return=representation" },
    body: JSON.stringify(projection),
  })
  const invoice = rows[0] ?? projection
  const lines = ((object.lines as { data?: Record<string, unknown>[] } | undefined)?.data ?? []).slice(0, 100)
  if (lines.length > 0) {
    await adminRequest(`billing_invoice_items?invoice_id=eq.${invoice.id}`, { method: "DELETE" })
    await adminRequest("billing_invoice_items", {
      method: "POST",
      body: JSON.stringify(lines.map((line) => {
        const quantity = Math.max(1, integer(line.quantity) || 1)
        const amount = Math.max(1, integer(line.amount))
        return {
          invoice_id: invoice.id,
          stripe_invoice_item_id: typeof line.id === "string" ? line.id : null,
          description: typeof line.description === "string" ? line.description.slice(0, 200) : "Invoice item",
          quantity,
          unit_amount_cents: Math.max(1, Math.round(amount / quantity)),
          amount_cents: amount,
        }
      })),
    })
  }
  return invoice
}

async function syncPaymentIntent(object: Record<string, unknown>, connectedAccount: string | undefined, eventCreated?: number) {
  const paymentIntentID = String(object.id ?? "")
  const stripeInvoiceID = idValue(object.invoice)
  if (!paymentIntentID || !stripeInvoiceID) return
  const account = await paymentAccount(connectedAccount)
  const invoices = await adminRows<InvoiceProjection & { id: string }>(
    `billing_invoices?select=id,school_id,parent_user_id,payment_status&stripe_invoice_id=eq.${encodeURIComponent(stripeInvoiceID)}&limit=1`,
  )
  const invoice = invoices[0]
  if (!invoice) return
  const status = normalizePaymentStatus(object.status)
  const methodTypes = Array.isArray(object.payment_method_types) ? object.payment_method_types : []
  await adminRequest("billing_payments?on_conflict=stripe_payment_intent_id", {
    method: "POST",
    headers: { prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify({
      invoice_id: invoice.id,
      school_id: account.school_id,
      parent_user_id: invoice.parent_user_id,
      stripe_payment_intent_id: paymentIntentID,
      amount_cents: integer(object.amount_received) || integer(object.amount),
      currency: String(object.currency ?? "usd").toUpperCase(),
      status,
      payment_method_type: typeof methodTypes[0] === "string" ? methodTypes[0] : null,
      failure_code: ((object.last_payment_error ?? {}) as Record<string, unknown>).code ?? null,
      provider_created_at: unixDate(object.created),
      provider_updated_at: unixDate(eventCreated) ?? new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }),
  })
  await adminRequest(`billing_invoices?id=eq.${invoice.id}`, {
    method: "PATCH",
    body: JSON.stringify({ payment_status: status, last_synced_at: new Date().toISOString() }),
  })
}

async function syncChargeState(object: Record<string, unknown>, status: "refunded" | "disputed", eventCreated?: number) {
  const paymentIntentID = idValue(object.payment_intent)
  if (!paymentIntentID) return
  const payments = await adminRows<{ id: string; invoice_id: string | null }>(
    `billing_payments?select=id,invoice_id&stripe_payment_intent_id=eq.${encodeURIComponent(paymentIntentID)}&limit=1`,
  )
  if (!payments[0]) return
  await adminRequest(`billing_payments?id=eq.${payments[0].id}`, {
    method: "PATCH",
    body: JSON.stringify({ status, provider_updated_at: unixDate(eventCreated), updated_at: new Date().toISOString() }),
  })
  if (payments[0].invoice_id) {
    await adminRequest(`billing_invoices?id=eq.${payments[0].invoice_id}`, {
      method: "PATCH",
      body: JSON.stringify({ payment_status: status, last_synced_at: new Date().toISOString() }),
    })
  }
}

async function paymentAccount(stripeAccountID: string | undefined) {
  if (!stripeAccountID) throw new Error("Connected account is missing from event")
  const accounts = await adminRows<{ school_id: string }>(
    `school_payment_accounts?select=school_id&stripe_account_id=eq.${encodeURIComponent(stripeAccountID)}&limit=1`,
  )
  if (!accounts[0]) throw new Error("Connected account is not mapped to a school")
  return accounts[0]
}

async function notifyInvoice(invoice: InvoiceProjection, title: string, body: string, eventID: string) {
  const notifications = await adminRequest<Array<{ id: string }>>("notifications", {
    method: "POST",
    body: JSON.stringify({
      school_id: invoice.school_id,
      title,
      body,
      safe_body: body,
      category: "billing_invoice",
      priority: "important",
      source_type: "billing_invoice",
      source_id: invoice.id,
      route: { type: "billing_invoice", id: invoice.id },
      thread_key: `billing:${invoice.id}`,
    }),
  })
  if (notifications[0]) {
    await adminRequest("notification_recipients", {
      method: "POST",
      body: JSON.stringify({ notification_id: notifications[0].id, user_id: invoice.parent_user_id }),
    })
  }
  await adminRequest("billing_audit_log", {
    method: "POST",
    body: JSON.stringify({
      school_id: invoice.school_id,
      action: title === "Invoice paid" ? "invoice_paid" : "invoice_payment_failed",
      entity_type: "billing_invoice",
      entity_id: invoice.id,
      stripe_event_id: eventID,
    }),
  })
}

function normalizeInvoiceStatus(value: unknown): string {
  return ["draft", "open", "paid", "void", "uncollectible"].includes(String(value)) ? String(value) : "draft"
}

function normalizePaymentStatus(value: unknown): string {
  switch (value) {
    case "processing": return "processing"
    case "succeeded": return "succeeded"
    case "requires_payment_method":
    case "canceled": return "failed"
    default: return "pending"
  }
}

function idValue(value: unknown): string | null {
  if (typeof value === "string") return value
  if (value && typeof value === "object" && typeof (value as Record<string, unknown>).id === "string") {
    return (value as Record<string, unknown>).id as string
  }
  return null
}

function integer(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? Math.max(0, Math.round(value)) : 0
}

function validUUID(value: unknown): string | null {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
    ? value
    : null
}
