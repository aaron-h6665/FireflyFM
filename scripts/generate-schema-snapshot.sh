#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
snapshot="$repo_root/supabase_schema.sql"
temporary="$(mktemp)"
trap 'rm -f "$temporary"' EXIT

for migration in "$repo_root"/supabase/migrations/*.sql; do
  printf '\n-- Migration: %s\n\n' "$(basename "$migration")" >> "$temporary"
  sed -e 's/[[:space:]]*$//' "$migration" >> "$temporary"
done

if [[ "${1:-}" == "--check" ]]; then
  if ! cmp -s "$temporary" "$snapshot"; then
    echo "supabase_schema.sql is stale. Run scripts/generate-schema-snapshot.sh."
    exit 1
  fi
  exit 0
fi

cp "$temporary" "$snapshot"
