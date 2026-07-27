# FireflyFM Functionality-First Childcare Plan

> **Revision notice (July 27, 2026):** `chat-first-revision-plan.md` is the current implementation source of truth for communication, teacher navigation, attendance, report drafting, director setup, assignments, events, and albums. Where the two documents conflict, follow the chat-first revision plan. Deferred ideas are tracked in `future-product-directions.md`.

## Product conclusion

FireflyFM already has broad feature coverage, but it is not yet a complete childcare operating system. Its strongest areas are onboarding, assignments, role-aware data access, and the breadth of its child, community, calendar, and chat screens. Its weakest area is the operational relationship model connecting a child to guardians, classrooms, assigned teachers, school directors, and headquarters.

That relationship model exists partially in the database, but it is not consistently manageable in the app and does not consistently control recipient selection, notifications, chat membership, or teacher access. As a result, FireflyFM can present many capabilities without yet making the most important daily childcare workflows dependable.

The next product cycle should therefore prioritize:

1. Classroom and family relationships as first-class application data.
2. A complete daily-care loop for parents, teachers, and directors.
3. Communications routed by those relationships and linked to real work.
4. Safety, incident, medication, pickup, and attendance workflows.
5. Child development and school operations after the daily loop is dependable.

Beta-release work, visual polish, billing, localization, and marketing readiness should remain separate from this plan. UI work is included only where it is needed to make a workflow understandable and operable.

## Current capability assessment

| Childcare capability | Current state | Assessment |
| --- | --- | --- |
| Role onboarding and document requirements | Versioned templates, uploads, review, waivers, per-child scope, and access gating | Strong, but more elaborate than several core daily-care features |
| Child and guardian records | Child profiles, guardians, medical data, attendance, activities, goals, reports, and documents | Broad but fragmented; some records have no creation or management journey |
| Classroom organization | Classroom, classroom-child, and classroom-teacher tables plus read APIs | Incomplete: no practical director-facing assignment workflow |
| Attendance | Check-in and check-out records | Basic; lacks expected attendance, authorized pickup verification, exceptions, signatures/PINs, and classroom ratio context |
| Daily care | Activity types for medication, pickup, absence, bowel/potty, meal, nap, and notes | Too unstructured for fast teacher entry or a useful parent daily report |
| Health and medication | Medical profiles, medication instructions, tasks, acknowledgements, and escalation concepts | Promising but role ownership is inconsistent: the backend permits guardians to manage instructions while the current UI exposes schedule creation to staff/directors instead |
| Emergency and pickup information | Emergency-contact data model and policies | Not covered by a complete app workflow |
| Incidents and injuries | No dedicated end-to-end workflow | Missing core childcare functionality |
| Child development | Goals and progress-report viewing, curriculum and assignment infrastructure | Partial; no simple observation-to-milestone-to-report workflow |
| Chat | Rooms, membership, realtime messages, unread state, mute, media, reply, edit, delete, and search | Feature-rich composer, incomplete relationship and safety model |
| Notifications | In-app notification records, categories, recipient selection, and generic deep links | Functional only at a basic level; routing is manual, non-atomic, and usually not linked to the exact child or source task |
| Community and announcements | Posts, scheduled dates, media, albums, events, and displayed polls | Broad but incomplete: no poll voting, RSVP, classroom audience, reliable scheduled publication, or consent-aware child-media targeting |
| Staff operations | Training and assignments | Missing schedules, classroom coverage, ratio monitoring, timeclock, and substitute handling |
| Director operations | School setup, people, children, attendance, documents, and review workflows | Broad but lacks a single operational view of today's exceptions and required actions |
| Headquarters operations | School creation, director onboarding, portfolio metrics, training/curriculum/event distribution | Partial; several operational areas are placeholders and HQ visibility is not consistently aggregate-first |
| Billing | Deliberately disabled but still surfaced in parts of the app | Defer and hide until the childcare operating loop is complete |

