#!/bin/sh

# Remote deployment script
# Usage: remote-deploy.sh <archive-path> <flake-name>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1" >&2
}

log_docker() {
    echo -e "${CYAN}[DOCKER]${NC} $1" >&2
}

REMOTE_ARCHIVE="$1"
FLAKE_NAME="$2"

if [ -z "$REMOTE_ARCHIVE" ] || [ -z "$FLAKE_NAME" ]; then
    log_error "Missing required arguments"
    echo "Usage: $0 <archive-path> <flake-name>"
    exit 1
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

# Process docker services and capture changed services
CHANGED_SERVICES=$(process_docker_services "$TEMP_DIR" "$FLAKE_NAME")

# Move configuration files
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

# Run nixos-rebuild
log_step 'Running nixos-rebuild switch...'
sudo nixos-rebuild switch

# Restart changed services
restart_changed_services "$CHANGED_SERVICES"

# Clean up
log_step 'Cleaning up temporary files...'
rm -rf "$TEMP_DIR"
rm -f "$REMOTE_ARCHIVE"

log_success "Remote deployment complete!"