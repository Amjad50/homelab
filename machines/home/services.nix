{ config, pkgs, ... }:
{

  # Docker services for applications
  services.compose-services.services = [
    "traefik"
    "fireflyiii"
    "blinko"
    "memos"
    "minio"
    "n8n"
    "wud"
    "solidtime"
    "media-stack"
    "dashy"
    "filebrowser"
    "linkwarden"
    "stirling-pdf"
    "syncthing"
    "kavita"
    "audiobookshelf"
    "upsnap"
    "freshrss"
    "immich"
  ];

  # Create btrfs subvolumes for docker services
  systemd.tmpfiles.rules = [
    "v /mnt/storage/blinko 0755 dock docker - -"
    "v /mnt/storage/firefly 0755 dock docker - -"
    "v /mnt/storage/memos 0755 dock docker - -"
    "v /mnt/storage/minio 0755 dock docker - -"
    "v /mnt/storage/n8n 0755 dock docker - -"
    "v /mnt/storage/solidtime 0755 dock docker - -"
    "v /mnt/storage/wud 0755 dock docker - -"
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
    "v /mnt/storage/filebrowser 0755 1000 1000 - -"
    "d /mnt/storage/filebrowser/config 0755 1000 1000 - -"
    "d /mnt/storage/filebrowser/database 0755 1000 1000 - -"
    "v /mnt/storage/linkwarden 0755 dock docker - -"
    "v /mnt/storage/syncthing 0755 1000 1000 - -"
    "v /mnt/storage/upsnap 0755 1000 1000 - -"
    "v /mnt/storage/freshrss 0755 dock docker - -"
    "v /mnt/storage/immich 0755 dock docker - -"
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
      blinko-nextauth-secret = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      blinko-db-password = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      memos-telegram-bot-token = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      minio-root-password = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      n8n-db-password = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      n8n-encryption-key = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      wud-openid-client-secret = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      solidtime-app-key = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      solidtime-passport-private-key = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      solidtime-passport-public-key = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      solidtime-db-password = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      solidtime-super-admins = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      openai-api-key = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      linkwarden-nextauth-secret = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      linkwarden-db-password = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      linkwarden-kanidm-client-secret = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      stirlingpdf-kanidm-client-secret = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      freshrss-kanidm-client-secret = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      freshrss-crypto-secret = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      immich-db-password = {
        owner = "dock";
        group = "docker";
        mode = "0400";
      };
      # Backup secrets
      restic-repository-password = {
        owner = "root";
        group = "root";
        mode = "0400";
      };
      backup-aws-access-key-id = {
        owner = "root";
        group = "root";
        mode = "0400";
      };
      backup-aws-secret-access-key = {
        owner = "root";
        group = "root";
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

  # Blinko environment template
  sops.templates."blinko.env" = {
    owner = "dock";
    group = "docker";
    mode = "0400";
    path = "/var/lib/dock/blinko.env";
    content = ''
      # Database configuration
      POSTGRES_PASSWORD=${config.sops.placeholder.blinko-db-password}

      # Blinko application configuration
      DATABASE_URL=postgresql://blinko:${config.sops.placeholder.blinko-db-password}@blinko-db:5432/blinko
      NEXTAUTH_SECRET=${config.sops.placeholder.blinko-nextauth-secret}
    '';
  };

  # Memos Telegram bot environment template
  sops.templates."memos-telegram.env" = {
    owner = "dock";
    group = "docker";
    mode = "0400";
    path = "/var/lib/dock/memos-telegram.env";
    content = ''
      BOT_TOKEN=${config.sops.placeholder.memos-telegram-bot-token}
    '';
  };

  # MinIO environment template
  sops.templates."minio.env" = {
    owner = "dock";
    group = "docker";
    mode = "0400";
    path = "/var/lib/dock/minio.env";
    content = ''
      MINIO_ROOT_PASSWORD=${config.sops.placeholder.minio-root-password}
    '';
  };

  # Solidtime environment template
  sops.templates."solidtime.env" = {
    owner = "dock";
    group = "docker";
    mode = "0400";
    path = "/var/lib/dock/solidtime.env";
    content = ''
      # Database configuration
      DB_PASSWORD=${config.sops.placeholder.solidtime-db-password}

      # Application configuration
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

  # Linkwarden environment template
  sops.templates."linkwarden.env" = {
    owner = "dock";
    group = "docker";
    mode = "0400";
    path = "/var/lib/dock/linkwarden.env";
    content = ''
      # Database configuration
      POSTGRES_PASSWORD=${config.sops.placeholder.linkwarden-db-password}

      # linkwarden application configuration
      DATABASE_URL=postgresql://linkwarden:${config.sops.placeholder.linkwarden-db-password}@linkwarden-db:5432/linkwarden
      NEXTAUTH_SECRET=${config.sops.placeholder.linkwarden-nextauth-secret}
      AUTHELIA_CLIENT_SECRET=${config.sops.placeholder.linkwarden-kanidm-client-secret}
      OPENAI_API_KEY=${config.sops.placeholder.openai-api-key} # use same API key as Karakeep
    '';
  };

  # Stirling-PDF environment template
  sops.templates."stirlingpdf.env" = {
    owner = "dock";
    group = "docker";
    mode = "0400";
    path = "/var/lib/dock/stirlingpdf.env";
    content = ''
      # Stirling-PDF application configuration
      SECURITY_OAUTH2_CLIENTSECRET=${config.sops.placeholder.stirlingpdf-kanidm-client-secret}
    '';
  };

  # FreshRSS environment template
  sops.templates."freshrss.env" = {
    owner = "dock";
    group = "docker";
    mode = "0400";
    path = "/var/lib/dock/freshrss.env";
    content = ''
      # FreshRSS OIDC configuration
      OIDC_CLIENT_SECRET=${config.sops.placeholder.freshrss-kanidm-client-secret}
      OIDC_CLIENT_CRYPTO_KEY=${config.sops.placeholder.freshrss-crypto-secret}
    '';
  };

  # S3 environment template for Backblaze B2
  sops.templates."restic-s3.env" = {
    owner = "root";
    group = "root";
    mode = "0400";
    path = "/var/lib/restic/s3.env";
    content = ''
      AWS_ACCESS_KEY_ID=${config.sops.placeholder.backup-aws-access-key-id}
      AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.backup-aws-secret-access-key}
    '';
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
      remote_addr = "home.amsh.dev:2333"
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
