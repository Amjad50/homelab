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
      device = lib.mkDefault "nodev"; # set in hardware configuration
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
    btop
    ncdu
    git
    zsh
    python3
    jq
    yq
    fd
    fastfetch
    tree
    zellij
    bind
    dnsutils

    btrfs-list

    # alternative to `nixos-rebuild` commands
    nh

    # Archive tools
    unzip
    p7zip

    # User CLI tools 
    delta
    ripgrep
    bat
    eza
    cargo
    git-lfs
    direnv

    # Toolchain for nvim (nvim-treesitter compiles grammars at runtime)
    gcc
    gnumake
  ];

  # Enable programs
  programs.zsh.enable = true;

  # Run dynamically-linked, non-Nix prebuilt binaries (e.g. zinit-downloaded
  # yazi/sd) that expect a standard glibc interpreter.
  programs.nix-ld.enable = true;

  # Enable experimental features for flakes
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    substituters = [
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://nix-community.cachix.org" # Nix community cache
      "https://cache.garnix.io" # Garnix cache
      "https://cache.nixos.org" # Official cache (default)
    ];

    # Trusted public keys for the caches
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbCHOoEo8tQdAq3n8l0="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];

    # Build settings
    max-jobs = "auto"; # Use all available cores
    build-cores = 0; # Use all available cores for each job
  };

  # Optional: Add more cache optimization
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Optimize
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };

  # NixOS version
  system.stateVersion = "25.05";
}
