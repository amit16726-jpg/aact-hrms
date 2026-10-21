#!/usr/bin/env bash
# Upgrade to a new AACT HRMS version: unzip the new release over the repository folder, then run
#   sudo bash deploy/scripts/update.sh
# It backs up first, applies new migrations, copies the e-mail function and rebuilds the web app.
source "$(dirname "$0")/common.sh"
[ "$(id -u)" = "0" ] || die "Run as root (sudo)."
load_env "$DEPLOY_DIR/.env"
INSTALL_DIR="${INSTALL_DIR:-/opt/aact-hrms}"
log "1/4 backup before upgrading"; bash "$DEPLOY_DIR/scripts/backup.sh"
log "2/4 migrations"; bash "$DEPLOY_DIR/scripts/apply-migrations.sh"
log "3/4 e-mail function"; cp -a "$REPO_DIR/supabase/functions/." "$INSTALL_DIR/supabase/volumes/functions/"
docker restart supabase-edge-functions >/dev/null 2>&1 || true
log "4/4 web app"; ( cd "$DEPLOY_DIR" && docker compose --env-file .env -f docker-compose.app.yml up -d --build )
log "updated to $(node -p "require('$REPO_DIR/package.json').version" 2>/dev/null || grep -m1 '"version"' "$REPO_DIR/package.json")"
