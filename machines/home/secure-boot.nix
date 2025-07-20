# Secure Boot Configuration for Home Machine (unused now)
# Uses Lanzaboote for UEFI Secure Boot support
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Disable GRUB in favor of Lanzaboote
  boot.loader.grub.enable = lib.mkForce false;
  
  # Enable systemd-boot and disable it in favor of Lanzaboote
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = true;

  # Lanzaboote configuration for Secure Boot
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  # Required tools for Secure Boot management
  environment.systemPackages = with pkgs; [
    sbctl  # Secure Boot key management tool
  ];
}