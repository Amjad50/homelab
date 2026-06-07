# Hardware profile for the Oracle Cloud Ampere A1 (aarch64) replica of middle.
# Oracle presents the boot volume as /dev/sda and boots via UEFI.
# Disk layout is disko-managed (same layout as the other machines).
{ lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (import ../disko/home.nix { inherit lib; device = "/dev/sda"; })
  ];

  # virtio + Oracle (KVM) guest modules needed in initrd to find the root disk.
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_net"
    "sd_mod"
    "sr_mod"
    "xhci_pci"
  ];
  boot.initrd.kernelModules = [ ];
  # No kvm-amd/kvm-intel on aarch64.
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  swapDevices = [ ];

  # GRUB UEFI. disko mounts the ESP at /boot/efi (see disko/home.nix).
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.efi.canTouchEfiVariables = false;

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
