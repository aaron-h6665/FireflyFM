# FireflyFM legal release and publishing checklist

This checklist turns the Terms and Privacy Policy drafts into a release-ready
legal surface. It is a product and operational checklist, not legal advice.

## Public pages and in-app parity

- [ ] Choose FireflyFM's legal entity, physical mailing address, privacy/legal
  contact, security contact, support contact, governing law, and any required
  data-protection officer or representative.
- [ ] Replace every placeholder in both public documents and have counsel
  approve the final versions.
- [ ] Host the Terms and Privacy Policy at stable, public HTTPS URLs on a
  verified domain. Pages must be readable without an account and must not be a
  draft, a repository file, or a temporary URL.
- [ ] Put the exact Privacy Policy URL in App Store Connect and make it easily
  available inside the app. Put the Privacy Policy and Terms URLs in the Google
  OAuth consent-screen configuration and on the application home page.
- [ ] Update LegalContent.swift, sign-up links, Legal & Privacy, and the
  accepted document versions so users see the same final text as the public
  pages. Record an immutable, server-owned acceptance/audit event rather than
  relying only on client-editable user metadata.
- [ ] Re-present material policy changes and record the version, timestamp,
  actor, and acknowledgement/consent when required.

## Apple App Store

- [ ] Complete App Store Connect's App Privacy answers from a production data
  inventory. At minimum re-evaluate contact information, identifiers, health
  and care information, financial information, user content, photos/videos,
  audio, other child data, diagnostics, and any tracking. Mark collection,
  linkage, tracking, purposes, and third-party SDK behavior accurately.
- [ ] Add PrivacyInfo.xcprivacy and ensure it reflects the app and every
  included SDK. Verify the archive's privacy report.
- [ ] Confirm every iOS permission prompt accurately explains its actual,
  narrowly scoped use. Do not request an unrelated permission as a condition
  of using other features.
- [ ] Build an easy-to-find in-app account-deletion initiation flow. It must
  support deleting the account and associated personal data, not merely
  deactivation. If the user finishes on the web, link directly to that page;
  show expected completion timing and any lawful retention exceptions.
- [ ] Give users an in-app way to request privacy help, data export, and
  account deletion; complete the operational workflow behind it.
- [ ] Keep the app adult-facing in its marketing and metadata. Do not select
  the Kids Category unless the entire app, advertising/analytics posture,
  external links, and parental-gate design comply with its rules.
- [ ] Because FireflyFM has messages and shared media, implement and test
  report, moderation, timely response, blocking/restriction, and published
  contact mechanisms appropriate to its user-generated content.
- [ ] Provide complete reviewer access, a valid review account or approved
  demo mode, live backend access, and accurate review notes.

## Google OAuth and Google Forms

- [ ] Verify the OAuth consent screen lists the exact, public Privacy Policy
  and Terms URLs, verified authorized domain, accurate app name/logo/support
  email, and production/development contact details.
- [ ] Request only the exact scopes needed by released functionality:
  Forms body (to read Forms and add only the FireflyFM submission-reference
  routing field when a director selects a Form), Forms responses read,
  Drive read, OpenID, and email. Remove
  a scope before release if the feature no longer needs it; do not request
  future-use scopes.
- [ ] Keep the system browser authorization flow; do not use an embedded web
  view. Explain each scope immediately before the director starts OAuth.
- [ ] Configure the exact authorized iOS client, bundle ID, redirect scheme,
  and consent-screen authorized domain. Do not ship secrets in the app.
- [x] Implement a visible **Disconnect Google** control. It stops future
  syncs, invalidates/deletes the encrypted refresh credential, shows what
  happens to selected Forms and already imported records, and creates an audit
  event.
- [ ] Manually verify two-account selection, relaunch persistence, disconnect,
  paused-Form behavior, reconnection, and resumed synchronization in staging.
- [ ] Submit one parent Form and one teacher Form in staging. Verify the
  recipient immediately sees **Checking response**, cannot launch a duplicate
  session, advances to **Awaiting review**, and the response appears exactly
  once in the school director inbox. Interrupt ingestion once and verify the
  next sync recovers the existing raw import.
- [ ] Test Google revocation from Google Account settings, refresh-token
  failure, reconnect, director transfer, school deletion, account deletion,
  and Organization offboarding.
