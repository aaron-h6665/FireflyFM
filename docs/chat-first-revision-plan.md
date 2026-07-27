# FireflyFM Chat-First Revision Plan

## Status and product direction

This is the implementation source of truth for the chat-first revision. Where it conflicts with `functionality-first-childcare-plan.md`, this document takes precedence.

The revision has two primary goals:

1. Make child-centered chat rooms the main communication and progress-update surface for parents, teachers, and school directors.
2. Make the teacher experience faster and clearer by reducing navigation, removing duplicated workspaces, and keeping common daily actions within a few obvious interactions.

Secondary work covers attendance, assignments, director setup, events, albums, and future progress-report assistance. Financial reporting remains deferred until payment data has an authoritative integration.

## Locked product decisions

- Create one private family-team room per active child and school.
- Create one open school-community room per school for all full-access parents, teachers, and the school director.
- Include all active full-access teachers in child rooms initially. Preserve a school policy switch for assigned-teachers-only access later.
- Teachers land on Today. Chat remains one tap away.
- Parents create structured family requests, not official care records.
- Structured care events and requests remain their own audited records and render as cards inside the child-room timeline.
- Preserve the existing camera, photo-library, and file composer buttons. Add a microphone button and a separate square-plus button at the leftmost position.
- Audio messages are supported in chat but excluded from initial AI report evidence.
- School codes identify a school and begin a connection request; they never grant record access or privileged roles by themselves.
- Director replacement follows vacate-then-invite, with at most one active director per school.
- Event creators can edit/archive their own events; school directors and HQ can manage all scoped events and permanently delete with confirmation and audit.
- Production AI remains disabled until an approved provider, privacy review, and contract are in place.
- Cognito Forms is the intended final report destination, with a secure export fallback.

## Current implementation findings

### Chat

- The backend model and storage service already support image, file, and audio attachment fields and private signed media URLs.
- `ChatViewManager` does not record, render, or play audio. An audio-only message currently becomes `Unsupported message`.
- The composer currently exposes camera, photo-library, and file buttons, but no square-plus action tray.
- Search covers message text and attachment names but there is no room-level Photos, Files, Links, or Audio index.
- Messages are loaded as one collection without cursor pagination or durable sending/failed/retry states.
- Rooms are manually created `director_managed` groups. Parent approval, guardian changes, teacher changes, graduation, and family departure do not provision or archive rooms.
- System-managed rooms need different rules from custom rooms: participants cannot manually leave, rename, delete, or arbitrarily change membership.

### Confidentiality

- `has_school_role` returns true for any HQ director regardless of the requested school role.
- Chat room and message RLS policies use that helper to grant school-director access, which also gives HQ direct database access to private chat despite the intended UI policy.
- Child/report authorization contains similar broad HQ and teacher fallbacks. These must be audited and narrowed before chat becomes the application record.
- All-teacher child-room membership is an explicit initial product policy, but it must not grant the same teachers unrelated medical, document, or profile access outside the parent-visible room projection.

### Reusable structured workflows

- Care Today already supports meals, bottles, naps, toileting, diapering, medication, health checks, activities, notes, photos, visibility, and transactional recording.
- Family Requests already supports absence, pickup change, medication questions, and general requests with staff acknowledgement/completion.
- These services should be reused. Chat cards reference their source records rather than duplicating structured data as formatted message text.

### Other areas

- Attendance has child status, history, automatic backend timestamps, absence handling, and correction history, but its UI is a long card list and HQ lacks a clean school-first filter journey.
- Assignments preserve immutable submission attempts and review feedback but have no creator edit flow, visible submission-revision setting, or 1–10 score.
- The database does not enforce one active school director. Pending director invitations cannot be explicitly cancelled from the current HQ UI.
- Events already have edit and permanent-delete operations. Archive/restore, tighter ownership rules, history, and parent event details are the missing pieces.
- The current iOS target compiles successfully for a generic iOS Simulator.

