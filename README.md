<p align="center">
  <img src="FireflyFM/Core/Resources/Assets.xcassets/Logo.imageset/Logo.png" alt="FireflyFM logo" width="120">
</p>

<h1 align="center">FireflyFM</h1>

<p align="center">
  A role-aware iOS workspace for childcare centers, staff, and families.
</p>

<p align="center">
  <a href="https://github.com/aaron-h6665/FireflyFM/actions/workflows/verify.yml"><img src="https://github.com/aaron-h6665/FireflyFM/actions/workflows/verify.yml/badge.svg" alt="Verify status"></a>
  <img src="https://img.shields.io/badge/platform-iOS-000000?logo=apple" alt="iOS">
  <img src="https://img.shields.io/badge/UI-SwiftUI-F05138?logo=swift" alt="SwiftUI">
  <img src="https://img.shields.io/badge/backend-Supabase-3FCF8E?logo=supabase&logoColor=white" alt="Supabase">
</p>

FireflyFM brings the daily work of a childcare organization into one app. Families, teachers, school directors, and headquarters staff receive different tools and data access based on their responsibilities and school memberships.

> [!NOTE]
> FireflyFM is under active beta development. The repository includes production-facing configuration and child-sensitive workflows; do not use real records for development or assume that a local build is connected to a disposable backend.

## What it supports

- Role-specific Today dashboards and workspaces for parents, teachers, school directors, and HQ directors
- Family and school messaging with structured care updates, replies, and private media
- Child rosters, profiles, attendance, guardian QR check-in, and family requests
- Events, newsletters, community posts, albums, and notifications
- Training, curriculum, and other assignment workflows with file attachments
- Paperwork, onboarding, Google Forms review, corrections, and document submission
- Manual Zelle invoice, payment-report, review, and receipt workflows
- Multi-school administration with school-scoped access and cross-school HQ oversight
- On-device child summaries using Apple frameworks

## Roles

| Role | Primary experience |
| --- | --- |
| Parent | Child records, family requests, messages, paperwork, payments, community updates, and QR check-in |
| Teacher | Attendance, classroom care updates, child context, training, paperwork, and school communication |
| School director | Rosters, attendance, people and access, assignments, paperwork, billing, events, and community management |
| HQ director | Cross-school operations, reporting, paperwork, billing oversight, schools, and selected communications |

Authorization is enforced in both the app's access policies and the Supabase database/RPC layer. Changes to a role boundary should include client behavior, server-side enforcement, and regression tests.

## Technology

| Area | Technology |
| --- | --- |
| App | Swift, SwiftUI, UIKit integrations, async/await |
| Backend | Supabase Auth, PostgreSQL, Row Level Security, Storage, Realtime, and Edge Functions |
| Messaging and media | MessageKit, SDWebImage, SDWebImageSwiftUI |
| Integrations | Google Forms, Google Drive Picker, Apple Push Notification service |
| Verification | XCTest/XCUITest, pgTAP, Deno tests, GitHub Actions |

## Repository layout

```text
FireflyFM/                 iOS application source
  Core/Features/           Product areas such as attendance, chat, and paperwork
  Core/Model/              Shared domain and access models
  Core/Service/            Supabase and workflow services
  Core/Views/AppShell/     Role-aware navigation and dashboards
FireflyFMTests/            Unit and policy tests
FireflyFMUITests/          Launch and role-matrix UI smoke tests
supabase/
  migrations/              Versioned database changes
  functions/               Edge Functions and their tests
  tests/                   pgTAP authorization and behavior tests
docs/                      Architecture, operations, privacy, and release guides
scripts/                   Schema, test-user, media, and demo utilities
```

## Getting started

### Requirements

- macOS with an Xcode release that supports the project's iOS 26.5 deployment target
- Git
- An iOS Simulator
- An authorized FireflyFM account or invite for authenticated app flows
- Docker Desktop and Node.js for local backend work

### Run the iOS app

