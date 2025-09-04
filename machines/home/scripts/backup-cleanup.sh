#!/usr/bin/env bash

# Generic Backup Cleanup Script
# Cleans up temporary database dump directories
# Usage: backup-cleanup.sh [dump_dir1] [dump_dir2] ...

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
    echo -e "${CYAN}[CLEANUP]${NC} ${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${CYAN}[CLEANUP]${NC} ${GREEN}[SUCCESS]${NC} $1" >&2
}

log_error() {
    echo -e "${CYAN}[CLEANUP]${NC} ${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${CYAN}[CLEANUP]${NC} ${YELLOW}[WARN]${NC} $1" >&2
}

log_step() {
    echo -e "${CYAN}[CLEANUP]${NC} ${PURPLE}[STEP]${NC} $1" >&2
}


# Cleanup directory
cleanup_dir() {
    local dir="$1"
    
    if [[ ! -d "$dir" ]]; then
        log_warn "Directory does not exist: $dir (skipping)"
        return 0
    fi
    
    local size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "unknown")
    log_info "Cleaning up directory: $dir ($size)"
    
    if rm -rf "$dir"; then
        log_success "✓ Successfully cleaned up: $dir"
        return 0
    else
        log_error "⚠ Failed to clean up: $dir"
        return 1
    fi
}

# Main execution
main() {
    # Require at least one argument
    if [[ $# -lt 1 ]]; then
        log_error "Usage: $0 <dump_dir1> [dump_dir2] ..."
        log_error "At least one dump directory is required"
        exit 1
    fi
    
    local dirs_to_cleanup=("$@")
    log_info "Cleaning up specified directories: ${dirs_to_cleanup[*]}"
    
    log_step "Starting backup cleanup"
    
    local successful=0
    local failed=0
    
    # Process each directory
    for dir in "${dirs_to_cleanup[@]}"; do
        if cleanup_dir "$dir"; then
            successful=$((successful + 1))
        else
            failed=$((failed + 1))
        fi
    done
    
    # Summary
    log_info "Backup cleanup completed:"
    log_info "  • Directories processed: ${#dirs_to_cleanup[@]}"
    log_info "  • Successfully cleaned: $successful"  
    log_info "  • Failed to clean: $failed"
    
    if [ "$failed" -gt 0 ]; then
        log_warn "⚠ Some cleanup operations failed"
        return 1
    fi
    
    log_success "✓ All cleanup operations completed successfully"
}

# Execute main function
main "$@"