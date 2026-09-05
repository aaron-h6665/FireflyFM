# FireflyFM public legal documents

These are public-facing **drafts**, prepared from the implementation that exists
in this repository on September 4, 2026. They are not legal advice and are not
ready to publish unchanged. They deliberately do not promise a retention,
deletion, controller/processor, or dispute-resolution practice that FireflyFM
has not yet approved and implemented.

## Documents

- [Terms of Service](terms-of-service.md)
- [Privacy Policy](privacy-policy.md)
- [Release and publishing checklist](release-and-publishing-checklist.md)

## Before publishing

1. Replace every `[bracketed placeholder]`, including the legal entity,
   physical address, privacy contact, public URLs, governing law, and the
   organization agreement reference.
2. Have privacy counsel confirm the school/FireflyFM controller and processor
   roles for every jurisdiction in which the app will be offered. In particular,
   obtain the agreements and verified-parent/guardian authorization process
   required for the child, medical, and education records the product handles.
3. Finalize, document, and implement the retention schedule, account-deletion
   flow, school-offboarding/export process, legal-hold process, and backup
   deletion period. Do not turn the bracketed target statements into promises
   until they are operationally true.
4. Publish stable, public HTTPS pages at the final URLs. The privacy-policy URL
   must be included both in App Store Connect and the Google OAuth consent
   screen; the Terms URL should also be listed in the OAuth consent screen.
   Do not submit placeholder, repository, login-gated, or temporary pages.
5. Make the text shown in **Legal & Privacy** and during sign-up match the
   published version exactly. The app currently has an older, shorter embedded
   version in `FireflyFM/Core/Features/Legal/LegalContent.swift`; update its
   version, text, acceptance/audit record, and public links as one release.
6. Complete the product requirements in the release checklist. A policy alone
   does not make an App Store, Google OAuth, COPPA, FERPA, HIPAA, GDPR, state
   privacy law, or payment-provider requirement satisfied.

## Source facts used for this draft

- FireflyFM is an adult-facing school and family coordination service. Children
  do not create or operate FireflyFM accounts.
- The app handles accounts and school memberships; child and guardian records;
  attendance, care, health/medical, onboarding, assignment, and goal records;
  communications; photos, videos, audio, files; notifications; and audit and
  security information.
- Private records are protected by role- and relationship-based access rules.
- A school director may connect a Google account to select existing Google
  Forms for onboarding. The integration requests Forms body read, Forms
  responses read, Drive read, OpenID, and email. Refresh credentials are
  encrypted and backend-only; form responses and eligible Drive uploads are
  copied into FireflyFM for the configured onboarding workflow.
- Payments use a connected school's Stripe-hosted flow. FireflyFM does not
  collect card or bank credentials in the app.
- The current Smart Summary feature runs on the authorized director's device
  using local Apple frameworks; it neither sends inputs/results to a cloud AI
  provider nor analyzes attachment contents.

These facts must be re-checked whenever a feature, SDK, analytics provider,
subprocessor, permission, data category, retention practice, or OAuth scope
changes.
