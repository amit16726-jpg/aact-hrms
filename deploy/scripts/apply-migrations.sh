#!/usr/bin/env bash
# Apply database migrations in order. Each file runs in one transaction and is recorded in
# aact_admin.migrations, so running this again only applies new files. Use after every upgrade.
#   bash deploy/scripts/apply-migrations.sh            # apply new migrations
#   bash deploy/scripts/apply-migrations.sh --status   # list applied / pending
source "$(dirname "$0")/common.sh"

MIG_DIR="${MIG_DIR:-$REPO_DIR/supabase/migrations}"
[ -d "$MIG_DIR" ] || die "No migrations folder at $MIG_DIR"

psql_db -q -c "create schema if not exists aact_admin;
  create table if not exists aact_admin.migrations (version text primary key, name text not null, checksum text not null, applied_at timestamptz not null default now());
  revoke all on schema aact_admin from public;" >/dev/null

applied="$(psql_db -At -c "select version || ' ' || checksum from aact_admin.migrations")"
pending=0; done_n=0
for f in "$MIG_DIR"/*.sql; do
  name="$(basename "$f" .sql)"; version="${name%%_*}"
  sum="$(sha256sum "$f" | cut -c1-16)"
  prev="$(printf '%s\n' "$applied" | awk -v v="$version" '$1==v {print $2}')"
  if [ -n "$prev" ]; then
    [ "$prev" = "$sum" ] || warn "$name was changed after it was applied (checksum $prev → $sum). Not re-applied."
    continue
  fi
  pending=$((pending + 1))
  if [ "${1:-}" = "--status" ]; then echo "pending  $name"; continue; fi
  log "apply $name"
  { cat "$f"; printf '\ninsert into aact_admin.migrations(version, name, checksum) values (%s, %s, %s);\n' \
      "'$version'" "'$name'" "'$sum'"; } | psql_db -q -1 -f - >/dev/null
  done_n=$((done_n + 1))
done
if [ "${1:-}" = "--status" ]; then
  psql_db -At -c "select 'applied  ' || name || '  ' || to_char(applied_at, 'YYYY-MM-DD HH24:MI') from aact_admin.migrations order by version"
  log "$pending pending"; exit 0
fi
psql_db -q -c "notify pgrst, 'reload schema';" >/dev/null || true
log "done: $done_n applied, $(printf '%s\n' "$applied" | grep -c . || true) were already in place"
