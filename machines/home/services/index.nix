# Home machine service registry — single source of truth.
# Replaces machines/home/services.nix and machines/home/backup.nix.
{ config, lib, pkgs, ... }:
{
  homelab.services = {
    traefik = {
      tmpfiles = [];
    };

    memos = {
      enable = false;
      tmpfiles = [ "v /mnt/storage/memos 0755 dock docker - -" ];
      secrets.memos-telegram-bot-token = { owner = "dock"; group = "docker"; mode = "0400"; };
      templates."memos-telegram.env" = {
        owner = "dock"; group = "docker"; mode = "0400";
        path = "/var/lib/dock/memos-telegram.env";
        content = ''
          BOT_TOKEN=${config.sops.placeholder.memos-telegram-bot-token}
        '';
      };
    };

    minio = {
      enable = false;
      tmpfiles = [ "v /mnt/storage/minio 0755 dock docker - -" ];
      secrets.minio-root-password = { owner = "dock"; group = "docker"; mode = "0400"; };
      templates."minio.env" = {
        owner = "dock"; group = "docker"; mode = "0400";
        path = "/var/lib/dock/minio.env";
        content = ''
          MINIO_ROOT_PASSWORD=${config.sops.placeholder.minio-root-password}
        '';
      };
    };

    wud = {
      enable = false;
      tmpfiles = [ "v /mnt/storage/wud 0755 dock docker - -" ];
      secrets.wud-openid-client-secret = { owner = "dock"; group = "docker"; mode = "0400"; };
    };

    freshrss = {
      enable = false;
      tmpfiles = [ "v /mnt/storage/freshrss 0755 dock docker - -" ];
      secrets = {
        freshrss-kanidm-client-secret = { owner = "dock"; group = "docker"; mode = "0400"; };
        freshrss-crypto-secret        = { owner = "dock"; group = "docker"; mode = "0400"; };
      };
      templates."freshrss.env" = {
        owner = "dock"; group = "docker"; mode = "0400";
        path = "/var/lib/dock/freshrss.env";
        content = ''
          OIDC_CLIENT_SECRET=${config.sops.placeholder.freshrss-kanidm-client-secret}
          OIDC_CLIENT_CRYPTO_KEY=${config.sops.placeholder.freshrss-crypto-secret}
        '';
      };
    };

    dockge = {
      tmpfiles = [
        "v /mnt/storage/dockge 0755 dock docker - -"
      ];
      dependsOnBackups = [ config.homelab.backups.default ];
    };

    dashy = {
    };

    filebrowser = {
      tmpfiles = [
        "v /mnt/storage/filebrowser 0755 1000 1000 - -"
        "d /mnt/storage/filebrowser/config 0755 1000 1000 - -"
        "d /mnt/storage/filebrowser/database 0755 1000 1000 - -"
      ];
      dependsOnBackups = [ config.homelab.backups.default ];
    };

    syncthing = {
      tmpfiles = [
        "v /mnt/storage/syncthing 0755 1000 1000 - -"
      ];
      dependsOnBackups = [ config.homelab.backups.default ];
    };

    upsnap = {
      tmpfiles = [ "v /mnt/storage/upsnap 0755 1000 1000 - -" ];
      dependsOnBackups = [ config.homelab.backups.default ];
    };

    stirling-pdf = {
      secrets.stirlingpdf-kanidm-client-secret = {
        owner = "dock"; group = "docker"; mode = "0400";
      };
      templates."stirlingpdf.env" = {
        owner = "dock"; group = "docker"; mode = "0400";
        path = "/var/lib/dock/stirlingpdf.env";
        content = ''
          SECURITY_OAUTH2_CLIENTSECRET=${config.sops.placeholder.stirlingpdf-kanidm-client-secret}
        '';
      };
    };

    kavita = {
    };

    audiobookshelf = {
    };

    media-stack = {
      tmpfiles = [
        "v /mnt/storage/media 0755 dock docker - -"
        "v /mnt/storage/media/movies 0755 1000 1000 - -"
        "v /mnt/storage/media/tv 0755 1000 1000 - -"
        "v /mnt/storage/media/configs 0755 dock docker - -"
        "v /mnt/storage/media/downloads 0755 1000 1000 - -"
        "v /mnt/storage/media/books 0755 1000 1000 - -"
        "v /mnt/storage/media/comics 0755 1000 1000 - -"
        "v /mnt/storage/media/manga 0755 1000 1000 - -"
        "v /mnt/storage/media/audiobooks 0755 1000 1000 - -"
        "v /mnt/storage/media/podcasts 0755 1000 1000 - -"
      ];
      dependsOnBackups = [ config.homelab.backups.default ];
    };

    fireflyiii = {
      tmpfiles = [ "v /mnt/storage/firefly 0755 dock docker - -" ];
      secrets = {
        firefly-app-key     = { owner = "www-data"; group = "www-data"; mode = "0400"; };
        firefly-db-password = { owner = "www-data"; group = "www-data"; mode = "0400"; };
      };
      dependsOnBackups = [ config.homelab.backups.default ];
    };

    blinko = {
      tmpfiles = [ "v /mnt/storage/blinko 0755 dock docker - -" ];
      secrets = {
        blinko-nextauth-secret = { owner = "dock"; group = "docker"; mode = "0400"; };
        blinko-db-password     = { owner = "dock"; group = "docker"; mode = "0400"; };
      };
      templates."blinko.env" = {
        owner = "dock"; group = "docker"; mode = "0400";
        path = "/var/lib/dock/blinko.env";
        content = ''
          POSTGRES_PASSWORD=${config.sops.placeholder.blinko-db-password}
          DATABASE_URL=postgresql://blinko:${config.sops.placeholder.blinko-db-password}@blinko-db:5432/blinko
          NEXTAUTH_SECRET=${config.sops.placeholder.blinko-nextauth-secret}
        '';
      };
      dependsOnBackups = [ config.homelab.backups.default ];
    };

    n8n = {
      tmpfiles = [ "v /mnt/storage/n8n 0755 dock docker - -" ];
      secrets = {
        n8n-db-password    = { owner = "dock"; group = "docker"; mode = "0400"; };
        n8n-encryption-key = { owner = "dock"; group = "docker"; mode = "0400"; };
      };
      dependsOnBackups = [ config.homelab.backups.default ];
    };

    solidtime = {
      tmpfiles = [ "v /mnt/storage/solidtime 0755 dock docker - -" ];
      secrets = {
        solidtime-app-key              = { owner = "dock"; group = "docker"; mode = "0400"; };
        solidtime-passport-private-key = { owner = "dock"; group = "docker"; mode = "0400"; };
        solidtime-passport-public-key  = { owner = "dock"; group = "docker"; mode = "0400"; };
        solidtime-db-password          = { owner = "dock"; group = "docker"; mode = "0400"; };
        solidtime-super-admins         = { owner = "dock"; group = "docker"; mode = "0400"; };
      };
      templates."solidtime.env" = {
        owner = "dock"; group = "docker"; mode = "0400";
        path = "/var/lib/dock/solidtime.env";
        content = ''
          DB_PASSWORD=${config.sops.placeholder.solidtime-db-password}
          APP_KEY="${config.sops.placeholder.solidtime-app-key}"
          PASSPORT_PRIVATE_KEY="${
            builtins.replaceStrings [ "\\\\" ] [ "\\" ] config.sops.placeholder.solidtime-passport-private-key
          }"
          PASSPORT_PUBLIC_KEY="${
            builtins.replaceStrings [ "\\\\" ] [ "\\" ] config.sops.placeholder.solidtime-passport-public-key
          }"
          SUPER_ADMINS="${config.sops.placeholder.solidtime-super-admins}"
        '';
      };
      dependsOnBackups = [ config.homelab.backups.default ];
    };

    linkwarden = {
      tmpfiles = [ "v /mnt/storage/linkwarden 0755 dock docker - -" ];
      secrets = {
        linkwarden-nextauth-secret      = { owner = "dock"; group = "docker"; mode = "0400"; };
        linkwarden-db-password          = { owner = "dock"; group = "docker"; mode = "0400"; };
        linkwarden-kanidm-client-secret = { owner = "dock"; group = "docker"; mode = "0400"; };
        openai-api-key                  = { owner = "dock"; group = "docker"; mode = "0400"; };
      };
      templates."linkwarden.env" = {
        owner = "dock"; group = "docker"; mode = "0400";
        path = "/var/lib/dock/linkwarden.env";
        content = ''
          POSTGRES_PASSWORD=${config.sops.placeholder.linkwarden-db-password}
          DATABASE_URL=postgresql://linkwarden:${config.sops.placeholder.linkwarden-db-password}@linkwarden-db:5432/linkwarden
          NEXTAUTH_SECRET=${config.sops.placeholder.linkwarden-nextauth-secret}
          AUTHELIA_CLIENT_SECRET=${config.sops.placeholder.linkwarden-kanidm-client-secret}
          OPENAI_API_KEY=${config.sops.placeholder.openai-api-key}
        '';
      };
      dependsOnBackups = [ config.homelab.backups.default ];
    };

    immich = {
      tmpfiles = [ "v /mnt/storage/immich 0755 dock docker - -" ];
      secrets.immich-db-password = {
        owner = "dock"; group = "docker"; mode = "0400";
      };
      dependsOnBackups = [ config.homelab.backups.immich ];
    };

    infisical = {
      tmpfiles = [
        "v /mnt/storage/infisical 0755 dock docker - -"
        "d /mnt/storage/infisical/database 0755 dock docker - -"
      ];
      secrets = {
        infisical-db-password                 = { owner = "dock"; group = "docker"; mode = "0400"; };
        infisical-auth-secret                 = { owner = "dock"; group = "docker"; mode = "0400"; };
        infisical-encryption-key              = { owner = "dock"; group = "docker"; mode = "0400"; };
        infisical-github-oauth-client-id      = { owner = "dock"; group = "docker"; mode = "0400"; };
        infisical-github-oauth-client-secret  = { owner = "dock"; group = "docker"; mode = "0400"; };
        infisical-github-app-client-id        = { owner = "dock"; group = "docker"; mode = "0400"; };
        infisical-github-app-client-secret    = { owner = "dock"; group = "docker"; mode = "0400"; };
        infisical-github-app-slug             = { owner = "dock"; group = "docker"; mode = "0400"; };
        infisical-github-app-id               = { owner = "dock"; group = "docker"; mode = "0400"; };
        infisical-github-app-private-key      = { owner = "dock"; group = "docker"; mode = "0400"; };
      };
      templates."infisical.env" = {
        owner = "dock"; group = "docker"; mode = "0400";
        path = "/var/lib/dock/infisical.env";
        content = ''
          POSTGRES_PASSWORD=${config.sops.placeholder.infisical-db-password}
          DB_CONNECTION_URI=postgresql://infisical:${config.sops.placeholder.infisical-db-password}@infisical-db:5432/infisical
          REDIS_URL=redis://infisical-redis:6379
          ENCRYPTION_KEY=${config.sops.placeholder.infisical-encryption-key}
          AUTH_SECRET=${config.sops.placeholder.infisical-auth-secret}
          CLIENT_ID_GITHUB_LOGIN=${config.sops.placeholder.infisical-github-oauth-client-id}
          CLIENT_SECRET_GITHUB_LOGIN=${config.sops.placeholder.infisical-github-oauth-client-secret}
          INF_APP_CONNECTION_GITHUB_OAUTH_CLIENT_ID=${config.sops.placeholder.infisical-github-oauth-client-id}
          INF_APP_CONNECTION_GITHUB_OAUTH_CLIENT_SECRET=${config.sops.placeholder.infisical-github-oauth-client-secret}
          INF_APP_CONNECTION_GITHUB_APP_CLIENT_ID=${config.sops.placeholder.infisical-github-app-client-id}
          INF_APP_CONNECTION_GITHUB_APP_CLIENT_SECRET=${config.sops.placeholder.infisical-github-app-client-secret}
          INF_APP_CONNECTION_GITHUB_APP_SLUG=${config.sops.placeholder.infisical-github-app-slug}
          INF_APP_CONNECTION_GITHUB_APP_ID=${config.sops.placeholder.infisical-github-app-id}
          INF_APP_CONNECTION_GITHUB_APP_PRIVATE_KEY="${
            builtins.replaceStrings [ "\\\\" ] [ "\\" ] config.sops.placeholder.infisical-github-app-private-key
          }"
        '';
      };
      dependsOnBackups = [ config.homelab.backups.default ];
    };
  };

  homelab.backups = {
    default = {
      autoStart = true;

      paths = [
        "/mnt/storage/dockge/data/db-config.json"
        "/mnt/storage/dockge/data/dockge.db"
        "/mnt/storage/filebrowser"
        "/mnt/storage/syncthing/config"
        "/mnt/storage/syncthing/data"
        "/mnt/storage/upsnap"
        "/mnt/storage/media/configs"
        "/mnt/storage/media/books"
        "/mnt/storage/firefly/upload"
        "/mnt/storage/blinko/data"
        "/mnt/storage/n8n/data"
        "/mnt/storage/solidtime/app"
      ];

      postgres = [
        { stack = "fireflyiii"; composeService = "fireflyiii-db"; container = "fireflyiii-db"; database = "firefly";    user = "firefly";    }
        { stack = "blinko";     composeService = "blinko-db";     container = "blinko-db";     database = "blinko";     user = "blinko";     }
        { stack = "n8n";        composeService = "n8n-db";        container = "n8n-db";        database = "n8n";        user = "n8n";        }
        { stack = "solidtime";  composeService = "solidtime-db";  container = "solidtime-db";  database = "solidtime";  user = "solidtime";  }
        { stack = "linkwarden"; composeService = "linkwarden-db"; container = "linkwarden-db"; database = "linkwarden"; user = "linkwarden"; }
        { stack = "infisical";  composeService = "infisical-db";  container = "infisical-db";  database = "infisical";  user = "infisical";  }
      ];
    };

    immich = {
      autoStart = false;

      paths = [ "/mnt/storage/immich/upload/library" ];

      postgres = [
        { stack = "immich"; composeService = "database"; container = "immich_postgres"; database = "immich"; user = "postgres"; }
      ];

      postRestoreScript = ''
        for dir in encoded-video library upload profile thumbs backups; do
          mkdir -p "/mnt/storage/immich/upload/$dir"
          touch "/mnt/storage/immich/upload/$dir/.immich"
        done
      '';
    };
  };

  # Sops global configuration for this machine
  sops = {
    defaultSopsFile = ../secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  # Non-registry items: rathole user/group/template/service
  users.users.rathole = {
    isSystemUser = true;
    group = "rathole";
    home = "/var/lib/rathole";
    createHome = true;
  };
  users.groups.rathole = { };

  users.users.www-data = {
    isSystemUser = true;
    group = "www-data";
    uid = 33;
  };
  users.groups.www-data = {
    gid = 33;
  };

  sops.secrets = {
    rathole-token              = { owner = "rathole"; group = "rathole"; mode = "0400"; };
    rathole-noise-public       = { owner = "rathole"; group = "rathole"; mode = "0400"; };
    restic-repository-password = { owner = "root"; group = "root"; mode = "0400"; };
    backup-aws-access-key-id   = { owner = "root"; group = "root"; mode = "0400"; };
    backup-aws-secret-access-key = { owner = "root"; group = "root"; mode = "0400"; };
  };

  sops.templates."restic-s3.env" = {
    owner = "root"; group = "root"; mode = "0400";
    path = "/var/lib/restic/s3.env";
    content = ''
      AWS_ACCESS_KEY_ID=${config.sops.placeholder.backup-aws-access-key-id}
      AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.backup-aws-secret-access-key}
    '';
  };

  sops.templates."rathole-client.toml" = {
    owner = "rathole"; group = "rathole"; mode = "0400";
    path = "/var/lib/rathole/rathole-client.toml";
    restartUnits = [ "rathole-client.service" ];
    content = ''
      [client]
      remote_addr = "home.amsh.dev:2333"
      default_token = "${config.sops.placeholder.rathole-token}"

      [client.transport]
      type = "noise"
      [client.transport.noise]
      remote_public_key = "${config.sops.placeholder.rathole-noise-public}"

      [client.services.traefik]
      type = "tcp"
      local_addr = "127.0.0.1:8080"

      [client.services.dockge]
      type = "tcp"
      local_addr = "127.0.0.1:5001"
    '';
  };

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
