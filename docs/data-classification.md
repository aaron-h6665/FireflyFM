# FireflyFM data classification

| Classification | Examples | Access rule |
|---|---|---|
| Public branding | App logo and bundled art | App bundle only; no user data |
| Relationship-private profile | Display names and avatars | Owner, shared school/chat, authorized HQ |
| School private | Notices, events, posts, albums | Active full-access school members |
| Workflow private | Assignments, onboarding, submissions | Recipient, submitter, reviewer, or manager |
| Child restricted | Identity, attendance, activity, documents | Guardian or authorized school staff |
| Medical highly restricted | Allergies, medication, medical notes | Guardian and explicitly authorized staff |
| Communication private | Rooms, messages, attachments, voice notes, temporary attachment previews, and user-selected in-app downloads | Active room participants only; on-device copies use file protection, are excluded from backup, and are cleared at sign-out |
| Financial highly restricted | Invoices, receipts, payment records | Subject parent and authorized finance roles |
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

## Google Form resume links

- Classification: Secret. A launch URL contains a one-time response-routing reference, not unfinished answers.
- Device storage: Keychain, when-unlocked and this-device-only; keyed by backend, FireflyFM user ID, and Form connection ID. It survives FireflyFM sign-out for that same account. Expired or malformed entries are discarded when next accessed.
- Server storage: SHA-256 reference hash and assignment snapshot; two-hour expiry and one-time consumption remain enforced. Resuming rechecks the active membership and timeline order. Another account cannot resume the reference.
- Google stores Form drafts under its own signed-in account and autosave settings. FireflyFM does not read or locally save unfinished Form answers.
- Providers/scopes: unchanged Google Forms, Google Drive and Supabase; no additional OAuth scope or subprocessor is introduced by resuming a link.
- Release review: public policy drafts describe the local cache; verify published policy versions, Google consent and App Store privacy before shipment. Signed-device Keychain persistence and a real submitted-response walkthrough remain release checks.
