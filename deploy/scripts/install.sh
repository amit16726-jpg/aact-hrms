#!/usr/bin/env bash
# First installation on the company server (Ubuntu 24.04 LTS, 4 CPU / 8 GB RAM / 100 GB disk or more).
# Run as root from the unzipped repository:   sudo bash deploy/scripts/install.sh
# Steps: Docker check → self-hosted Supabase (pinned release) → secrets → database migrations →
#        e-mail function → web app with TLS → nightly backup.  Safe to re-run: finished steps are skipped.
source "$(dirname "$0")/common.sh"

SUPABASE_REF="${SUPABASE_REF:-self-hosted/v0.8.3}"     # tested release of the Supabase docker setup
[ "$(id -u)" = "0" ] || die "Run as root (sudo)."
[ -f "$DEPLOY_DIR/.env" ] || { cp "$DEPLOY_DIR/env.server.example" "$DEPLOY_DIR/.env"; chmod 600 "$DEPLOY_DIR/.env";
  die "Created deploy/.env — fill DOMAIN, PUBLIC_URL and SMTP_*, then run this again."; }
load_env "$DEPLOY_DIR/.env"
: "${DOMAIN:?DOMAIN missing in deploy/.env}"; : "${PUBLIC_URL:?PUBLIC_URL missing in deploy/.env}"
INSTALL_DIR="${INSTALL_DIR:-/opt/aact-hrms}"; CERT_DIR="${CERT_DIR:-$INSTALL_DIR/certs}"
SB_DIR="$INSTALL_DIR/supabase"

log "1/7 checking Docker"
command -v docker >/dev/null || die "Docker is not installed. Install Docker Engine + Compose plugin: https://docs.docker.com/engine/install/ubuntu/"
docker compose version >/dev/null || die "Docker Compose plugin missing (apt install docker-compose-plugin)"
for c in git openssl rsync sha256sum; do command -v "$c" >/dev/null || die "Install $c first (apt install $c)"; done
mkdir -p "$INSTALL_DIR" "$CERT_DIR" "${BACKUP_DIR:-$INSTALL_DIR/backups}"

log "2/7 Supabase ($SUPABASE_REF)"
if [ ! -f "$SB_DIR/docker-compose.yml" ]; then
  tmp="$(mktemp -d)"
  git clone -q --depth 1 --branch "$SUPABASE_REF" --filter=blob:none --sparse https://github.com/supabase/supabase.git "$tmp/sb"
  git -C "$tmp/sb" sparse-checkout set docker
  mkdir -p "$SB_DIR"; cp -a "$tmp/sb/docker/." "$SB_DIR/"; rm -rf "$tmp"
  cp "$SB_DIR/.env.example" "$SB_DIR/.env"; chmod 600 "$SB_DIR/.env"
  ( cd "$SB_DIR" && sh utils/generate-keys.sh --update-env >/dev/null )
  log "secrets generated in $SB_DIR/.env (keep a copy in the company password safe)"
fi
set_env "$SB_DIR/.env" SUPABASE_PUBLIC_URL "$PUBLIC_URL"
set_env "$SB_DIR/.env" API_EXTERNAL_URL "$PUBLIC_URL"
set_env "$SB_DIR/.env" SITE_URL "$PUBLIC_URL"
set_env "$SB_DIR/.env" ADDITIONAL_REDIRECT_URLS "$PUBLIC_URL/**"
set_env "$SB_DIR/.env" DISABLE_SIGNUP "true"
set_env "$SB_DIR/.env" ENABLE_EMAIL_AUTOCONFIRM "false"
set_env "$SB_DIR/.env" ENABLE_PHONE_SIGNUP "false"
set_env "$SB_DIR/.env" ENABLE_ANONYMOUS_USERS "false"
set_env "$SB_DIR/.env" PGRST_DB_SCHEMAS "public"
if [ -z "${MAIL_CRON_SECRET:-}" ]; then MAIL_CRON_SECRET="$(openssl rand -hex 24)"; set_env "$DEPLOY_DIR/.env" MAIL_CRON_SECRET "$MAIL_CRON_SECRET"; fi
set_env "$SB_DIR/.env" FUNCTIONS_VERIFY_JWT "false"   # send-mail checks MAIL_CRON_SECRET itself
for k in SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASS SMTP_ADMIN_EMAIL SMTP_SENDER_NAME M365_TENANT_ID M365_CLIENT_ID M365_CLIENT_SECRET M365_SENDER MAIL_CRON_SECRET; do
  [ -n "${!k:-}" ] && set_env "$SB_DIR/.env" "$k" "${!k}"
done
cp "$DEPLOY_DIR/supabase-override.yml" "$SB_DIR/docker-compose.aact.yml"
set_env "$SB_DIR/.env" COMPOSE_FILE "docker-compose.yml:docker-compose.aact.yml"
mkdir -p "$SB_DIR/volumes/functions"
cp -a "$REPO_DIR/supabase/functions/." "$SB_DIR/volumes/functions/"
( cd "$SB_DIR" && docker compose pull -q && docker compose up -d )

log "3/7 waiting for the database"
for i in $(seq 1 60); do docker exec supabase-db pg_isready -U postgres >/dev/null 2>&1 && break; sleep 5; [ "$i" = 60 ] && die "Database did not start"; done
sleep 10

log "4/7 database migrations"
bash "$DEPLOY_DIR/scripts/apply-migrations.sh"

log "5/7 TLS certificate"
if [ ! -f "$CERT_DIR/fullchain.pem" ] || [ ! -f "$CERT_DIR/privkey.pem" ]; then
  warn "No certificate in $CERT_DIR — creating a self-signed one for $DOMAIN (browsers will warn; replace it with the company certificate)."
  openssl req -x509 -nodes -newkey rsa:2048 -days 825 -subj "/CN=$DOMAIN" -addext "subjectAltName=DNS:$DOMAIN" \
    -keyout "$CERT_DIR/privkey.pem" -out "$CERT_DIR/fullchain.pem" 2>/dev/null
  chmod 600 "$CERT_DIR/privkey.pem"
fi

log "6/7 web app"
anon="$(grep -E '^ANON_KEY=' "$SB_DIR/.env" | cut -d= -f2-)"
[ -n "$anon" ] || die "ANON_KEY not found in $SB_DIR/.env"
set_env "$DEPLOY_DIR/.env" ANON_KEY "$anon"
export ANON_KEY="$anon" CERT_DIR
( cd "$DEPLOY_DIR" && docker compose --env-file .env -f docker-compose.app.yml up -d --build )

log "7/7 nightly backup (02:00) and monthly restore test"
sed -e "s#__REPO__#$REPO_DIR#g" -e "s#__BACKUPS__#${BACKUP_DIR:-$INSTALL_DIR/backups}#g" "$DEPLOY_DIR/cron/aact-hrms" > /etc/cron.d/aact-hrms
chmod 644 /etc/cron.d/aact-hrms

log "installed. Open $PUBLIC_URL — the first person to sign up through the set-up page becomes the administrator."
log "Supabase Studio (database admin) is only on the server: ssh -L 8000:127.0.0.1:8000 <server>, then http://localhost:8000"
