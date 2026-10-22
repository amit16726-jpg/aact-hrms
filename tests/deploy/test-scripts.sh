#!/usr/bin/env bash
# Exercises the server scripts against the local test PostgreSQL (port 5433) instead of Docker:
# migrations (twice — second run must do nothing), backup, restore test, damaged-backup detection.
set -euo pipefail
cd "$(dirname "$0")/../.."
H="-h ${PGHOST:-/tmp} -p ${PGPORT:-5433} -U postgres"
DB=aact_deploy_test
psql $H -q -d postgres -c "drop database if exists $DB" -c "create database $DB"
psql $H -q -d $DB -f tests/db/00_supabase_stub.sql >/dev/null
export PSQL_CMD="psql $H -d $DB" PG_DUMP_CMD="pg_dump $H -d $DB" PG_RESTORE_CMD="pg_restore $H"
export BACKUP_DIR="$(mktemp -d)" STORAGE_DIR="$(mktemp -d)/storage" CHECK_DB=aact_deploy_check
mkdir -p "$STORAGE_DIR/employee-docs" && echo test > "$STORAGE_DIR/employee-docs/a.pdf"

bash deploy/scripts/apply-migrations.sh | tail -1
out="$(bash deploy/scripts/apply-migrations.sh | tail -1)"; echo "$out"
[[ "$out" == *"done: 0 applied"* ]] || { echo "FAIL: second run applied migrations"; exit 1; }
psql $H -q -v ON_ERROR_STOP=1 -d $DB -f supabase/seed_masters.sql >/dev/null || { echo "FAIL: masters"; exit 1; }
psql $H -q -v ON_ERROR_STOP=1 -d $DB -f supabase/seed_masters.sql >/dev/null || { echo "FAIL: masters second run"; exit 1; }
[ "$(psql $H -At -d $DB -c "select count(*) from hr.departments")" = "30" ] || { echo "FAIL: masters departments"; exit 1; }

bash deploy/scripts/backup.sh | tail -1
D="$(ls -1d "$BACKUP_DIR"/20* | tail -1)"
[ -s "$D/db.dump" ] && [ -s "$D/storage.tar.gz" ] && grep -q '^employees=0$' "$D/manifest.txt" || { echo "FAIL: backup contents"; exit 1; }
bash deploy/scripts/restore.sh --verify "$D" | tail -1
echo tamper >> "$D/storage.tar.gz"
if bash deploy/scripts/restore.sh --verify "$D" >/dev/null 2>&1; then echo "FAIL: damaged backup not detected"; exit 1; fi
psql $H -q -d postgres -c "drop database if exists $DB" -c "drop database if exists $CHECK_DB"
rm -rf "$BACKUP_DIR"
echo "ALL DEPLOY SCRIPT TESTS PASSED"
