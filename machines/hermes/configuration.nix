{ pkgs, lib, adminKeys, hermes-agent, ... }:
{
  imports = [
    hermes-agent.nixosModules.default
    ./networking.nix
    ./cloudflared.nix
  ];
  system.stateVersion = "26.05";
  nixpkgs.hostPlatform = "x86_64-linux";
  time.timeZone = "Asia/Kuala_Lumpur";
  networking.hostName = "hermes";
  nix.enable = false;
  # Hermes invokes agent-browser from npm; its prebuilt ELF expects the
  # conventional Linux loader rather than a Nix store interpreter.
  programs.nix-ld.enable = true;
  documentation.enable = false;
  security.sudo.wheelNeedsPassword = false;
  users.mutableUsers = false;
  users.users.amjad = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = adminKeys;
  };
  services.openssh = {
    enable = true;
    openFirewall = false;
    hostKeys = [{ path = "/var/lib/ssh/ssh_host_ed25519_key"; type = "ed25519"; }];
    settings = { PasswordAuthentication = false; KbdInteractiveAuthentication = false; PermitRootLogin = "no"; };
  };
  systemd.tmpfiles.rules = [ "d /var/lib/ssh 0700 root root - -" ];
  services.journald.extraConfig = "SystemMaxUse=256M\nRuntimeMaxUse=64M";
  boot.initrd.kernelModules = [ "qemu_fw_cfg" ];
  environment.systemPackages = with pkgs; [ curl jq iproute2 ];
  microvm = {
    hypervisor = "qemu";
    vcpu = 2;
    mem = 4096;
    shares = [];
    storeOnDisk = true;
    # Store paths carry no required xattrs; disabling them also supports builds
    # on filesystems that return EOPNOTSUPP for listxattr (e.g. local sandbox FS).
    storeDiskErofsFlags = [ "-zlz4hc" "-Eztailpacking" "-Efragments" "-x-1" ];
    writableStoreOverlay = null;
    # No software-emulation fallback; own store disk, no host filesystem exports.
    qemu.machine = "q35";
    # nixpkgs' headless variant retains KVM/seccomp without display/audio stacks.
    qemu.package = pkgs.qemu_kvm.override { nixosTestRunner = true; };
    qemu.machineOpts = { accel = "kvm"; acpi = "on"; mem-merge = "off"; };
    interfaces = [{ type = "tap"; id = "hermes-tap"; mac = "02:00:00:fa:00:02"; }];
    volumes = [
      { image = "state.img"; mountPoint = "/var"; size = 32768; }
      { image = "docker.img"; mountPoint = "/var/lib/hermes-execution"; size = 32768; }
    ];
    credentialFiles = lib.genAttrs [ "hermes.env" "cloudflared-token" ]
      (name: "/run/credentials/microvm@hermes.service/${name}");
  };
}
