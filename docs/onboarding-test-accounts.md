# Onboarding Test Accounts

Use `scripts/create-onboarding-test-users.mjs` to create three confirmed Auth
identities in a local or staging Supabase project: one director, one teacher,
and one parent. The script creates no school, membership, invitation, template,
checklist, or assignment. This ensures onboarding begins only after the test
identity accepts a real invitation created inside the app.

Do not run the script against production. It uses service-role access and
creates confirmed Auth users.

## Run

Set these values in the shell or secret manager without committing them:

```sh
export SUPABASE_URL="https://YOUR_PROJECT.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="YOUR_LEGACY_SERVICE_ROLE_JWT"
export TEST_PASSWORD="REMOVED_TEST_PASSWORD"
export TEST_EMAIL_DOMAIN="test.fireflyfm.local"
export TEST_RUN_ID="onboarding-001"

npm run test-users:onboarding
```

`TEST_RUN_ID` is optional. When omitted, the script uses a timestamp. Use a new
run ID for every clean cohort. Re-running the same cohort resets its three Auth
users to the current `TEST_PASSWORD` and updates their names, but does not
change any memberships they obtained through accepted invitations.

## Test sequence

1. In HQ, publish Director Setup for the destination school and invite the test
   director email. Copy the one-time invitation link shown by the app.
2. Sign in as the test director, open the invitation link, and explicitly
   accept it. Only then should the director checklist appear.
3. Complete the director checklist, then approve it from an existing HQ account.
4. After the director has full access, publish the teacher and parent setup
   templates and invite their test emails. Each test identity must open and
   accept its own link.
5. Complete the teacher and parent checklists, then approve them as the director.
6. Confirm that each approved membership changes independently from
   `onboarding` to `full` and opens the normal workspace.

The accounts bypass email confirmation because the default test domain has no
mailbox. They do not bypass invitation acceptance. Creating an invitation alone
does not create a membership or checklist; the invitee must accept its token.
