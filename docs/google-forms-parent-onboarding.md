# Parent Google Forms onboarding

The first Google Forms integration is parent-only. A school director creates one
Google Form in the school Google account, adds the child/medical/emergency
questions and file-upload questions, then connects the form from the FireflyFM
Onboarding screen.

## Required deployment configuration

The `sync-google-parent-form` Edge Function requires these Supabase secrets:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `GOOGLE_FORMS_ACCESS_TOKEN` for the current test deployment

`GOOGLE_FORMS_ACCESS_TOKEN` is a temporary test bridge. Production must replace
it with per-director OAuth authorization and encrypted refresh-token storage.
The iOS app never receives this token.

The Google Forms API returns text answers and file-upload Drive IDs. The current
worker stores normalized response provenance and file metadata in
`google_form_imports` and `google_form_import_attachments`. Completing the
production slice still requires the Drive download/private-storage step,
question mapping UI, child matching/review actions, and approval materialization
into medical profiles, emergency contacts, medication instructions, and
`child_documents`.

## Form question contract

Keep question titles stable and maintain the mapping in
`google_form_question_mappings`. The intended field keys are:

`parent_email`, `child_first_name`, `child_last_name`, `child_birthdate`,
`relationship`, `allergies`, `immunization_status`, `physical_status`,
`dietary_notes`, `emergency_contacts`, `medicine_requirements`,
`immunization_document`, `physical_document`, `medication_authorization`, and
`additional_documents`.

Disconnecting a form only removes the FireflyFM connection. It does not delete
the Google Form or files in Google Drive.
