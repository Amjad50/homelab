#!/bin/bash

# Usage: ./deploy.sh [server]
# If server is provided, deploy remotely via SSH
# Otherwise, run locally

set -e

SERVER=$1
FLAKE_NAME="myserver"

if [ -n "$SERVER" ]; then
    echo "Deploying to remote server: $SERVER"
    
    # Copy files to remote server
    echo "Copying configuration files..."
    scp -r flake.nix configuration.nix hardware-configuration.nix "$SERVER:/tmp/"
    
    # SSH and rebuild
    echo "Running nixos-rebuild on remote server..."
    ssh "$SERVER" "
        sudo mv /tmp/flake.nix /tmp/configuration.nix /tmp/hardware-configuration.nix /etc/nixos/
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
    sudo cp flake.nix configuration.nix hardware-configuration.nix /etc/nixos/
    sudo nixos-rebuild switch --flake /etc/nixos#$FLAKE_NAME
    
    echo "Local deployment complete!"
fi