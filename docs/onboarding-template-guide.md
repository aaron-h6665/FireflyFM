# Onboarding Template Guide

FireflyFM onboarding templates are intentionally small: each requirement needs only a title. Instructions and paperwork are optional. Audience, reviewer, access blocking, assignment category, and school are filled in from the screen where the builder was opened.

## Where to manage templates

### FireflyFM HQ

Open **HQ Home → My Schools → select a school → Operations → Director Setup**.

When adding a school, create the school first. FireflyFM then directs HQ to this Director Setup location; a director link cannot be created or accepted until the template is published.

- **Manage Template** edits that school's director requirements.
- **Preview** shows the real recipient layout with sample data and disabled controls.
- **Invite Director** becomes available only after publication.
- **Review Submissions** opens the assignment review workflow.

HQ always manages the School Director role at the selected school. There is no recipient/reviewer selector: FireflyFM HQ is the reviewer.

### Approved school director

Open **Home → Workspaces → Onboarding**, then select **Parents** or **Teachers**.

The actions and builder match the HQ experience. The current school and selected segment determine the recipients, and the approved school director is automatically the reviewer.

## Create and publish a template

1. Select **Manage Template**, then **Add Requirement**.
2. Enter a title such as “Signed enrollment agreement.”
3. Optionally add instructions and one or more paperwork files.
4. For a parent template, choose **Parent** for one family-level task or **Each Child** for a separate shared child task.
5. Select **Save**, arrange the list if needed, and use **Preview as Recipient**.
6. Select **Publish Changes**. Publishing validates titles and successful attachment uploads.

Edits to a published template create a new draft version. People already onboarding keep their assigned version. While the draft is being edited, invitations continue using the current published version; invitations receive the new version only after **Publish Changes**.

Use **Delete Draft** only for an unused draft. Published or used versions remain in the audit history and can only be archived. Archiving pauses invitations; it does not unlock anyone or change existing work.

## Recipient workflow

The Setup Checklist groups work into **Needs You**, **Waiting on Review**, and **Complete**. Open a requirement to download paperwork, attach completed files, add a message, and submit. If changes are requested, read the reviewer feedback and submit a revised attempt from the same requirement.

Only **Approved** and **Waived** satisfy a requirement. A waiver requires the authorized reviewer to record a reason. Parent **Each Child** work is shared by authorized guardians, including its submission and review state.

Template paperwork and submissions live in private storage. A recipient can open only files linked to an assignment they can view; the authorized reviewer can access them through the same assignment. Signed URLs are short-lived.

## Invitation delivery and production links

Invitation secrets are email-bound, single-use, returned to the inviter once, and stored only as SHA-256 hashes. If a link is lost, create a replacement; doing so revokes the prior pending link.

Set the app Info value `RoleInviteUniversalBaseURL` to the production HTTPS route, for example `https://your-domain.example/role-invite`. The domain must serve the Apple App Site Association file and be added as an associated domain for the production app. Until that deployment is configured, FireflyFM shares the manual `fireflyfm://role-invite` fallback.

Apple Developer Program membership is not required for local simulator development. The current program fee is **$99 per year**, and membership is needed for TestFlight/App Store distribution and production capabilities such as associated domains and push notifications.

## Future payments and signatures

V1 uses download, sign, and upload. The original paperwork, every submitted revision, reviewer feedback, and decisions remain in the assignment audit history. The schema reserves a `payment` requirement type, but it should not be published until provider webhooks, idempotency, invoices, and receipts are enabled. A future e-signature or payment provider should connect through the requirement/assignment boundary rather than replacing the checklist.
