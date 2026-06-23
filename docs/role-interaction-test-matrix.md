# FireflyFM Role Interaction Test Matrix

Use this checklist with a dedicated staging Supabase project when possible. If staging is not available, use clearly named test schools and accounts in the current project.

## Test Accounts

- HQ director: `hq-test@fireflyfm.test`
- School A director: `director-a@fireflyfm.test`
- School B director: `director-b@fireflyfm.test`
- School A teacher: `teacher-a@fireflyfm.test`
- School B teacher: `teacher-b@fireflyfm.test`
- School A parents: `parent-a1@fireflyfm.test`, `parent-a2@fireflyfm.test`
- School B parents: `parent-b1@fireflyfm.test`, `parent-b2@fireflyfm.test`

## Setup

- Run the latest `supabase_schema.sql`.
- Run `supabase_director_seed.sql` after replacing the HQ director email with the test HQ email.
- Sign in as HQ and create School A and School B.
- Invite each school director through HQ school creation or role invite.
- Each school director creates one teacher invite and two parent invites.
- Each parent adds one child.

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

## Regression Checks

- Sign out from regular Home and HQ Home; no SchoolWelcomeView flash appears.
- Switch tabs quickly while Home, Events, Notifications, Paperwork, Curriculum, Children, or Community is loading; no `Swift.CancellationError` banner appears.
- Force a real backend error, such as missing schema/RPC, and confirm the specific Supabase schema message still appears.
