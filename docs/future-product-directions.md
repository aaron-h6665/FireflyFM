# FireflyFM Future Product Directions

## Purpose

This document records ideas that are intentionally outside the current chat-first implementation. It is a product backlog, not a promise that every item will ship. Each item is labeled so user-requested directions remain distinguishable from additional suggestions.

Before promoting an item into active scope, define its owner, privacy classification, legal requirements, success criteria, and relationship to the child/family/school authorization model.

## Privacy, AI, and report governance

### AI-processing notice and consent

**Source: User-requested**

Add a versioned parent-facing disclosure for AI-assisted progress-report drafting. This should not be hidden only inside general Terms of Service. The experience should explain, in plain language:

- which child-room messages, structured care events, goals, and selected media may be processed;
- that audio is excluded unless a future transcription feature is separately enabled;
- that AI creates a draft for human review and cannot diagnose a child, make medication decisions, or release a report automatically;
- which service providers process the data, where processing occurs, and applicable retention/training terms;
- how families can ask questions, withdraw consent where applicable, or use a manual-report alternative;
- whether staff-authored messages and observations are processed and how staff are notified;
- when a material policy change requires a new acknowledgement.

Store the notice version, acceptance/decline, timestamp, actor, child/school scope, and later withdrawal as auditable records. If permission is declined or withdrawn, ordinary chat and care functions must continue to work and report drafting must exclude that child's material.

Have privacy counsel determine the correct legal basis and whether affirmative consent is required in each operating jurisdiction. A Terms acceptance checkbox alone must not be treated as proof that all child-data processing is lawful.

### AI voice-message transcription

**Source: User-requested**

Consider opt-in transcription of individual voice messages for report evidence. Preserve the source message and timestamps, expose corrections, cite the recording in the draft, and apply separate retention and access controls. Do not enable this with the initial audio-message release.

### Report-provider governance

**Source: Suggested**

Maintain a provider review checklist covering data retention, model training, regional processing, subprocessors, incident response, deletion, auditability, and contractual requirements. Keep AI report generation disabled until the review is complete.

### Native report completion

**Source: User-requested alternative**

If Cognito Forms cannot meet workflow, API-tier, or privacy requirements, consider completing, approving, signing, releasing, and exporting progress reports entirely in FireflyFM.

## Family-room access and retention

### Assigned-teachers-only room membership

**Source: User-requested**

The first chat release may include all active teachers at the school. Retain the planned school policy switch to restrict future child-room access to assigned teachers and explicitly authorized temporary coverage. Preview and audit membership changes before applying them.

### Family keepsake vault

**Source: User-requested direction**

Explore a permanent read-only family vault for selected reports, photos, and videos after a child leaves. Keep it separate from institutional chat retention, allow simple one-tap saving, and define account recovery, deletion, export, and long-term storage policy before launch.

### Advanced archive export

**Source: User-requested**

Keep a simple `Download all` action, with an advanced chooser for date range and categories such as reports, photos/videos, files, messages, care summaries, and goals. The selected export must include only parent-visible information for that guardian's linked child.

## Communication and daily operations

### Chat media to Daily Log labeling

**Status: Previously implemented, temporarily removed (September 9, 2026)**

FireflyFM previously showed a **“Save this moment?”** prompt after an
authorized teacher sent a photo, video, or voice message in a child’s family
chat. The prompt could create a linked Daily Log activity with a teacher note,
activity type, developmental areas, and an optional progress highlight while
preserving the original chat media and timestamp. It was removed from the
current product for now. A future version may revisit this as an explicit,
privacy-reviewed way to connect family-chat evidence to Daily Log and report
review workflows. Any return should preserve child-scoped authorization,
director review, audio non-transcription, and clear separation from device
“Save to Photos” behavior.

### Explicit check-after-reading acknowledgement

**Source: User-requested deferral**

Reconsider an explicit “Check After Reading” action for assignments if schools need a separate acknowledgement beyond automatic viewed state and ordinary submissions. Keep the existing backend fields compatible, but leave this control out of the current assignment interface until its reporting, compliance, and reminder behavior is clearly defined.

### Media and people tagging

**Source: User-requested**

Consider tagging children, guardians, or staff in album and chat media. Require consent-aware visibility, scoped search, tag correction/removal, and an audit trail. Do not add facial recognition by default.

### Album history and Photos-style management

**Source: User-requested**

Add album metadata history, photo add/remove history, restore windows, captions, ordering, and clearly attributed edits. Advanced pixel editing remains out of scope unless a concrete need emerges.

### Communication assistance

**Source: Suggested**

Evaluate quiet hours, scheduled delivery, configurable digests, translation, saved reply templates, and unanswered-message indicators after reliable chat delivery and membership are established.

### Temporary classroom coverage

**Source: Suggested**

Add effective-dated substitute/coverage assignments so temporary teachers receive only the children, rooms, and communication access required for the coverage window.

## Attendance and classroom operations

### Expected attendance and schedule planning

**Source: User-requested deferral**

Keep expected/not-expected attendance out of the simplified initial interface. Reconsider scheduled attendance, vacations, late arrivals, early pickup, and exception alerts only after basic batch check-in/out and absence handling are dependable.

### Staff attendance, ratios, and room movement

**Source: Suggested**

Consider staff check-in/out, classroom movement, live ratios, capacity, coverage gaps, and licensing exports. Student room movement must remain distinct from permanent classroom assignment.

### Attendance analytics

**Source: Suggested**

Add configurable school/HQ summaries for days present, hours present, arrival/departure distributions, missing check-outs, overlapping sessions, corrections, and audit-log exports.

## Financial operations

### School financial statistics

**Source: User-requested**

Create school-by-school financial dashboards for directors and consolidated reporting for HQ only after payment, invoice, refund, subsidy, and adjustment data have authoritative integrations. Reports should reconcile to source transactions and support scheduled delivery, period comparison, outstanding balances, and audit exports.

Do not infer revenue or balances from manually entered estimates and do not present placeholder financial metrics as operational truth.

## Product-quality opportunities

### Teacher workflow analytics

**Source: Suggested**

Measure taps, time-on-task, retry rates, and abandonment for attendance, care events, parent contact, and requests. Use aggregated privacy-preserving telemetry and pair it with moderated teacher usability sessions.

### Offline daily-care queue

**Source: Suggested**

Consider a conflict-aware local queue for attendance and care events in schools with unreliable connectivity. Preserve idempotency and show explicit pending, synced, conflicted, and failed states.

### Accessibility and language support

**Source: Suggested**

Continue improving Dynamic Type, VoiceOver, contrast, reduced motion, multilingual family communication, translated school notices, and readable export formats.
