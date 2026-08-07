import {
  adminRequest,
  adminRows,
  assertUUID,
  authenticatedUser,
  BillingError,
  environment,
  errorResponse,
  json,
  requireLiveBillingAssurance,
  requirePost,
  requireSchoolDirector,
  stripeRequest,
} from "../_shared/billing.ts"

type RequestBody = { schoolId?: string }
type PaymentAccount = { id: string; stripe_account_id: string | null }

Deno.serve(async (request) => {
  try {
    requirePost(request)
    const user = await authenticatedUser(request)
    const body = await request.json() as RequestBody
    assertUUID(body.schoolId, "schoolId")
    await requireSchoolDirector(body.schoolId, user.id)
    await requireLiveBillingAssurance(user)

    const env = environment()
    if (!env.connectReturnURL || !env.connectRefreshURL) {
      throw new BillingError("Stripe Connect return URLs are not configured", 503)
    }

    const records = await adminRows<PaymentAccount>(
      `school_payment_accounts?select=id,stripe_account_id&school_id=eq.${body.schoolId}&limit=1`,
    )
    let record = records[0]
    let accountID = record?.stripe_account_id
    if (!accountID) {
      const account = await stripeRequest<{ id: string }>("POST", "accounts", {
        type: "express",
        country: "US",
        "capabilities[card_payments][requested]": true,
        "capabilities[transfers][requested]": true,
        "business_profile[product_description]": "Childcare tuition and school fees",
        "metadata[firefly_school_id]": body.schoolId,
      }, undefined, `connect-account:${body.schoolId}`)
      accountID = account.id
      const rows = await adminRequest<PaymentAccount[]>("school_payment_accounts?on_conflict=school_id", {
        method: "POST",
        headers: { prefer: "resolution=merge-duplicates,return=representation" },
        body: JSON.stringify({
          school_id: body.schoolId,
          stripe_account_id: accountID,
          status: "onboarding",
          sandbox: env.stripeSecretKey.startsWith("sk_test_"),
          updated_at: new Date().toISOString(),
        }),
      })
      record = rows[0]
    }

    const link = await stripeRequest<{ url: string; expires_at?: number }>("POST", "account_links", {
      account: accountID,
      refresh_url: env.connectRefreshURL,
      return_url: env.connectReturnURL,
      type: "account_onboarding",
      "collection_options[fields]": "eventually_due",
    }, undefined, `connect-link:${body.schoolId}:${crypto.randomUUID()}`)

    await adminRequest("billing_audit_log", {
      method: "POST",
      body: JSON.stringify({
        school_id: body.schoolId,
        actor_id: user.id,
        action: "connect_onboarding_link_created",
        entity_type: "school_payment_account",
        entity_id: record?.id,
      }),
    })
    return json({ url: link.url, expiresAt: link.expires_at ? new Date(link.expires_at * 1000).toISOString() : null })
  } catch (error) {
    return errorResponse(error)
  }
})
