{ config, pkgs, ... }:
{
  imports = [
    ./fail2ban.nix
    ./networking.nix
  ];

  # Docker Compose services
  services.compose-services.services = [
    "traefik" # Reverse proxy with HTTPS
    "wg-easy" # WireGuard VPN management
    "ys-sitecore" # Django web application
    "kanidm"
    "oauth2-proxy" # OAuth2 proxy for authentication
    "adguard" # DNS server
    "netdata" # Monitoring
  ];

  systemd.tmpfiles.rules = [
    "v /storage 0755 dock docker - -"
    "v /storage/adguard 0755 dock docker - -"
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
      rathole-noise-private = {
        owner = "rathole";
        group = "rathole";
        mode = "0400";
      };
      oauth2-proxy-client-secret = {
        owner = "nobody";
        group = "nogroup";
        mode = "0400";
      };
      oauth2-proxy-cookie-secret = {
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

  # OAuth2 Proxy environment file template
  sops.templates."oauth2-proxy.env" = {
    owner = "dock";
    group = "docker";
    mode = "0400";
    path = "/var/lib/dock/oauth2-proxy.env";
    content = ''
      OAUTH2_PROXY_COOKIE_SECRET=${config.sops.placeholder.oauth2-proxy-cookie-secret}
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

  # Restic backup configuration
  services.restic.backups = {
    # Daily backups for middle server
    middle-daily = {
      repository = "s3:s3.eu-central-003.backblazeb2.com/amsh-homelab-backup/backups/middle-daily";
      passwordFile = config.sops.secrets.restic-repository-password.path;
      environmentFile = config.sops.templates."restic-s3.env".path;
      paths = [
        "/tmp/middle-backups-daily" # Service backups
        "/storage/adguard/conf" # AdGuard configuration (direct path backup)
      ];
      initialize = true;
      timerConfig = {
        OnCalendar = "03:00"; # Run at 3 AM (offset from home server)
        RandomizedDelaySec = "15m";
        Persistent = true;
      };
      pruneOpts = [
        "--keep-daily 30"
        "--keep-weekly 8"
        "--keep-monthly 12"
      ];
      extraBackupArgs = [
        "--tag daily"
        "--tag homelab"
        "--tag middle-server"
      ];
      backupPrepareCommand = ''
        export PATH="${pkgs.docker}/bin:${pkgs.hostname}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:${pkgs.gawk}/bin:${pkgs.findutils}/bin:${pkgs.gnutar}/bin:${pkgs.sqlite}/bin:$PATH"
        ${pkgs.writeShellScriptBin "backup-prepare-middle" (builtins.readFile ./scripts/backup-prepare-middle.sh)}/bin/backup-prepare-middle /tmp/middle-backups-daily
      '';
      backupCleanupCommand = ''
        export PATH="${pkgs.coreutils}/bin:$PATH"
        ${pkgs.writeShellScriptBin "backup-cleanup-middle" (builtins.readFile ./scripts/backup-cleanup-middle.sh)}/bin/backup-cleanup-middle /tmp/middle-backups-daily
      '';
    };
  };

  # Install backup scripts as system packages
  environment.systemPackages = with pkgs; [
    sqlite
    (writeShellScriptBin "backup-prepare-middle" (builtins.readFile ./scripts/backup-prepare-middle.sh))
    (writeShellScriptBin "backup-cleanup-middle" (builtins.readFile ./scripts/backup-cleanup-middle.sh))
  ];
}
