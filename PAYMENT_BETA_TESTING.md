# Zelle feedback beta: test without a Zelle account

This beta keeps invoices, corrections, school review, receipts, and onboarding
in FireflyFM. **No Zelle account, bank login, or real transfer is needed.** The
Simulator demo has a separate local Supabase project and a simulated bank ledger.
Every demo receipt means “DEMO — no money moved.”

## Start the demo

Requirements: Docker Desktop running, Xcode with an iPhone 17 Pro Simulator,
and this repository’s installed Supabase CLI (`npm install` if needed).

From the repository root:

```bash
bash scripts/payment-demo/prepare.sh --reset
xcodebuild -project FireflyFM.xcodeproj -scheme FireflyFM -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /private/tmp/firefly-payment-build CODE_SIGNING_ALLOWED=NO build
node scripts/payment-demo/launch.mjs
```

`--reset` resets **only** `fireflyfm-payment-demo`, runs the full database regression
suite, and seeds synthetic accounts. Omit it to apply pending local migrations and resume an existing demo.
The project uses ports 55421–55424 and lives at
`/private/tmp/fireflyfm-payment-demo`. It never uses the linked cloud project,
repository `.env`, or production credentials. The demo SQL lives outside the
production migration directory. Do not install it in any cloud database.

Use **Demo account** at the top of the app to switch between real authenticated
local accounts. This performs a normal sign-out and password sign-in; it does
not override roles or bypass database authorization.

| Account | Purpose |
|---|---|
| `parent-a` | Onboarding deposit, acknowledgement, later tuition invoice |
| `director-a` | School A invoices and payment reviews |
| `teacher-a` | Assigned child readiness; no parent billing access |
| `parent-b` | School B privacy/isolation check |
| `hq` | New school-director payment review |
| `new-director` | School B onboarding payer |

Manual sign-in: append `@payment-demo.example.test` to an account name.
Password: `REMOVED_DEMO_PASSWORD` (local synthetic accounts only).

## Walk through the feedback loop

1. Select **parent-a**. Open **Demo enrollment deposit** in the setup checklist.
2. Scroll to **DEMO bank**, choose **Generate simulated transfer → Matching
   payment**, and copy its reference. Open **I sent this payment**, paste the
   reference, and submit. The invoice becomes Submitted, not Paid.
3. Select **director-a**. Open **Workspace → Payments** or the review notification.
   Open the deposit and compare the claimed reference, amount, recipient, and
   date with the received entry in **DEMO bank**. Use **Verify in bank & review**.
4. Choose **Request an update** with a specific explanation. Return as the parent:
   the invoice displays that feedback and prior submissions. Correct the report
   using the **same reference**; do not generate/send another payment merely to
   correct the reference or date.
5. Return as director and approve. The parent sees a demo receipt, and the payment
   checklist item is approved. The separate acknowledgement must also be accepted
   before full access is released. This uses a native synthetic acknowledgement,
   so no Google account or external form setup is required.
6. Once onboarding is complete, open **Workspace → Payments → Second semester
   tuition**. Repeat the transfer/submission/review loop. This ordinary invoice
   never re-locks enrollment. Directors can also create another one-time invoice.

For the opposite order, reset the demo and accept the acknowledgement before
approving the payment. Access must remain restricted until both are complete.

## Negative cases

- **No received payment / Wrong amount:** generate that scenario and submit its
  reference. Even a direct approval API call is rejected by the demo database.
  The reviewer should request clarification. These controls simulate bank facts;
  generating a matching transfer later represents a separate hypothetical event.
- **Duplicate reference:** reuse a reference on a different invoice. The server
  rejects it. Corrections on the original invoice preserve all attempts.
- **Void:** cancels the invoice and closes pending submissions; it neither
  refunds money nor clears the onboarding blocker.
- **Replacement:** from a void invoice, choose **Create replacement invoice**.
  It retains the amount, uses current recipient instructions, and gets a new
  seven-day due date. The old invoice stays in history; only one replacement
  can be created from it.
- **Waiver:** choose **Waive payment requirement** with a reason. This is separate
  from voiding and may release access, but never produces a paid receipt.
- **Role isolation:** teacher/other-parent accounts cannot read parent invoices;
  directors cannot approve their own payment or an HQ-reviewed director fee.
- **Recipient changes:** changing school instructions does not change an issued
  invoice. Void and replace an incorrect invoice rather than silently redirecting it.

## Automated checks

After a fresh reset, run:

```bash
node scripts/payment-demo/verify.mjs
```

This uses real local Auth sessions to test isolation, missing/wrong-amount bank
entries, correction history, same-reference retry, concurrent approval,
onboarding plus an acknowledgement, later tuition, teacher readiness, and HQ
replacement/waiver. It leaves sample payments completed; reset to practice again.

Database regressions are in `009_zelle_manual_billing.sql` and
`010_zelle_feedback_beta.sql`. Production migrations must report demo disabled
and have no `zelle_demo_transfers` table. The broader database suite can be run
against the fresh local project before installing demo SQL; record unrelated
failures separately. Swift tests cover payment policy and model behavior;
`PaymentDemoUITests` is opt-in and requires `FIREFLY_DEMO_ANON_KEY` in its test
runner environment.

## Real-money boundary

Release/device builds exclude demo controls and the local endpoint override.
Real payments still happen in the payer’s bank app, and an authorized reviewer
must verify receipt there. A short reference is not proof. No screenshots, bank
credentials, account numbers, or routing numbers are collected. Never enter a
practice reference into a real invoice.

A real pilot still needs verified recipient ownership, business-bank eligibility,
limits, reviewer procedures, legal disclosure review, and actual bank/device
validation. Older invoices have migration-time recipient snapshots; those do not
reconstruct historical instructions and must be reconciled before a pilot.

## Verification after the failure fixes

The full database regression suite passes **337 checks across 10 files** in a
separate database-only environment. Application-schema lint (`--schema public`)
is clean. Scope lint to application code: pgTAP extension helpers intentionally
refer to temporary test objects and older PostgreSQL catalogs, which generate
irrelevant errors when linted as application functions.

Onboarding assignment lifecycle/content changes now use the same role-aware
management policy as the read model. Director promotion remains gated by the
new role's onboarding; the chat tests explicitly verify restricted access before
representing approved access. Simulator/demo walkthroughs were not rerun during
these fixes.
