# FireflyFM Payment Beta Testing Guide

This guide tests the complete parent-payment workflow without moving real money. The beta uses Stripe **test mode**, Stripe Connect test accounts, Supabase Edge Functions, and FireflyFM parent/director beta users.

> Never put a live Stripe secret key, webhook signing secret, card number, bank number, or Supabase service-role key in the app, this repository, screenshots, or test notes.

## 1. What the beta covers

- A school director connects the school to a Stripe test account.
- The director issues a one-time or repeating invoice to one named parent.
- Stripe creates the invoice and hosted payment page.
- The parent sees the invoice in FireflyFM and pays on Stripe's hosted page.
- Signed Stripe webhooks update FireflyFM to `processing`, `paid`, `failed`, `refunded`, or `disputed`.
- The parent can view the invoice PDF and paid receipt.
- The school director can review, resend, or void an unpaid invoice.
- HQ can review cross-school totals but cannot issue, void, or pay invoices.

Refunds and disputes are reviewed in the connected school's Stripe Dashboard during beta. FireflyFM does not collect or store card or bank credentials.

## 2. Prerequisites

You need:

1. A Stripe platform account with Connect enabled in test mode.
2. Access to the FireflyFM Supabase project and CLI. For local database tests, Docker Desktop must be running; for Edge Function unit tests, install Deno.
3. A director beta account with `school_director`, active membership, and `access_state = 'full'`.
4. A parent beta account at the same school with `access_state = 'full'`.
5. If an invoice is associated with a child, the parent must have an active `child_guardians` row with `verification_status = 'verified'`.
6. A TestFlight or Debug build pointed at the Supabase project where the billing migration and functions are deployed.

Use dedicated test emails and Stripe's test identity/payment data. Do not use a real parent's financial or identity information.

### Required third-party services

- **Stripe Connect Express and Stripe Invoicing** provide school onboarding, hosted payment pages, payment collection, invoice PDFs, receipts, refunds, disputes, and signed webhooks.
- **Supabase** remains FireflyFM's existing backend for Auth, Postgres/RLS, Edge Functions, notification routing, and the non-sensitive billing projection.
- No additional invoice, card-vault, or email vendor is required for this beta. Stripe-hosted pages keep card and bank credentials out of FireflyFM.

Stripe CLI is optional for local webhook experiments. The hosted Stripe test webhook configured below is the shortest reliable end-to-end beta path.

## 3. Deploy the beta backend

From the repository root:

```bash
npx supabase db push
npx supabase functions deploy stripe-connect-onboard
npx supabase functions deploy stripe-connect-return --no-verify-jwt
npx supabase functions deploy billing-create-invoice
npx supabase functions deploy billing-invoice-action
npx supabase functions deploy billing-document-link
npx supabase functions deploy stripe-connect-webhook --no-verify-jwt
```

Set project secrets. All Stripe values in beta must begin with the test prefixes `sk_test_` or `whsec_`:

```bash
npx supabase secrets set STRIPE_SECRET_KEY=sk_test_REPLACE_ME
npx supabase secrets set STRIPE_CONNECT_WEBHOOK_SECRET=whsec_REPLACE_ME
npx supabase secrets set BILLING_REQUIRE_AAL2=false
npx supabase secrets set STRIPE_CONNECT_RETURN_URL=https://PROJECT_REF.supabase.co/functions/v1/stripe-connect-return?state=complete
npx supabase secrets set STRIPE_CONNECT_REFRESH_URL=https://PROJECT_REF.supabase.co/functions/v1/stripe-connect-return?state=refresh
```

`BILLING_REQUIRE_AAL2=false` is allowed only for an isolated Stripe test-mode beta. The functions automatically require AAL2 whenever the Stripe key is live. Production should explicitly set it to `true` after the director MFA UI is enabled.

In Stripe Dashboard, add this endpoint and select **Events on connected accounts**:

```text
https://PROJECT_REF.supabase.co/functions/v1/stripe-connect-webhook
```

Subscribe to at least:

