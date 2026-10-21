#!/usr/bin/env bash
# Nightly backup: database (pg_dump custom format) + uploaded files (storage volume) + checksums.
# Keeps BACKUP_KEEP_DAYS days; optionally copies to BACKUP_OFFSITE with rsync.
#   bash deploy/scripts/backup.sh
source "$(dirname "$0")/common.sh"
[ -f "$DEPLOY_DIR/.env" ] && load_env "$DEPLOY_DIR/.env"

BACKUP_DIR="${BACKUP_DIR:-/opt/aact-hrms/backups}"
KEEP="${BACKUP_KEEP_DAYS:-30}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$BACKUP_DIR/$STAMP"
STORAGE_DIR="${STORAGE_DIR:-${INSTALL_DIR:-/opt/aact-hrms}/supabase/volumes/storage}"
mkdir -p "$DEST"
chmod 700 "$BACKUP_DIR" "$DEST"

log "database → $DEST/db.dump"
if [ -n "${PG_DUMP_CMD:-}" ]; then
  # shellcheck disable=SC2086
  $PG_DUMP_CMD -Fc --no-owner > "$DEST/db.dump"
else
  docker exec supabase-db pg_dump -U "${DB_USER:-postgres}" -d postgres -Fc --no-owner > "$DEST/db.dump"
fi
[ -s "$DEST/db.dump" ] || die "Database dump is empty"

if [ -d "$STORAGE_DIR" ]; then
  log "uploaded files → $DEST/storage.tar.gz"
  tar -czf "$DEST/storage.tar.gz" -C "$(dirname "$STORAGE_DIR")" "$(basename "$STORAGE_DIR")"
else
  warn "No storage folder at $STORAGE_DIR (skipped)"
fi

{ echo "created=$STAMP"; echo "host=$(hostname)"; echo "app_version=${APP_VERSION:-unknown}"
  psql_db -At -c "select 'employees=' || count(*) from hr.employees" 2>/dev/null || true
  psql_db -At -c "select 'last_migration=' || coalesce(max(name), '-') from aact_admin.migrations" 2>/dev/null || true; } > "$DEST/manifest.txt"
( cd "$DEST" && sha256sum ./* > SHA256SUMS )
log "checksums written"

find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name '20*' -mtime +"$KEEP" -print0 | while IFS= read -r -d '' old; do
  log "expired backup removed: $(basename "$old")"; rm -rf -- "$old"
done

if [ -n "${BACKUP_OFFSITE:-}" ]; then
  log "copy to $BACKUP_OFFSITE"
  rsync -a "$DEST" "$BACKUP_OFFSITE/" || die "Off-site copy failed — the local backup is still in $DEST"
fi
log "backup complete: $DEST ($(du -sh "$DEST" | cut -f1))"