## The relationship model FireflyFM needs

The application should resolve permissions and recipients from one authoritative graph:

`organization -> school -> classroom -> child -> guardian`

Teachers attach to one or more classrooms; directors manage one school; HQ directors manage organizations and schools. Every screen and backend policy should use the same effective-dated relationships.

### Parent

- Sees only linked children and the staff, classrooms, messages, events, and records relevant to those children.
- Maintains emergency contacts, pickup authorizations, health information, medication requests, and routine family requests.
- Receives a daily timeline/report and acknowledges incidents, medication changes, documents, and urgent messages.
- Starts a conversation with the child's assigned team without selecting from all school employees.

### Teacher

- Sees only currently assigned classrooms and children, except for explicit temporary coverage.
- Records attendance, meals, bottles, naps, toileting, activities, mood, health notes, medication administration, and incidents.
- Communicates with guardians of assigned children and the appropriate school leaders.
- Has a fast “Classroom Today” workspace rather than navigating individual child profiles for every entry.

### School director

- Owns classroom rosters, teacher assignments, temporary coverage, capacity, authorized pickup policy, and school communications.
- Reviews incidents, medication requests, attendance exceptions, staffing/ratio exceptions, expiring records, and unanswered family requests.
- Can inspect school activity and safeguarding records, with sensitive access logged and clearly disclosed.
- Sees queues of work requiring action, not only counts and content lists.

### Headquarters director

- Manages schools, directors, organization-wide templates, policies, curriculum, training, and compliance standards.
- Sees portfolio aggregates and exceptions first, then drills into a school only when operationally necessary.
- Does not receive routine access to family chat or raw health/child records merely because HQ is a higher role; sensitive drill-down should be capability-based and audited.
- Compares schools using consistent definitions for enrollment, attendance, ratios, incidents, open requests, compliance, and staff completion.

## Prioritized implementation roadmap

### Phase 0 — Make relationships and authorization dependable

This is the prerequisite for every later feature.

#### Application functionality

- Add director-facing classroom management: create/archive classrooms, assign age group and capacity, place children, assign primary/support teachers, and schedule temporary coverage.
- Show parents their child's classroom and teaching team; show teachers their current classrooms and coverage periods.
- Remove the fallback that grants a teacher access to every child in a school when the teacher has no classroom assignment. An unassigned teacher should see no children until explicitly assigned or granted temporary coverage.
- Replace role-only recipient lists with relationship-derived lists. A parent should see the child's teachers and directors; a teacher should see guardians of assigned children and directors.
- Add a backend-issued capability/relationship context so SwiftUI does not independently reinterpret roles on each screen.

#### Backend changes

- Make classroom-child and classroom-teacher assignments effective-dated with `starts_at`, `ends_at`, assignment type, and audit metadata.
- Add a server-owned `relationship_context` RPC that returns current school, classroom, child, guardian, and staff relationships for the signed-in user.
- Add narrowly scoped authorization helpers such as `can_view_child`, `can_record_child_care`, `can_contact_user`, `can_review_incident`, and `can_manage_classroom`.
- Change profile visibility from “all authenticated users” to self, valid school/child relationships, and specifically authorized administrators.
- Disallow direct client insertion of arbitrary chat participants. Add a transactional RPC that verifies the target user belongs to the room's school and is an allowed participant for the room type.
- Keep HQ permissions capability-based. Separate portfolio reporting from permission to open raw child, medical, or message data.
- Record relationship changes and sensitive administrative reads in an append-only audit log.

#### Acceptance scenarios

- A teacher assigned to Classroom A can see its children but cannot query Classroom B's children.
- An unassigned teacher cannot see the entire school roster.
- Moving a child between classrooms updates teacher access, recipient lists, and managed classroom channels together.
- No user can add a cross-school UUID to a chat room.
- A parent cannot browse unrelated authenticated-user profiles.

### Phase 1 — Complete the daily childcare loop

#### Structured care events and daily report

