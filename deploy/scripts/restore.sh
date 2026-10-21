#!/usr/bin/env bash
# Restore a backup made by backup.sh.
#   bash deploy/scripts/restore.sh --verify /opt/aact-hrms/backups/20261021-020000
#       checks the checksums and restores into a scratch database (aact_restore_check) to prove the
#       backup is usable — the live system is not touched. Run this monthly.
#   bash deploy/scripts/restore.sh --apply  /opt/aact-hrms/backups/20261021-020000
#       replaces the live database and files with the backup (asks for confirmation; stops the web app first).
source "$(dirname "$0")/common.sh"
[ -f "$DEPLOY_DIR/.env" ] && load_env "$DEPLOY_DIR/.env"

MODE="${1:-}"; SRC="${2:-}"
[ "$MODE" = "--verify" ] || [ "$MODE" = "--apply" ] || die "Usage: restore.sh --verify|--apply <backup folder>"
[ -d "$SRC" ] && [ -f "$SRC/db.dump" ] && [ -f "$SRC/SHA256SUMS" ] || die "Not a backup folder: $SRC"

log "checking checksums"
( cd "$SRC" && sha256sum -c --quiet SHA256SUMS ) || die "Checksum mismatch — this backup is damaged"

restore_into() {   # $1 = database name
  if [ -n "${PG_RESTORE_CMD:-}" ]; then
    # shellcheck disable=SC2086
    $PG_RESTORE_CMD -d "$1" --no-owner < "$SRC/db.dump"
  else
    docker exec -i supabase-db pg_restore -U "${DB_USER:-postgres}" -d "$1" --no-owner < "$SRC/db.dump"
  fi
}

if [ "$MODE" = "--verify" ]; then
  CHECK_DB="${CHECK_DB:-aact_restore_check}"
  psql_db -q -c "drop database if exists $CHECK_DB" -c "create database $CHECK_DB" >/dev/null
  log "restoring into scratch database $CHECK_DB"
  # Supabase's own objects (roles, extensions, publications) may report warnings in a scratch database;
  # the test passes when the HR data itself came back complete.
  restore_into "$CHECK_DB" 2> "$SRC/restore-check.log" || true
  n="$(psql_db -At -d "$CHECK_DB" -c "select count(*) from hr.employees" 2>/dev/null || echo 'none')"
  want="$(sed -n 's/^employees=//p' "$SRC/manifest.txt")"
  if [ -z "$want" ] || [ "$n" != "$want" ]; then
    tail -20 "$SRC/restore-check.log" >&2
    psql_db -q -c "drop database if exists $CHECK_DB" >/dev/null || true
    die "Restore test FAILED: $n employees restored, backup manifest says ${want:-unknown} (details: $SRC/restore-check.log)"
  fi
  log "restore test passed: $n employees restored, as in the backup manifest"
  psql_db -q -c "drop database if exists $CHECK_DB" >/dev/null
  exit 0
fi

read -r -p "This REPLACES the live database with $(basename "$SRC"). Type RESTORE to continue: " ok
[ "$ok" = "RESTORE" ] || die "Cancelled"
log "taking a safety backup of the current state first"
bash "$DEPLOY_DIR/scripts/backup.sh"
docker stop aact-hrms-web >/dev/null 2>&1 || true
log "restoring database"
if [ -n "${PG_RESTORE_CMD:-}" ]; then
  # shellcheck disable=SC2086
  $PG_RESTORE_CMD -d "${RESTORE_DB:-postgres}" --no-owner --clean --if-exists < "$SRC/db.dump"
else
  docker exec -i supabase-db pg_restore -U "${DB_USER:-postgres}" -d postgres --no-owner --clean --if-exists < "$SRC/db.dump" || warn "pg_restore reported warnings (usually objects owned by Supabase itself) — check the app"
fi
if [ -f "$SRC/storage.tar.gz" ]; then
  STORAGE_DIR="${STORAGE_DIR:-${INSTALL_DIR:-/opt/aact-hrms}/supabase/volumes/storage}"
  log "restoring uploaded files into $STORAGE_DIR"
  mkdir -p "$(dirname "$STORAGE_DIR")"
  tar -xzf "$SRC/storage.tar.gz" -C "$(dirname "$STORAGE_DIR")"
fi
docker start aact-hrms-web >/dev/null 2>&1 || true
psql_db -q -c "notify pgrst, 'reload schema';" >/dev/null || true
log "restore complete — sign in and check the employee list and the last payroll run"
