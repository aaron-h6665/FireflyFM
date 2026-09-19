# Repository instructions

## Commits
After outputting code changes, provide a concise commit message and a copyable
`git add` command listing the specific changed files. Keep unrelated changes out.

## Privacy and new files
Before creating files or proposing a commit, consider whether the content belongs
in source control. Never commit real personal records, customer/child data, private
contact details, account exports, passwords (including test passwords), tokens,
service-role keys, signing keys, authenticated URLs, or raw sensitive responses.
Use synthetic identities and reserved example domains in fixtures and documentation.
Use portable paths rather than personal home-directory paths.

Keep credentials in environment variables or protected, ignored local files.
Test tools must require supplied passwords or generate fresh local passwords;
never use a hardcoded fallback or print credentials, sessions, or raw auth responses.
Keep reusable sanitized test scripts tracked; keep account/password lists, editor
backups, local reports, and private datasets under ignored `private-data/` or
`local-artifacts/` directories. Templates must contain placeholders only.

When creating a new kind of private/generated file, add a narrowly scoped rule to
`.gitignore` at the same time. Verify with `git check-ignore`. Adding a rule does
not untrack existing files: remove already tracked private artifacts from the index
while preserving local copies when appropriate. Review the staged diff and tracked
file list for secrets and personal information before committing or pushing.
Do not ignore all tests, SQL, JSON, or documentation to conceal a sensitive file.
Public client configuration such as Supabase publishable keys may remain tracked;
backend authorization must still enforce access.

A current-file cleanup does not erase Git history. Report historical exposure,
require rotation of exposed credentials still in use, and get explicit approval
before rewriting published history or force-pushing. Inspect both main and backup
branches when auditing old exposure. Use a verified GitHub noreply commit identity
when the user requests private commit attribution; never invent that identity.
