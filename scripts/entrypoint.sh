#!/bin/sh
set -eu

info()  { echo "[entrypoint |  INFO] $*" >&2; }
error() { echo "[entrypoint | ERROR] $*" >&2; }

LITESTREAM_ENABLED="${LITESTREAM_ENABLED:-true}"
# Normalize to lowercase for safer comparisons (portable POSIX `sh` approach)
LITESTREAM_ENABLED="$(printf '%s' "$LITESTREAM_ENABLED" | tr '[:upper:]' '[:lower:]')"

# --- Headscale config check ---
if [ ! -f /etc/headscale/config.yaml ]; then
  error "No headscale config found at /etc/headscale/config.yaml"
  error "Mount your headscale config: -v ./config/headscale.yaml:/etc/headscale/config.yaml"
  exit 1
fi

if [ "$LITESTREAM_ENABLED" = "false" ]; then
  info "Litestream disabled. Starting headscale directly..."
  info "To enable litestream replication, set LITESTREAM_ENABLED=true and provide the required S3 environment variables."
  exec headscale serve
  exit 0
fi

# --- Validate required S3 vars ---
for var in S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY S3_BUCKET S3_ENDPOINT S3_REGION; do
  eval "val=\${$var:-}"
  if [ -z "$val" ]; then
    error "Missing required env var: $var"
    info "Skip litestream replication by setting LITESTREAM_ENABLED=false"
    exit 1
  fi
done

DB_PATH="${HEADSCALE_DB_PATH:-/var/lib/headscale/db.sqlite}"

# --- Export vars for litestream.yml substitution ---
export DB_PATH S3_BUCKET S3_ENDPOINT S3_REGION
export LITESTREAM_BACKUP_DIR="${LITESTREAM_BACKUP_DIR:-headscale-backups}"
export LITESTREAM_SYNC_INTERVAL="${LITESTREAM_SYNC_INTERVAL:-10s}"
export LITESTREAM_RETENTION="${LITESTREAM_RETENTION:-24h}"
export LITESTREAM_RETENTION_CHECK_INTERVAL="${LITESTREAM_RETENTION_CHECK_INTERVAL:-1h}"
export LITESTREAM_SNAPSHOT_INTERVAL="${LITESTREAM_SNAPSHOT_INTERVAL:-6h}"

# --- Restore from S3 if database is missing ---
info "Checking for existing database at ${DB_PATH}..."
if litestream restore -if-db-not-exists -if-replica-exists "${DB_PATH}"; then
  info "Restore check complete."
else
  info "No replica found or database already exists. Starting fresh."
fi

# --- Start headscale wrapped by litestream replication ---
info "Starting headscale with litestream replication..."
exec litestream replicate -exec "headscale serve"
