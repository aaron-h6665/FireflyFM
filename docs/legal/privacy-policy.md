# FireflyFM Privacy Policy

> **Publishing status:** Draft 2026-09-07. Replace all bracketed text and have
> qualified privacy counsel approve this document before publishing. The
> operational commitments in this policy must be true in the released product,
> contracts, support process, and vendor configuration.

**Effective date:** [Month Day, Year]  
**Version:** [YYYY-MM-DD]  
**Provider:** [Full legal name of FireflyFM provider] ("FireflyFM," "we," "us," or "our")  
**Address:** [Physical mailing address]  
**Privacy contact:** [privacy@your-domain.example]  
**Privacy Policy URL:** https://[your-domain]/privacy  
**Account-deletion URL:** https://[your-domain]/delete-account [must be a live direct page if the app sends users to the web]

## 1. Summary

FireflyFM is an adult-facing service for schools, childcare providers, and
families to coordinate authorized care, education, administration, onboarding,
communications, and payments. It is not directed to children, and children do
not create or operate FireflyFM accounts.

We handle personal information to provide and secure the Service. We do not
sell personal information or use child information or Google user data for
targeted advertising, behavioral advertising, data brokerage, or credit
decisions. This policy describes the information we handle, why, with whom we
share it, how long we keep it, and the choices available to people whose
information we handle.

## 2. Scope and roles

This policy applies to FireflyFM's app, website, support, and connected
services. A school or childcare Organization usually decides why and how child,
family, staff, and school records are used. In that situation, the Organization
is ordinarily the controller or business, and FireflyFM acts on its documented
instructions as a service provider or processor. FireflyFM may act as an
independent controller or business for its own account administration,
security, billing, legal compliance, and product operations.

The final allocation of roles depends on the Organization Agreement and
applicable law. This policy does not replace an Organization's own privacy
notice. If you are a parent, guardian, or staff member with a question about an
Organization record, please begin with the Organization unless local law says
otherwise.

## 3. Information we handle

Depending on the features used, we may handle the following categories:

| Category | Examples | Source |
|---|---|---|
| Account and profile information | Name, email address, phone number if supplied, profile photo, authentication details, role, and organization membership | You, your Organization, or an authorized invitation flow |
| Child and family information | Child and guardian names, relationship, date of birth, emergency contacts, pickup information, attendance, and authorized relationship records | Parents/guardians, school staff, or approved onboarding workflows |
| Care, health, and safety information | Allergies, dietary information, immunization status, medication requirements, physical/medical notes, care events, health checks, and related documents | Authorized adults and Organization workflows |
| Education and workflow information | Goals, activities, assignments, submissions, onboarding responses, review decisions, newsletters, events, notices, and operational records | Authorized users and Organization workflows |
| Communications and content | Messages, posts, comments, photos, videos, audio, files, attachment names/types/sizes, and report/abuse submissions | Users who submit or receive the content |
| Payment and transaction information | Invoice, line-item, payment-status, receipt, and payer-supplied short confirmation-reference information | Your Organization and the payer; any transfer occurs separately in the payer's bank or Zelle experience |
| Google Forms connection information | Connected Google account email, authorized Form titles/questions/configuration, response content, eligible Drive-upload metadata and file content, encrypted refresh credential, and connection/audit status | An authorized school director and Google APIs |
| Device and service information | Device/app version, IP address, timestamps, push-notification token and preferences, log/error/security events, and access/audit records | Your device and our systems |

We do not intentionally collect information directly from a child through a
child-operated account. Organizations and authorized adults must not use
FireflyFM to collect information they are not legally allowed to collect or
share.

## 4. How we use information

We use personal information to:

- create and secure accounts, authenticate users, assign roles, and prevent
  unauthorized access;
- provide the school and family coordination features selected by an
  Organization, including records, communications, notifications, onboarding,
  and authorized file sharing;
- process and show invoice and payment-status information;
- connect, configure, synchronize, and review Google Forms when a director
  chooses that feature;
- maintain the Service, investigate errors, prevent abuse and fraud, protect
  people and data, and enforce our agreements;
