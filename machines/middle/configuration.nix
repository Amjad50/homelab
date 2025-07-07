{ config, pkgs, ... }:
{
  imports = [
    ./fail2ban.nix
  ];

  networking.hostName = "middle";

  # Firewall - allow web traffic, VPN, and rathole
  networking.firewall.allowedTCPPorts = [
    80
    443
    2333
  ];
  networking.firewall.allowedUDPPorts = [ 51820 ];

  # Docker Compose services
  services.compose-services.services = [
    "traefik" # Reverse proxy with HTTPS
    "wg-easy" # WireGuard VPN management
  ];

  # IPv6 NAT support for WireGuard
  boot.kernelModules = [ "ip6table_nat" ];

  # Sops secrets configuration using SSH host keys
  sops = {
    defaultSopsFile = ./secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      rathole-token = {
        owner = "rathole";
        group = "rathole";
        mode = "0400";
      };
      rathole-noise-private = {
        owner = "rathole";
        group = "rathole";
        mode = "0400";
      };
    };
  };

  # Rathole user
  users.users.rathole = {
    isSystemUser = true;
    group = "rathole";
    home = "/var/lib/rathole";
    createHome = true;
  };
  users.groups.rathole = { };

  # Rathole server configuration template
  sops.templates."rathole-server.toml" = {
    owner = "rathole";
    group = "rathole";
    mode = "0400";
    path = "/var/lib/rathole/rathole-server.toml";
    restartUnits = [ "rathole-server.service" ];
    content = ''
      [server]
      bind_addr = "0.0.0.0:2333"
      default_token = "${config.sops.placeholder.rathole-token}"

      [server.transport]
      type = "noise"
      [server.transport.noise]
      local_private_key = "${config.sops.placeholder.rathole-noise-private}"

      [server.services.home-web]
      type = "tcp"
      bind_addr = "0.0.0.0:8080"
    '';
  };

  # Rathole server service
  systemd.services.rathole-server = {
    description = "Rathole proxy server";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "rathole";
      Group = "rathole";
      Restart = "always";
      RestartSec = "5";
      ExecStart = "${pkgs.rathole}/bin/rathole ${config.sops.templates."rathole-server.toml".path}";
    };
  };
}
