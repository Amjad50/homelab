# Service registry module — single source of truth for compose services,
# secrets, templates, tmpfiles, backups, and restore metadata.
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab;

  postgresType = lib.types.submodule {
    options = {
      stack          = lib.mkOption { type = lib.types.str; description = "Compose stack name (directory under /opt/docker-services)."; };
      composeService = lib.mkOption { type = lib.types.str; description = "Compose service name inside the stack (for docker-compose up/stop)."; };
      container      = lib.mkOption { type = lib.types.str; description = "Actual Docker container name (for docker exec)."; };
      database       = lib.mkOption { type = lib.types.str; description = "Postgres database name."; };
      user           = lib.mkOption { type = lib.types.str; description = "Postgres user."; };
    };
  };

  backupType = lib.types.submodule ({ name, ... }: {
    options = {
      enable = lib.mkOption { type = lib.types.bool; default = true; };

      paths    = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; description = "Filesystem paths to include in this backup group."; };
      postgres = lib.mkOption { type = lib.types.listOf postgresType;  default = []; description = "Postgres databases to dump before backup."; };

      schedule          = lib.mkOption { type = lib.types.str; default = "02:00"; description = "OnCalendar value for the backup timer."; };
      postRestoreScript = lib.mkOption { type = lib.types.str; default = ""; description = "Shell commands to run after a successful restore of this group."; };

      autoStart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "If false, the backup timer for this group is not enabled automatically (manual trigger only).";
      };

      sentinel = lib.mkOption {
        type    = lib.types.str;
        default = "/var/lib/homelab/restored/${name}";
        description = "Path of the sentinel file written after a successful restore. Computed automatically as /var/lib/homelab/restored/<name>.";
      };
    };
  });

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

      tmpfiles  = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
      secrets   = lib.mkOption { type = lib.types.attrsOf secretType;   default = {}; };
      templates = lib.mkOption { type = lib.types.attrsOf templateType; default = {}; };

      dependsOnBackups = lib.mkOption {
        type    = lib.types.listOf (lib.types.attrsOf lib.types.anything);
        default = [];
        description = "List of homelab.backups.<group> attrsets this service depends on. Adds ConditionPathExists= for each group's sentinel.";
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
    backups = lib.mkOption {
      type    = lib.types.attrsOf backupType;
      default = {};
      description = "Backup group registry. Each entry is one restic job + sentinel.";
    };
  };

  config = let
    enabled = lib.filterAttrs (_: s: s.enable) cfg.services;

    backupGroups = lib.filterAttrs (_: b: b.enable) cfg.backups;

    # For each backup group, the list of enabled service names that depend on it.
    # Derived automatically — no need to declare composeServices manually.
    groupServices = lib.mapAttrs (groupName: _:
      lib.attrNames (lib.filterAttrs (_: svc:
        lib.any (b: b.sentinel == cfg.backups.${groupName}.sentinel) svc.dependsOnBackups
      ) enabled)
    ) backupGroups;

    machine  = cfg.machineName;
    lockDir  = "/run/backup-locks";
    lockFile = "${lockDir}/${machine}.lock";

    repoUrl = "s3:s3.eu-central-003.backblazeb2.com/amsh-homelab-backup/backups/${machine}-daily";

    mkResticBackup = groupName: group:
      let
        dumpDir = "/tmp/db-dumps/${groupName}";
        hasPg   = group.postgres != [];
        paths   = group.paths ++ lib.optional hasPg dumpDir;
      in {
        repository      = repoUrl;
        passwordFile    = config.sops.secrets.restic-repository-password.path;
        environmentFile = config.sops.templates."restic-s3.env".path;

        paths = paths;

        extraBackupArgs = [
          "--tag=backup-v2"
          "--tag=machine-${machine}"
          "--tag=group-${groupName}"
        ];

        pruneOpts = [
          "--tag=group-${groupName},machine-${machine},backup-v2"
          "--keep-daily=30"
          "--keep-weekly=8"
          "--keep-monthly=12"
        ];

        backupPrepareCommand = lib.optionalString hasPg ''
          export PATH="${lib.makeBinPath (with pkgs; [ coreutils docker jq bash ])}:$PATH"
          export DUMP_DIR=${lib.escapeShellArg dumpDir}
          export GROUP_NAME=${lib.escapeShellArg groupName}
          ${pkgs.bash}/bin/bash ${../scripts/homelab-backup-postgres.sh} \
            ${lib.escapeShellArg (builtins.toJSON (map (pg: { inherit (pg) stack composeService container database user; }) group.postgres))}
        '';

        backupCleanupCommand = lib.optionalString hasPg ''
          rm -rf ${lib.escapeShellArg dumpDir}
        '';

        # Suppress auto-timer; restic-locked-<group> owns scheduling.
        timerConfig = null;
      };

    mkLockedService = groupName: _: {
      name  = "restic-locked-${groupName}";
      value = {
        description = "Flock wrapper for restic-backups-${groupName}";
        wants       = [ "network-online.target" ];
        after       = [ "network-online.target" ];
        serviceConfig.Type = "oneshot";
        script = ''
          exec ${pkgs.util-linux}/bin/flock -x -w 21600 ${lib.escapeShellArg lockFile} \
            ${pkgs.systemd}/bin/systemctl start --wait restic-backups-${groupName}.service
        '';
      };
    };

    mkLockedTimer = groupName: group: {
      name  = "restic-locked-${groupName}";
      value = {
        wantedBy  = lib.optionals group.autoStart [ "timers.target" ];
        timerConfig = {
          OnCalendar         = group.schedule;
          RandomizedDelaySec = "1h";
          Persistent         = true;
        };
      };
    };

    # Shared env + PATH setup for homelab-restore invocations (both systemd and CLI).
    hlRestoreEnv = ''
      export PATH="${lib.makeBinPath (with pkgs; [ coreutils restic util-linux jq gnused docker systemd bash ])}:$PATH"
      export HOMELAB_MACHINE=${lib.escapeShellArg machine}
      export HOMELAB_LOCK=${lib.escapeShellArg lockFile}
      export HOMELAB_REPO=${lib.escapeShellArg repoUrl}
      export HOMELAB_RESTIC_PASSWORD_FILE=${lib.escapeShellArg config.sops.secrets.restic-repository-password.path}
      export HOMELAB_RESTIC_S3_ENV=${lib.escapeShellArg config.sops.templates."restic-s3.env".path}
    '';

    hlRestoreScript = pkgs.writeShellScript "homelab-restore-impl" ''
      ${hlRestoreEnv}
      ${builtins.readFile ../scripts/homelab-restore.sh}
    '';

    # Auto-restore unit: runs on boot if sentinel is absent.
    # Calls the shared homelab-restore script so postgres + postScript are handled.
    mkAutoRestoreService = groupName: group: {
      name  = "homelab-restore-${groupName}";
      value = {
        description = "Auto-restore backup group ${groupName}";
        wants       = [ "network-online.target" ];
        after       = [ "network-online.target" ];
        wantedBy    = [ "multi-user.target" ];
        unitConfig.ConditionPathExists = "!${group.sentinel}";
        serviceConfig = {
          Type            = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          exec ${hlRestoreScript} group ${lib.escapeShellArg groupName}
        '';
      };
    };

    # Given a backup group attrset, return the name of its auto-restore unit.
    # We look up the group name by finding which backupGroups entry has the same sentinel.
    autoRestoreUnit = b:
      let groupName = lib.head (lib.attrNames (lib.filterAttrs (_: g: g.sentinel == b.sentinel) backupGroups));
      in "homelab-restore-${groupName}.service";

  in {
    services.compose-services.services = lib.attrNames enabled;

    systemd.tmpfiles.rules =
      lib.concatLists (lib.mapAttrsToList (_: s: s.tmpfiles) enabled)
      ++ [ "d ${lockDir} 0755 root root - -"
           "d /var/lib/homelab/restored 0755 root root - -"
         ];

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

    services.restic.backups =
      lib.mapAttrs mkResticBackup backupGroups;

    systemd.services = lib.mkMerge (
      # Flock wrapper services for backup jobs
      [ (lib.listToAttrs (lib.mapAttrsToList mkLockedService backupGroups)) ]
      # Auto-restore services (only for autoStart = true groups)
      ++ [ (lib.listToAttrs (lib.mapAttrsToList mkAutoRestoreService
              (lib.filterAttrs (_: b: b.autoStart) backupGroups))) ]
      # Per-service sentinel conditions + ordering after restore units
      ++ lib.mapAttrsToList (svcName: svc:
        let
          sentinels    = map (b: b.sentinel) svc.dependsOnBackups;
          restoreUnits = map autoRestoreUnit (lib.filter (b: b.autoStart) svc.dependsOnBackups);
        in lib.optionalAttrs (sentinels != []) {
          "docker-compose-${svcName}" = {
            unitConfig.ConditionPathExists = sentinels;
          } // lib.optionalAttrs (restoreUnits != []) {
            wants = restoreUnits;
            after = restoreUnits;
          };
        }
      ) (lib.filterAttrs (_: s: s.dependsOnBackups != []) enabled));

    systemd.timers = lib.listToAttrs
      (lib.mapAttrsToList mkLockedTimer backupGroups);

    environment.etc."homelab/services.json".text =
      builtins.toJSON {
        machineName = cfg.machineName;
        services    = lib.attrNames enabled;
        backups     = lib.mapAttrs (groupName: b: {
          inherit (b) sentinel schedule autoStart postRestoreScript;
          composeServices = groupServices.${groupName};
          postgres = map (pg: { inherit (pg) stack composeService container database user; }) b.postgres;
        }) backupGroups;
      };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "homelab-restore" ''
        exec ${hlRestoreScript} "$@"
      '')
    ];
  };
}