- respond to support, privacy, safety, and legal requests; and
- comply with applicable law and contractual obligations.

Where a privacy law requires a legal basis, we process information as necessary
to perform a contract, follow an Organization's documented instructions, comply
with a legal obligation, protect safety and security, pursue legitimate
interests that are not overridden by applicable rights, or obtain consent where
required. Do not rely on this generic statement in place of a counsel-approved
record of processing activities and jurisdiction-specific notice.

## 5. Google user data and Google Forms

This section applies when an authorized school director voluntarily connects a
Google account to configure existing Google Forms for FireflyFM onboarding.
This connection is optional and is not required for unrelated Service features.

### Information and permissions requested

At the time a director starts the connection, FireflyFM requests these Google
OAuth permissions only for the selected onboarding workflow:

| Google permission | What FireflyFM accesses | Why it is needed |
|---|---|---|
| OpenID and email | The connected Google account's email address | Identify and display the director-selected connection |
| Google Forms body | Form title, structure, questions, and responder link for Forms the account can access; add the FireflyFM submission-reference routing field only when the director selects the in-app repair | Let the director select a Form, configure its onboarding fields, and repair the required private routing field |
| Google Forms responses read | Responses to Forms configured in FireflyFM | Synchronize submitted onboarding responses for the configured school workflow |
| Google Drive read | Metadata for eligible file uploads and the content of eligible files attached to configured Form responses | Securely import the file into the corresponding private onboarding record |

FireflyFM does not use these permissions to read Gmail, Google Calendar, Google
Contacts, or unrelated Drive files. It does not delete or share Google Forms
or Drive files. Its only Google Forms write is adding the visible
submission-reference routing field after the director explicitly selects that
repair. The Service uses Google user data only to provide or improve the
visible, user-facing Form-configuration and onboarding features described
above.

### Storage, sharing, and safeguards

FireflyFM stores the connected account email, selected Form configuration,
imported response information, and any imported eligible attachment in the
school's private FireflyFM records. A refresh credential is encrypted before it
is stored and is available only to FireflyFM's backend services; it is never
returned to the mobile app. Access tokens are used only to call the Google APIs
needed for this feature.

Imported responses and files are available only to authorized people in the
configured Organization workflow, such as the submitting family member and
authorized school reviewers. We do not sell, rent, transfer, or use Google user
data for advertising, profiling, creditworthiness, surveillance, or any
purpose unrelated to this feature. We do not permit people to read Google user
data except as necessary to provide the configured user-facing workflow, with
the director's/Organization's authorization, for security, to comply with law,
or as otherwise permitted by the Google API Services User Data Policy.

Our use and transfer of information received from Google APIs adheres to the
[Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy),
including the Limited Use requirements.

### Disconnecting and deletion

You can revoke FireflyFM's Google access at any time in your Google Account's
third-party access settings or with the in-app **Disconnect Google** control.
The in-app control revokes FireflyFM's authorization, deletes the encrypted
refresh credential, and pauses synchronization for Forms linked to that
account. The connection record remains in a revoked state so a director can
see what was disconnected and reconnect the same account.

Revoking Google access stops future Google API access but does not automatically
delete Form responses or files already imported into the Organization's
FireflyFM records. Those records remain subject to the Organization's retention
schedule and applicable law. To request deletion of connection information or
imported information, contact
[privacy contact] or the responsible Organization. [Before publication, state
and implement the specific response time and deletion/backup schedule.]

## 6. When we disclose information

We disclose personal information only as needed for the purposes above:

- **Authorized Organization users.** We display records and Content to people
  with an authorized role and relationship, such as a child's approved guardian
  or appropriate school staff.
- **Service providers.** We use providers for cloud infrastructure, database,
  authentication, private file storage, push notifications, and Google API
  access. They may process information only to provide services
  to us and must protect it under contractual, technical, and organizational
  safeguards that provide protection consistent with this policy and applicable
  law.