- Replace free-form activity logging with a common `ChildCareEvent` model supporting meal/bottle, nap, toileting/diaper, activity, mood, health observation, supply reminder, and note.
- Give each event structured fields appropriate to its type: event time, start/end or duration, quantity and unit, result/status, notes, visibility, attachments, and recorder.
- Build a classroom quick-entry screen that can record one event for one child or a safe batch event for several selected children.
- Generate a parent-facing chronological “My Child Today” timeline and end-of-day summary from attendance, care events, medication, incidents, and staff notes.
- Let parents acknowledge or ask a follow-up question without copying the event into an unrelated chat.

#### Attendance, pickup, and classroom safety

- Add expected attendance and schedule exceptions such as absent, late arrival, early pickup, and vacation.
- Record who checked a child in/out, who physically picked the child up, and whether authorization was verified.
- Add pickup contacts with relationship, photo, phone, permission status, validity dates, and optional secure PIN/signature confirmation.
- Surface missing check-in, overdue pickup, unexpected absence, and unverified pickup as director/teacher actions.
- Calculate live classroom presence, assigned staff coverage, capacity, and configured ratio exceptions.

#### Incidents

- Add a dedicated incident workflow with child, date/time, location, category, severity, narrative, injury/body area, first aid, witnesses, attachments, and staff author.
- Require director review for configured severities and lock material fields after review; corrections should append history rather than rewrite it silently.
- Notify the correct guardians, record delivery, require acknowledgement/signature when appropriate, and preserve an audit trail.
- Give HQ aggregate incident trends without making all family details visible by default.

#### Medication and health

- Make the role sequence explicit: guardian submits instructions/request; director or authorized health role verifies; assigned staff administers; guardian sees the record; missed tasks escalate.
- Correct the current UI/backend mismatch so guardians can create appropriate medication instructions while staff cannot originate a guardian authorization accidentally.
- Add start/end dates, prescriber/pharmacy details where required, storage instructions, permissions, attachment support, PRN rules, remaining quantity, and discontinue/replace behavior.
- Turn the existing emergency-contact and medical data into complete edit/review flows with change history.

#### Role home screens

- Parent: “My Child Today,” arrival status, recent care, open requests, upcoming events, and quick actions for absence, pickup change, medication, and message.
- Teacher: “Classroom Today,” present/expected children, rapid care entry, medication due, incidents, pickup changes, and unread family requests.
- Director: “School Today,” attendance exceptions, staffing/ratio coverage, incidents, medication exceptions, expiring documents, and requests awaiting response.
- HQ: portfolio exceptions, consistent cross-school metrics, incomplete director actions, and drill-down by school.

These dashboards should be backed by actionable queries and exact destinations; they should not be decorative summaries.

### Phase 2 — Rebuild communications around real relationships and work

Communications are not complete until the correct people are automatically included, the message is linked to its subject, delivery is reliable, and responsibility for the next action is visible.

#### Separate four communication modes

1. **Conversation:** ongoing family, classroom, or staff discussion.
2. **Family request:** structured item requiring a response, such as absence, late arrival, pickup change, schedule change, medication, supplies, or a meeting request.
3. **Announcement:** one-to-many information with an audience, publish time, and acknowledgement/RSVP when needed.
4. **Urgent safety alert:** controlled escalation with delivery tracking and a backup response path.

#### Conversations

- Introduce explicit room types: family, classroom, staff, announcement discussion, and custom.
- Create and maintain family threads automatically for each child and classroom channels for current members. Synchronize membership when guardians, children, or staff assignments change.
- Replace raw UUID entry and display with a name/role/relationship people picker. Never expose UUIDs as the user-facing membership mechanism.
- Define private-room oversight in product policy and disclose it in the UI. If directors can access a private room for safeguarding, log that access.
- Add dependable client outbox states: sending, sent, failed, and retry. Preserve drafts and attachment progress across navigation and transient network failures.
- Add per-message read state where operationally useful, archive/close behavior, reporting/moderation, and retention rules. Typing indicators and reactions can wait.

