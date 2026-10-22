#!/usr/bin/env bash
# Upgrade to a new AACT HRMS version: unzip the new release over the repository folder, then run
#   sudo bash deploy/scripts/update.sh
# It backs up first, applies new migrations, updates the edge functions and rebuilds the web app and the translation service.
source "$(dirname "$0")/common.sh"
[ "$(id -u)" = "0" ] || die "Run as root (sudo)."
load_env "$DEPLOY_DIR/.env"
INSTALL_DIR="${INSTALL_DIR:-/opt/aact-hrms}"
log "1/4 backup before upgrading"; bash "$DEPLOY_DIR/scripts/backup.sh"
log "2/4 migrations"; bash "$DEPLOY_DIR/scripts/apply-migrations.sh"
log "3/4 edge functions (e-mail, translation) and their settings"
SB_DIR="$INSTALL_DIR/supabase"
cp "$DEPLOY_DIR/supabase-override.yml" "$SB_DIR/docker-compose.aact.yml"
for k in M365_TENANT_ID M365_CLIENT_ID M365_CLIENT_SECRET M365_SENDER MAIL_CRON_SECRET LIBRETRANSLATE_URL LIBRETRANSLATE_API_KEY; do
  [ -n "${!k:-}" ] && set_env "$SB_DIR/.env" "$k" "${!k}"
done
cp -a "$REPO_DIR/supabase/functions/." "$SB_DIR/volumes/functions/"
( cd "$SB_DIR" && docker compose up -d functions ) || warn "could not recreate the edge functions container"
docker restart supabase-edge-functions >/dev/null 2>&1 || true
log "4/4 web app and translation service (first start downloads the English/Arabic models)"; ( cd "$DEPLOY_DIR" && docker compose --env-file .env -f docker-compose.app.yml up -d --build )
log "updated to $(node -p "require('$REPO_DIR/package.json').version" 2>/dev/null || grep -m1 '"version"' "$REPO_DIR/package.json")"
