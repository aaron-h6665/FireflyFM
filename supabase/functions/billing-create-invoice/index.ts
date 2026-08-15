import {
  adminRequest,
  adminRows,
  assertIdempotencyKey,
  assertUUID,
  authenticatedUser,
  authAdminUser,
  BillingError,
  errorResponse,
  json,
  requireLiveBillingAssurance,
  requirePost,
  requireSchoolDirector,
  stripeRequest,
  unixDate,
} from "../_shared/billing.ts"

type LineItem = { description?: string; quantity?: number; unitAmountCents?: number }
type RequestBody = {
  schoolId?: string
  parentUserId?: string
  childId?: string | null
  lineItems?: LineItem[]
  dueDate?: string
  recurrence?: "once" | "weekly" | "biweekly" | "monthly"
  memo?: string | null
  idempotencyKey?: string
}
type AccountRow = {
  stripe_account_id: string | null
  charges_enabled: boolean
  live_payments_enabled: boolean
  sandbox: boolean
}
type CustomerRow = { id: string; stripe_customer_id: string }
type StripeInvoice = Record<string, unknown> & {
  id: string
  customer: string
  number?: string | null
  description?: string | null
  currency?: string
  amount_due?: number
  amount_paid?: number
  amount_remaining?: number
  status?: string
  due_date?: number | null
  created?: number
  status_transitions?: { finalized_at?: number; paid_at?: number; voided_at?: number }
}

