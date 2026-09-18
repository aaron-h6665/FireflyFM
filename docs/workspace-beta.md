# Workspace beta implementation and release

The beta uses the existing FireflyTheme tokens and adds compact grouped lists.
Only an approved school director receives Mine / Manage. Teachers and parents
complete their own work; HQ sees management work. Onboarding keeps management
locked and routes into the same Paperwork and Payments details.

## Configuration

- Debug enables the beta for development.
- Archive the shared **FireflyFM Beta** scheme. Its **Beta** configuration adds
  `FIREFLY_WORKSPACE_BETA` without enabling DEBUG or the payment simulator.
- The ordinary Release configuration retains the existing workspace entry UI.
- Beta requires schema version **20260918110000**. The app shows the existing
  compatibility gate when the backend is older instead of silently falling back
  to incomplete workflows.

## Backend contracts

Apply `20260918090000_workspace_beta.sql`,
`20260918091000_hq_zelle_recipient.sql`,
`20260918100000_private_document_reservations.sql`, and
`20260918110000_workspace_notifications.sql` on the intended staging project.

- `fetch_my_paperwork_items_v2` preserves recipient/child identities, correlates
  Google responses with their requirement snapshot, and places completed native
  obligations in Done. Existing v1 remains available.
- Scoped recipient/payer label projections avoid broad client directory reads.
- `fetch_unmatched_paperwork_responses` preserves a manager's exception inbox.
- Google and native correction-review RPCs write target-specific notes and the
  decision atomically. RLS restricts correction visibility to the source record.
- Google submission history is scoped to a requirement instance and its evidence.
- New policy acknowledgements include the published text/material references.
  Legacy evidence is not reconstructed.
- `hq_zelle_profile` is HQ-only receiving configuration. New director invoices
  snapshot it; parent/teacher invoices snapshot their school instructions.
  Previously issued invoices are never redirected. Use the existing audited
  void/replacement path where an old invoice must be corrected.
- Duplicate references are checked against the actual receiving account across
  schools. There is no bank API, automatic verification, or TestFlight simulation.
- Paperwork assignment, submission, review, and Google Form response notifications
  are deduplicated and route to the exact request, submission, response, or invoice.

Google Forms still open externally and import answers and eligible Drive files.
Native paperwork uses Files; the separate assignment Drive-picker work is not
extended to Paperwork. No additional OAuth scope is introduced.

## Release checks

1. Select the staging Supabase project explicitly; do not assume the application's
   currently configured hosted project is staging.
2. Verify all four migrations and returned schema version `20260918110000` on that project.
3. Configure real HQ receiving details through HQ Payments → Receiving settings.
4. Exercise the four role/onboarding journeys on staging: direct notifications,
   corrections/resubmission, document access, director Mine/Manage, Zelle receipt
   review, and school isolation. Check large text, VoiceOver and both appearances.
5. Publish the matching legal disclosures and verify acceptance version
   `2026-09-17-workspace-beta-v1`, App Store privacy information and Google consent.
6. Archive the Beta scheme, sign with the existing app distribution setup, upload
   through App Store Connect, and complete internal/external TestFlight processing.

Local test results do not establish hosted deployment, bank verification, signed
archive creation, or TestFlight distribution. No migration has been pushed as
part of the local validation; SQL suites run inside rollback-only transactions.

## Local validation

- Complete Swift unit target: 89 tests passed on iPhone 17 Pro Simulator.
- Complete SQL suite: 571 assertions passed across 19 files, including 32 new beta assertions. Migrations and tests were rolled back.
- Debug app build and dedicated non-DEBUG Beta configuration build passed.
- Project/scheme syntax, canonical schema parity, and diff whitespace checks passed.
- Authenticated staging journeys, visual/accessibility device QA, signed distribution archive, and TestFlight upload remain release gates.

## Suggested commit

`Add role-scoped workspace beta and HQ payment routing`

Several shared files also contain earlier staged or unstaged work. Stage new beta
files directly and review the shared-file hunks before including them:

```sh
git add 'FireflyFM.xcodeproj/xcshareddata/xcschemes/FireflyFM Beta.xcscheme' FireflyFM/Core/Views/Shared/WorkspaceBetaComponents.swift FireflyFM/Core/Features/Paperwork/PaperworkBetaView.swift FireflyFM/Core/Features/Paperwork/PaperworkCorrections.swift FireflyFM/Core/Features/Paperwork/PaperworkNotificationDestination.swift FireflyFM/Core/Features/Payments/PaymentsBetaView.swift FireflyFM/Core/Features/Payments/HQZelleSettingsView.swift FireflyFMTests/WorkspaceBetaTests.swift supabase/migrations/20260918090000_workspace_beta.sql supabase/migrations/20260918091000_hq_zelle_recipient.sql supabase/tests/019_workspace_beta.sql docs/workspace-beta.md
git add -p FireflyFM.xcodeproj/project.pbxproj FireflyFM/Core/Utils/AppConfiguration.swift FireflyFM/Core/Manager/AppSessionManager.swift FireflyFM/Core/Model/Access/AppAccessContext.swift FireflyFM/Core/Model/SchoolModels.swift FireflyFM/Core/Views/AppShell/RoleWorkspaceViews.swift FireflyFM/Core/Views/Assignments/AssignmentsView.swift FireflyFM/Core/Features/Paperwork/PaperworkWorkspaceView.swift FireflyFM/Core/Features/Onboarding/OnboardingViews.swift FireflyFM/Core/Features/Onboarding/GoogleFormReviewView.swift FireflyFM/Core/Features/Notifications/NotificationDestinationResolver.swift FireflyFM/Core/Features/Notifications/NotificationsView.swift FireflyFM/Core/Features/Payments/PaymentsView.swift FireflyFM/Core/Features/Payments/PaymentsModel.swift FireflyFM/Core/Features/Payments/PaymentInvoiceComposerView.swift FireflyFM/Core/Features/Payments/PaymentInvoiceDetailView.swift FireflyFM/Core/Features/HQ/HQSchoolsView.swift FireflyFM/Core/Features/Legal/LegalContent.swift FireflyFMTests/FireflyFMTests.swift supabase_schema.sql supabase/tests/001_schema_onboarding_and_invites.sql supabase/tests/005_school_level_child_operations.sql supabase/tests/007_chat_first_foundation.sql supabase/tests/008_assignment_workflow_improvements.sql supabase/tests/009_zelle_manual_billing.sql supabase/tests/010_zelle_feedback_beta.sql supabase/tests/018_guardian_qr_attendance.sql docs/data-classification.md docs/legal/privacy-policy.md docs/legal/terms-of-service.md docs/legal/release-and-publishing-checklist.md
```

Do not run a commit until the staged diff contains only the intended change set;
these commands do not unstage any existing work.
