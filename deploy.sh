#!/bin/bash

# Usage: ./deploy.sh <flake-name> [server]
# If server is provided, deploy remotely via SSH
# Otherwise, run locally

set -e

FLAKE_NAME=$1
SERVER=$2

if [ -z "$FLAKE_NAME" ]; then
    echo "Usage: $0 <flake-name> [server]"
    echo "Example: $0 myserver user@remote-server"
    exit 1
fi

if [ -n "$SERVER" ]; then
    echo "Deploying to remote server: $SERVER"
    
    # Create compressed archive
    echo "Creating compressed archive for $FLAKE_NAME..."
    ARCHIVE="/tmp/nixos-deploy-$(date +%s).tar.xz"
    tar -cJf "$ARCHIVE" \
        --exclude='.git' \
        --exclude='*.backup' \
        --exclude='result' \
        flake.nix common/ "machines/$FLAKE_NAME/"
    
    echo "Archive created: $(du -h "$ARCHIVE" | cut -f1)"
    
    # Copy archive to remote server
    echo "Transferring archive..."
    scp "$ARCHIVE" "$SERVER:/tmp/"
    REMOTE_ARCHIVE="/tmp/$(basename "$ARCHIVE")"
    
    # SSH and rebuild
    echo "Running nixos-rebuild on remote server..."
    ssh -t "$SERVER" "
        # Create temporary directory for extraction
        TEMP_DIR=\$(mktemp -d /tmp/nixos-deploy.XXXXXX)
        echo \"Using temp directory: \$TEMP_DIR\"
        
        # Extract archive
        echo 'Extracting archive...'
        cd \"\$TEMP_DIR\" && tar -xJf $REMOTE_ARCHIVE
        
        # Move files to proper locations
        sudo mv \"\$TEMP_DIR/flake.nix\" /etc/nixos/
        sudo rm -rf /etc/nixos/common /etc/nixos/machines
        sudo mv \"\$TEMP_DIR/common\" /etc/nixos/
        
        # Move machine-specific docker-services before moving machine directory
        if [ -d \"\$TEMP_DIR/machines/$FLAKE_NAME/docker-services\" ]; then
            echo 'Moving machine-specific docker-services to /opt/docker-services...'
            echo 'Found: '\$(ls \"\$TEMP_DIR/machines/$FLAKE_NAME/docker-services\")''
            sudo mkdir -p /opt/docker-services
            sudo cp -r \"\$TEMP_DIR/machines/$FLAKE_NAME/docker-services/.\" /opt/docker-services/
            sudo chown -R dock:docker /opt/docker-services
            sudo rm -rf \"\$TEMP_DIR/machines/$FLAKE_NAME/docker-services\"
        fi
        
        # Now move machine directory
        sudo mkdir -p /etc/nixos/machines
        sudo mv \"\$TEMP_DIR/machines/$FLAKE_NAME\" /etc/nixos/machines/

        # Remove old configuration.nix if it exists
        if [ -f /etc/nixos/configuration.nix ]; then
            echo "Removing old configuration.nix..."
            sudo rm /etc/nixos/configuration.nix
        fi
        
        sudo nixos-rebuild switch
        
        # Clean up
        echo 'Cleaning up temporary files...'
        rm -rf \"\$TEMP_DIR\"
        rm -f $REMOTE_ARCHIVE
    "
    
    # Clean up local archive
    rm -f "$ARCHIVE"
    echo "Remote deployment complete!"
else
    echo "Running local nixos-rebuild..."
    
    # Check if we're on NixOS
    if [ ! -f /etc/nixos/configuration.nix ]; then
        echo "Error: This doesn't appear to be a NixOS system"
        echo "Usage: $0 <flake-name> [server] - specify server for remote deployment"
        exit 1
    fi
    
    # Copy files to /etc/nixos and rebuild
    sudo cp flake.nix /etc/nixos/
    sudo rm -rf /etc/nixos/common /etc/nixos/machines
    sudo cp -r common /etc/nixos/
    
    # Copy machine-specific docker-services if they exist
    if [ -d "machines/$FLAKE_NAME/docker-services" ]; then
        sudo mkdir -p /opt/docker-services
        sudo cp -r "machines/$FLAKE_NAME/docker-services"/* /opt/docker-services/
        sudo chown -R dock:docker /opt/docker-services
    fi
    
    # Copy machine directory
    sudo mkdir -p /etc/nixos/machines
    sudo cp -r "machines/$FLAKE_NAME" /etc/nixos/machines/

    # Remove old configuration.nix if it exists
    if [ -f /etc/nixos/configuration.nix ]; then
        echo "Removing old configuration.nix..."
        sudo rm /etc/nixos/configuration.nix
    fi
    
    sudo nixos-rebuild switch
    
    echo "Local deployment complete!"
fi