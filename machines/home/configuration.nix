{ config, pkgs, ... }:
{
  networking.hostName = "home";

  networking.firewall.allowedTCPPorts = [ ];

  # Docker services for applications
  services.compose-services.services = [
    "webapp"
    "traefik"
    "fireflyiii"
  ];

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
      rathole-noise-public = {
        owner = "rathole";
        group = "rathole";
        mode = "0400";
      };
      firefly-app-key = {
        owner = "www-data";
        group = "www-data";
        mode = "0400";
      };
      firefly-db-password = {
        owner = "www-data";
        group = "www-data";
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

  # www-data user for web services
  users.users.www-data = {
    isSystemUser = true;
    group = "www-data";
    uid = 33;
  };
  users.groups.www-data = {
    gid = 33;
  };

  # Rathole client configuration template
  sops.templates."rathole-client.toml" = {
    owner = "rathole";
    group = "rathole";
    mode = "0400";
    path = "/var/lib/rathole/rathole-client.toml";
    restartUnits = [ "rathole-client.service" ];
    content = ''
      [client]
      remote_addr = "home.alsharafi.dev:2333"
      default_token = "${config.sops.placeholder.rathole-token}"

      [client.transport]
      type = "noise"
      [client.transport.noise]
      remote_public_key = "${config.sops.placeholder.rathole-noise-public}"

      [client.services.traefik]
      type = "tcp"
      local_addr = "127.0.0.1:8080"
    '';
  };

  # Rathole client service
  systemd.services.rathole-client = {
    description = "Rathole proxy client";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "rathole";
      Group = "rathole";
      Restart = "always";
      RestartSec = "5";
      ExecStart = "${pkgs.rathole}/bin/rathole ${config.sops.templates."rathole-client.toml".path}";
    };
  };
}