## Chat-room architecture

### Child family-team rooms

Each active child/school combination has one automatically managed room.

User-facing names must never say `system-managed`. Use:

- Primary name: `Avery Chen • Family Team`
- Staff subtitle: `Firefly Academy • Blue Room`
- Parent subtitle: `Firefly Academy • Teachers & Director`

Use the child's full display name so staff can distinguish children with the same first name. Group a multi-school teacher's conversations by school. Regenerate names/subtitles when child, classroom, or school display information changes.

Participants are:

- all verified guardians with active full access to that child;
- the sole active school director;
- all active full-access teachers at the school for the initial release.

Store the teacher membership strategy as a school policy with `all_school_teachers` and `assigned_teachers` values. Changing it requires an impact preview, confirmation, and audit record.

Provision the room idempotently when the first linked guardian reaches full access. Add later guardians to the same room. Remove an individual guardian when that relationship is revoked without closing the room for remaining guardians.

Archive the room when the child leaves or transfers from the school. Remove former teachers immediately and make the timeline read-only. If the child joins another school, create a distinct room there. If the child returns to the same school during the configured retention window, restore the existing room; otherwise create a new room linked to the archived record.

### School-community rooms

Create one automatically managed room per active school named:

`Firefly Academy • School Community`

All active full-access parents, teachers, and the school director may post. Onboarding members and HQ are excluded. Child-specific care cards and family requests cannot be created in this room.

Parents see display names and roles, not other participants' phone numbers or email addresses. Users can mute the room. The director can moderate, soft-delete inappropriate content, and review reports; moderation actions are audited.

### Custom rooms

Preserve existing manually created chats as `custom` rooms. Do not copy their historic messages into new family-team rooms. Custom rooms retain explicit participant management and leave behavior, subject to cross-school and role validation.

## Child-room timeline

### Structured cards

Keep `child_care_events`, `family_requests`, goals, and messages as their own source records. Create an immutable timeline/message entry referencing the structured source.

The card renders the source's current state while its audit history preserves corrections and status changes. Replies attach to the card without changing the source data.

Initial structured cards include:

- meal/bottle;
- nap;
- toileting/diaper;
- activity;
- health observation;
- authorized medication administration;
- note;
- milestone/goal update;
- absence, schedule, or pickup request;
- medication question;
- supplies, meeting, or general family request.

Staff can acknowledge and complete requests. Parents can reply, acknowledge, or cancel an eligible pending request. Medication administration still requires an approved instruction/task and cannot be created as an informal chat action.

### Composer

The persistent composer layout is:

`[Square Plus] [Camera] [Photos] [File] [Microphone] [Message Field] [Send]`

All icons remain individually available. Use 44-point touch targets; on narrow widths allow the message field to occupy a second row rather than hiding attachment controls.

The square-plus tray opens in the keyboard area and repeats common media actions intentionally. Repetition is acceptable because the persistent buttons support speed while the tray improves discovery. Both paths invoke the same code.

Staff child-room tray:

- Everyday Care
- Camera/Photo
- File
- Voice Message
- Call Guardians

Parent child-room tray:

- Family Request
- Camera/Photo
- File
- Voice Message

School-community tray:

- Camera/Photo
- File
- Voice Message

`Call Guardians` displays verified guardians for that child only. If one callable guardian exists, show a confirmation and start the device call. If several exist, show a short chooser. FireflyFM never records call contents.

### Audio messages

Support microphone permission, recording duration, cancel, preview, send, upload progress, failure/retry, playback progress, playback speed, route/interruption handling, and accessibility labels.

Use the existing private-room media paths and signed URLs. Store duration and attachment metadata. Do not create transcripts in the initial release.

### Attachments and links

Room details contain:

- Photos & Videos
- Files
- Links
- Audio

Allow filtering by sender, date, and type, with jump-to-message. Extract normalized links into a secure index without automatically scraping private URLs on the server.

