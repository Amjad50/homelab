# Middle machine service registry.
{ config, lib, pkgs, ... }:
{
  homelab.dockerServicesDir = ../docker-services;

  homelab.services = {
    traefik = {
      secrets = {
        cloudflare-email           = { owner = "dock";    group = "docker";  mode = "0400"; };
        cloudflare-dns-api-token   = { owner = "dock";    group = "docker";  mode = "0400"; };
        cloudflare-zone-api-token  = { owner = "dock";    group = "docker";  mode = "0400"; };
      };
    };

    wg-easy = {
      tmpfiles = [
        "v /storage/wg-easy 0755 dock docker - -"
      ];
      backup = {
        group = config.homelab.backups.default;
        paths = [
          "/storage/wg-easy"
        ];
        sqlite = [
          { path = "/storage/wg-easy/wg-easy.db"; }
        ];
      };
    };

    dockge = {
      tmpfiles = [
        "v /storage/dockge 0755 dock docker - -"
      ];
      backup = {
        group = config.homelab.backups.default;
        paths = [
          "/storage/dockge/data/db-config.json"
          "/storage/dockge/data/dockge.db"
        ];
        sqlite = [
          { path = "/storage/dockge/data/dockge.db"; }
        ];
      };
    };

    beszel = {
      tmpfiles = [
        "v /storage/beszel 0755 dock docker - -"
        "d /storage/beszel/data 0755 dock docker - -"
        "v /storage/beszel-agent 0755 dock docker - -"
        # for socket
        "d /var/run/beszel 0755 dock docker - -"
      ];
      secrets = {
        beszel-hub-public-key = { owner = "dock"; group = "docker"; mode = "0400"; };
        beszel-middle-agent-token = { owner = "dock"; group = "docker"; mode = "0400"; };
      };
      backup = {
        group = config.homelab.backups.default;
        paths = [ "/storage/beszel/data" ];
        sqlite = [
          { path = "/storage/beszel/data/data.db"; }
          { path = "/storage/beszel/data/auxiliary.db"; }
        ];
      };
    };

    kanidm = {
      backup = {
        group = config.homelab.backups.default;
        customBackupScript = ''
          compose-manage exec -T kanidm kanidm /sbin/kanidmd database backup -c /data/server.toml /data/backups/kanidm.backup.json.gz
          docker cp "kanidm:/data/backups/kanidm.backup.json.gz" "$SERVICE_ARTIFACT_DIR/kanidm.backup.json.gz"
          docker run --rm --volumes-from kanidm alpine rm /data/backups/kanidm.backup.json.gz
          echo "Backup complete, artifact stored at $SERVICE_ARTIFACT_DIR/kanidm.backup.json.gz"
        '';
        customRestoreScript = ''
          test -f "$SERVICE_ARTIFACT_DIR/kanidm.backup.json"
          docker run --rm -i \
            -v /opt/docker-services/kanidm/config/server.toml:/data/server.toml:ro \
            -v kanidm_kanidm_data:/data \
            -v "$SERVICE_ARTIFACT_DIR:/backup" \
            kanidm/server:latest \
            /sbin/kanidmd database restore -c /data/server.toml /backup/kanidm.backup.json.gz
        '';
      };
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

    headscale = {
      tmpfiles = [
        "v /storage/headscale 0755 dock docker - -"
        "d /storage/headscale/headscale 0755 dock docker - -"
        "d /storage/headscale/headplane 0755 dock docker - -"
        # dns_records.json must pre-exist as a FILE (else docker bind-mounts a dir).
        # Seed with empty-array JSON; headplane rewrites it. 'f' won't clobber existing.
        "f /storage/headscale/dns_records.json 0664 dock docker - []"
      ];
      secrets = {
        headscale-kanidm-client-secret = { owner = "dock"; group = "docker"; mode = "0400"; };
        headplane-cookie-secret = { owner = "dock"; group = "docker"; mode = "0400"; };
        headplane-headscale-api-key = { owner = "dock"; group = "docker"; mode = "0400"; };
      };
      templates."headscale.env" = {
        owner = "dock"; group = "docker"; mode = "0400";
        path = "/var/lib/dock/headscale.env";
        content = ''
          HEADSCALE_OIDC_CLIENT_SECRET=${config.sops.placeholder.headscale-kanidm-client-secret}
        '';
      };
      backup = {
        group = config.homelab.backups.default;
        paths = [ "/storage/headscale" ];
        sqlite = [
          { path = "/storage/headscale/headscale/db.sqlite"; }
          { path = "/storage/headscale/headplane/hp_persist.db"; }
        ];
      };
    };

    adguard = {
      tmpfiles = [
        "v /storage/adguard 0755 dock docker - -"
      ];
      backup = {
        group = config.homelab.backups.default;
        paths = [
          "/storage/adguard/conf"
        ];
      };
    };

    netbird = {
      tmpfiles = [
        "v /storage/netbird 0755 dock docker - -"
        "d /storage/netbird/data 0755 dock docker - -"
      ];
      secrets = {
        netbird-datastore-enc-key = { owner = "dock"; group = "docker"; mode = "0400"; };
        netbird-relay-auth-secret = { owner = "dock"; group = "docker"; mode = "0400"; };
      };
      templates = {
        "netbird-config.yaml" = {
          owner = "dock"; group = "docker"; mode = "0400";
          path = "/var/lib/dock/netbird-config.yaml";
          content = ''
            server:
              listenAddress: ":80"
              exposedAddress: "https://netbird.leaf-svc.cc:443"
              stunPorts:
                - 3480
              metricsPort: 9090
              healthcheckAddress: ":9000"
              logLevel: "info"
              logFile: "console"
              disableAnonymousMetrics: true
              authSecret: "${config.sops.placeholder.netbird-relay-auth-secret}"
              dataDir: "/var/lib/netbird"
              auth:
                issuer: "https://netbird.leaf-svc.cc/oauth2"
                localAuthDisabled: true
                signKeyRefreshEnabled: true
                # Both domains registered during the amsh.dev -> leaf-svc.cc migration
                # so the dashboard authenticates on either host. Drop the amsh.dev
                # entries once all clients have reconnected on leaf-svc.cc.
                dashboardRedirectURIs:
                  - "https://netbird.leaf-svc.cc/nb-auth"
                  - "https://netbird.leaf-svc.cc/nb-silent-auth"
                  - "https://netbird.home.amsh.dev/nb-auth"
                  - "https://netbird.home.amsh.dev/nb-silent-auth"
                cliRedirectURIs:
                  - "http://localhost:53000/"
              reverseProxy:
                trustedHTTPProxies:
                  - "172.18.0.0/16"
                trustedPeers:
                  - "0.0.0.0/0"
              store:
                engine: "sqlite"
                encryptionKey: "${config.sops.placeholder.netbird-datastore-enc-key}"
          '';
        };
        "netbird-dashboard.env" = {
          owner = "dock"; group = "docker"; mode = "0400";
          path = "/var/lib/dock/netbird-dashboard.env";
          content = ''
            NETBIRD_MGMT_API_ENDPOINT=https://netbird.leaf-svc.cc
            NETBIRD_MGMT_GRPC_API_ENDPOINT=https://netbird.leaf-svc.cc
            AUTH_AUDIENCE=netbird-dashboard
            AUTH_CLIENT_ID=netbird-dashboard
            AUTH_CLIENT_SECRET=
            AUTH_AUTHORITY=https://netbird.leaf-svc.cc/oauth2
            USE_AUTH0=false
            AUTH_SUPPORTED_SCOPES=openid profile email groups
            AUTH_REDIRECT_URI=/nb-auth
            AUTH_SILENT_REDIRECT_URI=/nb-silent-auth
            NGINX_SSL_PORT=443
            LETSENCRYPT_DOMAIN=none
          '';
        };
      };
      backup = {
        group = config.homelab.backups.default;
        paths = [ "/storage/netbird/data" ];
      };
    };

    ntfy = {
      tmpfiles = [
        "v /storage/ntfy 0755 dock docker - -"
        "d /storage/ntfy/cache 0755 dock docker - -"
        "d /storage/ntfy/attachments 0755 dock docker - -"
        "d /storage/ntfy/data 0755 dock docker - -"
      ];
      secrets = {
        ntfy-first-provisioned-users = { owner = "dock"; group = "docker"; mode = "0400"; };
      };
      templates."ntfy.env" = {
        owner = "dock"; group = "docker"; mode = "0400";
        path = "/var/lib/dock/ntfy.env";
        content = ''
          NTFY_AUTH_USERS=${config.sops.placeholder.ntfy-first-provisioned-users}
        '';
      };
      backup = {
        group = config.homelab.backups.default;
        paths = [ "/storage/ntfy" ];
        # cache.db omitted (regenerable message cache); auth.db holds users/tokens.
        sqlite = [
          { path = "/storage/ntfy/data/auth.db"; }
        ];
      };
    };
  };

  homelab.backups.default = {
    restoreAutoStart = true;
    schedule = "03:00";
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
      RESTIC_PROGRESS_FPS=0.1
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
      bind_addr = "[::]:2333"
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
