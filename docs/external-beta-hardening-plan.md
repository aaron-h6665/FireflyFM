# FireflyFM External-Beta Hardening Plan

## Summary

FireflyFM has a solid privacy-oriented backend foundation: reproducible migrations, RLS documentation, database CI, schema compatibility checks, and role-aware UI smoke tests. The current simulator build is warning-free; all 17 unit tests and available launch/role tests passed, while two data-dependent UI tests skipped. Local pgTAP verification remains pending because Docker was unavailable.

The main risks are production-environment coupling, an iOS 26.5-only target, limited automated coverage for a 64-table backend, large singleton-driven features, missing release privacy/account-deletion support, incomplete push delivery, and no production-safe diagnostics.

Use a phased roadmap targeting external beta and iOS 17+.

## Implementation Changes

### Phase 1 — Release and data safety

- Replace hard-coded Supabase configuration with typed `AppConfiguration` values supplied through Development, Staging, and Production `.xcconfig` files and shared schemes. Give non-production builds distinct bundle IDs and visual environment labels; prevent Debug builds from using production without an explicit override.
- Lower the deployment target to iOS 17.0, resolve availability issues, and test both iOS 17 and the current SDK.
- Provision a separate hosted staging Supabase project. Keep local development, staging tests, and production data strictly separated.
- Add `PrivacyInfo.xcprivacy`, declaring collected data from the existing classification document and `UserDefaults` reason `CA92.1`; validate the archive privacy report.
- Add a “Privacy & Account” screen containing privacy-policy, support, data-export/request, and account-deletion actions.
- Implement account deletion as an authenticated server-owned request workflow. The client submits only for the current user; a service-role worker performs deletion or approved anonymization, reports status, and never exposes administrative credentials. Require an approved retention/ownership-transfer policy before enabling it.
- Complete APNs delivery before calling the beta communication-ready: register and revoke device tokens, deliver queued notifications through a Supabase Edge Function, handle retries and invalid tokens, and route chat/assignment/notification payloads to the correct screen.
- Replace `print` diagnostics with privacy-redacted `Logger` categories and signposts. Never log message bodies, invite tokens, signed URLs, medical details, child data, or credentials.
- Hide payments and prevent payment onboarding requirements while the payment integration remains disabled.
- Remove unused Core Data boilerplate, the saved script backup, unused package products, and other template residue.
- Add a root README covering architecture, schemes, local Supabase setup, staging configuration, verification commands, and production-safety rules.

### Phase 2 — Testable feature architecture

- Introduce `AppDependencies` and protocols for authentication, schools, assignments, onboarding, children, community, chat, notifications, and media. Supply live implementations at the app root and fakes in tests.
- Split `SchoolWorkflowService` by domain and move direct network calls out of SwiftUI views into `@MainActor @Observable` feature models with explicit loading, loaded, empty, and error states.
- Break the largest files into cohesive feature screens and reusable components while preserving current navigation and backend RPC contracts.
- Divide the shared model file by domain and centralize date decoding, upload validation, pagination, error translation, and signed-media handling.
- Replace swallowed `try?` failures in user-facing loads with cancellation-aware error states and retry actions.
- Audit package linkage and retain only directly required products. Enable strict concurrency checking, fix findings, then migrate the app target to Swift 6 after feature boundaries are stable.

### Phase 3 — UX and operational quality

- Create an English String Catalog and route all user-facing copy through localization keys.
- Complete VoiceOver, Dynamic Type, contrast, reduced-motion, keyboard, and minimum-target reviews for every role and critical journey.
- Consolidate repeated cards, buttons, loading states, empty states, and destructive confirmations into the existing semantic design system.
- Add Apple-first operational diagnostics using `Logger`, signposts, MetricKit, and TestFlight diagnostics behind a `DiagnosticsReporting` interface; introduce no third-party telemetry until its privacy impact is reviewed.
- Instrument launch, authentication, school switching, inbox loading, chat opening, and assignment loading, then address measured regressions rather than speculative optimization.

## Interfaces and Backend Additions

- Add `AppEnvironment`, `AppConfiguration`, `FeatureAvailability`, and `AppDependencies`.
- Add repository protocols with async, typed results; live implementations continue using the existing Supabase RPC and table contracts.
- Add authenticated account-deletion request/status endpoints and server-only processing.
- Extend device-token registration with APNs environment and token lifecycle operations; keep service-role and APNs credentials server-side.
- Preserve existing RPC names and migration history unless a tested compatibility migration is explicitly introduced.

## Test and Acceptance Plan

- Require warning-free Development, Staging, and Production builds, plus a successful unsigned Release archive and privacy-manifest validation.
- Add configuration tests proving each scheme uses the expected bundle ID and backend; CI must reject production endpoints in Development.
- Add feature-model tests for authentication, cancellation, school switching, onboarding gates, assignments, chat updates, uploads, notifications, and account-deletion states.
- Replace data-dependent UI skips with deterministic launch fixtures. Gate sign-in/onboarding, all four role dashboards, school switching, assignment feedback, chat, notification routing, and account deletion.
- Promote the manual role, onboarding, and assignment SQL checks into pgTAP. Cover anonymous, cross-school, cross-child, nonparticipant, onboarding-only, reviewer, storage, deletion-request, and notification-token boundaries.
- Retain the existing baseline-to-head upgrade, clean reset, schema snapshot, lint, and drift checks.
- Before beta, require zero skipped gating tests, staging role-matrix sign-off, APNs delivery verification, account-deletion rehearsal, accessibility review, backup/restore rehearsal, and the existing release gates.

## Assumptions

- Defaults selected: external-beta readiness first, iOS 17+, and a phased roadmap.
- The current hosted Supabase project remains Production; a separate Staging project will be provisioned.
- Payments remain outside beta scope.
- Legal/product ownership supplies the retention and school-ownership-transfer rules before account deletion is enabled.
- Production migrations continue following the backup, parity, and review process already documented in the repository.
