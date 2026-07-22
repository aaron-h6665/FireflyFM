# FireflyFM database guide

This guide assumes you have not used Docker, the Supabase CLI, or database
migrations before. The product is spelled **Supabase**.

## The short explanation

FireflyFM has two database environments:

| Environment | What it is | Who uses it | Can experiments hurt real users? |
|---|---|---|---|
| Local database | A temporary FireflyFM backend running on your Mac | Developers and automated tests | No |
| Hosted database | The real Supabase project on the internet | The beta or production app | Yes |

The local database is where migrations and privacy rules should be tested
first. The hosted database must only be changed after the local and CI checks
pass and a backup exists.

### What is Docker?

Docker Desktop is an application that runs small, isolated environments called
containers. For this project, those containers provide a private practice copy
of PostgreSQL, Supabase Authentication, Storage, and the Supabase dashboard on
your computer.

You do not need to build or manage the containers yourself. Keep Docker Desktop
open, and the Supabase CLI will start and stop the containers it needs.

Think of Docker as the empty practice building where a temporary FireflyFM
backend can run. Closing Docker does not change the hosted FireflyFM database.

### What is the Supabase CLI?

The Supabase command-line interface, or CLI, is a program used from Terminal.
It reads the files in the `supabase` folder and tells Docker how to create a
local FireflyFM backend. It also provides commands to rebuild that backend, run
database tests, and—only when explicitly linked—deploy migrations to the hosted
project.

Think of the CLI as the site manager: it reads the construction instructions
and asks Docker to build the practice database in the correct order.

```text
Migration files in this repository
             |
             v
        Supabase CLI
             |
             v
Docker containers on this Mac --> disposable local FireflyFM database

Hosted Supabase project ----------> separate; not changed by local commands
```

Official introductions:

