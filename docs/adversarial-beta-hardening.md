# Adversarial beta hardening

## Implementation and compatibility

Migration `20260918100000_private_document_reservations.sql` introduces one-hour,
server-authorized upload reservations for legacy required documents. The app reserves
an exact path, uploads without overwrite, then finalizes only after the object exists.
Finalization rechecks assignment and active membership. Direct client table mutations
and storage overwrites/deletes are denied; review RPCs retain review authority.

Shared requirement membership does not grant access to another recipient's evidence.
Existing files remain readable only when an unambiguous submission record binds their
exact path to the correct school and requirement. No objects are deleted or moved.
The service-only `document_upload_reconciliation` view reports orphaned, ambiguous,
and incorrectly scoped paths. Operators must resolve these against authoritative records,
not guess ownership. Pending reservations expire after one hour; expiry prevents use
but does not automatically delete the reservation or uploaded bytes.

Both app configurations require schema version `20260918110000`. Deploy the document
reservation and workspace notification migrations before distributing this client.
Older clients cannot submit documents without a
reservation and receive an update-required error. Do not restore the insecure path-only
contract as a rollback. Previously issued signed links may remain usable until expiry;
this change does not claim to revoke already-issued URLs or downloaded copies.

Paperwork and beta payments publish independent sections scoped to user, membership,
and school. Failed sections have targeted retries. Same-scope refresh failures preserve
available content; scope changes hide old content immediately. Superseded results and
errors cannot replace newer state. A successful empty response is distinct from failure.

## Beta limitations and disclosure review

Guardian QR attendance remains unchanged. A saved school code can be reused remotely
by an otherwise authorized guardian; it does not establish physical presence. Rotating
codes, presence verification, and staff confirmation remain product decisions for later.

The upload reservation contains existing submission identifiers, filename/path, owner,
expiry, and finalization time. It adds no provider, OAuth scope, content category, tracking,
or new purpose. Existing child/private-document and financial-data classifications apply.
Terms, public/in-app Privacy, accepted versions, App Store privacy, Google consent, and
subprocessor inventory were reviewed: this hardening does not require a new acceptance
version or scope. Do not publish it as a hosted safeguard before deployment verification.
Account deletion, retention operations (including abandoned uploads), and final disclosure
publication remain release gates; this change does not implement those operations.

## Verification

See the test results recorded below. Local schema tests are separate from hosted rollout.
The isolated database contains a schema-only copy of the local Supabase database, with
beta and hardening migrations applied and transaction-rolled-back synthetic fixtures.
The scheduler extension is omitted because pg_cron is configured for the original database;
its scheduling assertion is explicitly skipped, not counted as passing.

Before distribution, check the hosted migration ledger and schema version, verify the
reservation/finalization RPCs and exact-path storage denial using staging accounts, inspect
the reconciliation view, and confirm deployed Google Drive function version and cron health.
No hosted migration, function deployment, or production data mutation is part of this run.

### Local results (September 17, 2026)

- Fresh application/test build succeeded using `FireflyFM Beta` (Debug test configuration), with existing unrelated compiler warnings.
- All 93 unit tests passed on a fresh iPhone 17 Pro Simulator, including four new asynchronous section-loader regressions.
- 239 SQL assertions passed across payment, Paperwork, Drive, QR, and reservation suites; one scheduler assertion was explicitly skipped in the schema-only database. The new reservation suite contributes 37 assertions.
- Two concurrent-connection checks passed: repeated payment submissions create one submission, and simultaneous reviewers cannot approve it twice.
- All 10 Google Drive Deno tests passed, including download-time access revocation and oversized body rejection. The byte-reader now preserves its inferred ArrayBuffer-backed type for compatibility with the Deno type checker.
- Migration application, schema snapshot consistency, and `git diff --check` passed. The snapshot was regenerated from the full current migration history, including previously committed beta migrations missing from the old snapshot.
- The existing four-role navigation UI smoke test passed on the fresh Simulator (one test covering parent, teacher, school director and HQ). It used a temporary scheme because the shared scheme omits UI tests; the temporary scheme was removed afterward. This is not authenticated workflow E2E evidence.
- Hosted schema, function deployment, scheduler execution, signed-device flows, and authenticated end-to-end workflows remain unverified.

The dedicated synthetic database and fresh Simulator were removed after verification. Build artifacts and test logs remain under `/private/tmp/firefly-adversarial-build` and `/private/tmp/final-*.log`.
