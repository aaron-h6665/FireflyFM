# FireflyFM release gates

The work is organized as six reviewable change sets even when developed on one
integration branch. Do not merge or deploy a later gate before its prerequisites
are green.

| Gate | Scope | Required evidence |
|---|---|---|
| 1 | Baseline, migrations, schema snapshot, CI | Hosted parity approval; clean rebuild; baseline-to-head upgrade; pgTAP; empty diff |
| 2 | Onboarding and invitations | Existing-member cross-school invite; wrong-account retry; parent child creation while onboarding |
| 3 | Private media and policy audit | Zero-error manifests; checksum/reference counts; restore rehearsal; anonymous and cross-room denial |
| 4 | Membership context, theme, navigation | School-switch stale-data test; five tabs; light/dark token review |
| 5 | Home and recipient onboarding | Role dashboard checks; one-next-action flow; review-state journey |
| 6 | Community and supporting screens | Accessibility matrix; role smoke tests; release sign-off |

Backend reproducibility and privacy are hard gates. UI code may be reviewed in
parallel, but it must not be released until Gates 1–3 have production evidence.

Universal links remain disabled until an owned HTTPS host and association file
are supplied. Beta invitations continue to use `fireflyfm://` and manual codes.