1. Clone the repository:

   ```sh
   git clone https://github.com/aaron-h6665/FireflyFM.git
   cd FireflyFM
   ```

2. Open `FireflyFM.xcodeproj` in Xcode. Swift Package Manager will resolve the app dependencies.
3. Select the `FireflyFM` scheme and an available iPhone Simulator.
4. Build and run.

The standard app configuration connects to the hosted backend configured in `AppConfiguration.swift`. Building in Debug does **not** make that backend local. Use only approved test accounts and data.

For the workspace beta, use the shared `FireflyFM Beta` scheme and follow [the workspace beta guide](docs/workspace-beta.md).

### Start the local Supabase stack

Local database development is separate from a normal app run:

```sh
npm install
npx supabase start
npx supabase db reset --local
npx supabase test db
npx supabase db lint --local --level error
bash scripts/generate-schema-snapshot.sh --check
```

Docker must be running. `db reset --local` deletes only the disposable local database, reapplies every migration, and reloads `supabase/seed.sql`. See [the database guide](docs/database-migrations.md) before creating or deploying a migration.

> [!CAUTION]
> Commands containing `--linked`, `db push`, or `migration repair` can change the hosted project. They are intentionally outside the normal local workflow.

## Testing

Build the app without code signing:

```sh
xcodebuild \
  -project FireflyFM.xcodeproj \
  -scheme FireflyFM \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/FireflyFMDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Run the unit tests, replacing the Simulator name if necessary:

```sh
xcodebuild \
  -project FireflyFM.xcodeproj \
  -scheme FireflyFM \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /private/tmp/FireflyFMDerivedData \
  CODE_SIGNING_ALLOWED=NO test \
  -only-testing:FireflyFMTests
```

Pull requests and pushes to `main` run the iOS build, unit tests, migration rebuilds, pgTAP suites, database linting, and schema-drift checks. A scheduled workflow also exercises launch and role-matrix UI smoke tests.

## Isolated payment demo

The Simulator-only payment demo uses its own local Supabase project, synthetic accounts, and a simulated bank ledger. It never moves money and is the supported way to exercise the end-to-end payment feedback loop without touching the hosted project.

Follow [PAYMENT_BETA_TESTING.md](PAYMENT_BETA_TESTING.md) for setup, scenarios, test accounts, and safety boundaries.

## Security and privacy

FireflyFM handles child, family, attendance, health, communication, media, paperwork, and payment-related records. Contributors should:

- Keep access school-scoped, role-scoped, and relationship-scoped.
- Route sensitive mutations through tested services or RPCs instead of direct table writes.
- Add positive and denial coverage for RLS, storage paths, and cross-school access.
- Never commit service-role keys, database passwords, OAuth client secrets, or real user data.
- Treat local test results, hosted deployment, device validation, and release approval as separate evidence.

The documents under [`docs/legal`](docs/legal/) are drafts, not legal advice or publish-ready policies. Review [the data classification](docs/data-classification.md), [release gates](docs/release-gates.md), and [privacy/App Store checklist](docs/ai-privacy-and-app-store-release-checklist.md) before changing data handling, identity, payments, AI, OAuth scopes, or providers.

## Working on the project

1. Create a focused branch from the current default branch.
2. Keep UI capability checks and backend authorization changes in sync.
3. Add or update Swift, pgTAP, and Edge Function tests appropriate to the change.
4. Rebuild the local database from migrations and verify the schema snapshot.
5. Open a pull request with separate notes for local, hosted, Simulator/device, and release verification.

Useful references:

- [Database migrations](docs/database-migrations.md)
- [Role interaction test matrix](docs/role-interaction-test-matrix.md)
- [External beta hardening plan](docs/external-beta-hardening-plan.md)
- [Google Forms parent onboarding](docs/google-forms-parent-onboarding.md)
- [Legal release and publishing checklist](docs/legal/release-and-publishing-checklist.md)

## License

No open-source license is currently included. Unless a license is added, permission to view the source does not grant permission to copy, modify, or distribute it.