- [Supabase local development](https://supabase.com/docs/guides/local-development)
- [Docker overview](https://docs.docker.com/get-started/docker-overview/)

## What is a database migration?

A migration is a numbered SQL file containing one set of database changes. It
is similar to a numbered renovation instruction: create this table, add this
column, or tighten this privacy policy.

Supabase applies migrations from the oldest timestamp to the newest. This lets
an empty database be created reliably and lets an older database be upgraded
without someone repeating changes manually in the Supabase dashboard.

For FireflyFM:

- `supabase/migrations` is the only editable source of database structure.
- `supabase/tests` contains privacy and behavior tests.
- `supabase/seed.sql` is for predictable local sample data.
- `supabase/config.toml` describes the local Supabase services.
- `supabase_schema.sql` is a generated, human-reviewable snapshot. Do not edit
  it directly.

Database rows belonging to real schools, families, children, or messages are
data. Migrations describe the structure and rules around that data; they are
not a replacement for a backup.

## One-time setup on a Mac

1. Install [Docker Desktop](https://docs.docker.com/desktop/setup/install/mac-install/).
2. Open Docker Desktop and wait until it reports that the engine is running.
3. Install the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started).
4. Open Terminal and move into this repository:

   ```sh
   cd "/path/to/FireflyFM"
   ```

5. Check that both tools are available:

   ```sh
   docker --version
   supabase --version
   docker info
   ```

`docker info` must finish successfully. If it says it cannot connect to the
Docker daemon, open Docker Desktop and try again.

The repository already contains `supabase/config.toml`, so do not run
`supabase init` for this project.

## Routine local verification

These commands operate on the disposable local database. Run them from the
FireflyFM repository directory.

### 1. Start the local backend

```sh
supabase start
```

On the first run, Docker downloads the required components. This can take
several minutes. Later starts should be faster. The command prints local URLs,
including the local Supabase Studio dashboard.

This command does **not** connect to or change the hosted database.

### 2. Rebuild the local database

```sh
supabase db reset --local
```

This deletes the disposable local database, applies every migration in order,
and then loads `supabase/seed.sql`. It is intentionally destructive to local
test data. It does not delete hosted data because `--local` is present.

A successful reset proves that a new developer or CI machine can reconstruct
the database from the repository alone.

### 3. Run database and privacy tests

```sh
supabase test db
```

This runs the pgTAP files under `supabase/tests`. They check important rules
such as onboarding-parent access, invitation privacy, anonymous access, room
participants, and private-media permissions.

### 4. Check the SQL for database errors

```sh
supabase db lint --local --level error
```

The linter catches certain invalid functions, references, and SQL problems.

### 5. Check the generated schema snapshot

```sh
bash scripts/generate-schema-snapshot.sh --check
```

This fails if `supabase_schema.sql` no longer matches the migration files. If a
migration was intentionally added or changed, regenerate the snapshot with:

```sh
bash scripts/generate-schema-snapshot.sh
```

Review and commit both the migration and updated snapshot together.

### 6. Stop the local backend when finished

```sh
supabase stop
```

This stops the local containers. It does not stop or alter the hosted Supabase
project.

## Adding a database change

1. Create a new timestamped migration:

   ```sh
   supabase migration new short_description
   ```

2. Edit the new SQL file under `supabase/migrations`.
3. Run the complete routine local verification above.
4. Regenerate `supabase_schema.sql`.
5. Open a pull request and wait for database and iOS CI to pass.

Do not make an unrecorded schema or policy change directly in the hosted
Supabase dashboard. If an emergency dashboard change is unavoidable, capture
the same change in a migration immediately and reconcile the schema before the
next release.

## Understanding the baseline

`20260721000000_baseline.sql` describes the database structure that existed
when migrations became the source of truth.

- A new empty database must execute the baseline.
- The existing hosted beta database already contains that structure.
- Therefore, the baseline must be marked as already applied on the hosted
  project only after the two structures are proven equivalent.

Running the baseline again against an existing hosted database is not the
adoption process. Marking it as applied records history; it does not execute the
baseline SQL again.

## Hosted database adoption — experienced operator only

> **Stop here if you are only doing local development.** Commands containing
> `--linked`, `db push`, or `migration repair` can affect the real FireflyFM
> backend. Never experiment with them.

Before adopting the baseline:

1. Schedule a coordinated beta maintenance window.
2. Create and verify a hosted database backup.
3. Link the CLI to the correct Supabase project and confirm its project ID.
4. Produce a schema-only dump of the hosted project.
5. Rebuild a fresh local database from the baseline.
6. Compare the hosted and local structures, including tables, functions,
   triggers, RLS policies, storage buckets, and grants.
7. Have a second reviewer approve the comparison and project identity.

Only after parity is confirmed should the operator record the baseline as
already applied:

```sh
supabase migration repair --linked --status applied 20260721000000
supabase db push --linked --dry-run
```

The dry run must show only migrations newer than the baseline. If it shows the
baseline or unexpected destructive SQL, stop and investigate. After review:

```sh
supabase db push --linked
```

Never run `supabase db reset --linked` against a project containing real data.

## Private-media migration

The private-media release moves legacy public attachments into private buckets.
The migration has three deliberately separate stages so each stage can be
reviewed before anything is deleted.

`SUPABASE_SERVICE_ROLE_KEY` is an administrative secret that bypasses normal
user permissions. Use it only on a secured operator machine, never paste it
into chat or logs, and never commit it or a migration manifest to Git.

### Stage 1: dry run — reads and reports only

```sh
SUPABASE_URL=https://PROJECT.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=... \
node scripts/migrate-private-media.mjs \
  --manifest=/secure/path/dry-run.json
```

The dry run inventories the legacy bucket and database references. It reports
what would move but does not copy, update, or delete objects.

Require all of the following before continuing:

- Zero errors.
- Zero missing source objects.
- Zero unreferenced source objects, or a separately reviewed explanation and
  recovery plan for each one.
- Source, reference, and discovered counts that reconcile.

### Stage 2: copy and verify — no source deletion

```sh
SUPABASE_URL=https://PROJECT.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=... \
node scripts/migrate-private-media.mjs --execute \
  --manifest=/secure/path/copy.json
```

For every referenced object, the tool:

1. Copies it to the private recovery bucket.
2. Copies it to its new private destination.
3. Compares SHA-256 checksums for the source, recovery copy, and destination.
4. Writes the new object path to the database.
5. Reads the database row back to verify the reference.

The original legacy object and URL remain at this stage. Test every media type
through real participant and nonparticipant accounts, then rehearse restoring
an object from `legacy_media_recovery`.

### Stage 3: cutover — destructive and approval required

```sh
SUPABASE_URL=https://PROJECT.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=... \
node scripts/migrate-private-media.mjs --execute --delete-source \
  --manifest=/secure/path/cutover.json
```

This verifies the copies again, removes the original legacy objects, and clears
legacy URL columns. Afterward, confirm that anonymous requests, old public URLs,
and old signed URLs no longer work.

Keep the private recovery copies for 30 days. Purging them is a separate,
destructive operation requiring written approval after the retention period.
The tool does not purge them automatically.

## What CI does automatically

The GitHub Actions workflow repeats the important checks on clean machines:

- Starts a local Supabase stack in Docker.
- Rebuilds from the baseline and upgrades it to the newest migration.
- Rebuilds a completely clean database at the newest version.
- Runs pgTAP/RLS tests and database linting.
- Fails if the generated snapshot or resulting schema drifts.
- Builds the iOS app and runs unit tests.

The weekly UI workflow also runs launch checks and the role-based navigation
matrix. CI validates repository changes; it does not replace hosted backups,
media recovery rehearsal, or release approval.

## Common beginner problems

| Symptom | Likely cause | What to do |
|---|---|---|
| `supabase: command not found` | Supabase CLI is not installed or Terminal has not reloaded its path | Follow the official CLI install guide, then open a new Terminal window |
| `Cannot connect to the Docker daemon` | Docker Desktop is closed or still starting | Open Docker Desktop, wait for it to finish starting, and run `docker info` |
| `supabase start` is slow the first time | Docker is downloading the Supabase components | Let it finish; later starts reuse the downloads |
| A port is already in use | Another local Supabase project or service is running | Run `supabase stop`, check the other project, then retry |
| Local sample data disappeared | `db reset --local` rebuilt the disposable database | Expected; add deterministic sample data to `supabase/seed.sql` if needed |
| Snapshot check fails | Migrations and `supabase_schema.sql` differ | Review the migration, then regenerate the snapshot |

If a command mentions a linked or remote project unexpectedly, stop rather
than guessing. Save its output without secrets and ask a maintainer to review
it.

## Release evidence to retain

Before enabling the redesigned client, retain:

- Hosted schema comparison and baseline-adoption approval.
- Clean rebuild and baseline-to-head CI logs.
- pgTAP/RLS role-matrix results.
- Private-media dry-run, copy, cutover, checksum, and recovery manifests.
- Recovery rehearsal evidence.
- iOS build, unit, launch, accessibility, and smoke-test results.
