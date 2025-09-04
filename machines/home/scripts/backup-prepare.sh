#!/usr/bin/env bash

# Generic Database Backup Preparation Script
# Inspects container environment variables to extract DB connection info
# Usage: backup-prepare.sh <dump_dir> <container1> <container2> ...

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
    echo -e "${CYAN}[BACKUP]${NC} ${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${CYAN}[BACKUP]${NC} ${GREEN}[SUCCESS]${NC} $1" >&2
}

log_error() {
    echo -e "${CYAN}[BACKUP]${NC} ${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${CYAN}[BACKUP]${NC} ${YELLOW}[WARN]${NC} $1" >&2
}

log_step() {
    echo -e "${CYAN}[BACKUP]${NC} ${PURPLE}[STEP]${NC} $1" >&2
}

log_database() {
    echo -e "${CYAN}[BACKUP]${NC} ${ORANGE}[DB]${NC} $1" >&2
}

# Error handling
cleanup_on_error() {
    log_error "Database backup preparation failed. Cleaning up..."
    rm -rf "$DUMP_DIR"
    exit 1
}

trap cleanup_on_error ERR

# Extract database info from container environment
extract_db_info() {
    local container="$1"
    local env_output
    
    # Get container environment variables
    if ! env_output=$(docker exec "$container" env 2>/dev/null); then
        log_error "Could not access container environment: $container"
        return 1
    fi
    
    # Extract database connection info - fail if not found
    local db_name db_user
    
    db_name=$(echo "$env_output" | grep -E "(POSTGRES_DB|DATABASE_NAME|DB_DATABASE|DB_NAME)" | head -1 | cut -d'=' -f2- || echo "")
    db_user=$(echo "$env_output" | grep -E "(POSTGRES_USER|DATABASE_USER|DB_USERNAME|DB_USER)" | head -1 | cut -d'=' -f2- || echo "")
    
    # Fail fast if required info is missing
    if [[ -z "$db_name" ]]; then
        log_error "Could not find database name in container $container environment"
        return 1
    fi
    
    if [[ -z "$db_user" ]]; then
        log_error "Could not find database user in container $container environment"  
        return 1
    fi
    
    # Return the extracted info
    echo "$db_name|$db_user"
}

# Dump database from container
dump_database() {
    local container="$1"
    local service_name=$(echo "$container" | sed 's/-db$//' | sed 's/-database$//')
    
    log_database "Processing container: $container (service: $service_name)"
    
    # Check if container exists and is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        log_error "Container $container is not running or does not exist"
        return 1
    fi
    
    # Extract database connection info
    local db_info
    if ! db_info=$(extract_db_info "$container"); then
        log_error "Failed to extract database info for $container"
        log_error "Container environment may be missing required database variables"
        return 1
    fi
    
    local db_name=$(echo "$db_info" | cut -d'|' -f1)
    local db_user=$(echo "$db_info" | cut -d'|' -f2)
    
    log_info "  → Database: $db_name, User: $db_user"
    
    # Dump the database - show error output  
    if ! docker exec "$container" pg_dump -U "$db_user" "$db_name" > "$DUMP_DIR/${service_name}.sql" 2>&1; then
        log_error "pg_dump failed for container $container"
        log_error "Check if PostgreSQL is running and credentials are correct"
        if [[ -f "$DUMP_DIR/${service_name}.sql" ]]; then
            log_error "pg_dump output: $(head -n 5 "$DUMP_DIR/${service_name}.sql")"
            rm -f "$DUMP_DIR/${service_name}.sql"  # Clean up partial file
        fi
        return 1
    fi
    
    local size=$(du -h "$DUMP_DIR/${service_name}.sql" | cut -f1)
    log_success "✓ Database dump completed for $service_name ($size)"
    return 0
}

# Main execution
main() {
    # Require at least 2 arguments: dump_dir + at least one container
    if [[ $# -lt 2 ]]; then
        log_error "Usage: $0 <dump_dir> <container1> [container2] ..."
        log_error "Both dump directory and container names are required"
        exit 1
    fi
    
    local dump_dir="$1"
    shift
    local containers=("$@")
    
    # Validate dump directory argument
    if [[ ! "$dump_dir" == /* ]]; then
        log_error "Dump directory must be an absolute path: $dump_dir"
        exit 1
    fi
    
    # Set global dump dir
    DUMP_DIR="$dump_dir"
    
    log_info "Dump directory: $dump_dir"
    log_info "Containers to process: ${containers[*]}"
    
    log_step "Starting database backup preparation"
    
    # Create dump directory
    mkdir -p "$DUMP_DIR"
    log_info "Created dump directory: $DUMP_DIR"
    
    local successful=0
    local failed=0
    
    # Process each container
    for container in "${containers[@]}"; do
        if dump_database "$container"; then
            successful=$((successful + 1))
        else
            failed=$((failed + 1))
            log_error "Failed to process container: $container"
        fi
    done
    
    # Create summary manifest
    log_step "Creating backup manifest..."
    cat > "$DUMP_DIR/manifest.json" << EOF
{
    "backup_type": "database-dumps",
    "timestamp": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "containers_processed": ${#containers[@]},
    "successful_dumps": $successful,
    "failed_dumps": $failed,
    "total_size": "$(du -sh "$DUMP_DIR" | cut -f1)"
}
EOF
    
    # Final summary
    log_info "Database backup preparation completed:"
    log_info "  • Containers processed: ${#containers[@]}"
    log_info "  • Successful dumps: $successful"
    log_info "  • Failed dumps: $failed"
    log_info "  • Total size: $(du -sh "$DUMP_DIR" | cut -f1)"
    
    if [ "$failed" -gt 0 ]; then
        log_warn "⚠ Some database dumps failed. Check container status and logs."
        return 1
    fi
    
    log_success "✓ All database dumps completed successfully"
}

# Execute main function
main "$@"