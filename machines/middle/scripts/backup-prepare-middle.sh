#!/usr/bin/env bash

# Middle Server Backup Preparation Script
# Backs up wg-easy, adguard, and kanidm data
# Usage: backup-prepare-middle.sh <dump_dir>

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${CYAN}[MIDDLE-BACKUP]${NC} ${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${CYAN}[MIDDLE-BACKUP]${NC} ${GREEN}[SUCCESS]${NC} $1" >&2
}

log_error() {
    echo -e "${CYAN}[MIDDLE-BACKUP]${NC} ${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${CYAN}[MIDDLE-BACKUP]${NC} ${YELLOW}[WARN]${NC} $1" >&2
}

log_step() {
    echo -e "${CYAN}[MIDDLE-BACKUP]${NC} ${PURPLE}[STEP]${NC} $1" >&2
}

# Error handling
cleanup_on_error() {
    log_error "Middle server backup preparation failed. Cleaning up..."
    rm -rf "$DUMP_DIR"
    exit 1
}

trap cleanup_on_error ERR

# Backup WireGuard Easy
backup_wg_easy() {
    local container="wg-easy"
    local backup_dir="$DUMP_DIR/wg-easy"
    
    log_step "Backing up WireGuard Easy..."
    
    # Check if container exists and is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        log_error "Container $container is not running or does not exist"
        return 1
    fi
    
    mkdir -p "$backup_dir"
    
    # Copy database and config files from container to host
    log_info "Copying database and configuration files from container..."
    
    # Copy the database file
    if ! docker cp "$container:/etc/wireguard/wg-easy.db" "$backup_dir/wg-easy.db"; then
        log_error "Failed to copy WireGuard database from container"
        return 1
    fi
    
    # Copy the WireGuard configuration
    if ! docker cp "$container:/etc/wireguard/wg0.conf" "$backup_dir/wg0.conf"; then
        log_error "Failed to copy WireGuard config from container"
        return 1
    fi
    
    # Create SQLite backup on host (requires sqlite3 to be available in PATH)
    log_info "Creating SQLite backup on host..."
    if command -v sqlite3 >/dev/null 2>&1; then
        if sqlite3 "$backup_dir/wg-easy.db" ".backup '$backup_dir/wg-easy.db.bkp'"; then
            log_info "SQLite backup successful, removing original database file"
            rm -f "$backup_dir/wg-easy.db"
        else
            log_warn "SQLite backup command failed, keeping original database file"
        fi
    else
        log_warn "sqlite3 not available on host, database file copied as-is"
    fi

    local size=$(du -sh "$backup_dir" | cut -f1)
    log_success "✓ WireGuard backup completed ($size)"
    
    return 0
}


# Backup Kanidm
backup_kanidm() {
    local container="kanidm"
    local backup_dir="$DUMP_DIR/kanidm"
    
    log_step "Backing up Kanidm..."
    
    # Check if container exists and is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        log_error "Container $container is not running or does not exist"
        return 1
    fi
    
    mkdir -p "$backup_dir"
    
    # Copy Kanidm backups from container
    if docker cp "$container:/data/backups" "$backup_dir/" 2>/dev/null; then
        local size=$(du -sh "$backup_dir" | cut -f1)
        log_success "✓ Kanidm backup completed ($size)"
    else
        log_warn "No Kanidm backups found in container or copy failed"
        # Create empty directory to indicate attempt was made
        mkdir -p "$backup_dir/backups"
        echo "No backups found at $(date)" > "$backup_dir/backups/README.txt"
        return 0
    fi
    
    return 0
}

# Main execution
main() {
    # Require dump directory argument
    if [[ $# -lt 1 ]]; then
        log_error "Usage: $0 <dump_dir>"
        log_error "Dump directory is required"
        exit 1
    fi
    
    local dump_dir="$1"
    
    # Validate dump directory argument
    if [[ ! "$dump_dir" == /* ]]; then
        log_error "Dump directory must be an absolute path: $dump_dir"
        exit 1
    fi
    
    # Set global dump dir
    DUMP_DIR="$dump_dir"
    
    log_info "Middle server backup starting..."
    log_info "Dump directory: $dump_dir"
    
    log_step "Starting middle server backup preparation"
    
    # Create dump directory
    mkdir -p "$DUMP_DIR"
    log_info "Created dump directory: $DUMP_DIR"
    
    local successful=0
    local failed=0
    
    # Backup each service
    if backup_wg_easy; then
        successful=$((successful + 1))
    else
        failed=$((failed + 1))
        log_error "Failed to backup WireGuard Easy"
    fi
    
    if backup_kanidm; then
        successful=$((successful + 1))
    else
        failed=$((failed + 1))
        log_error "Failed to backup Kanidm"
    fi
    
    # AdGuard is backed up directly via restic paths, not via script
    log_info "AdGuard configuration backed up directly via restic paths"
    
    # Create summary manifest
    log_step "Creating backup manifest..."
    cat > "$DUMP_DIR/manifest.json" << EOF
{
    "backup_type": "middle-server-backups",
    "timestamp": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "services_processed": 2,
    "successful_backups": $successful,
    "failed_backups": $failed,
    "total_size": "$(du -sh "$DUMP_DIR" | cut -f1)",
    "services": {
        "wg-easy": "WireGuard VPN management database and config",
        "kanidm": "Identity management backups",
        "adguard": "DNS filtering configuration (backed up via direct path)"
    }
}
EOF
    
    # Final summary
    log_info "Middle server backup preparation completed:"
    log_info "  • Script-handled services: 2 (wg-easy, kanidm)"
    log_info "  • Direct-path services: 1 (adguard)"
    log_info "  • Successful backups: $successful"
    log_info "  • Failed backups: $failed"
    log_info "  • Total size: $(du -sh "$DUMP_DIR" | cut -f1)"
    
    if [ "$failed" -gt 0 ]; then
        log_warn "⚠ Some service backups failed. Check logs above."
        return 1
    fi
    
    log_success "✓ All middle server backups completed successfully"
}

# Execute main function
main "$@"
