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
- After publishing and accepting the seeded parent template, run `docs/onboarding-template-rls-tests.sql` for access-gate, reviewer-hierarchy, shared-child, hashed-invite, and cross-school assertions.

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

- HQ keeps **One** selected and creates an assignment for Alpha only; Beta receives no assignment or notification.
- HQ chooses Alpha and Beta, then repeats with **All**. Each target school receives its own school-scoped assignment, eligible recipient list, notification, review history, and private material path.
- A selected school with no eligible recipient for the chosen role is named in the composer and publishing remains disabled until the audience or school selection is corrected.
- If one school fails during a multi-school publish, retry creates only the failed school assignment and does not duplicate assignments already created for the other schools.
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

## Role Onboarding Templates

- HQ opens **My Schools → Alpha → Operations → Director Setup**, creates a requirement with only a title, previews it, and publishes it.
- Invite Director remains disabled until the director template is published. The invite works only for the bound email, can be used once, and the database stores only its SHA-256 hash.
- The approved Alpha director opens **Home → Workspaces → Onboarding**, switches between Parents and Teachers, and sees the same builder actions as HQ.
- Editing a published template creates a new draft. Publishing applies it to recipients still in setup and to later invites, while preserving matching approved or waived steps and completed payment history.
- Reorder, duplicate, remove, and Undo all preserve contiguous positions. An unused draft can be deleted; a published/used template can only be archived.
- Archiving prevents a new role invitation from being accepted and never changes an active recipient's version or access state.
- Preview uses sample status and child data, disables upload/download mutations, and never queries real submissions or comments.
- A parent **Each Child** requirement creates one assignment for the child. Both authorized guardians can open and submit it, see the same review state, and unlock together after approval or waiver.
- A reviewer cannot approve or waive their own work. HQ reviews directors; only the school's full-access director reviews parents and teachers.
- Request Changes requires actionable feedback. Resubmission creates a new immutable attempt; approval or a reasoned waiver is the only path to satisfying the requirement.
- While `access_state = onboarding`, setup assignments and private linked files remain accessible, while operational newsletters, events, community, chats, and unrelated assignments remain blocked by RLS.
- Completing setup in Alpha changes only the Alpha membership to `full`; the same user's Beta membership remains independently gated.
- Configure `RoleInviteUniversalBaseURL` with the production HTTPS invite route and associated-domain/AASA deployment. Confirm the custom `fireflyfm://` link remains available as the manual fallback.
- Keep payment requirements out of published V1 templates. The reserved `payment` requirement type remains dormant until idempotent provider webhooks, receipts, and invoices are enabled.

## Regression Checks

- Sign out from regular Home and HQ Home; no SchoolWelcomeView flash appears.
- Switch tabs quickly while Home, Events, Notifications, Paperwork, Curriculum, Children, or Community is loading; no `Swift.CancellationError` banner appears.
- Force a real backend error, such as missing schema/RPC, and confirm the specific Supabase schema message still appears.
