# Google Form response recovery — September 12, 2026

## Findings

1. **Wrong routing URL.** Hosted mappings had hexadecimal question ID `7181a7e3` and no separate prefill key. The signed-in responder page identified the routing entry as decimal `1904322531`. The old launch function used `entry.7181a7e3` literally. New connections now store the decimal entry key, and the migration repairs existing mappings.
2. **Opening was treated as submission.** The UI disabled awaiting-sync cards and the database rejected any second launch. Continue Form now remains available. A device-only, account-scoped Keychain entry retains the launch link across sign-out; the new resume RPC revalidates membership, assignment, ordering, expiry and the token hash. It preserves historical sessions so a late response from an older device is not invalidated merely by reopening.
3. **Refresh was detached from the check.** Refresh only reloaded the projection and started an unawaited polling task. It now awaits a sync and reload, shows a result, and treats a missing connection outcome as a failure rather than a successful check. Forms no longer disappear from projections while the worker marks them syncing or error. Account changes discard old projections and late results.
4. **Valid birthdates could not create a child review request.** A full response fixture matched the reference but exposed a double-escaped SQL date regex. The migration fixes it and catches invalid calendar dates as school-review issues instead of aborting the worker.
5. **Draft ownership was unclear.** Google displayed “Your progress has been restored” in the signed-in responder page. FireflyFM's sign-out copy incorrectly implied it saved unfinished answers itself. UI, policy drafts, workflow guidance and data inventory now distinguish the saved checklist/link from Google's drafts.

The live Google credential was connected, had a successful sync timestamp, and had no recorded error. Recent sessions were unconsumed and the import table was empty. This establishes a routing defect and functioning authorization at inspection time, not that a particular response was submitted to Google. Production OAuth verification is still required separately; testing-mode refresh grants can expire after seven days.

## Verification

- iOS Debug Simulator build and complete FireflyFMTests suite passed with reopening-state, account/backend cache isolation, cache expiry, and new-store-instance persistence regressions.
- 14 Google Edge Function/helper tests passed, including the observed hexadecimal-to-decimal mapping and prior worker/pagination/refresh tests.
- The focused parent timeline/Forms database regression passed 32 checks on a separate local Supabase stack. Coverage includes real launch-link generation, resuming, hash matching and consumption, a complete child-intake payload, invalid dates, expired/consumed references, different recipients, unassigned users, and syncing/error projections.
- The broader database suite ran 386 checks but did not finish cleanly: test 010 references a nonexistent `notifications.user_id`, and test 013 creates two active directors in the same school. These fixture errors were not introduced or changed by this recovery patch.
- Schema snapshot and whitespace checks passed.
- No hosted migration or Edge Function was deployed, and no Google Form was submitted by this audit. Signed-device Keychain behavior and full authenticated app-to-Google-to-review flow still require verification.

## Deployment

After approval, apply migration `20260912190000_google_form_resume_and_routing.sql` and deploy both `google-forms-oauth` and `sync-google-onboarding-forms`, including their helper modules. The app requires schema version `20260912190000`; deploy the backend before installing the new build. Verify that reopening prefills the reference, Submit shows Google's confirmation, Check response reaches Awaiting review, and school approval advances onboarding. Existing raw responses without a valid reference must not be assigned by guessed email matching.

Automatic approval review blocked opening the Google Form editor to inspect its response count. Permission is needed for that inspection; the public/responder-page field metadata was verified without entering the editor.

## Google references

- [Google Form draft autosave](https://support.google.com/docs/answer/10952360?hl=en): signed-in Google account, autosave enabled, draft retention up to 30 days.
- [OAuth refresh-token expiry](https://developers.google.com/identity/protocols/oauth2): external applications in Testing with Forms/Drive scopes receive refresh tokens that expire after seven days.