- [ ] Ensure Google API data is used only for the visible Forms/onboarding
  feature; never sell it, use it for advertising/profiling/credit decisions,
  or disclose it except as permitted by Google's Limited Use policy.
- [ ] Complete Google OAuth verification/brand verification and any sensitive
  or restricted-scope security-assessment requirements that apply before
  public availability. Keep a current screen recording and explanation of each
  scope's in-product use for the verification submission.

## Data governance and service providers

- [ ] Maintain a versioned data inventory that maps each feature to data
  categories, sources, purposes, roles, access rules, storage locations,
  retention, deletion, and subprocessors.
- [ ] Execute required data-processing, student-data, confidentiality, and
  vendor agreements. Establish who is controller/business and who is
  processor/service provider for each data flow.
- [ ] Finalize a written retention schedule covering live data, private files,
  logs, backups, Google credentials, imports, payments, exports, legal holds,
  school closure, account closure, and restoration.
- [ ] Test deletion against the schedule, including files, tables, queues,
  search indexes, notifications, backups, OAuth credentials, and vendor-held
  data. Make deletion status and retention exceptions understandable to users.
- [ ] Test chat attachment preview/download lifecycle on a locked physical
  device: temporary cleanup, complete file protection, backup exclusion,
  individual removal, sign-out cleanup, revoked-room access, and exported-copy
  messaging.
- [ ] Maintain an approved subprocessor list and re-review it before adding an
  SDK, analytics provider, support tool, payment provider, AI provider, or new
  regional hosting location.
- [ ] Review and document incident response, access logging, security testing,
  staff access, export handling, data minimization, and breach notice duties.

## Child, sensitive, payments, and AI data

- [ ] Have counsel determine the actual applicability of COPPA, FERPA, HIPAA,
  state childcare/education laws, state consumer-privacy laws, GDPR/UK GDPR,
  PIPEDA/provincial law, biometric laws, and cross-border transfer rules. Do
  not claim compliance with a law merely because the policy names it.
- [ ] Establish and test the parent/guardian notice, consent, authority,
  correction, access, and deletion process appropriate to each jurisdiction.
- [ ] Confirm the exact role-based access matrix for child, medical,
  educational, financial, and communications data in a production-like
  environment; test cross-school, cross-child, staff, guardian, and revoked
  membership boundaries.
- [ ] Confirm school Zelle recipient instructions, manual bank-verification
  process, retention period, audit access, and exact invoice/confirmation
  metadata before enabling payments. Do not collect bank or Zelle credentials.
- [ ] Re-review the AI disclosure before enabling a cloud AI provider, media
  transcription/OCR/analysis, saved summaries, automated recommendations,
  expanded access, model training/evaluation, or prompt/result logging.

## Every task/change gate

Before closing any task that changes data handling, identity, permissions,
providers, or a user-facing workflow:

1. Update the data inventory and these public legal documents if the change
   affects collection, use, sharing, retention, deletion, security, rights,
   disclosures, or a third-party integration.
2. Re-check App Store privacy labels, iOS permission strings/privacy manifest,
   Google OAuth scopes/consent screen, and the subprocessor list as applicable.
3. Decide whether the change requires a new consent, acknowledgement, contract
   amendment, vendor review, security assessment, or counsel review before it
   is released.
4. Update in-app legal copy, public pages, version/acceptance records, support
   runbooks, and tests together. Do not ship a behavior that the policy does
   not accurately describe.

## Zelle feedback beta release boundary

- [ ] Validate recipient ownership, bank business eligibility, and review procedures before a real-money pilot.
- [ ] Confirm Release builds contain no Simulator payment controls and production migrations install no demo ledger or demo transfer RPC.
- [ ] Keep recipient snapshots, review history, replacement/waiver audit data, and retention disclosures aligned with financial-information inventory.
- [ ] Run the onboarding payment role matrix end to end: parent and teacher payer to school-director review, plus school-director payer to HQ review. Verify rejection feedback, corrected resubmission, receipt wording, notification routing, access release, and cross-role/cross-school denial.
- [ ] Review and publish the 2026-09-10-active-onboarding-updates-v1 terms/privacy changes before production release; verify that matching completed work and submitted payment history survive an active template update.
- [ ] Reconcile legacy invoices before a pilot: their recipient snapshot was backfilled from migration-time settings, not historical bank evidence.
