# FireflyFM AI privacy and App Store release checklist

Status: implementation draft, July 30, 2026. This is a product/compliance checklist, not legal advice. The in-app Terms, Privacy Policy, AI Notice, legal entity, contact address, retention commitments, and jurisdiction-specific language must be approved by qualified counsel before production release.

## Implemented prototype boundary

- Only a school director receives the `generateChildAISummary` capability.
- Generation uses Apple Foundation Models on the director’s device.
- FireflyFM does not call a cloud AI API, upload the prompt, or persist the result.
- The prompt may contain recent message text, sender name/role/time, attendance, care/activity-card details, goals, and attachment metadata.
- The prompt does not contain attachment URLs or storage paths.
- Image, video, audio, and file contents are not opened, transcribed, classified, or interpreted.
- The prompt is capped for the model context window and reports omitted-message counts.
- The UI requires the director to acknowledge human review before generation.
- Generated text is labeled as an unsaved draft and may not be the sole basis for consequential decisions.

## Legal presentation pattern

The usual consumer-app pattern is implemented:

1. Signup presents a required unchecked acceptance control immediately above Create Account.
2. Terms, Privacy Policy, and AI Notice are individually readable before acceptance.
3. The accepted document versions and timestamp are stored in authenticated user metadata.
4. Profile contains a permanent Legal & Privacy screen with all documents and a privacy contact route.
5. The AI feature repeats its just-in-time disclosure and human-review acknowledgment at the moment of use.

Do not pre-check acceptance. Material changes should use a new version and require renewed acceptance. Existing accounts also need a migration/re-consent gate before public release; the signup implementation alone does not cover them.

The prototype stores version and timestamp in Supabase Auth user metadata. Before production, replace or supplement that with a server-owned, append-only acceptance record containing document versions, actor, timestamp, and withdrawal/re-consent events; client-editable metadata should not be the legal audit trail.

## App Store checks before submission

- Publish the final Privacy Policy at a public URL and add that URL in App Store Connect.
- Complete App Privacy labels from the production data flow, including child records, health/care information, photos/videos/audio, user content, identifiers, and diagnostics as applicable.
- In App Review notes, explain that Foundation Models inference is on-device and provide the navigation path: Director -> Children -> Child -> Create AI Review Draft.
- Provide a reviewer account and a supported physical-device test path. The Foundation Model may be unavailable on Simulator or unsupported devices.
- Keep all advertised functionality useful when the model is unavailable; the source records remain available.
- Implement in-app account deletion before submission. A mail contact by itself is not a substitute for Apple’s account-deletion requirement for apps that support account creation.
- Confirm all purpose strings and permissions accurately describe photo, camera, microphone, and notification use.
- Confirm the app is adult-facing and do not select the Kids Category unless the entire app and data model are redesigned for those rules.

## Counsel and operations decisions still required

- Replace or verify `privacy@fireflyfm.app` and identify the legal entity and mailing address.
- Decide whether the school, FireflyFM, or both are controller/business for each data flow and document processor/service-provider contracts.
- Define record-by-record retention, backup deletion timing, school export/ownership transfer, legal holds, and verified deletion handling.
- Determine jurisdiction-specific guardian notice/consent requirements for child records and AI-assisted processing.
- Decide whether a school-level feature switch or child-specific guardian opt-out is required even for on-device processing.
- Define incident response, access logging, AI quality review, complaint escalation, and staff training.
- Verify that the Terms’ disclaimers, limitations, dispute terms, governing law, and organization agreements are consistent.

## Changes that require a new AI/privacy review

Do not silently extend this notice. Re-review and update consent/disclosure before any of the following:

- Gemini, OpenAI, or another cloud/third-party model;
- media download, transcription, OCR, image/video understanding, or document parsing;
- saving summaries or using them to prefill or submit forms;
- automated alerts, scores, recommendations, developmental assessment, or decisions;
- access by teachers, parents, HQ staff, or cross-school users;
- model training, evaluation, telemetry, or prompt/result logging;
- combining child data with advertising, profiling, or unrelated analytics.

For a cloud AI provider, document the exact fields sent, location, subprocessors, training policy, abuse-monitoring retention, contractual deletion, regional processing, and whether a zero-data-retention arrangement actually covers every endpoint and feature used. Obtain explicit permission before transmitting personal information when required by Apple policy or law.