#### Family requests

- Add a `FamilyRequest` object with child, request type, effective date/time, details, status, submitter, assigned recipient/team, responder, and response history.
- Resolve recipients automatically from the child's current relationships. Parents should not manually guess which teacher is working that day.
- Support submitted, acknowledged, accepted, declined, needs-information, completed, and cancelled states.
- Show requests in the teacher/director action inbox and on the child's timeline. Keep a discussion thread attached to the request.

#### Notifications and delivery

- Make notification creation and recipient creation one server transaction; do not permit orphaned notifications.
- Link every actionable notification to its source object, school, child when relevant, and exact destination.
- Resolve recipients on the server from classroom and guardian relationships instead of trusting client-supplied lists.
- Record queued, delivered, opened, acknowledged, failed, and expired states for important notifications.
- Add device push after in-app routing and transactional correctness are complete. Include quiet hours, urgency rules, duplicate suppression, token cleanup, retries, and fallback escalation for safety-critical items.
- Do not silently ignore secondary notification errors. The originating workflow should expose partial delivery and allow retry.

#### Announcements, events, and community

- Support school, classroom, selected-family, staff, and organization audiences, with server-side authorization.
- Publish scheduled posts only when their scheduled time arrives; do not display or notify early.
- Add photo/media consent rules and child-aware audience checks before exposing classroom media.
- Add RSVP and attendance responses to events, including reminders and material-change notifications.
- Materialize or correctly query recurring event instances instead of storing a display-only repeat label.
- Implement real poll voting, results visibility, and closing rules, or remove poll controls until they work.
- Consolidate duplicate event access between Calendar and Community around one event source of truth.

### Phase 3 — Child development, staff operations, and headquarters oversight

#### Child development

- Add fast teacher observations with tags, attachments, developmental domain, and visibility.
- Let observations support goals/milestones and flow into a draft progress report without requiring teachers to re-enter evidence.
- Add director review, parent release, parent acknowledgement, and follow-up discussion.
- Keep curriculum plans distinct from employee assignments; link planned learning activities to observations where useful.

#### Staff and classroom operations

- Add staff schedules, classroom coverage, breaks, substitutes, clock-in/out, qualifications, and ratio eligibility.
- Alert directors to coverage gaps and ratio exceptions using actual attendance and scheduled staff.
- Add enrollment status, room capacity, transition dates, and a lightweight waitlist before considering a full CRM.
- Add document signatures, expiry dates, renewal reminders, and compliance status for required records.
- Implement fire drills, licensing checks, corrective actions, and incident/compliance trends rather than presenting placeholder “Ready” rows.

#### Headquarters

- Standardize portfolio metrics and exception definitions across schools.
- Give HQ configurable templates and minimum requirements while preserving school-level execution and ownership.
- Provide school drill-down for staffing, enrollment, attendance, training, incidents, compliance, and unanswered requests.
- Require a reason and audit event for exceptional access to sensitive child-level information.

## UI and information-architecture changes that are necessary now

The current five-tab structure does not need a wholesale redesign before these functions are built. Make only the changes required for operational clarity:

- Make Home role-specific and action-oriented.
- Use a shared Action Inbox for requests, reviews, incidents, medication exceptions, documents, and required acknowledgements.
- Keep Chat for conversations; do not bury structured requests inside free-form messages.
- Make “Up Next” items tappable and route directly to the underlying child, request, medication task, event, or review.
- Stop presenting disabled or placeholder functions such as payments and HQ “Ready” operations as available capabilities.
- Remove duplicate entry points when they cause conflicting state, especially Community chat versus Chat and Community events versus Calendar.
- Replace generic “Work” groupings over time with role language: Tasks for parents, Classroom Work for teachers, School Operations for directors, and Portfolio for HQ.
- Use clear state labels showing child/school, source, urgency, owner, due time, and next action.

