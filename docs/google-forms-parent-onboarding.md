# Google Forms onboarding and child intake

FireflyFM connects **existing** Google Forms through the school director's
Google account. The director signs in once, previews an authorized Form, then
places Forms and an optional Zelle payment in one Parent Onboarding Timeline.
FireflyFM maps standard questions and binds each selected Form to its checklist
step automatically. There is no family-invite spreadsheet and no pasted access
token, Form URL, Google account email, manual question mapping, routing-field
repair, or requirement dropdown.

Connected Google accounts are remembered for that director and school and are
shared by the parent and teacher setup views. The director chooses one account
as the default for new Forms; switching that default never moves existing Form
connections. Account management is available from the director's Profile and
from Form setup. The director is asked to sign in only to connect a different
account or reconnect revoked or expired access.

**Disconnect Google** revokes FireflyFM's Google authorization, deletes the
encrypted refresh credential, and pauses every Form linked to that account.
It does not delete the original Google Forms or any responses or files already
imported into FireflyFM. Reconnecting the same account resumes the paused Forms.

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

The OAuth client needs Forms body read/edit, Forms responses read, Drive read,
`openid`, and `email`. Schedule a POST to `sync-google-onboarding-forms` at
least every five minutes with `x-google-forms-worker-secret`; directors can
also request an immediate sync from Form setup.
[`configure_worker.sql`](../supabase/functions/sync-google-onboarding-forms/configure_worker.sql)
installs the five-minute hosted Supabase cron job using Vault secrets.

## Parent Form contract

FireflyFM recognizes these standard parent-intake labels automatically:

- Child first name
- Child last name
- Child birthdate in `YYYY-MM-DD` format
- Parent or guardian relationship
- Parent email
- FireflyFM submission reference

Only `FireflyFM submission reference` is required to safely send a Form to the
right signed-in person. It is a private routing field, not a question the
recipient needs to answer. When a director adds a Form, FireflyFM reuses that
field if it exists or adds the required short-answer field once, then records
its mapping. If Google needs renewed permission, the director sees the single
action **Reconnect Google to finish setup**. Missing child-profile questions
remain warnings rather than blocking the connection; they simply are not
written to the child record from that Form.

`FireflyFM submission reference` must be a short-answer Form question.
FireflyFM creates a one-time, two-hour reference when it launches the Form and
prefills it. It links the response to the authenticated membership without
exposing an invite secret. Keep the question in the Form; recipients should
not edit it.

Optional recognized labels are Allergies, Immunization status, Physical status,
Medication requirements, Dietary notes, and Emergency contacts. Emergency
contacts are retained as reviewed notes rather than guessed structured people.
File uploads are copied from Drive to a quarantined `school_private_files` path
and remain inaccessible in storage until the director approves the response.

The Parent Onboarding Timeline is the only ordering source for Forms and a
payment. Parents see every assigned checklist card and can work on ready Forms,
paperwork, and payment in any order while other items await review. All invited parents receive
the Form steps; the director marks one parent as the payer during invitation,
so only that parent receives the optional manual-Zelle invoice. Publishing
creates a version for people still onboarding and future invitees. Form connections, mappings, and
response boundaries are copied into a new draft rather than reinterpreting an
in-progress or accepted parent's onboarding.

## Review and access flow

`Parent Form → immutable import + quarantined files → pending child connection
→ director create/match decision → child, guardian, medical/doc records →
recipient access refresh`

Opening a Form creates a two-hour, single-use routing session. Opening is not
proof of submission: the card stays actionable as **Continue Form**, with a
separate **Check response** button. Pull-to-refresh awaits a recipient-scoped
sync and reloads the result; an empty/no-op sync is not reported as success.
Background polling and the protected scheduled worker remain available.

The app retains the launch link in device-only Keychain storage scoped to the
backend, signed-in FireflyFM user, and Form. Signing out preserves that link;
resuming validates the active membership, assigned checklist, expiry, and token hash
on the server before returning it. Expired or consumed references cannot be
reused. If an old device did not retain its link, a new session is created
without invalidating an already submitted response from the older session.
Expired cached links are discarded when next accessed. No unfinished answers
are stored in FireflyFM. Google saves drafts when the recipient is signed into
Google and Form autosave is enabled; returning requires the same Google account.

API question IDs remain hexadecimal in response mappings; launch URLs use the
corresponding decimal `entry` parameter. The September 12 migration repairs
existing routing mappings and keeps Forms visible during syncing/error states.
Duplicate Google response IDs are reprocessed idempotently when an earlier
import stopped before ingestion completed.
If Google's timestamp-filtered response lookup does not include the active
submission, the synchronizer scans the configured Form’s response pages and keeps
only a response containing the exact active one-time reference; unrelated
historic responses found by that fallback are not imported.

`approve_google_form_child_intake` is the only approval API. It locks the
import, creates or validates the selected child, verifies the guardian,
materializes mapped medical text and approved documents, completes the bound
requirement, and refreshes onboarding access atomically. Requesting changes or
rejecting preserves evidence; a later response gets a new session and request.
Recipients never see possible existing child matches.

## Operational checks

1. A director can connect Google, search authorized Forms, order them, and sync.
2. A parent or teacher can reopen **Continue Form** while delivery is pending,
   including after signing out and back in. **Check response** waits for the
   check, then shows a result or a specific failure. Ingested responses show
   “awaiting school review.” Verify draft restoration using the same Google account.
3. Quarantined uploads are invisible before approval and visible to the
   guardian/director after approval.
4. A teacher Form completes its bound requirement without a child connection.
5. A failed or interrupted ingestion is retried and the imported response
   appears in the school director's review inbox exactly once.
6. Repeated cancellation of the general onboarding dashboard does not cancel
   the pending Form-response poller.
7. After the bounded foreground poll ends, pull-to-refresh starts a fresh
   recipient-scoped sync instead of only reloading the existing status.

## September 12 diagnosis and deployment

Read-only hosted inspection found a connected Google credential with successful
sync timestamps, unconsumed sessions, and no imported responses. The active
mapping stored question ID `7181a7e3` with no prefill parameter; the signed-in
Google responder page identified its entry as `1904322531`. The old launch URL
used the hexadecimal ID literally, so it did not target the routing field.
The browser also displayed “Your progress has been restored,” confirming Google
had retained a draft in that account. This does not prove that the recipient
pressed Submit or that an earlier response exists in Google's response store.

Testing-mode OAuth refresh tokens can expire after seven days; missing production
verification is not itself evidence of a response-matching failure. Publish the
required policy pages and complete OAuth release requirements separately.

Deploy migration `20260912190000_google_form_resume_and_routing.sql`, then the
`google-forms-oauth` and `sync-google-onboarding-forms` functions with their helper
modules, then the app. The app requires schema version `20260912190000`.
Do not remove historical sessions/imports to recover this issue. Reopen through
the fixed app to obtain a valid reference; do not infer routing from email alone.
