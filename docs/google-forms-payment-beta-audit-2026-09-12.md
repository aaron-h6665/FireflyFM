# Google Forms and Payment Beta audit — September 12, 2026

## Scope and fixes

Reviewed the current Forms connection/synchronization path, onboarding routing, payment composer/model, named-payer/reviewer policies, payment RPC authorization and existing regression coverage. Existing uncommitted onboarding, sync fallback, and legal edits were preserved.

| Problem | Fix |
| --- | --- |
| Google response pagination silently stopped after 20 pages, then advanced the sync timestamp. | Read all pages; fail on repeated page tokens or any page error instead of returning partial success. |
| A terminated worker left a connection in `syncing`, excluded from every subsequent run. | Select interrupted `syncing` connections after ten minutes. |
| A long sync recorded its completion time, potentially skipping submissions made during processing outside the five-minute overlap. | Record the start of the successful run as the next sync watermark. |
| Any token-refresh failure marked credentials as requiring reconnection, including network and Google server outages. | Only an invalid refresh grant marks the credential for reconnection; temporary errors remain retryable. |
| Payment parsing accepted malformed numeric prefixes and converted unbounded decimals into integers before multiplying invoice quantities. | Validate the complete USD entry, require at most two decimal places, bound amounts to the database limit before conversion, and validate the combined invoice total. |
| Payment actions could overlap while suspended at an async call, and one completion could clear the busy state of another. | Guard model mutations before suspension; also require a submitted draft to match the invoice authorized by the payer policy. |

## Verification

- iOS Debug Simulator build and FireflyFMTests unit suite passed, including new malformed/oversized amount and suspended duplicate invoice-request regressions.
- 11 Node tests passed: Google pagination beyond 20 pages, incomplete page failure, repeated tokens, refresh grant classification, worker recovery selection, and existing revocation tests. Worker tests use mocked services; they are not hosted integration tests.
- `git diff --check` passed.
- Database test execution was unavailable: Docker daemon is stopped. Existing SQL authorization checks were reviewed as source only; no new RLS/runtime claim is made.
- Authenticated Google account/Form submission, hosted cron execution, attachments, and payment bank/reviewer end-to-end flows remain unverified. No hosted deployment or real transfer was performed.

## Disclosure review and release gates

Reviewed Terms, Privacy, and the release checklist against these fixes. They retain the current data categories, Google scopes, providers, manual payment verification, access policy, and retention model. Updated the existing draft Terms, Privacy, and workflow guidance to describe scanning the configured Form’s response pages without the former page cap. This adds no provider or new data category; unmatched fallback responses remain transient. Accepted legal versions were not changed; draft publication/version acceptance remains a release gate. Existing legal edits remain pending in the working tree.

Before release, deploy the sync function with its new helper module after approval, verify the protected cron is active, run the database suite on an isolated local stack, and verify actual Google submission/import/review plus named-payer payment submission and authorized review. Exercise interrupted sync recovery and temporary Google outages. Existing App Store privacy, OAuth consent, subprocessor/data inventory, and beta isolation gates remain required.
