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

  # Sadly no way to do this in NixOS firewall
  # Allow port 8080 only from Docker networks (dynamically detect all Docker networks)
  networking.firewall.extraCommands = ''
    # Allow from all Docker bridge networks (172.16.0.0/12 covers docker0 and custom networks)
    iptables -A INPUT -p tcp --dport 8080 -s 172.16.0.0/12 -j ACCEPT
    # Allow from localhost
    iptables -A INPUT -p tcp --dport 8080 -s 127.0.0.1 -j ACCEPT
    # Drop everything else
    iptables -A INPUT -p tcp --dport 8080 -j DROP
  '';

  networking.firewall.extraStopCommands = ''
    iptables -D INPUT -p tcp --dport 8080 -s 172.16.0.0/12 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 8080 -s 127.0.0.1 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 8080 -j DROP 2>/dev/null || true
  '';

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

      [server.services.traefik]
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
