# Service registry module — single source of truth for compose services,
# secrets, templates, tmpfiles, backups, and restore metadata.
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab;

  postgresType = lib.types.submodule {
    options = {
      composeService = lib.mkOption { type = lib.types.str; description = "Folder name under /opt/docker-services/"; };
      container       = lib.mkOption { type = lib.types.str; description = "Docker container name."; };
      database        = lib.mkOption { type = lib.types.str; description = "Postgres database name."; };
      user            = lib.mkOption { type = lib.types.str; description = "Postgres user."; };
      dumpName        = lib.mkOption { type = lib.types.str; description = "Filename for the dump under /tmp/db-dumps/<service>/"; };
    };
  };

  secretType = lib.types.submodule {
    options = {
      owner = lib.mkOption { type = lib.types.str; default = "root"; };
      group = lib.mkOption { type = lib.types.str; default = "root"; };
      mode  = lib.mkOption { type = lib.types.str; default = "0400"; };
    };
  };

  templateType = lib.types.submodule {
    options = {
      content = lib.mkOption { type = lib.types.str; description = "Template content (with sops placeholders)."; };
      owner   = lib.mkOption { type = lib.types.str; default = "root"; };
      group   = lib.mkOption { type = lib.types.str; default = "root"; };
      mode    = lib.mkOption { type = lib.types.str; default = "0400"; };
      path    = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Where to render the template; null = sops default."; };
      restartUnits = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
    };
  };

  serviceType = lib.types.submodule ({ name, ... }: {
    options = {
      enable = lib.mkOption { type = lib.types.bool; default = true; };

      compose.enable = lib.mkOption { type = lib.types.bool; default = false; };

      tmpfiles  = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
      secrets   = lib.mkOption { type = lib.types.attrsOf secretType;   default = {}; };
      templates = lib.mkOption { type = lib.types.attrsOf templateType; default = {}; };

      backup = {
        enable   = lib.mkOption { type = lib.types.bool; default = false; };
        paths    = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
        postgres = lib.mkOption { type = lib.types.listOf postgresType; default = []; };
      };

      restore = {
        enable     = lib.mkOption { type = lib.types.bool; default = false; };
        large      = lib.mkOption { type = lib.types.bool; default = false; };
        postScript = lib.mkOption { type = lib.types.str;  default = ""; };
      };
    };
  });

