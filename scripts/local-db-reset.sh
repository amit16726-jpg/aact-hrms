#!/usr/bin/env bash
# Recreate the local test database and apply every migration in order.
set -euo pipefail
PSQL="psql -h ${PGHOST:-/tmp} -p ${PGPORT:-5433} -U postgres -v ON_ERROR_STOP=1 -q"
$PSQL -d postgres -c "drop database if exists aact_test" -c "create database aact_test"
$PSQL -d aact_test -f supabase/tests/00_supabase_stub.sql
for f in supabase/migrations/*.sql; do
  echo "apply $f"
  $PSQL -d aact_test -f "$f"
done