Search includes message text, attachment names, structured-card labels, and indexed URLs.

### Archive access and downloads

When a child room is archived, guardians receive an automatic read-only access window, initially 90 days.

The main action is `Download all`. An advanced `Choose what to download` action supports:

- date range;
- reports;
- photos/videos;
- files;
- messages;
- care summaries;
- goals/milestones.

Exports contain only information visible to that guardian for the linked child. Institutional retention remains separate from family download access.

## Navigation and role experience

Avoid a generic More tab. Use a stable four-position shell:

1. Today
2. Messages
3. Calendar
4. A clearly named role workspace

The fourth label is:

- Parent: My Child
- Teacher: Training
- School director: School
- HQ director: Schools

The first three tabs keep the same position and meaning for every role. Profile/settings moves to the avatar in the header. Notifications use the header bell and relevant badges.

### Teacher Today

Teachers land here. It contains:

- persistent school switcher for multi-school teachers;
- classroom/room selector;
- child attendance grid;
- unread family-team conversations;
- family requests requiring action;
- medication/care items due;
- quick batch care entry.

Remove separate teacher workspace tiles for Children, Attendance, Care Today, and Family Requests. Those functions become context-sensitive actions from Today and child rooms.

### Parent

My Child contains today's timeline, current attendance state, recent care, goals, reports, and upcoming events. Messages holds family-team and school-community rooms. Family requests begin from the child room rather than a separate module.

### School director

Today contains attendance exceptions, open requests, medication/health exceptions, unread family items, and operational work requiring action. School contains people, children, classrooms, director-visible attendance history, events, albums, onboarding, and configuration.

### HQ director

Today presents portfolio exceptions and pending administrative work. Schools provides a school-first drill-down for directors, staff, children/attendance, onboarding, events, and later financial reporting. HQ has no family-chat access; Messages contains only explicitly designed organization/director administrative communication.

## Attendance design

### Mobile teacher/director attendance mode

Use a room-first workflow inspired by Brightwheel's current attendance mode:

1. Choose the school/room if not already scoped.
2. Open Attendance.
3. Tap child circles to select one or more eligible children.
4. Use the bottom action bar.

Display children in a three-column grid. An unselected circle shows initials, name, and a small status indicator. When selected, it changes to a light check mark. Tapping again restores the initials/name.

The first selected child establishes the action cohort. Children with an incompatible attendance state remain visible but cannot be added to the same batch without clearing/switching the selection. This prevents a single ambiguous action from checking some children in while checking others out.

State actions are:

| State | Actions |
| --- | --- |
| Not checked in today | Check In, Mark Absent |
| Present | Check Out |
| Checked out | Check In Again |
| Absent | Undo Absence, or Check In with confirmation |

Do not offer `Mark Absent` after a completed attendance session. A child who was present and then absent on the same day is an attendance data conflict.

Generate ordinary timestamps on the server. Teachers do not enter times. Directors correct missing or inaccurate records through audited history.

Use an idempotent batch RPC that returns a result for every selected child. Show partial conflicts explicitly and never silently skip a record.

Keep expected/not-expected attendance out of the initial interface.

### Daily care from the roster

Support both Brightwheel-style room batch logging and child-specific feed logging:

- From Teacher Today, select one or more children and log an applicable batch activity.
- From a Family Team room, use Square Plus > Everyday Care with the child already selected.

The same structured event service handles both paths, and parent-visible results appear as timeline cards.

### HQ and reporting view

Merge HQ Children and Attendance under `Schools > Children & Attendance`.

Provide a desktop/tablet-style filter row and mobile filter sheet with:

- date range;
- school;
- classroom/room;
- child;
- enrollment status;
- attendance state;
- check-in range;
- check-out range;
- include absences;
- data issues only;
- group by child.

Display summary counts, filterable rows, child history, missing checkout and overlap warnings, and export options with optional attendance audit logs.

