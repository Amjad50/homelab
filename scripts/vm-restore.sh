#!/usr/bin/env bash
# scripts/vm-restore.sh
# Run inside the VM as root after first boot.
# Restores all data from Restic B2 backup, imports DB dumps, starts all services.
# Usage: bash /etc/homelab-scripts/vm-restore.sh
set -euo pipefail

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
die()  { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; exit 1; }
warn() { echo "[$(date '+%H:%M:%S')] WARNING: $*" >&2; }

log "Starting homelab data restore on $(hostname)"
[[ $EUID -eq 0 ]] || die "Must be run as root. Use: sudo $0"

# ---------------------------------------------------------------------------
# 0. Stop all running containers before touching /mnt/storage
# ---------------------------------------------------------------------------
log "Stopping all services in parallel..."
compose-manage stop
log "All services stopped."

# ---------------------------------------------------------------------------
# 1. Verify Restic repository is reachable
# ---------------------------------------------------------------------------
# restic-homelab-daily is a NixOS-generated wrapper with all credentials built in
RESTIC="restic-homelab-daily"
command -v "$RESTIC" >/dev/null 2>&1 || die "$RESTIC not found — is this the home-vm NixOS system?"

log "Checking Restic repository connectivity..."
$RESTIC snapshots >/dev/null || die "Cannot reach Restic repository. Check credentials and network."
log "Repository OK — listing latest snapshot:"
$RESTIC snapshots latest

# ---------------------------------------------------------------------------
# 2. Restore /mnt/storage from the latest Restic snapshot
#    (exclude /tmp/db-dumps-daily — we restore DBs via SQL dumps below)
# ---------------------------------------------------------------------------
log "Restoring from latest Restic snapshot..."
mkdir -p /tmp/db-dumps-daily
$RESTIC restore latest \
  --target / \
  --exclude "/mnt/storage/immich" \
  --tag homelab
log "Restore complete."

# ---------------------------------------------------------------------------
# 4+5. For each DB: start container, wait, restore, done
# ---------------------------------------------------------------------------
DUMP_DIR="/tmp/db-dumps-daily"

restore_db() {
  local compose_svc="$1"      # folder name under /opt/docker-services
  local compose_container="$2" # service name inside the compose file (for docker-compose up)
  local container="$3"         # actual docker container name (for docker exec)
  local db_name="$4"           # database name inside postgres
  local db_user="$5"           # postgres user
  local dump_name="${container%-db}"  # mirrors backup-prepare.sh naming: strip -db suffix
  local dump_file="$DUMP_DIR/${dump_name}.sql"

  log "[$compose_svc] Starting DB container..."
  compose-manage start-container "$compose_svc" "$compose_container" || warn "[$compose_svc] Failed to start container"

  if [[ ! -f "$dump_file" ]]; then
    warn "[$compose_svc] Dump not found: $dump_file — skipping restore"
    return
  fi

  log "[$compose_svc] Waiting for postgres to be ready..."
  local retries=20
  until docker exec "$container" pg_isready -U "$db_user" -d "$db_name" -q 2>/dev/null; do
    retries=$((retries - 1))
    [[ $retries -gt 0 ]] || die "[$compose_svc] Timed out waiting for $container"
    sleep 3
  done

  log "[$compose_svc] Restoring $db_name..."
  docker exec "$container" psql -U "$db_user" -c "
    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE datname = '$db_name' AND pid <> pg_backend_pid();
  " postgres >/dev/null 2>&1 || true
  docker exec "$container" psql -U "$db_user" -c "DROP DATABASE IF EXISTS \"$db_name\";" postgres
  docker exec "$container" psql -U "$db_user" -c "CREATE DATABASE \"$db_name\" OWNER \"$db_user\";" postgres
  cat "$dump_file" | docker exec -i "$container" psql -U "$db_user" -d "$db_name" -q

  log "[$compose_svc] Restore complete."
}

# compose_svc   compose_container  container          db_name    db_user
restore_db fireflyiii  fireflyiii-db  fireflyiii-db    firefly    firefly
restore_db blinko      blinko-db      blinko-db        blinko     blinko
restore_db n8n         n8n-db         n8n-db           n8n        n8n
restore_db solidtime   solidtime-db   solidtime-db     solidtime  solidtime
restore_db linkwarden  linkwarden-db  linkwarden-db    linkwarden linkwarden
restore_db immich      database       immich_postgres  immich     postgres
restore_db infisical   infisical-db   infisical-db     infisical  infisical

log "All database restores complete."

# ---------------------------------------------------------------------------
# 6. Start all services
# ---------------------------------------------------------------------------
log "Starting all services..."
compose-manage start

# ---------------------------------------------------------------------------
# 7. Final status
# ---------------------------------------------------------------------------
log "All services started. Current Docker container status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

log ""
log "=== Homelab restore complete! ==="
log ""
log "Services are starting up. Allow a few minutes for all containers to"
log "become healthy. Check individual service logs with:"
log "  compose-manage logs <service>"
log ""
log "Traefik dashboard (if port-forwarded): http://localhost:8080"
