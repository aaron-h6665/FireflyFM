# Zelle-guided Payments Beta Test Guide

This beta does **not** connect FireflyFM to Zelle or move money. A parent, teacher, or new school director sees the school’s recipient instructions, then submits a short confirmation reference. The authorised reviewer verifies the transfer in the school’s bank experience before marking it paid.

That makes this safe to test even if you do not have Zelle: enable the school’s **beta simulation guidance** and use a reference such as `TEST-0001`. FireflyFM never sends money for a test reference.

> Never enter or upload a bank login, account/routing number, card number, Zelle password, full payment receipt, or screenshot. The beta stores only the recipient detail, invoice, short confirmation reference, review decision, and audit history.

## What is included

- School-specific Zelle recipient instructions (email or mobile number) and a memo prefix.
- One-time parent invoices, line items, due dates, a native invoice view, and a receipt after director approval.
- Native onboarding payment steps for parents, teachers, and new school directors.
- A payment-submitted → bank-verified → paid/rejected workflow with immutable audit events.
- A no-money simulation path for every beta role.
- Role and school isolation enforced in the database, not just hidden in the app.

The beta intentionally does not include automatic bank reconciliation, Zelle credentials, recurring payments, partial payments, refunds, payment screenshots, or a direct Zelle API.

## Before starting

1. Deploy the database migration and install a build that requires it:

   ```bash
   npx supabase db push
   npx supabase test db
   npx supabase db lint --local --level error
   bash scripts/generate-schema-snapshot.sh --check
   ```

2. Create dedicated beta accounts. Do not use real family or financial data.

   | Account | Required role and state | Test purpose |
   |---|---|---|
   | HQ director | `hq_director`, full access | Enrols and reviews a new school director |
   | School A director | `school_director`, full access | Sets up Zelle, invites parents/teachers, issues/reviews invoices |
   | Parent A | `parent`, onboarding or full access | Pays an onboarding fee and a normal invoice |
   | Teacher A | `teacher`, onboarding | Completes a teacher fee if the template includes one |
   | New School B director | `school_director`, onboarding | Completes the HQ-reviewed contract/deposit step |
   | School B director | `school_director`, full access | Confirms School A data is inaccessible |

3. In the app as School A’s director, open **Workspace → Payments → Zelle settings**. Enter a non-real recipient, for example `beta-payments@example.test`, use a memo prefix such as `FFA`, turn on **Accept new Zelle invoices**, and keep **Show beta simulation guidance** enabled.

4. For a school-director onboarding template, HQ must first save active Zelle instructions for that school. This is intentional: a payment requirement cannot be published with nowhere safe to send the payer.

## Fast no-Zelle smoke test

1. As the School A director, issue a `$1.00` invoice to Parent A.
2. As Parent A, open **Workspace → Payments**, open the invoice, and verify the recipient, amount, and memo are correct.
3. Tap **I sent this payment**. Enter today’s time and `TEST-0001` as the confirmation reference.
4. Confirm the invoice becomes **Submitted**, not paid.
5. Switch back to the School A director. Open the invoice, verify that the card says to check the school’s bank experience, and use **Verify in bank & review**.
6. For this simulation, the director records the manual check and selects **Approve verified payment**.
7. Switch back to Parent A. Confirm the invoice is **Paid**, remaining balance is `$0.00`, and the in-app receipt shows the invoice number.

Expected result: no external payment is sent, no credentials are requested, and a reviewer—not the parent—controls the paid state.

## Parent onboarding with forms and a deposit

This checks that Forms and payment steps work together without using a Form as payment proof.

1. As the School A director, open **Workspace → Onboarding → Parent Onboarding → Manage template**.
2. Add the required Google Form steps as usual. Add a separate **Payment** requirement named “Enrollment deposit,” set `$1.00`, and set a due period such as seven days.
3. The editor should explain that a payment step applies once to the invited person, is member-scoped, always blocks access, and cannot accept paperwork uploads. This avoids accidentally charging every guardian connected to a child.
4. Publish the template. If Zelle instructions are inactive, publishing must fail until the director activates them in Payments.
5. Invite only the financially responsible beta parent. The normal form invitation and the native payment checklist item appear together in that parent’s setup checklist.
6. As Parent A, complete the Google Form according to the existing intake test procedure. Separately open the payment item, enter `TEST-PARENT-01`, and submit it.
7. As School A director, approve the Form response using the existing Forms review process. Then independently review and approve the payment only after the simulated bank check.
8. Confirm Parent A remains in onboarding until **both** blocking requirements are approved, then gains full access.

Try the reverse order too: approve payment first and leave the Form pending. Full access must still remain locked.

## Teacher onboarding fee

1. As School A director, select **Teacher Onboarding** and add a `$1.00` Payment step to the template.
2. Invite Teacher A. The director controls the invitation and review; HQ is not the reviewer for this flow.
3. As Teacher A, open the setup checklist, submit `TEST-TEACHER-01`, and verify the invoice is submitted rather than paid.
4. As School A director, approve it after the simulated check.
5. Confirm the teacher’s access is released only after all other blocking teacher requirements are approved.

## New school-director onboarding fee

1. As HQ, open the selected school’s **School Director Onboarding** template and add a `$1.00` Payment step.
2. Generate a director invite. School directors cannot generate or edit this template.
3. As the new School B director, complete the native payment step using `TEST-DIRECTOR-01`.
4. Confirm that School B’s director cannot review this payment, even if they have full access at School B.
5. As HQ, open the submitted onboarding payment and approve it after the simulation check.
6. Confirm the new director’s payment requirement becomes approved and that their onboarding access is refreshed. Other School B onboarding requirements, if any, must still be completed before full access is granted.

## Negative and security checks

Run these before inviting real families.

| Check | Expected result |
|---|---|
| Parent B opens Parent A’s invoice UUID | No invoice, items, recipient detail, or submission is returned. |
| Teacher A opens a parent invoice | No billing data is returned. |
| School B director opens School A billing | No School A data is returned. |
| HQ opens an ordinary parent invoice | Read-only visibility; HQ cannot change it. |
| School director attempts to approve a new-director onboarding fee | Rejected; only HQ can review that specific onboarding role. |
| Parent attempts to mark an invoice paid through the API/table | Rejected by database permissions/RPC checks. |
| Payer submits a different amount | Rejected; this beta accepts one full payment only. |
| Payer submits after an invoice is paid or voided | Rejected. |
| Director rejects a payment with no feedback | Rejected; feedback is required so the payer knows what to correct. |
| Director voids an invoice | The invoice is retained as `void` with a reason; it is not deleted. |
| Payment template has no active Zelle profile | Publishing is rejected. |
| User tries to attach a screenshot or bank document | The payment UI has no upload path; it accepts only a short reference. |

For database-level confirmation, the `supabase/tests/009_zelle_manual_billing.sql` test covers the primary RLS, reviewer, onboarding-release, and no-credential-column boundaries.

## What to review after each beta session

1. Match each approved app payment with the corresponding bank transfer or the documented simulation run.
2. Check the invoice’s amount, payer, reviewer, and decision in the app; do not change the table manually to make a test pass.
3. Confirm only the authorised payer and reviewer saw the payment record.
4. Ensure test references and notes contain no actual bank data.
5. Deactivate a school’s Zelle instructions if it pauses payments. Existing records remain readable for audit, but no new invoice should be issued.

## Moving beyond the beta

Keep the manual reviewer step until the school has a contracted, documented source of transaction confirmation. A direct Zelle integration would require a relationship with a participating financial institution, processor, or Zelle/Early Warning partner; it is not something the iOS app can safely simulate with scraped banking data or stored credentials.
