{ config, lib, pkgs, ... }:
{
  imports = [
    ../middle/services/index.nix
  ];

  networking.hostName = "middle-vm";
  networking.useDHCP = lib.mkForce true;
  # Add ports relevant for middle machine if any, or keep it minimal
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  homelab.machineName = "middle";
  homelab.backupJobs.enable = false;

  nix.settings.trusted-users = [ "root" "@wheel" ];

  # Temporary root password for VM debugging — NOT for production
  users.users.root.initialPassword = "nixos";

  # VM-only SSH policy for post-install checks and restore.
  services.openssh.settings.PermitRootLogin = lib.mkForce "yes";

  # Override sops to use VM-specific secrets file
  sops = {
    defaultSopsFile = lib.mkForce ./secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  environment.systemPackages = with pkgs; [ restic ];

  # Copy docker-compose files from the Nix store into /opt/docker-services on activation
  system.activationScripts.docker-services = {
    deps = [ "users" "groups" ];
    text = ''
      mkdir -p /opt/docker-services
      cp -r --no-preserve=ownership ${../middle/docker-services}/. /opt/docker-services/
      chown -R dock:docker /opt/docker-services
      chmod -R u+rw /opt/docker-services
    '';
  };
}
