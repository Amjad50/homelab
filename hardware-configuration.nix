# This is a template hardware configuration.
# You'll need to replace this with your actual hardware configuration
# which you can get from /etc/nixos/hardware-configuration.nix on your server

{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "virtio_pci"
    "sr_mod"
    "virtio_blk"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
    fsType = "btrfs";
    options = [
      "subvol=root"
      "compress=zstd:3"
      "noatime"
      "space_cache=v2"
    ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
    fsType = "btrfs";
    options = [
      "subvol=home"
      "compress=zstd:1"
      "noatime"
      "space_cache=v2"
    ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
    fsType = "btrfs";
    options = [
      "subvol=nix"
      "compress=zstd:3"
      "noatime"
      "space_cache=v2"
    ];
  };

  fileSystems."/var" = {
    device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
    fsType = "btrfs";
    options = [
      "subvol=var"
      "compress=zstd:1"
      "noatime"
      "space_cache=v2"
    ];
  };

  fileSystems."/var/log" = {
    device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
    fsType = "btrfs";
    options = [
      "subvol=var-log"
      "compress=zstd:6"
      "noatime"
      "space_cache=v2"
    ];
  };

  fileSystems."/var/cache" = {
    device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
    fsType = "btrfs";
    options = [
      "subvol=var-cache"
      "nodatacow"
      "noatime"
      "space_cache=v2"
    ];
  };

  fileSystems."/var/tmp" = {
    device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
    fsType = "btrfs";
    options = [
      "subvol=var-tmp"
      "nodatacow"
      "noatime"
      "space_cache=v2"
    ];
  };

  fileSystems."/var/lib" = {
    device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
    fsType = "btrfs";
    options = [
      "subvol=var-lib"
      "compress=zstd:1"
      "noatime"
      "space_cache=v2"
    ];
  };

  fileSystems."/var/lib/docker" = {
    device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
    fsType = "btrfs";
    options = [
      "subvol=var-lib-docker"
      "compress=zstd:1"
      "noatime"
      "space_cache=v2"
    ];
  };

  fileSystems."/srv" = {
    device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
    fsType = "btrfs";
    options = [
      "subvol=srv"
      "compress=zstd:1"
      "noatime"
      "space_cache=v2"
    ];
  };

  fileSystems."/opt" = {
    device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
    fsType = "btrfs";
    options = [
      "subvol=opt"
      "compress=zstd:1"
      "noatime"
      "space_cache=v2"
    ];
  };

  fileSystems."/tmp" = {
    device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
    fsType = "btrfs";
    options = [
      "subvol=tmp"
      "nodatacow"
      "noatime"
      "space_cache=v2"
    ];
  };

  fileSystems."/.snapshots" = {
    device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
    fsType = "btrfs";
    options = [
      "subvol=snapshots"
      "compress=zstd:1"
      "noatime"
      "space_cache=v2"
    ];
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-uuid/FF06-F2B1";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  swapDevices = [ ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp1s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
