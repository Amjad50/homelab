{ config, pkgs, ... }:
{

  # Restic backup configuration
  services.restic.backups = {
    # Daily backups for critical services
    homelab-daily = {
      repository = "s3:s3.eu-central-003.backblazeb2.com/amsh-homelab-backup/backups/home-daily";
      passwordFile = config.sops.secrets.restic-repository-password.path;
      environmentFile = config.sops.templates."restic-s3.env".path;
      paths = [
        "/tmp/db-dumps-daily" # Database dumps
        "/mnt/storage/blinko/data" # blinko extra data
        "/mnt/storage/firefly/upload" # firefly uploads
        "/mnt/storage/memos"
        "/mnt/storage/minio"
        "/mnt/storage/n8n/data" # extra data beside DB
        "/mnt/storage/solidtime/app"
        "/mnt/storage/wud"
        "/mnt/storage/filebrowser"
        "/mnt/storage/upsnap"
        "/mnt/storage/syncthing/config"
        "/mnt/storage/syncthing/data" # data being synced
        "/mnt/storage/media/configs"
        "/mnt/storage/media/books"
        "/mnt/storage/immich/upload/library"
        "/mnt/storage/dockge/data/db-config.json"
        "/mnt/storage/dockge/data/dockge.db"
      ];
      initialize = true;
      timerConfig = {
        OnCalendar = "02:00";
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
        "--tag home-server"
      ];
      backupPrepareCommand = ''
        export PATH="${pkgs.docker}/bin:${pkgs.hostname}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:${pkgs.gawk}/bin:$PATH"
        ${pkgs.writeShellScriptBin "backup-prepare" (builtins.readFile ./scripts/backup-prepare.sh)}/bin/backup-prepare /tmp/db-dumps-daily fireflyiii-db blinko-db n8n-db solidtime-db linkwarden-db immich_postgres
      '';
      backupCleanupCommand = ''
        export PATH="${pkgs.coreutils}/bin:$PATH"
        ${pkgs.writeShellScriptBin "backup-cleanup" (builtins.readFile ./scripts/backup-cleanup.sh)}/bin/backup-cleanup /tmp/db-dumps-daily
      '';
    };
  };

  # Install backup scripts as system packages
  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "backup-prepare" (builtins.readFile ./scripts/backup-prepare.sh))
    (writeShellScriptBin "backup-cleanup" (builtins.readFile ./scripts/backup-cleanup.sh))
  ];
}
