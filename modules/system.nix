# Core system configuration
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Boot loader configuration
  boot.loader = {
    grub = {
      enable = true;
      device = "nodev";
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
    efi = {
      efiSysMountPoint = "/boot/efi";
      canTouchEfiVariables = false;
    };
  };

  # Localization
  time.timeZone = "Asia/Kuala_Lumpur";
  i18n.defaultLocale = "en_US.UTF-8";

  # System packages
  environment.systemPackages = with pkgs; [
    neovim
    wget
    curl
  ];

  # Enable experimental features for flakes
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # NixOS version
  system.stateVersion = "25.05";
}
