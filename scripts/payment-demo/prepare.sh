#!/usr/bin/env bash
set -euo pipefail
# This project never uses the repository's linked Supabase project or credentials.
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
demo_root="/private/tmp/fireflyfm-payment-demo"
mkdir -p "$demo_root/supabase/migrations"
cp "$repo_root"/supabase/migrations/*.sql "$demo_root/supabase/migrations/"
mkdir -p "$demo_root/supabase/tests"
cp "$repo_root"/supabase/tests/*.sql "$demo_root/supabase/tests/"
cat > "$demo_root/supabase/config.toml" <<'TOML'
project_id = "fireflyfm-payment-demo"
[api]
port = 55421
schemas = ["public", "graphql_public"]
extra_search_path = ["public", "extensions"]
[db]
port = 55422
shadow_port = 55420
major_version = 17
[db.seed]
enabled = false
[studio]
port = 55423
[inbucket]
port = 55424
[auth]
site_url = "fireflyfm://auth-callback"
additional_redirect_urls = ["fireflyfm://**"]
[auth.email]
enable_confirmations = false
TOML
printf 'Prepared isolated project at %s\n' "$demo_root"
"$repo_root/node_modules/.bin/supabase" start --workdir "$demo_root"
if [[ "${1:-}" == "--reset" ]]; then
    "$repo_root/node_modules/.bin/supabase" db reset --local --workdir "$demo_root" --yes
    "$repo_root/node_modules/.bin/supabase" test db --workdir "$demo_root"
else
    "$repo_root/node_modules/.bin/supabase" db push --local --workdir "$demo_root" --yes
fi
# Explicit container target: no remote connection strings or destructive reset.
docker exec -i supabase_db_fireflyfm-payment-demo psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$repo_root/scripts/payment-demo/install.sql"
"$repo_root/node_modules/.bin/supabase" status --workdir "$demo_root" -o env > "$demo_root/local.env"
chmod 600 "$demo_root/local.env"
node "$repo_root/scripts/payment-demo/seed.mjs"
