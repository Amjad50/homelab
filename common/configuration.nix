# Main NixOS configuration
# Imports all module configurations
{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    # Modular configurations
    ./modules/system.nix
    ./modules/btrfs.nix
    ./modules/services.nix
    ./modules/users.nix
    ./modules/docker.nix
    ./modules/compose-services.nix
    ./modules/service-registry.nix
    ./modules/notifications.nix
  ];

  # This file primarily serves as an entry point
  # Individual configurations are organized in modules/
}
