# This is a template hardware configuration.
# You'll need to replace this with your actual hardware configuration
# which you can get from /etc/nixos/hardware-configuration.nix on your server

{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/profiles/qemu-guest.nix")
    ];

  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "sr_mod" "virtio_blk" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
      fsType = "btrfs";
      options = [ "subvol=root" "compress=zstd" "noatime" ];
    };

  fileSystems."/home" =
    { device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
      fsType = "btrfs";
      options = [ "subvol=home" "compress=zstd" "noatime" ];
    };

  fileSystems."/nix" =
    { device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
      fsType = "btrfs";
      options = [ "subvol=nix" "compress=zstd" "noatime" ];
    };

  fileSystems."/var" =
    { device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
      fsType = "btrfs";
      options = [ "subvol=var"  "compress=zstd" "noatime"];
    };

  fileSystems."/tmp" =
    { device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
      fsType = "btrfs";
      options = [ "subvol=tmp"  "compress=zstd" "noatime" ];
    };

  fileSystems."/snapshots" =
    { device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
      fsType = "btrfs";
      options = [ "subvol=snapshots" "compress=zstd" "noatime" ];
    };

  fileSystems."/boot/efi" =
    { device = "/dev/disk/by-uuid/FF06-F2B1";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
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