## Progress reports and Cognito Forms

### Evidence and drafting

Each child receives a report workspace with report period, report type, evidence review, generated draft, director edits, Cognito status, and released reports.

Eligible evidence is limited to the selected child and date window:

- parent-visible family-room messages;
- structured care-event and request cards;
- goals/milestones;
- explicitly selected and consented media.

Exclude audio, staff-only notes, school-community messages, and other children's records.

Every generated claim includes a source citation that opens the corresponding message/card/media. Directors can remove evidence, edit the draft, and regenerate. AI cannot submit, release, diagnose, or provide medication advice.

Implement a server-only AI provider adapter and keep it disabled in production until vendor, retention/training, regional-processing, subprocessor, security, and contractual requirements are approved.

### Cognito integration

Map versioned Firefly report fields to a configured Cognito form. After director approval, the backend creates or updates the Cognito entry idempotently and stores the entry ID, form version, payload hash, actor, timestamps, and errors.

Use authenticated/idempotent webhooks plus manual/scheduled reconciliation for entry status and generated documents. Keep Cognito keys in backend secrets.

If API tier or privacy requirements are not met, generate a secure PDF/JSON export and provide one-click field copying without blocking manual report completion.

### Future notice and consent

The detailed AI-processing notice, consent/legal-basis review, optional transcription, and other deferred governance work are recorded in `future-product-directions.md`.

## Secondary workflow changes

### Assignments

- Only the creator edits assignment content.
- Store published assignment changes as revisions and notify assignees of material changes.
- If submissions exist, require a change summary and preserve the assignment version tied to each submission.
- Expose `Allow submission revisions`, default on. Editing a submission creates a new immutable attempt.
- Add an optional integer score from 1–10 to reviews, visible with feedback and audited when changed.
- Collapse My Activity into compact status/date rows; expand a row for complete history.

### Director setup

- Enforce one active director per school with a database constraint.
- HQ must vacate/archive the current director before inviting a replacement.
- Show schools as Active Director, Invite Pending, or Director Needed.
- For vacant schools, guide HQ through template readiness, director details, send, status, and expiry.
- Add Cancel Invite and Reissue Invite. Revoked links stop working immediately.

### School codes

- A school code locates the school and starts a parent/teacher connection request.
- Verify email and the family/staff relationship before creating onboarding access.
- Full access still requires approval and completed requirements.
- Director invitations remain individual HQ-issued links.

### Events

- Creators edit/archive/restore their own events.
- School directors and HQ manage any event in scope and permanently delete with confirmation, reason, and audit.
- Parents can open full event details.
- Preserve the existing event service rather than rebuilding working edit/delete behavior.

### Albums

After the chat/attendance core, allow creators to edit metadata and add/remove/reorder media; directors/HQ manage any scoped album. Use soft delete/restore and audit history. Defer people tagging and advanced editing to the future backlog.

## Data and interface changes

- Extend `chat_rooms` with room types `child_family`, `school_group`, and `custom`; child subject, system-managed flag, and archive/retention metadata.
- Add unique active-room constraints for one child-family room per child/school and one school-community room per school.
- Extend `chat_participants` with membership source and removal metadata. Only lifecycle RPCs mutate system-room membership.
- Add `schools.family_chat_teacher_scope` with initial value `all_school_teachers` and supported value `assigned_teachers`.
- Extend messages with entry kind, structured-source references, and audio duration. Structured card entries are immutable.
- Add an indexed link record and paginated attachment/timeline RPCs.
- Add idempotent room provisioning/synchronization RPCs triggered by access-state, guardian, staff, child, and school lifecycle changes.
- Add archive export jobs with requester-scoped visibility.
- Add idempotent batch attendance actions and per-child results.
- Add report-draft, evidence-citation, generation-audit, Cognito mapping, and export-attempt records.
- Add assignment revision/submission revision/score support, event archive history, invite revocation, and the active-director constraint.