- `account.updated`
- `invoice.created`
- `invoice.finalized`
- `invoice.sent`
- `invoice.paid`
- `invoice.payment_failed`
- `invoice.voided`
- `payment_intent.processing`
- `payment_intent.succeeded`
- `payment_intent.payment_failed`
- `charge.refunded`
- `charge.dispute.created`
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`

Copy that endpoint's signing secret into `STRIPE_CONNECT_WEBHOOK_SECRET`. A signing secret from another endpoint or from Stripe CLI will not work.

### Fastest end-to-end smoke test

After deployment, the shortest useful pass is:

1. Director opens **Workspace → Payments** and completes Stripe test onboarding.
2. Director issues a one-time $1.00 invoice to the beta parent.
3. Parent opens **Workspace → Payments**, checks the amount, and pays on Stripe's hosted page with `4242 4242 4242 4242`.
4. Parent refreshes until the invoice says **Paid** and can open the receipt.
5. Director refreshes and confirms the same payment appears in collected totals.
6. Repeat once with another parent and once with the decline card in section 7 before moving on to the full security matrix.

## 4. Prepare beta users

Create two accounts through the normal FireflyFM invitation/onboarding flow:

| User | Required state |
|---|---|
| Director | Active `school_director`, full access, same school as parent |
| Parent | Active `parent`, full access, verified email |
| Child, if used | Active child at that school with the parent as a verified, non-ended guardian |

For access-control testing, also prepare a teacher and a director from a second school.

Do not manually grant client write access to billing tables. The iOS app reads through RLS; only authenticated Edge Functions and verified webhooks write provider state.

## 5. Test school onboarding

1. Sign into the beta as the school director.
2. Open **Workspace → Payments**.
3. Confirm the card says **Stripe beta account**.
4. Tap **Continue Stripe setup**.
5. Complete Stripe's test onboarding with Stripe test identity and bank data.
6. Return to FireflyFM, dismiss the secure browser, and pull to refresh.
7. Confirm the setup card says charges and payouts are enabled.

Expected result:

- `school_payment_accounts` contains one opaque `acct_...` identifier.
- `sandbox = true`.
- `status = 'ready'`, `charges_enabled = true`, and `payouts_enabled = true` after Stripe sends `account.updated`.
- No bank account, identity-document contents, SSN, or representative details appear in Supabase.

If the account stays in onboarding, inspect Stripe's connected-account requirements and the `account.updated` webhook delivery before editing database status.

## 6. Issue and receive an invoice

1. As the director, tap **New Invoice**.
2. Select the beta parent.
3. Optionally select a child linked to that parent.
4. Add one or more line items, choose a due date 1–90 days away, and choose **One time**, **Weekly**, **Every two weeks**, or **Monthly**.
5. Tap **Issue** once.
6. Confirm the invoice appears as **Open** in the director list.
7. Sign in as the named parent and open **Workspace → Payments**.
8. Confirm only that parent's invoice appears.

Expected result:

- Stripe contains the Customer and Invoice under the school's connected test account.
- FireflyFM contains only opaque Stripe IDs, amounts, dates, and status.
- A FireflyFM in-app notification routes to Payments.
- Stripe test mode can suppress invoice emails to arbitrary recipients. Validate the invoice through the app and Stripe Dashboard; validate actual email delivery later with an approved controlled live pilot.

Repeat the issue action after simulating a slow network. The idempotency key should prevent duplicate Stripe objects for the same accepted request.

## 7. Test card payment

1. As the named parent, open the invoice.
2. Tap **Pay securely with Stripe**.
3. Confirm the page is hosted on `invoice.stripe.com` and shows the correct school, amount, and line items.
4. Use Stripe's standard success test card:
   - Card: `4242 4242 4242 4242`
   - Any future expiration date
   - Any valid CVC and postal code
5. Complete payment, return to FireflyFM, and pull to refresh.

Expected result:

- The app initially may show **Processing**.
- After signed webhooks arrive, the invoice becomes **Paid**, remaining balance becomes `$0.00`, and the director's collected total increases.
- **View receipt** opens the Stripe-hosted paid invoice/receipt page.
- A second payment is not offered for the paid invoice.

For a decline, create another invoice and use Stripe's insufficient-funds test card `4000 0000 0000 9995`. Confirm no paid state is shown and the parent can retry.

## 8. Test ACH payment

Enable ACH Direct Debit in the connected account's Invoice payment-method settings, then create a new invoice.

Use Stripe's ACH test values on the hosted page:

- Routing number: `110000000`
- Success account: `000123456789`
- Failure account: `000111111116`

Expected result:

- ACH never appears instantly settled in FireflyFM merely because the hosted form completed.
- It remains **Processing** until Stripe sends the final success webhook.
- A failed ACH test becomes **Failed** and the invoice remains payable.

## 9. Test director controls

Create a new unpaid invoice, then verify:

1. **Resend invoice email** calls Stripe but does not create a second invoice.
2. **Void invoice** requires destructive confirmation.
3. A void invoice can no longer be paid.
4. A paid invoice cannot be voided in FireflyFM.
5. Refund controls are absent from FireflyFM; perform a test refund in Stripe Dashboard and confirm the app synchronizes to **Refunded**.
6. Create a Stripe test dispute and confirm it synchronizes to **Disputed**.

Never manually change invoice or payment status in Supabase to make a test pass. Stripe is authoritative.

## 10. Test role and school isolation

Run this matrix:

| Scenario | Expected result |
|---|---|
| Named parent | Sees and pays only their invoices |
| Another guardian/parent | Cannot retrieve the invoice or hosted URL |
| Teacher | No Payments workspace or billing data |
| School A director | Can manage School A, cannot see School B billing |
| School B director | Cannot see or mutate School A billing |
| HQ director | Sees cross-school totals and invoices, but no issue/void/pay actions |
| Inactive or onboarding membership | No billing access |

Also verify that copying a FireflyFM invoice UUID into another account does not produce a Stripe URL. The `billing-document-link` function must return `403`.

## 11. Verify webhook safety

In Stripe Dashboard:

1. Resend the same `invoice.paid` event twice.
2. Confirm only one `billing_provider_events` row exists for the event ID.
3. Confirm totals and notifications are not duplicated.
4. Send a request without a valid Stripe signature; confirm it returns `400` and writes nothing.
5. Inspect function logs and confirm they do not contain hosted invoice URLs, authorization headers, payment credentials, or raw webhook bodies.

Useful safe queries:

```sql
select school_id, status, charges_enabled, payouts_enabled, sandbox
from public.school_payment_accounts;

