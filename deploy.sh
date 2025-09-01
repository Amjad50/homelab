#!/usr/bin/env bash

# Usage: ./deploy.sh <flake-name> [server] [--no-docker]
# If server is provided, deploy remotely via SSH
# Otherwise, run locally
# Use --no-docker to skip Docker service deployment

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
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# Parse arguments
FLAKE_NAME=""
SERVER=""
NO_DOCKER=false
ONLY_DOCKER=false
UPDATE_FLAKE=false

for arg in "$@"; do
    case $arg in
        --no-docker)
            NO_DOCKER=true
            shift
            ;;
        --only-docker)
            ONLY_DOCKER=true
            shift
            ;;
        --update)
            UPDATE_FLAKE=true
            shift
            ;;
        *)
            if [ -z "$FLAKE_NAME" ]; then
                FLAKE_NAME="$arg"
            elif [ -z "$SERVER" ]; then
                SERVER="$arg"
            else
                log_error "Unexpected argument: $arg"
                echo "Usage: $0 <flake-name> [server] [--no-docker|--only-docker] [--update]"
                exit 1
            fi
            shift
            ;;
    esac
done

if [ "$ONLY_DOCKER" = true ] && [ "$NO_DOCKER" = true ]; then
    log_error "Cannot use both --no-docker and --only-docker flags together"
    exit 1
fi

if [ -z "$FLAKE_NAME" ]; then
    log_error "Missing flake name"
    echo "Usage: $0 <flake-name> [server] [--no-docker|--only-docker]"
    echo "Example: $0 myserver user@remote-server"
    echo "         $0 myserver user@remote-server --no-docker"
    echo "         $0 myserver user@remote-server --only-docker"
    exit 1
fi

if [ -n "$SERVER" ]; then
    log_info "Deploying to remote server: $SERVER"
    
    # Create compressed archive
    log_step "Creating compressed archive for $FLAKE_NAME..."
    ARCHIVE="/tmp/nixos-deploy-$(date +%s).tar.xz"
    tar -cJf "$ARCHIVE" \
        --exclude='.git' \
        --exclude='*.backup' \
        --exclude='result' \
        flake.nix common/ "machines/$FLAKE_NAME/"
    
    log_info "Archive created: $(du -h "$ARCHIVE" | cut -f1)"
    
    # Copy files to remote server
    log_step "Transferring archive and deployment script..."
    scp "$ARCHIVE" "scripts/remote-deploy.sh" "$SERVER:/tmp/"
    REMOTE_ARCHIVE="/tmp/$(basename "$ARCHIVE")"
    
    # SSH and run remote deployment
    log_step "Running remote deployment..."
    FLAGS=""
    if [ "$NO_DOCKER" = true ]; then
        log_info "Skipping Docker services deployment"
        FLAGS="--no-docker"
    elif [ "$ONLY_DOCKER" = true ]; then
        log_info "Only deploying Docker services (skipping nixos-rebuild)"
        FLAGS="--only-docker"
    fi
    if [ "$UPDATE_FLAKE" = true ]; then
        log_info "Updating flake before deployment"
        FLAGS="$FLAGS --update"
    fi
    ssh -t "$SERVER" "chmod +x /tmp/remote-deploy.sh && /tmp/remote-deploy.sh $REMOTE_ARCHIVE $FLAKE_NAME $FLAGS"
    
    # Clean up local archive
    rm -f "$ARCHIVE"
    log_success "Remote deployment complete!"
else
    log_info "Running local nixos-rebuild..."
    
    # Check if we're on NixOS
    if [ ! -f /etc/nixos/configuration.nix ]; then
        log_error "This doesn't appear to be a NixOS system"
        echo "Usage: $0 <flake-name> [server] - specify server for remote deployment"
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
    
    # Copy files to /etc/nixos and rebuild
    log_step "Copying configuration files..."
    sudo cp flake.nix /etc/nixos/
    sudo rm -rf /etc/nixos/common /etc/nixos/machines
    sudo cp -r common /etc/nixos/
    
    # Copy machine-specific docker-services if they exist and not skipped
    if [ "$NO_DOCKER" = false ] && [ -d "machines/$FLAKE_NAME/docker-services" ]; then
        log_step "Copying docker-services..."
        sudo mkdir -p /opt/docker-services
        sudo cp -r "machines/$FLAKE_NAME/docker-services"/* /opt/docker-services/
        sudo chown -R dock:docker /opt/docker-services
    elif [ "$NO_DOCKER" = true ]; then
        log_info "Skipping Docker services deployment (--no-docker flag)"
    fi
    
    # Copy machine directory
    sudo mkdir -p /etc/nixos/machines
    sudo cp -r "machines/$FLAKE_NAME" /etc/nixos/machines/

    # Remove old configuration.nix if it exists
    if [ -f /etc/nixos/configuration.nix ]; then
        log_info "Removing old configuration.nix..."
        sudo rm /etc/nixos/configuration.nix
    fi
    
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
    
    log_success "Local deployment complete!"
fi