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
    echo "Copying configuration files..."
    scp -r flake.nix configuration.nix modules/ scripts/ "$SERVER:/tmp/"
    
    # Copy docker-services if it exists
    if [ -d "docker-services" ]; then
        echo "Copying docker-services..."
        scp -r docker-services/ "$SERVER:/tmp/"
    fi
    
    # SSH and rebuild
    echo "Running nixos-rebuild on remote server..."
    ssh "$SERVER" "
        sudo mv /tmp/flake.nix /tmp/configuration.nix /etc/nixos/
        sudo rm -rf /etc/nixos/modules /etc/nixos/scripts
        sudo mv /tmp/modules /etc/nixos/
        sudo mv /tmp/scripts /etc/nixos/
        
        # Move docker-services to /opt directory if it exists
        if [ -d /tmp/docker-services ]; then
            sudo mkdir -p /opt/docker-services
            sudo cp -r /tmp/docker-services/* /opt/docker-services/
            sudo chown -R dock:docker /opt/docker-services
            sudo rm -rf /tmp/docker-services
        fi
        
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
    sudo cp flake.nix configuration.nix /etc/nixos/
    sudo rm -rf /etc/nixos/modules /etc/nixos/scripts
    sudo cp -r modules scripts /etc/nixos/
    
    # Copy docker-services if it exists
    if [ -d "docker-services" ]; then
        sudo mkdir -p /opt/docker-services
        sudo cp -r docker-services/* /opt/docker-services/
        sudo chown -R dock:docker /opt/docker-services
    fi
    
    sudo nixos-rebuild switch --flake /etc/nixos#$FLAKE_NAME
    
    echo "Local deployment complete!"
fi