in
{
  options.homelab = {
    machineName = lib.mkOption {
      type = lib.types.str;
      default = "unconfigured";
      description = "Machine identifier used in restic job names, tags, and lockfile path.";
    };
    services = lib.mkOption {
      type = lib.types.attrsOf serviceType;
      default = {};
      description = "Service registry — source of truth for compose, secrets, backup, restore.";
    };
  };

  config = let
    enabled  = lib.filterAttrs (_: s: s.enable) cfg.services;
    composeEnabled = lib.filterAttrs (_: s: s.compose.enable) enabled;
    backupEnabled  = lib.filterAttrs (_: s: s.backup.enable)  enabled;

    machine = cfg.machineName;
    lockFile = "/var/lock/restic-${machine}.lock";

    repoUrl = "s3:s3.eu-central-003.backblazeb2.com/amsh-homelab-backup/backups/${machine}-daily";

    mkBackupScript = svcName: svc:
      let
        dumpDir = "/tmp/db-dumps/${svcName}";
        pgDumpLines = lib.concatMapStringsSep "\n" (pg: ''
          echo "[$(date -Iseconds)] dumping ${pg.database} from ${pg.container}"
          ${pkgs.docker}/bin/docker exec "${pg.container}" pg_dump -U "${pg.user}" "${pg.database}" \
            > "${dumpDir}/${pg.dumpName}"
        '') svc.backup.postgres;
        backupPaths =
          svc.backup.paths
          ++ lib.optional (svc.backup.postgres != []) dumpDir;
        pathArgs = lib.concatMapStringsSep " " (p: lib.escapeShellArg p) backupPaths;
        tagArgs = lib.concatStringsSep " " [
          "--tag backup-v2"
          "--tag machine-${machine}"
          "--tag service-${svcName}"
        ];
      in
      pkgs.writeShellScript "restic-backup-${machine}-${svcName}" ''
        set -euo pipefail
        export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.docker pkgs.restic pkgs.util-linux pkgs.gnugrep pkgs.gnused pkgs.gawk ]}:$PATH"

        ${lib.optionalString (svc.backup.postgres != []) ''
          mkdir -p ${lib.escapeShellArg dumpDir}
          ${pgDumpLines}
        ''}

        restic backup ${pathArgs} ${tagArgs}

        restic forget --prune \
          --tag service-${svcName} --tag machine-${machine} --tag backup-v2 \
          --keep-daily 30 --keep-weekly 8 --keep-monthly 12

        ${lib.optionalString (svc.backup.postgres != []) ''
          rm -rf ${lib.escapeShellArg dumpDir}
        ''}
      '';

    mkBackupUnit = svcName: svc: {
      name = "restic-${machine}-${svcName}";
      value = {
        description = "Restic backup: ${svcName} (${machine})";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = with pkgs; [ coreutils docker restic util-linux ];
        environment = {
          RESTIC_REPOSITORY = repoUrl;
          RESTIC_PASSWORD_FILE = config.sops.secrets.restic-repository-password.path;
        };
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = config.sops.templates."restic-s3.env".path;
          ExecStart = "${pkgs.util-linux}/bin/flock ${lockFile} ${mkBackupScript svcName svc}";
        };
      };
    };

    mkBackupTimer = svcName: _: {
      name = "restic-${machine}-${svcName}";
      value = {
        description = "Timer for restic backup: ${svcName} (${machine})";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = if machine == "middle" then "03:00" else "02:00";
          RandomizedDelaySec = "1h";
          Persistent = true;
        };
      };
    };

  in {
    services.compose-services.services = lib.attrNames composeEnabled;

    systemd.tmpfiles.rules =
      lib.concatLists (lib.mapAttrsToList (_: s: s.tmpfiles) enabled);

    sops.secrets =
      lib.foldl' (acc: s: acc // s.secrets) {} (lib.attrValues enabled);

    sops.templates =
      lib.foldl' (acc: s: acc //
        (lib.mapAttrs (_: t:
          { inherit (t) content owner group mode; }
          // (lib.optionalAttrs (t.path != null) { inherit (t) path; })
          // (lib.optionalAttrs (t.restartUnits != []) { inherit (t) restartUnits; })
        ) s.templates)
      ) {} (lib.attrValues enabled);

    environment.etc."homelab/services.json".text =
      let
        restoreMeta = lib.mapAttrs (_: s: {
          inherit (s.restore) enable large postScript;
        }) (lib.filterAttrs (_: s: s.enable && s.restore.enable) cfg.services);
      in
      builtins.toJSON {
        machineName = cfg.machineName;
        services = restoreMeta;
      };

    systemd.services = lib.listToAttrs
      (lib.mapAttrsToList mkBackupUnit backupEnabled);

    systemd.timers = lib.listToAttrs
      (lib.mapAttrsToList mkBackupTimer backupEnabled);

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "homelab-restore" ''
        export PATH="${lib.makeBinPath (with pkgs; [ coreutils restic util-linux jq gnused docker ])}:$PATH"
        export HOMELAB_MACHINE=${lib.escapeShellArg machine}
        export HOMELAB_LOCK=${lib.escapeShellArg lockFile}
        export HOMELAB_REPO=${lib.escapeShellArg repoUrl}
        export HOMELAB_RESTIC_PASSWORD_FILE=${lib.escapeShellArg config.sops.secrets.restic-repository-password.path}
        export HOMELAB_RESTIC_S3_ENV=${lib.escapeShellArg config.sops.templates."restic-s3.env".path}
        ${builtins.readFile ../scripts/homelab-restore.sh}
      '')
    ];
  };
}