## Delivery sequence

### Phase 0: Privacy and schema foundation

- Fix HQ/private-chat RLS and audit other broad child/report policies.
- Add room types, lifecycle relationships, unique constraints, membership source, and school teacher-scope policy.
- Enforce one active director and add invitation revocation.
- Add audit records and pgTAP role matrices.

### Phase 1: Automatic rooms and reliable chat

- Provision/backfill child-family and school-community rooms without importing custom-chat history.
- Add lifecycle synchronization and archival.
- Add pagination, durable send/upload states, notification privacy, and system-room settings.
- Add the corrected composer, audio messages, structured cards, media/link indexes, and download flows.

### Phase 2: Teacher Today and attendance

- Introduce the stable navigation shell and remove duplicated teacher workspaces.
- Build the child-circle selection grid, state-safe bottom actions, batch RPC, history, and corrections.
- Add room and child care-entry paths.
- Merge HQ Children and Attendance with school-first filters and exports.

### Phase 3: Reports

- Build report periods, evidence review/citations, draft editing, and media selection.
- Add the gated AI provider interface.
- Add Cognito mapping/export/reconciliation and secure fallback exports.

### Phase 4: Administrative improvements

- Assignment editing/revisions/scores and collapsed activity.
- Director setup/invite cleanup.
- Event archive/restore/history and parent details.
- Album management/history.

## Test and acceptance plan

### Authorization and lifecycle

- Cross-school users and HQ cannot query child rooms, messages, media, or report evidence.
- Onboarding users cannot join system rooms.
- Concurrent approvals create one room and one participant record per relationship.
- Test multiple guardians, siblings, multi-school teachers, teacher removal, guardian revocation, transfer, graduation, re-enrollment, and school archival.
- Switching the teacher policy changes only intended room access and is audited.

### Chat and daily operations

- Test keyboard/square-plus switching, all persistent composer icons, redundant tray aliases, narrow-width layout, and accessibility.
- Test audio denial, interruption, cancellation, preview, upload retry, signed-URL expiry, playback, and backgrounding.
- Test structured cards for source integrity, correction history, request transitions, medication authorization, replies, and notifications.
- Test gallery filters, link search, jump-to-message, Download all, and selective export visibility.

### Attendance

- Tapping a child replaces initials with the selection check mark; tapping again restores them.
- Homogeneous batches show only valid actions; incompatible states cannot enter the same action batch accidentally.
- Check-in, checkout, re-entry, absence, and undo-absence are idempotent and server-timestamped.
- Test partial conflicts, missing checkouts, overlaps, corrections, school filters, child grouping, and audit exports.

### Reports and Cognito

- Test date/child evidence boundaries, citations, media consent, audio exclusion, provider-disabled behavior, regeneration, revoked access, and no automatic release.
- Test Cognito idempotency, duplicate/out-of-order webhooks, manual reconciliation, missing fields, credential errors, and fallback exports.

### Secondary features

- Test creator-only assignment changes, immutable revisions, submission permission, score range, and collapsed activity.
- Test one-director enforcement, vacancy, invite cancellation/reissue, and revoked-link rejection.
- Test creator/leader event permissions, archive/restore, audited deletion, and parent details.

### Usability targets

- Teacher opens directly to Today.
- Attendance requires child selection plus one bottom-bar action.
- A common child-room care event takes at most four taps once the room is open.
- A parent absence request takes at most four taps from the child room.
- Calling a single verified guardian takes at most three taps.
- Photos, files, links, and audio are reachable within two taps from room details.

## Related future work

See `future-product-directions.md` for explicitly deferred ideas, including AI notice/consent governance, audio transcription, assigned-teachers-only rollout, permanent family keepsakes, advanced exports, album tagging/history, expected attendance, attendance analytics, financial reporting, offline operation, and accessibility/language improvements.
