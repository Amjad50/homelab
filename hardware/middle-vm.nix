# Hardware profile for the VM replica of the middle machine.
# Uses disko-managed disk layout (vda=OS, vdb=storage).
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
    (import ../disko/home.nix {
      inherit lib;
      device = "/dev/vda";
      storageDevice = "/dev/vdb";
    })
  ];

  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "sr_mod"
  ];
  boot.initrd.kernelModules = [ "virtio_gpu" ];
  boot.kernelModules = [ "kvm-amd" "kvm-intel" ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };
  boot.loader.efi.canTouchEfiVariables = false;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
