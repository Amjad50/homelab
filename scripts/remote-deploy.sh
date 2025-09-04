#!/bin/sh

# Remote deployment script (runs in remote server context)
# Usage: remote-deploy.sh <archive-path> <flake-name> [--no-docker]

set -e

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
    echo -e "${ORANGE}[REMOTE]${NC} ${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${ORANGE}[REMOTE]${NC} ${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warn() {
    echo -e "${ORANGE}[REMOTE]${NC} ${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${ORANGE}[REMOTE]${NC} ${RED}[ERROR]${NC} $1" >&2
}

log_step() {
    echo -e "${ORANGE}[REMOTE]${NC} ${PURPLE}[STEP]${NC} $1" >&2
}

log_docker() {
    echo -e "${ORANGE}[REMOTE]${NC} ${CYAN}[DOCKER]${NC} $1" >&2
}

# Parse arguments
REMOTE_ARCHIVE="$1"
FLAKE_NAME="$2"
NO_DOCKER=false
ONLY_DOCKER=false
UPDATE_FLAKE=false

if [ "$3" = "--no-docker" ]; then
    NO_DOCKER=true
    shift
elif [ "$3" = "--only-docker" ]; then
    ONLY_DOCKER=true
    shift
fi

if [ "$3" = "--update" ]; then
    UPDATE_FLAKE=true
fi

if [ -z "$REMOTE_ARCHIVE" ] || [ -z "$FLAKE_NAME" ]; then
    log_error "Missing required arguments"
    echo "Usage: $0 <archive-path> <flake-name> [--no-docker|--only-docker]"
    exit 1
fi

if ! [ "$FLAKE_NAME" = "$(hostname -s)" ]; then
    log_error "Flake name does not match the current hostname ($FLAKE_NAME != $(hostname -s))."
    log_error "Are you sure you want to deploy? (y/N)"

    read -r confirmation
    if [ "$confirmation" != "y" ] && [ "$confirmation" != "Y" ]; then
        log_error "Deployment cancelled."
        exit 1
    else
        log_info "Deployment confirmed for $FLAKE_NAME" 
    fi
fi

# Function to calculate directory checksum (content + filenames)
calculate_directory_checksum() {
    local dir="$1"
    find "$dir" -type f -printf '%P' -exec sha256sum {} \; 2>/dev/null | sort | cut -d' ' -f1 | sha256sum | cut -d' ' -f1
}

# Function to check if docker service files changed
check_service_changes() {
    local service_dir="$1"
    local service_name="$2"

    if [ -d "/opt/docker-services/$service_name" ]; then
        local new_checksum=$(calculate_directory_checksum "$service_dir")
        local old_checksum=$(calculate_directory_checksum "/opt/docker-services/$service_name")

        log_info "  new → $new_checksum"
        log_info "  old → $old_checksum"
        if [ "$new_checksum" != "$old_checksum" ]; then
            log_docker "  → Changes detected in $service_name"
            
            # Show diff using delta
            if command -v delta >/dev/null 2>&1; then
                log_docker "  → Showing diff:"
                diff -ruN "/opt/docker-services/$service_name" "$service_dir" | delta --pager="none" --line-numbers --side-by-side >&2
            else
                log_warn "  → delta not found, install it to see diffs"
            fi
            
            return 0  # Changed
        else
            log_info "  → No changes in $service_name"
            return 1  # Not changed
        fi
    else
        log_docker "  → New service: $service_name"
        mkdir "/opt/docker-services/$service_name" # need to create directory for service to be moved into
        return 0  # New service counts as changed
    fi
}

# Function to process docker services
process_docker_services() {
    local temp_dir="$1"
    local flake_name="$2"
    local changed_services=()

    if [ -d "$temp_dir/machines/$flake_name/docker-services" ]; then
        log_step 'Processing docker-services...'
        sudo mkdir -p /opt/docker-services

        for service_dir in "$temp_dir/machines/$flake_name/docker-services"/*; do
            if [ -d "$service_dir" ]; then
                local service_name=$(basename "$service_dir")
                log_docker "Checking service: $service_name"

                if check_service_changes "$service_dir" "$service_name"; then
                    changed_services+=("$service_name")
                fi

                # Copy the service files
                sudo cp -r "$service_dir/." "/opt/docker-services/$service_name/"
            fi
        done

        sudo chown -R dock:docker /opt/docker-services
        sudo rm -rf "$temp_dir/machines/$flake_name/docker-services"

        if [ ${#changed_services[@]} -gt 0 ]; then
            log_success "Services with changes: ${changed_services[*]}"
            echo "${changed_services[*]}"  # Return for capture
        fi
    fi
}

# Function to restart changed services
restart_changed_services() {
    local services="$1"
    if [ -n "$services" ]; then
        log_step 'Restarting changed docker services...'
        for service in $services; do
            log_docker "Restarting service: $service"
            compose-manage restart "$service" || log_warn "Failed to restart $service"
        done
    fi
}

# Main deployment logic
log_info "Starting remote deployment for $FLAKE_NAME..."

TEMP_DIR=$(mktemp -d /tmp/nixos-deploy.XXXXXX)
log_info "Using temp directory: $TEMP_DIR"

# Extract archive
log_step 'Extracting archive...'
cd "$TEMP_DIR" && tar -xJf "$REMOTE_ARCHIVE"

# Process docker services and capture changed services (if not skipped)
if [ "$NO_DOCKER" = false ]; then
    CHANGED_SERVICES=$(process_docker_services "$TEMP_DIR" "$FLAKE_NAME")
else
    log_info "Skipping Docker services deployment (--no-docker flag)"
    CHANGED_SERVICES=""
    # Remove docker-services from temp directory to prevent copying
    rm -rf "$TEMP_DIR/machines/$FLAKE_NAME/docker-services" 2>/dev/null || true
fi

# Move configuration files (unless only-docker)
if [ "$ONLY_DOCKER" = false ]; then
    log_step 'Moving configuration files...'
    sudo mv "$TEMP_DIR/flake.nix" /etc/nixos/
    sudo rm -rf /etc/nixos/common /etc/nixos/machines
    sudo mv "$TEMP_DIR/common" /etc/nixos/
    sudo mkdir -p /etc/nixos/machines
    sudo mv "$TEMP_DIR/machines/$FLAKE_NAME" /etc/nixos/machines/

    # Remove old configuration.nix if it exists
    if [ -f /etc/nixos/configuration.nix ]; then
        log_info "Removing old configuration.nix..."
        sudo rm /etc/nixos/configuration.nix
    fi
else
    log_info "Skipping configuration deployment (--only-docker flag)"
fi

# Run nixos-rebuild (unless only-docker)
if [ "$ONLY_DOCKER" = false ]; then
    if [ "$UPDATE_FLAKE" = true ]; then
        log_info "Updating flake before rebuild..."
        sudo nix flake update --flake /etc/nixos || log_warn "Failed to update flake"
    fi
    log_step "Running nixos-rebuild switch..."
    sudo nixos-rebuild switch --fast
else
    log_info "Skipping nixos-rebuild (--only-docker flag)"
fi

# Restart changed services
restart_changed_services "$CHANGED_SERVICES"

# Clean up
log_step 'Cleaning up temporary files...'
rm -rf "$TEMP_DIR"
rm -f "$REMOTE_ARCHIVE"

log_success "Remote deployment complete!"
