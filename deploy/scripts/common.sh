#!/usr/bin/env bash
# Shared helpers for the AACT HRMS server scripts. Sourced, not run.
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$DEPLOY_DIR/.." && pwd)"

log()  { printf '\033[1;34m[aact-hrms]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[aact-hrms] WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[aact-hrms] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Read KEY=VALUE lines (no shell execution): strips " # comments" and surrounding quotes.
load_env() {
  local file="$1" line key val
  [ -f "$file" ] || die "Missing $file"
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
    if [[ "$val" =~ ^\"(.*)\"[[:space:]]*(#.*)?$ ]]; then val="${BASH_REMATCH[1]}"
    elif [[ "$val" =~ ^\'(.*)\'[[:space:]]*(#.*)?$ ]]; then val="${BASH_REMATCH[1]}"
    else val="${val%%[[:space:]]#*}"; val="${val%"${val##*[![:space:]]}"}"; fi
    if [ -z "${!key+x}" ]; then export "$key=$val"; fi   # values already in the environment win
  done < "$file"
}

# Set KEY=VALUE in an env file (replace or append). Values are written as-is.
set_env() {
  local file="$1" key="$2" val="$3" tmp
  tmp="$(mktemp)"
  if grep -qE "^${key}=" "$file"; then
    K="$key" V="$val" awk 'BEGIN{FS="="; k=ENVIRON["K"]; v=ENVIRON["V"]} $1==k {print k "=" v; next} {print}' "$file" > "$tmp"
  else
    cp "$file" "$tmp"; printf '%s=%s\n' "$key" "$val" >> "$tmp"
  fi
  cat "$tmp" > "$file"; rm -f "$tmp"
}

# psql into the Supabase database container (override with PSQL_CMD for testing, e.g. "psql -h /tmp -p 5433 -U postgres -d aact_test").
psql_db() {
  if [ -n "${PSQL_CMD:-}" ]; then
    # shellcheck disable=SC2086
    PGOPTIONS='-c client_min_messages=warning' $PSQL_CMD -v ON_ERROR_STOP=1 "$@"
  else
    docker exec -i -e PGOPTIONS="-c client_min_messages=warning" supabase-db psql -U "${DB_USER:-postgres}" -d postgres -v ON_ERROR_STOP=1 "$@"
  fi
}