select id, school_id, parent_user_id, description, amount_due_cents,
       amount_paid_cents, status, payment_status, last_synced_at
from public.billing_invoices
order by created_at desc;

select stripe_event_id, event_type, processed_at, processing_error
from public.billing_provider_events
order by received_at desc
limit 50;
```

Do not select or share secret columns from auth, environment settings, or Stripe.

## 12. Automated checks before each beta build

Run:

```bash
npx supabase status
npx supabase test db
npx supabase db lint --local --level error
deno test supabase/functions/_shared/billing_test.ts
bash scripts/generate-schema-snapshot.sh --check
xcodebuild -project FireflyFM.xcodeproj -scheme FireflyFM \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/FireflyFM-PaymentBetaDerivedData \
  CODE_SIGNING_ALLOWED=NO build-for-testing
```

Then run the complete `FireflyFMTests` suite and `testFourTabRoleMatrix` for Parent, Teacher, School Director, and HQ Director.

## 13. Exit criteria for live pilot

Do not switch to a live Stripe key until all are true:

- Every role/school isolation test passes.
- Duplicate and out-of-order webhook tests converge correctly.
- Card success, decline, ACH processing/success/failure, void, refund, and dispute states pass.
- Stripe totals reconcile with FireflyFM projections for the full beta period.
- Director MFA is enabled and `BILLING_REQUIRE_AAL2=true`.
- PCI attestation, privacy/retention review, connected-account agreements, refund policy, and incident-response/key-rotation procedures are approved.
- A server-side kill switch and per-school `live_payments_enabled` rollout procedure are documented and tested.

For the first live pilot, enable only one school, issue a low-value approved invoice to an internal tester, reconcile it in Stripe, and verify the receipt before inviting real families.