Deno.serve(async (request) => {
  try {
    requirePost(request)
    const user = await authenticatedUser(request)
    const body = await request.json() as RequestBody
    assertUUID(body.schoolId, "schoolId")
    assertUUID(body.parentUserId, "parentUserId")
    if (body.childId) assertUUID(body.childId, "childId")
    assertIdempotencyKey(body.idempotencyKey)
    await requireSchoolDirector(body.schoolId, user.id)
    await requireLiveBillingAssurance(user)

    const recurrence = body.recurrence ?? "once"
    if (!["once", "weekly", "biweekly", "monthly"].includes(recurrence)) {
      throw new BillingError("Unsupported invoice recurrence")
    }
    const items = validateLineItems(body.lineItems)
    const memo = body.memo?.trim() || "Childcare tuition and school fees"
    if (memo.length > 500) throw new BillingError("Memo must be 500 characters or fewer")
    const daysUntilDue = validateDueDate(body.dueDate)

    const parents = await adminRows<{ id: string }>(
      `school_memberships?select=id&school_id=eq.${body.schoolId}&user_id=eq.${body.parentUserId}`
        + "&role=eq.parent&active=eq.true&access_state=eq.full&limit=1",
    )
    if (parents.length === 0) throw new BillingError("The selected payer is not an active parent at this school", 422)
    if (body.childId) {
      const guardians = await adminRows<{ child_id: string }>(
        `child_guardians?select=child_id&child_id=eq.${body.childId}&guardian_id=eq.${body.parentUserId}`
          + "&verification_status=eq.verified&ended_at=is.null&limit=1",
      )
      const children = await adminRows<{ id: string }>(
        `children?select=id&id=eq.${body.childId}&school_id=eq.${body.schoolId}&active=eq.true&limit=1`,
      )
      if (guardians.length === 0 || children.length === 0) {
        throw new BillingError("The selected payer is not a verified guardian for that child", 422)
      }
    }

    const accounts = await adminRows<AccountRow>(
      `school_payment_accounts?select=stripe_account_id,charges_enabled,live_payments_enabled,sandbox`
        + `&school_id=eq.${body.schoolId}&limit=1`,
    )
    const account = accounts[0]
    if (!account?.stripe_account_id) throw new BillingError("Complete Stripe onboarding before issuing invoices", 409)
    if (!account.charges_enabled) throw new BillingError("Stripe has not enabled charges for this school", 409)
    if (!account.sandbox && !account.live_payments_enabled) throw new BillingError("Live payments are not enabled for this school", 403)

    const customerID = await findOrCreateCustomer(
      body.schoolId,
      body.parentUserId,
      account.stripe_account_id,
      body.idempotencyKey,
    )
    const localInvoiceID = crypto.randomUUID()
    let stripeInvoice: StripeInvoice
    let scheduleID: string | null = null

    if (recurrence === "once") {
      const draft = await stripeRequest<StripeInvoice>("POST", "invoices", {
        customer: customerID,
        collection_method: "send_invoice",
        days_until_due: daysUntilDue,
        auto_advance: false,
        description: memo,
        "metadata[firefly_invoice_id]": localInvoiceID,
        "metadata[firefly_school_id]": body.schoolId,
        "metadata[firefly_parent_user_id]": body.parentUserId,
        "metadata[firefly_child_id]": body.childId ?? "",
      }, account.stripe_account_id, `${body.idempotencyKey}:invoice`)
      for (const [index, item] of items.entries()) {
        await stripeRequest("POST", "invoiceitems", {
          customer: customerID,
          invoice: draft.id,
          description: item.description,
          quantity: item.quantity,
          unit_amount: item.unitAmountCents,
          currency: "usd",
        }, account.stripe_account_id, `${body.idempotencyKey}:item:${index}`)
      }
      await stripeRequest("POST", `invoices/${encodeURIComponent(draft.id)}/finalize`, {
        auto_advance: true,
      }, account.stripe_account_id, `${body.idempotencyKey}:finalize`)
      stripeInvoice = await stripeRequest<StripeInvoice>(
        "POST",
        `invoices/${encodeURIComponent(draft.id)}/send`,
        {},
        account.stripe_account_id,
        `${body.idempotencyKey}:send`,
      )
    } else {
      scheduleID = crypto.randomUUID()
      const interval = recurrence === "monthly" ? "month" : "week"
      const intervalCount = recurrence === "biweekly" ? 2 : 1
      const fields: Record<string, string | number | boolean> = {
        customer: customerID,
        collection_method: "send_invoice",
        days_until_due: daysUntilDue,
        "metadata[firefly_schedule_id]": scheduleID,
        "metadata[firefly_school_id]": body.schoolId,
        "metadata[firefly_parent_user_id]": body.parentUserId,
        "metadata[firefly_child_id]": body.childId ?? "",
        "expand[0]": "latest_invoice",
      }
      for (const [index, item] of items.entries()) {
        fields[`items[${index}][price_data][currency]`] = "usd"
        fields[`items[${index}][price_data][unit_amount]`] = item.unitAmountCents
        fields[`items[${index}][price_data][recurring][interval]`] = interval
        fields[`items[${index}][price_data][recurring][interval_count]`] = intervalCount
        fields[`items[${index}][price_data][product_data][name]`] = item.description
        fields[`items[${index}][quantity]`] = item.quantity
      }
      const subscription = await stripeRequest<Record<string, unknown> & { id: string; latest_invoice: StripeInvoice }>(
        "POST",
        "subscriptions",
        fields,
        account.stripe_account_id,
        `${body.idempotencyKey}:subscription`,
      )
      stripeInvoice = subscription.latest_invoice
      await adminRequest("billing_schedules", {
        method: "POST",
        body: JSON.stringify({
          id: scheduleID,
          school_id: body.schoolId,
          parent_user_id: body.parentUserId,
          child_id: body.childId ?? null,
          stripe_subscription_id: subscription.id,
          cadence: recurrence,
          description: memo,
          days_until_due: daysUntilDue,
          created_by: user.id,
        }),
      })
    }

    const invoiceRows = await adminRequest<Array<{ id: string }>>("billing_invoices?on_conflict=stripe_invoice_id", {
      method: "POST",
      headers: { prefer: "resolution=merge-duplicates,return=representation" },
      body: JSON.stringify(invoiceProjection(
        localInvoiceID,
        stripeInvoice,
        body,
        scheduleID,
        user.id,
        memo,
      )),
    })
    const savedInvoiceID = invoiceRows[0]?.id ?? localInvoiceID
    await adminRequest("billing_invoice_items", {
      method: "POST",
      body: JSON.stringify(items.map((item) => ({
        invoice_id: savedInvoiceID,
        description: item.description,
        quantity: item.quantity,
        unit_amount_cents: item.unitAmountCents,
        amount_cents: item.quantity * item.unitAmountCents,
      }))),
    })
    await adminRequest("billing_audit_log", {
      method: "POST",
      body: JSON.stringify({
        school_id: body.schoolId,
        actor_id: user.id,
        action: recurrence === "once" ? "invoice_issued" : "recurring_invoice_started",
        entity_type: "billing_invoice",
        entity_id: savedInvoiceID,
        metadata: { recurrence },
      }),
    })
    await createInvoiceNotification(body.schoolId, body.parentUserId, savedInvoiceID, memo)
    return json({ invoiceId: savedInvoiceID, status: stripeInvoice.status ?? "open" }, 201)
  } catch (error) {
    return errorResponse(error)
  }
})

