#!/bin/bash

# Usage: ./deploy.sh [server]
# If server is provided, deploy remotely via SSH
# Otherwise, run locally

set -e

SERVER=$1
FLAKE_NAME=${2:-"myserver"}

if [ -n "$SERVER" ]; then
    echo "Deploying to remote server: $SERVER"
    
    # Copy files to remote server
    echo "Copying configuration files for $FLAKE_NAME..."
    scp -r flake.nix common/ "machines/$FLAKE_NAME/" "$SERVER:/tmp/"
    
    # Copy docker-services if it exists
    if [ -d "docker-services" ]; then
        echo "Copying docker-services..."
        scp -r docker-services/ "$SERVER:/tmp/"
    fi
    
    # SSH and rebuild
    echo "Running nixos-rebuild on remote server..."
    ssh "$SERVER" "
        sudo mv /tmp/flake.nix /etc/nixos/
        sudo rm -rf /etc/nixos/common /etc/nixos/machines
        sudo mv /tmp/common /etc/nixos/
        
        # Move docker-services to /opt directory if it exists
        if [ -d /tmp/docker-services ]; then
            sudo mkdir -p /opt/docker-services
            sudo cp -r /tmp/docker-services/* /opt/docker-services/
            sudo chown -R dock:docker /opt/docker-services
            sudo rm -rf /tmp/docker-services
        fi
        
        # Move machine-specific docker-services before moving machine directory
        if [ -d /tmp/$FLAKE_NAME/docker-services ]; then
            sudo mkdir -p /opt/docker-services
            sudo cp -r /tmp/$FLAKE_NAME/docker-services/* /opt/docker-services/
            sudo chown -R dock:docker /opt/docker-services
            sudo rm -rf /tmp/$FLAKE_NAME/docker-services
        fi
        
        # Now move machine directory
        sudo mkdir -p /etc/nixos/machines
        sudo mv /tmp/$FLAKE_NAME /etc/nixos/machines/
        
        sudo nixos-rebuild switch --flake /etc/nixos#$FLAKE_NAME
    "
    
    echo "Remote deployment complete!"
else
    echo "Running local nixos-rebuild..."
    
    # Check if we're on NixOS
    if [ ! -f /etc/nixos/configuration.nix ]; then
        echo "Error: This doesn't appear to be a NixOS system"
        echo "Usage: $0 [server] - specify server for remote deployment"
        exit 1
    fi
    
    # Copy files to /etc/nixos and rebuild
    sudo cp flake.nix /etc/nixos/
    sudo rm -rf /etc/nixos/common /etc/nixos/machines
    sudo cp -r common /etc/nixos/
    
    # Copy docker-services if it exists
    if [ -d "docker-services" ]; then
        sudo mkdir -p /opt/docker-services
        sudo cp -r docker-services/* /opt/docker-services/
        sudo chown -R dock:docker /opt/docker-services
    fi
    
    # Copy machine-specific docker-services if they exist
    if [ -d "machines/$FLAKE_NAME/docker-services" ]; then
        sudo mkdir -p /opt/docker-services
        sudo cp -r "machines/$FLAKE_NAME/docker-services"/* /opt/docker-services/
        sudo chown -R dock:docker /opt/docker-services
    fi
    
    # Copy machine directory
    sudo mkdir -p /etc/nixos/machines
    sudo cp -r "machines/$FLAKE_NAME" /etc/nixos/machines/
    
    sudo nixos-rebuild switch --flake /etc/nixos#$FLAKE_NAME
    
    echo "Local deployment complete!"
fi