Visual restyling, animation, broad navigation experimentation, and cosmetic consistency can follow once these workflows are stable.

## Backend implementation shape

### New shared domain types

- `RelationshipContext`
- `ClassroomAssignment`
- `StaffCoverageAssignment`
- `ChildCareEvent`
- `DailyChildReport`
- `AuthorizedPickupContact`
- `FamilyRequest`
- `IncidentReport`
- `CommunicationAudience`
- `ConversationRoomType`
- `MessageDeliveryState`
- `NotificationDeliveryState`
- `ActionInboxItem`

### Service boundaries

Split the current large workflow service into relationship/classroom, children, attendance, care, health/medication, incidents, communications, events/community, development, staff, and HQ reporting services. SwiftUI feature models should call these boundaries rather than assembling multi-table operations in views.

Use transactional RPCs for operations that create related records or change access, including:

- assigning a child or teacher to a classroom;
- submitting and routing a family request;
- creating a notification with resolved recipients;
- publishing an announcement and queuing delivery;
- creating/reviewing/acknowledging an incident;
- approving a medication instruction and generating tasks;
- changing a child's classroom and synchronizing managed room membership.

Use append-only history for safety, authorization, incident, medication, pickup, and membership changes. Use scheduled backend jobs for post publication, reminders, missed medication, overdue acknowledgement, recurring events, and escalation.

## Test and acceptance plan

The most important tests should prove relationships and complete workflows, not just that screens launch.

### Required end-to-end role scenarios

1. A parent submits a pickup change for a child. Only the assigned classroom team and school director receive it; a teacher acknowledges it; pickup staff see the accepted change; the parent sees status and completion.
2. A teacher records meals, nap, toileting, and an activity. The child's guardians see the timeline; unrelated parents and teachers cannot query it.
3. A teacher creates an incident, a director reviews it, the guardians receive it, and one guardian acknowledges it. The history cannot be silently rewritten.
4. A guardian submits medication instructions, a director verifies them, an assigned teacher records administration, and a missed task escalates.
5. A director reassigns a child and teacher between classrooms. Roster access, recipient choices, and managed chat membership update atomically.
6. A parent contacts the child's team by name and relationship. The app never asks for or displays a raw UUID.
7. A chat member cannot add a cross-school or unrelated user, even by direct API call.
8. A scheduled announcement remains invisible and sends nothing before publication time.
9. Event RSVP and poll voting either work end to end or the controls are absent.
10. HQ sees portfolio-level incident and attendance trends without automatically reading routine family messages or medical details.

### Automated coverage

- Add pgTAP coverage for every relationship edge, cross-school denial, unassigned-teacher denial, temporary coverage, room membership, profile visibility, notification recipient resolution, and sensitive HQ drill-down.
- Add service and feature-model tests for offline/retry states, atomic operation failures, relationship changes, duplicate suppression, scheduled publication, and notification routing.
- Add deterministic UI fixtures for each role's daily dashboard and the four critical loops: attendance/pickup, care report, incident, and medication.
- Treat swallowed delivery errors, orphan records, broad role-only access, and generic deep links as test failures.

## Recommended sequence and stopping points

1. **Relationship foundation:** classroom management, scoped access, recipient resolver, chat participant fix, and profile privacy.
2. **Daily loop:** structured care events, daily report, attendance/pickup, incidents, medication role correction, and role dashboards.
3. **Communication loop:** managed rooms, family requests, atomic notifications, delivery state, audience-aware announcements, RSVP/polls/scheduling.
4. **Operational depth:** observations/progress, staff coverage/ratios, enrollment/capacity, compliance, and HQ aggregates.
5. **Deferred:** billing, release engineering, broad UX polish, localization, marketing instrumentation, and cosmetic redesign.

Do not begin the next stage merely because its screens can be mocked. Each stage should stop for role-matrix verification and backend authorization tests before additional breadth is added.
