# Google Forms onboarding and child intake

FireflyFM connects **existing** Google Forms through the school director's
Google account. The director signs in from the app, selects an authorized
Form, maps its questions, and binds it to an onboarding requirement. There is
no family-invite spreadsheet and no pasted access token, Form URL, or Google
account email.

For a parent, the first required Form collects child identity and records. A
completed Form creates a private pending child-connection request. A director
must approve that request to create or match the child and verify guardian
access. Teachers use the same Form flow but never create or match a child.

## Deployment configuration

Set these Supabase Edge Function secrets before deploying:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `GOOGLE_FORMS_OAUTH_CLIENT_ID`
- `GOOGLE_FORMS_OAUTH_CLIENT_SECRET` only when the Google OAuth client has one
- `GOOGLE_FORMS_OAUTH_REDIRECT_URI`, exactly
  `firefly.fireflyfm:/oauth2redirect`
- `GOOGLE_FORMS_TOKEN_ENCRYPTION_KEY`, a base64url random 32-byte AES key
- `GOOGLE_FORMS_WORKER_SECRET`, only for the scheduled synchronizer

Deploy `google-forms-oauth` and `sync-google-onboarding-forms`. OAuth requires
an authenticated director. The synchronizer authenticates the requesting
director or the worker secret, refreshes from encrypted backend-only
credentials, and never returns a Google token to the app.

Create the Google OAuth client as an **iOS** client with bundle ID
`Firefly.FireflyFM`; do not use a Web application client for this flow. The
redirect URI must be exactly `firefly.fireflyfm:/oauth2redirect` (one slash
after the colon, not `://`). FireflyFM registers that private URL scheme in
the iOS app. Use the system authorization browser that FireflyFM opens; do not
embed Google's sign-in page in a web view. Add the director's account as a test
user on the OAuth consent screen until the app is published/verified.

The OAuth client needs Forms body read, Forms responses read, Drive read,
`openid`, and `email`. Schedule a POST to `sync-google-onboarding-forms` at
least every five minutes with `x-google-forms-worker-secret`; directors can
also request an immediate sync from Form setup.
[`configure_worker.sql`](../supabase/functions/sync-google-onboarding-forms/configure_worker.sql)
installs the five-minute hosted Supabase cron job using Vault secrets.

## Parent Form contract

Map these active fields for every parent-intake Form:

- `child_first_name`
- `child_last_name`
- `child_birthdate` in `YYYY-MM-DD` format
- `relationship`
- `respondent_email`
- `submission_reference`

`submission_reference` must be a short-answer Form question. FireflyFM creates
a one-time, two-hour reference when it launches the Form and prefills it. It
links the response to the authenticated membership without exposing an invite
secret. Keep the question in the Form; recipients should not edit it.

Optional mappings are `allergies`, `immunization_status`, `physical_status`,
`medicine_requirements`, `dietary_notes`, and `emergency_contacts`. Emergency
contacts are retained as reviewed notes rather than guessed structured people.
File uploads are copied from Drive to a quarantined `school_private_files` path
and remain inaccessible in storage until the director approves the response.

Every required Form must be bound to an onboarding requirement. A snapshot of
the connection and mappings is captured when a recipient launches the Form, so
a replacement does not reinterpret an in-progress response.

## Review and access flow

`Parent Form → immutable import + quarantined files → pending child connection
→ director create/match decision → child, guardian, medical/doc records →
recipient access refresh`

`approve_google_form_child_intake` is the only approval API. It locks the
import, creates or validates the selected child, verifies the guardian,
materializes mapped medical text and approved documents, completes the bound
requirement, and refreshes onboarding access atomically. Requesting changes or
rejecting preserves evidence; a later response gets a new session and request.
Recipients never see possible existing child matches.

## Operational checks

1. A director can connect Google, list authorized Forms, map fields, and sync.
2. A parent sees only their next Form and then “awaiting school review.”
3. Quarantined uploads are invisible before approval and visible to the
   guardian/director after approval.
4. A teacher Form completes its bound requirement without a child connection.
