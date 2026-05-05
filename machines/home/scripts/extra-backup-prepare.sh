#!/usr/bin/env bash

# Extra Backup Preparation Script
# Handles service-specific backup artifacts that are not database dumps.
# Usage: extra-backup-prepare.sh <backup_dir>

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${CYAN}[EXTRA]${NC} ${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${CYAN}[EXTRA]${NC} ${GREEN}[SUCCESS]${NC} $1" >&2
}

log_error() {
    echo -e "${CYAN}[EXTRA]${NC} ${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${CYAN}[EXTRA]${NC} ${YELLOW}[WARN]${NC} $1" >&2
}

log_step() {
    echo -e "${CYAN}[EXTRA]${NC} ${PURPLE}[STEP]${NC} $1" >&2
}

cleanup_on_error() {
    log_error "Extra backup preparation failed. Cleaning up..."
    rm -rf "$BACKUP_DIR"
    exit 1
}

trap cleanup_on_error ERR

dump_vault_snapshot() {
    local container="vault"
    local snapshot_name="vault-raft.snap"
    local container_snapshot="/tmp/${snapshot_name}"
    local host_snapshot="${BACKUP_DIR}/${snapshot_name}"
    local vault_token=""

    log_step "Creating Vault Raft snapshot"

    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        log_warn "Vault container is not running; skipping Vault snapshot"
        return 0
    fi

    if [[ -n "${VAULT_TOKEN:-}" ]]; then
        vault_token="${VAULT_TOKEN}"
    elif [[ -r /var/lib/dock/vault-bootstrap.env ]]; then
        vault_token=$(sed -n 's/^VAULT_TOKEN=//p' /var/lib/dock/vault-bootstrap.env | head -n1)
    else
        log_warn "Vault token not provided and /var/lib/dock/vault-bootstrap.env is not readable; skipping Vault snapshot"
        return 0
    fi

    if [[ -z "$vault_token" ]]; then
        log_warn "Vault token is empty; skipping Vault snapshot"
        return 0
    fi

    docker exec "$container" rm -f "$container_snapshot" >/dev/null 2>&1 || true

    if ! docker exec \
        -e VAULT_ADDR="http://127.0.0.1:8200" \
        -e VAULT_TOKEN="$vault_token" \
        "$container" \
        vault operator raft snapshot save "$container_snapshot" >/dev/null; then
        log_error "Failed to create Vault Raft snapshot"
        return 1
    fi

    if ! docker cp "${container}:${container_snapshot}" "$host_snapshot" >/dev/null; then
        log_error "Failed to copy Vault Raft snapshot to host"
        return 1
    fi

    docker exec "$container" rm -f "$container_snapshot" >/dev/null 2>&1 || true

    local size
    size=$(du -h "$host_snapshot" | cut -f1)
    log_success "✓ Vault Raft snapshot completed ($size)"
}

main() {
    if [[ $# -ne 1 ]]; then
        log_error "Usage: $0 <backup_dir>"
        exit 1
    fi

    BACKUP_DIR="$1"

    if [[ ! "$BACKUP_DIR" == /* ]]; then
        log_error "Backup directory must be an absolute path: $BACKUP_DIR"
        exit 1
    fi

    mkdir -p "$BACKUP_DIR"
    log_info "Created extra backup directory: $BACKUP_DIR"

    dump_vault_snapshot

    cat > "$BACKUP_DIR/manifest.json" << EOF
{
    "backup_type": "extra-service-backups",
    "timestamp": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "vault_snapshot": "$(if [[ -f "${BACKUP_DIR}/vault-raft.snap" ]]; then echo true; else echo false; fi)",
    "total_size": "$(du -sh "$BACKUP_DIR" | cut -f1)"
}
EOF

    log_success "✓ Extra backup preparation completed successfully"
}

main "$@"
