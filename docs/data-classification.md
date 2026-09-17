# FireflyFM data classification

| Classification | Examples | Access rule |
|---|---|---|
| Public branding | App logo and bundled art | App bundle only; no user data |
| Relationship-private profile | Display names and avatars | Owner, shared school/chat, authorized HQ |
| School private | Notices, events, posts, albums | Active full-access school members |
| Learning workflow private | Training and curriculum assignments, attempts, attachments, feedback, and reviews | Assigned staff member, submitter, or authorized learning reviewer |
| Paperwork private | Google Form responses, document requests/uploads, acknowledgements, child-linked compliance records, attachments, feedback, and reviews | Recipient, linked guardian, submitter, or authorized Paperwork reviewer |
| Onboarding private | Requirement plan, sequence, completion state, waiver, and access-release decisions | Onboarding recipient or authorized onboarding manager |
| Child restricted | Identity, attendance, activity, documents | Guardian or authorized school staff |
| Attendance location signal | Opaque school QR token, code lifecycle, and scan-source audit metadata | Authorized directors manage codes; verified guardians may use an active code only for linked children |
| Medical highly restricted | Allergies, medication, medical notes | Guardian and explicitly authorized staff |
| Communication private | Rooms, messages, attachments, voice notes, temporary video-preparation and attachment-preview copies, and user-selected in-app downloads | Active room participants only; video-preparation copies are removed after sending, failure, or cancellation; kept on-device copies use file protection, are excluded from backup, and are cleared at sign-out |
| Financial highly restricted | Invoices, receipts, payment records | Named payer and authorized finance roles |
| Secret | Invite tokens, service keys, signed URLs | Hashed where possible; never logged |

## Required controls

- Every private table and bucket uses deny-by-default RLS.
- School identity is included in private object paths and authorization checks.
- Signed URLs expire after five minutes and are cached only in memory.
- Attachment previews use temporary local files that are deleted on close.
  User-selected in-app downloads use complete file protection, are excluded
  from device backup, support individual removal, and are cleared at sign-out.
- Privacy tests cover anonymous, cross-school, nonparticipant, and same-school
  but unauthorized access.
- Reusable attendance QR codes contain no school, child, or user identity. A
  scan is an onsite signal rather than guaranteed physical-presence proof;
  authorization comes from the authenticated verified guardian relationship.
  Camera frames stay on device, and rotation invalidates prior printed copies.
- Assignments contain only training and curriculum work. Legacy non-learning
  assignment rows are retained as read-only audit history, archived, and
  excluded from Assignment projections; their active and completed records
  appear in Paperwork instead.

## Google Form resume links

- Classification: Secret. A launch URL contains a one-time response-routing reference, not unfinished answers.
- Device storage: Keychain, when-unlocked and this-device-only; keyed by backend, FireflyFM user ID, and Form connection ID. It survives FireflyFM sign-out for that same account. Expired or malformed entries are discarded when next accessed.
- Server storage: SHA-256 reference hash and Paperwork requirement snapshot; two-hour expiry and one-time consumption remain enforced. Resuming rechecks the active membership and assigned onboarding plan. Another account cannot resume the reference.
- Google stores Form drafts under its own signed-in account and autosave settings. FireflyFM does not read or locally save unfinished Form answers.
- Providers/scopes: unchanged Google Forms, Google Drive and Supabase; no additional OAuth scope or subprocessor is introduced by resuming a link.
- Release review: public policy drafts describe the local cache; verify published policy versions, Google consent and App Store privacy before shipment. Signed-device Keychain persistence and a real submitted-response walkthrough remain release checks.

## Google Drive assignment picker

- Classification: Secret for PKCE/access-token operation data; Learning workflow private for selected file metadata, content, and imported snapshots.
- Scope: the non-sensitive, per-file `drive.file` scope in a separate OAuth request. It is never combined with the director-owned Forms/Drive-read connection.
- Server storage: state is hashed; PKCE verifier and the short-lived access token are AES-GCM encrypted in a service-role-only operation. No refresh token is retained. Selected-file manifests and token material are cleared on finish or expiry.
- Device storage: selected bytes enter the existing owner-scoped assignment draft directory, keep the 10 MB per-file limit, and follow existing draft cleanup and private upload behavior.
- Format behavior: ordinary files are copied unchanged; Docs, Sheets, and Slides become DOCX, XLSX, and PPTX snapshots. Drive links are not stored or exposed.
- Authorization: the operation is bound to the signed-in user, school, and creator/editor/submission context. Authorization is rechecked before every download.
- Release review: update Google OAuth consent, App Store Files and Documents answers, public/in-app policies, accepted versions, and signed-device Google Picker verification before shipment.

### Workspace beta additions

- Answer/file correction notes: private submission data, visible to the authorized recipient and reviewer; linked to immutable submission attempts.
- Published policy snapshots: private paperwork evidence retained with the acknowledgement; no invented backfill for legacy records.
- HQ Zelle profile: restricted HQ receiving configuration; immutable recipient snapshots are visible on authorized invoices.
- Receiving-account reference claims: restricted fraud/duplicate-reference control; no bank credentials or automatic verification.
- No new provider or Google OAuth scope. Existing retention/deletion policies apply; hosted rollout remains pending validation.

### Required-document upload reservations

- Classification: private submission metadata (school, requirement, submitter, submission/attempt IDs, filename/path, expiry and finalization time); service-only reservation records.
- New uploads use a one-hour reservation and immutable object path. Finalization checks the uploaded object and caller's current authority. Shared requirement access does not authorize another submitter's file.
- Existing object paths require an unambiguous submission association. Orphaned/ambiguous objects remain stored for service-only reconciliation; reservation expiry is not automatic data deletion.
- No new provider, OAuth scope, tracking, purpose, or App Store data category. Existing retention and deletion release gates apply. See `docs/adversarial-beta-hardening.md` for implementation and deployment limits.
