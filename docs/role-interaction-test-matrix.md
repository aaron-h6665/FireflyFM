# FireflyFM Role Interaction Test Matrix

Use this checklist with a dedicated staging Supabase project when possible. If staging is not available, use clearly named test schools and accounts in the current project.

## Test Accounts

- HQ director: `hq.director@test.fireflyfm.local`
- Alpha director: `alpha.director@test.fireflyfm.local`
- Beta director: `beta.director@test.fireflyfm.local`
- Alpha teacher: `alpha.teacher@test.fireflyfm.local`
- Beta teacher: `beta.teacher@test.fireflyfm.local`
- Alpha parents: `alpha.parent1@test.fireflyfm.local`, `alpha.parent2@test.fireflyfm.local`
- Beta parents: `beta.parent1@test.fireflyfm.local`, `beta.parent2@test.fireflyfm.local`

## Setup

- Run the latest `supabase_schema.sql`.
- Run `node scripts/create-test-users.mjs` with the required Supabase service-role environment.
- Confirm the script reports an active Alpha membership for the Alpha director and deactivates any reused Default School membership.
- After creating the seeded assignment scenario, run `docs/assignment-feedback-loop-rls-tests.sql` as an admin for read-only relationship/RLS assertions.

## Workflow Checks

- HQ creates a school, assigns a director invite, and sees both schools on HQ Home.
- Director invite accepts only for the invited email and creates a `school_director` membership.
- HQ assigns a required director document; director uploads; HQ approves and flags a resubmission.
- Director assigns parent paperwork; parent uploads; director approves and flags.
- Parent adds a child; child is associated with that parent and the school default classroom.
- Parent sees only their own child records, documents, medication instructions, and progress records.
- Teacher sees children in their classroom/default classroom, but not another school's children.
- School director sees all children and submissions in their school only.
- HQ sees children across schools.
- Parent sends medicine, pickup, absence, and birthday notifications to school staff.
- Teacher/director sends weather, supplies, sickness, potty, bowel movement, birthday, incident, and event notifications to parents.
- Parent creates a medication instruction; teacher sees and acknowledges the task with dosage and confirmation.
- Run `select public.escalate_missed_medication_tasks();` after creating an overdue task; school director receives an escalation.
- Community posts, events, and albums created in School A do not appear in School B.
- A guessed child/document/storage path from another school fails through RLS or signed URL access.

## Assignment Feedback Loop

- HQ creates one Alpha assignment for the Alpha director and teacher. HQ sees it only under **Assignments I Manage** and has no acknowledgment control.
- Both recipients see the assignment in cross-school **My Work** and receive exactly one assignment notification.
- The Alpha director cannot read or review the teacher's attempt on the HQ-owned assignment.
- The Alpha director creates a separate assignment for the teacher and can Accept or Request Changes only on that assignment's latest pending attempt.
- The teacher cannot query the director's recipient row, attempts, attachments, comments, or recipient events.
- Opening the assignment clears Unread and its notifications; **Check After Reading** remains unchecked until explicitly selected.
- Request Changes fails without feedback, then succeeds with feedback, creates one notification, and enables one revised attempt.
- Reviewing a stale or already-reviewed attempt fails. Accept prevents another attempt unless the creator explicitly reopens the workflow.
- A creator included as a recipient can submit their own attempt and review other recipients, but their own user never appears in the review selector.
- Assignment comments and decisions notify only the other participant; views and acknowledgments create no notification.
- Scheduled publishing creates recipients and one deduplicated notification per recipient when `publish_due_assignments()` runs repeatedly.

## Regression Checks

- Sign out from regular Home and HQ Home; no SchoolWelcomeView flash appears.
- Switch tabs quickly while Home, Events, Notifications, Paperwork, Curriculum, Children, or Community is loading; no `Swift.CancellationError` banner appears.
- Force a real backend error, such as missing schema/RPC, and confirm the specific Supabase schema message still appears.