- **Payment workflow.** FireflyFM may display a school's Zelle recipient
  instruction, invoice, payer-supplied short confirmation reference, and the
  school's manual review decision. We do not collect or process a bank login,
  account/routing number, card number, Zelle credential, or payment screenshot.
  The payer's bank and Zelle experience govern any transfer it processes.
- **Professional advisers and legal recipients.** We may disclose information
  to advisers under confidentiality and when we reasonably believe disclosure
  is required by law, legal process, safety, security, or to protect rights.
- **Business transfer.** If allowed by law, information may be transferred in a
  merger, financing, acquisition, reorganization, or sale of assets, subject to
  the applicable Organization Agreement and required notice or consent.

We do not sell personal information. We do not share personal information for
cross-context behavioral advertising or use it for targeted advertising.

**Before publishing, list each production subprocessor and link its privacy
notice:** [Supabase/hosting legal entity and region], [Apple Push Notification
service], [Google LLC], [error reporting/analytics provider or
state that none is used], and [any support, email, or CDN provider]. Remove
services that are not actually used.

## 7. Smart Summary and local automated processing

An authorized school director may ask FireflyFM to produce a review draft from
recent eligible child-related records. The current feature runs on the
director's device using Apple Natural Language and deterministic aggregation,
or an optional on-device Apple Foundation Model on supported devices. FireflyFM
does not send source material or the generated result to its servers or to a
cloud AI provider, and does not persist the result as a separate record.

The source set can include message text, sender role/time, attendance,
care/activity details, goals, and attachment metadata. It does not open,
transcribe, classify, or interpret image, video, audio, or file contents.
Results are not professional advice and must not be the sole basis for a
medical, safety, medication, disciplinary, developmental, educational,
eligibility, legal, or other consequential decision. See the separate On-Device
AI Notice. We will issue a new notice and obtain any required permission before
introducing cloud AI, media analysis, saved outputs, or a materially different
use of personal information.

## 8. Permissions and choices

You may control certain permissions through your device settings, including
notifications and, where used, camera, microphone, photo-library, or file
access. Declining an optional permission may prevent the related feature from
working but should not prevent unrelated features from working.

You may turn off push notifications in device settings. You may choose not to
connect Google, and you may revoke Google access through Google as described
above. You may ask your Organization to correct, update, restrict, or remove
Organization records, subject to its legal obligations and authority.

## 9. Retention, deletion, and account closure

We retain personal information only for as long as needed for the purposes in
this policy, to follow the Organization's documented instructions and
Organization Agreement, to meet legal obligations, resolve disputes, enforce
agreements, and maintain security. The applicable Organization may require us
to retain child, care, medical, financial, or educational records for a period
that continues after a user leaves or closes an account.

When an account or record is deleted, we will delete or de-identify it unless
we need to keep it for a lawful reason, another person's rights, the
Organization's record-retention obligation, fraud/security protection, or a
legal hold. Residual copies may remain in secure backups until overwritten or
deleted under our backup schedule.

**Release-required retention schedule.** Before publishing, replace this
paragraph with the approved schedule below and implement it in production:

| Data type | Live-system retention | Backup deletion period | Owner of decision |
|---|---|---|---|
| Account/profile and access logs | [approved period] | [approved period] | [FireflyFM/Organization] |
| Child, family, care, medical, and education records | [approved period] | [approved period] | [Organization, subject to law] |
| Messages, attachments, and community Content | [approved period] | [approved period] | [Organization] |
| Google OAuth credential and connection metadata | [until disconnect + approved period] | [approved period] | [FireflyFM] |
| Imported Google Form data | [approved period] | [approved period] | [Organization] |
| Payment/invoice records | [approved period] | [approved period] | [Organization/provider/law] |
| Security, audit, and support records | [approved period] | [approved period] | [FireflyFM] |

**Account deletion.** You must be able to initiate deletion of your FireflyFM
account in the app at [Profile → Privacy & Account → Delete Account] or at the
direct Account-deletion URL above. We may verify your identity and ask you to
confirm the request. [This workflow is a release blocker: do not publish this
sentence until the in-app or direct web flow, confirmation, timing, and school
ownership-transfer handling exist.] We will explain any records we cannot
delete and the reason before or when we complete the request.

