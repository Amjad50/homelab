# Middle machine service registry.
{ config, lib, pkgs, ... }:
{
  homelab.services = {
    traefik = {
      secrets = {
        cloudflare-email           = { owner = "dock";    group = "docker";  mode = "0400"; };
        cloudflare-dns-api-token   = { owner = "dock";    group = "docker";  mode = "0400"; };
        cloudflare-zone-api-token  = { owner = "dock";    group = "docker";  mode = "0400"; };
      };
    };

    wg-easy = {
    };

    dockge = {
      tmpfiles = [
        "v /storage/dockge 0755 dock docker - -"
      ];
      dependsOnBackups = [ config.homelab.backups.default ];
    };

    kanidm = {
    };

    oauth2-proxy = {
      secrets = {
        oauth2-proxy-client-secret = { owner = "nobody"; group = "nogroup"; mode = "0400"; };
        oauth2-proxy-cookie-secret = { owner = "dock";   group = "docker";  mode = "0400"; };
      };
      templates."oauth2-proxy.env" = {
        owner = "dock"; group = "docker"; mode = "0400";
        path = "/var/lib/dock/oauth2-proxy.env";
        content = ''
          OAUTH2_PROXY_COOKIE_SECRET=${config.sops.placeholder.oauth2-proxy-cookie-secret}
        '';
      };
    };

    adguard = {
      tmpfiles = [
        "v /storage/adguard 0755 dock docker - -"
      ];
      dependsOnBackups = [ config.homelab.backups.default ];
    };

    netdata = {
    };
  };

  homelab.backups.default = {
    autoStart = true;
    schedule = "03:00";

    paths = [
      "/storage/dockge/data/db-config.json"
      "/storage/dockge/data/dockge.db"
      "/storage/adguard/conf"
    ];

    postgres = [];
  };

  # Non-registry items: rathole server, cloudflare creds, /storage root.
  systemd.tmpfiles.rules = [
    "v /storage 0755 dock docker - -"
  ];

  sops.secrets = {
    rathole-token              = { owner = "rathole"; group = "rathole"; mode = "0400"; };
    rathole-noise-private      = { owner = "rathole"; group = "rathole"; mode = "0400"; };
    restic-repository-password = { owner = "root";    group = "root";    mode = "0400"; };
    backup-aws-access-key-id   = { owner = "root";    group = "root";    mode = "0400"; };
    backup-aws-secret-access-key = { owner = "root";  group = "root";    mode = "0400"; };
  };

  sops.templates."restic-s3.env" = {
    owner = "root"; group = "root"; mode = "0400";
    path = "/var/lib/restic/s3.env";
    content = ''
      AWS_ACCESS_KEY_ID=${config.sops.placeholder.backup-aws-access-key-id}
      AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.backup-aws-secret-access-key}
    '';
  };

  users.users.rathole = {
    isSystemUser = true;
    group = "rathole";
    home = "/var/lib/rathole";
    createHome = true;
  };
  users.groups.rathole = { };

  sops.templates."rathole-server.toml" = {
    owner = "rathole"; group = "rathole"; mode = "0400";
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

      [server.services.dockge]
      type = "tcp"
      bind_addr = "0.0.0.0:5001"
    '';
  };

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