function validateLineItems(raw: LineItem[] | undefined) {
  if (!raw || raw.length < 1 || raw.length > 20) throw new BillingError("Provide between 1 and 20 line items")
  let total = 0
  const items = raw.map((rawItem) => {
    const description = rawItem.description?.trim() ?? ""
    const quantity = rawItem.quantity ?? 1
    const unitAmountCents = rawItem.unitAmountCents ?? 0
    if (!description || description.length > 200) throw new BillingError("Every line item needs a description of 200 characters or fewer")
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 1000) throw new BillingError("Line-item quantity is invalid")
    if (!Number.isInteger(unitAmountCents) || unitAmountCents < 50 || unitAmountCents > 100000000) {
      throw new BillingError("Line-item amount must be between $0.50 and $1,000,000.00")
    }
    total += quantity * unitAmountCents
    return { description, quantity, unitAmountCents }
  })
  if (total > 100000000) throw new BillingError("Invoice total cannot exceed $1,000,000.00")
  return items
}

function validateDueDate(raw: string | undefined): number {
  if (!raw) return 7
  const date = new Date(raw)
  if (!Number.isFinite(date.getTime())) throw new BillingError("Due date is invalid")
  const days = Math.ceil((date.getTime() - Date.now()) / 86400000)
  if (days < 1 || days > 90) throw new BillingError("Due date must be between 1 and 90 days away")
  return days
}

async function findOrCreateCustomer(schoolID: string, parentID: string, accountID: string, idempotencyKey: string) {
  const existing = await adminRows<CustomerRow>(
    `billing_customers?select=id,stripe_customer_id&school_id=eq.${schoolID}&parent_user_id=eq.${parentID}&limit=1`,
  )
  if (existing[0]) return existing[0].stripe_customer_id
  const authUser = await authAdminUser(parentID)
  if (!authUser.email || !authUser.email_confirmed_at) {
    throw new BillingError("The selected parent needs a verified email before billing", 422)
  }
  const profiles = await adminRows<{ display_name: string | null }>(`profiles?select=display_name&id=eq.${parentID}&limit=1`)
  const customer = await stripeRequest<{ id: string }>("POST", "customers", {
    email: authUser.email,
    name: profiles[0]?.display_name ?? undefined,
    "metadata[firefly_school_id]": schoolID,
    "metadata[firefly_parent_user_id]": parentID,
  }, accountID, `${idempotencyKey}:customer`)
  await adminRequest("billing_customers?on_conflict=school_id,parent_user_id", {
    method: "POST",
    headers: { prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify({ school_id: schoolID, parent_user_id: parentID, stripe_customer_id: customer.id }),
  })
  return customer.id
}

function invoiceProjection(
  localID: string,
  invoice: StripeInvoice,
  body: RequestBody,
  scheduleID: string | null,
  actorID: string,
  memo: string,
) {
  const transitions = invoice.status_transitions ?? {}
  return {
    id: localID,
    school_id: body.schoolId,
    parent_user_id: body.parentUserId,
    child_id: body.childId ?? null,
    schedule_id: scheduleID,
    stripe_invoice_id: invoice.id,
    stripe_customer_id: invoice.customer,
    invoice_number: invoice.number ?? null,
    description: invoice.description ?? memo,
    currency: (invoice.currency ?? "usd").toUpperCase(),
    amount_due_cents: invoice.amount_due ?? 0,
    amount_paid_cents: invoice.amount_paid ?? 0,
    amount_remaining_cents: invoice.amount_remaining ?? invoice.amount_due ?? 0,
    status: invoice.status ?? "open",
    payment_status: invoice.status === "paid" ? "succeeded" : "pending",
    due_at: unixDate(invoice.due_date),
    sent_at: unixDate(transitions.finalized_at),
    paid_at: unixDate(transitions.paid_at),
    voided_at: unixDate(transitions.voided_at),
    provider_created_at: unixDate(invoice.created),
    provider_updated_at: new Date().toISOString(),
    last_synced_at: new Date().toISOString(),
    created_by: actorID,
  }
}

async function createInvoiceNotification(schoolID: string, parentID: string, invoiceID: string, memo: string) {
  const notifications = await adminRequest<Array<{ id: string }>>("notifications", {
    method: "POST",
    body: JSON.stringify({
      school_id: schoolID,
      title: "New invoice",
      body: memo,
      safe_body: "A new school invoice is ready.",
      category: "billing_invoice",
      priority: "important",
      source_type: "billing_invoice",
      source_id: invoiceID,
      route: { type: "billing_invoice", id: invoiceID },
      thread_key: `billing:${invoiceID}`,
    }),
  })
  if (notifications[0]) {
    await adminRequest("notification_recipients", {
      method: "POST",
      body: JSON.stringify({ notification_id: notifications[0].id, user_id: parentID }),
    })
  }
}