## 10. Privacy rights and requests

Depending on where you live and the relationship to the information, you may
have the right to ask for access, correction, deletion, export, restriction,
objection, or withdrawal of consent. You may also have the right to complain to
a regulator. These rights are not absolute and may be limited by law, the
Organization's role, another person's privacy, or a valid retention obligation.

For child or Organization records, please first contact the responsible
Organization, which can verify your relationship and direct FireflyFM where we
act as its processor/service provider. For FireflyFM account, security, Google
connection, or other privacy requests, contact [privacy contact] with the
subject line "Privacy Request." We will verify the requester and respond within
the time required by applicable law. Authorized agents must provide proof of
authority where required.

California residents: we do not sell or share personal information as those
terms are used for cross-context behavioral advertising. [Counsel must add a
California notice-at-collection, categories/disclosures/retention table,
authorized-agent process, and non-discrimination statement if the CCPA/CPRA
applies.]

Residents of the EEA, UK, Switzerland, Canada, and other jurisdictions:
[Counsel must add the correct controller identity, legal bases, international
transfer mechanism, representative/DPO details if required, complaint rights,
and jurisdiction-specific notices.]

## 11. Children's and sensitive information

FireflyFM is not a child-directed service and does not knowingly permit
children to create accounts. The Service can hold information about children,
including care, medical, education, and family information, when an authorized
adult or Organization provides it for legitimate school or childcare purposes.

Organizations and authorized adults are responsible for giving notices and
obtaining verifiable parental/guardian consent or other authority where
required. FireflyFM will process child and sensitive information only to
provide and secure the Service, follow documented Organization instructions,
and meet legal obligations. We do not use that information for targeted
advertising.

This policy is not a substitute for a COPPA, FERPA, HIPAA, state childcare,
education, biometric, health, or other regulated-data analysis. Before launch,
counsel must determine which laws apply, whether a data-processing agreement,
BAA, student-data agreement, parent notice, consent mechanism, or regional
hosting commitment is required, and whether the implemented product satisfies
those obligations.

## 12. Security

We use reasonable administrative, technical, and organizational safeguards
designed to protect information. These include authenticated access, role- and
relationship-based authorization, private storage, restricted backend handling
of secrets, encrypted storage of Google refresh credentials, and audit/security
controls. No method of transmission or storage is perfectly secure. Please
protect your account and promptly report suspected misuse to [security contact].

[Before publishing, add the approved incident-response contact and any legally
required breach-notification commitment.]

## 13. International processing

FireflyFM and its service providers may process information in countries other
than where you live. Before transferring personal information across borders,
we will use a lawful transfer mechanism and safeguards required by applicable
law. [Counsel must identify actual hosting regions, vendors, and the applicable
transfer mechanism before publication.]

## 14. Changes to this policy

We may update this policy when our practices, Service, laws, or providers
change. We will post the revised policy with a new effective date. For a
material change, including a new use of Google user data, we will provide
prominent notice and obtain consent or renewed acknowledgement when required
before using information in the new way.

## 15. Contact us

For questions, requests, or concerns about this policy, contact:

[Full legal entity]  
[Physical mailing address]  
[Privacy contact email]  
[Data protection officer or representative, if applicable]

## Payment feedback beta

The isolated local Simulator demo uses synthetic accounts and a simulated bank
ledger; demo invoices and receipts are marked “DEMO — no money moved.” Demo
approvals affect only test memberships. The demo ledger is not installed by
production database migrations.

For real invoices, FireflyFM preserves the recipient instructions shown when an
invoice was issued, payment submissions and correction history, school review
outcomes, replacement links, explicit waiver reasons, and audit events. Older
invoices receive a migration-time snapshot of the available instructions; this
cannot reconstruct their original recipient details. A receipt records school
confirmation, not independent Zelle verification. Voiding an invoice does not
refund money or automatically waive enrollment requirements. Classroom teachers
receive only an enrollment-readiness label, not parent payment details.
