{ config, lib, pkgs, ... }:
{
  imports = [
    ../home/services.nix
    ../home/backup.nix
    ./networking.nix
    # omit ../home/swap.nix — zram not needed in VM
    # omit ../home/secure-boot.nix — lanzaboote not used for VM
  ];

  networking.hostName = "home-vm";

  nix.settings.trusted-users = [ "root" "@wheel" ];

  # Temporary root password for VM debugging — NOT for production
  users.users.root.initialPassword = "nixos";

  # VM-only SSH policy for post-install checks and restore.
  # vm-create.sh injects the VM client key into /etc/ssh/authorized_keys.d.
  services.openssh.settings.PermitRootLogin = lib.mkForce "yes";

  # Override sops to use VM-specific secrets file
  sops = {
    defaultSopsFile = lib.mkForce ./secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  # Install restore script into VM
  environment.etc."homelab-scripts/vm-restore.sh" = {
    source = pkgs.writeShellScript "vm-restore"
      (builtins.readFile ../../scripts/vm-restore.sh);
    mode = "0755";
  };

  environment.systemPackages = with pkgs; [ restic ];

  # Copy docker-compose files from the Nix store into /opt/docker-services on activation
  # This replaces the manual `cp` step in deploy.sh for nixos-anywhere installs
  system.activationScripts.docker-services = {
    deps = [ "users" "groups" ];
    text = ''
      mkdir -p /opt/docker-services
      cp -r --no-preserve=ownership ${../home/docker-services}/. /opt/docker-services/
      chown -R dock:docker /opt/docker-services
      chmod -R u+rw /opt/docker-services
    '';
  };
}
