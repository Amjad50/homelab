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
    # Hardware configuration (auto-generated on target system)
    ../hardware-configuration.nix

    # Modular configurations
    ./modules/system.nix
    ./modules/btrfs.nix
    ./modules/services.nix
    ./modules/users.nix
    ./modules/docker.nix
    ./modules/compose-services.nix
  ];

  # This file primarily serves as an entry point
  # Individual configurations are organized in modules/
}
