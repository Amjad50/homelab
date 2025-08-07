{ config, pkgs, ... }:
{
  networking.hostName = "home";

  networking.firewall.allowedTCPPorts = [ 5055 8096 ];

  # Use static ipv4
  networking.interfaces.eno2 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "192.168.0.5";
        prefixLength = 24;
      }
    ];
  };
  networking.defaultGateway = {
    address = "192.168.0.1";
    interface = "eno2";
  };

  # Docker services for applications
  services.compose-services.services = [
    "webapp"
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
      PASSPORT_PRIVATE_KEY="${builtins.replaceStrings ["\\\\"] ["\\"] config.sops.placeholder.solidtime-passport-private-key}"
      PASSPORT_PUBLIC_KEY="${builtins.replaceStrings ["\\\\"] ["\\"] config.sops.placeholder.solidtime-passport-public-key}"
      SUPER_ADMINS="${config.sops.placeholder.solidtime-super-admins}"
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
