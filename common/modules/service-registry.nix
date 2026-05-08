# Service registry module — single source of truth for compose services,
# secrets, templates, tmpfiles, backups, and restore metadata.
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab;

  postgresType = lib.types.submodule {
    options = {
      composeService = lib.mkOption { type = lib.types.str; default = ""; description = "Compose service name inside the stack."; };
      database       = lib.mkOption { type = lib.types.str; default = ""; description = "Postgres database name."; };
      user           = lib.mkOption { type = lib.types.str; default = ""; description = "Postgres user."; };
    };
  };

  backupType = lib.types.submodule ({ name, ... }: {
    options = {
      enable = lib.mkOption { type = lib.types.bool; default = true; };

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

  serviceType = lib.types.submodule ({ name, config, ... }: {
    options = {
      enable = lib.mkOption { type = lib.types.bool; default = true; };

      tmpfiles  = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
      secrets   = lib.mkOption { type = lib.types.attrsOf secretType;   default = {}; };
      templates = lib.mkOption { type = lib.types.attrsOf templateType; default = {}; };

      backup = {
        group               = lib.mkOption { type = lib.types.nullOr (lib.types.attrsOf lib.types.anything); default = null; description = "The backup group this service belongs to."; };
        paths               = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; description = "Filesystem paths to include in the backup."; };
        postgres            = lib.mkOption { type = lib.types.listOf postgresType;  default = []; description = "Postgres databases to dump before backup."; };
        customBackupScript  = lib.mkOption { type = lib.types.lines; default = ""; description = "Host shell script run before backup while services are still up."; };
        customRestoreScript = lib.mkOption { type = lib.types.lines; default = ""; description = "Host shell script run after restic restore while services in the group are still stopped."; };
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

    # For each backup group, collect paths and postgres configs from services that depend on it.
    groupMeta = lib.mapAttrs (groupName: group:
      let
        dependentServices = lib.filterAttrs (_: svc:
          svc.backup.group != null && svc.backup.group.sentinel == group.sentinel
        ) enabled;
      in {
        paths = lib.unique (lib.concatLists (lib.mapAttrsToList (_: svc: svc.backup.paths) dependentServices));
        postgres = lib.concatLists (lib.mapAttrsToList (svcName: svc:
          map (pg: {
            inherit (pg) composeService database user;
            stack = svcName;
          }) svc.backup.postgres
        ) dependentServices);
        customBackups = lib.filter (x: x.script != "") (lib.mapAttrsToList (svcName: svc: {
          service = svcName;
          script = svc.backup.customBackupScript;
        }) dependentServices);
        customRestores = lib.filter (x: x.script != "") (lib.mapAttrsToList (svcName: svc: {
          service = svcName;
          script = svc.backup.customRestoreScript;
        }) dependentServices);
        serviceNames = lib.attrNames dependentServices;
      }
    ) backupGroups;

    machine  = cfg.machineName;
    lockDir  = "/run/backup-locks";
    lockFile = "${lockDir}/${machine}.lock";

    repoUrl = "s3:s3.eu-central-003.backblazeb2.com/amsh-homelab-backup/backups/${machine}-daily";

    mkResticBackup = groupName: group:
      let
        meta        = groupMeta.${groupName};
        dumpDir     = "/tmp/db-dumps/${groupName}";
        artifactDir = "/tmp/homelab-artifacts/${groupName}";
        hasPg       = meta.postgres != [];
        hasCustom   = meta.customBackups != [];
        paths       = meta.paths
          ++ lib.optional hasPg dumpDir
          ++ lib.optional hasCustom artifactDir;
        cleanupTargets = lib.concatStringsSep " " (
          lib.optional hasPg (lib.escapeShellArg dumpDir)
          ++ lib.optional hasCustom (lib.escapeShellArg artifactDir)
        );
        hookPath = "${lib.makeBinPath (with pkgs; [
          bash coreutils docker docker-compose jq gnugrep gnused findutils util-linux sqlite
        ])}:/run/current-system/sw/bin:$PATH";
        mkCustomBackupCommand = hook: ''
          export GROUP_NAME=${lib.escapeShellArg groupName}
          export SERVICE_NAME=${lib.escapeShellArg hook.service}
          export BACKUP_ROOT=${lib.escapeShellArg artifactDir}
          export SERVICE_ARTIFACT_DIR=${lib.escapeShellArg "${artifactDir}/${hook.service}"}
          mkdir -p "$SERVICE_ARTIFACT_DIR"
          ${pkgs.bash}/bin/bash <<'EOF'
          ${hook.script}
          EOF
        '';
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

        backupPrepareCommand =
          lib.optionalString (hasPg || hasCustom) ''
            export PATH="${hookPath}"
          ''
          + lib.optionalString hasPg ''
            export DUMP_DIR=${lib.escapeShellArg dumpDir}
            export GROUP_NAME=${lib.escapeShellArg groupName}
            ${pkgs.bash}/bin/bash ${../scripts/backup-postgres.sh} \
              ${lib.escapeShellArg (builtins.toJSON meta.postgres)}
          ''
          + lib.optionalString hasCustom (lib.concatMapStringsSep "\n" mkCustomBackupCommand meta.customBackups);

        backupCleanupCommand =
          lib.optionalString (hasPg || hasCustom) ''
            rm -rf ${cleanupTargets}
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
      export PATH="${lib.makeBinPath (with pkgs; [ coreutils restic util-linux jq gnused docker systemd bash ])}:/run/current-system/sw/bin:$PATH"
      export HOMELAB_MACHINE=${lib.escapeShellArg machine}
      export HOMELAB_LOCK=${lib.escapeShellArg lockFile}
      export HOMELAB_REPO=${lib.escapeShellArg repoUrl}
      export HOMELAB_RESTIC_PASSWORD_FILE=${lib.escapeShellArg config.sops.secrets.restic-repository-password.path}
      export HOMELAB_RESTIC_S3_ENV=${lib.escapeShellArg config.sops.templates."restic-s3.env".path}
    '';

    hlRestoreScript = pkgs.writeShellScript "restore-backup-impl" ''
      ${hlRestoreEnv}
      ${builtins.readFile ../scripts/restore-backup.sh}
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
    assertions = lib.mapAttrsToList (svcName: svc: {
      assertion = (svc.backup.paths == [] && svc.backup.postgres == []) || svc.backup.group != null;
      message   = "Service '${svcName}' has backup paths or postgres defined but no backup.group assigned.";
    }) enabled;

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
          group        = svc.backup.group;
          sentinel     = group.sentinel;
          restoreUnit  = if group.autoStart then autoRestoreUnit group else null;
        in {
          "docker-compose-${svcName}" = {
            unitConfig.ConditionPathExists = [ sentinel ];
          } // lib.optionalAttrs (restoreUnit != null) {
            wants = [ restoreUnit ];
            after = [ restoreUnit ];
          };
        }
      ) (lib.filterAttrs (_: s: s.backup.group != null) enabled));

    systemd.timers = lib.listToAttrs
      (lib.mapAttrsToList mkLockedTimer backupGroups);

    environment.etc."homelab/services.json".text =
      builtins.toJSON {
        machineName = cfg.machineName;
        services    = lib.attrNames enabled;
        backups     = lib.mapAttrs (groupName: b: {
          inherit (b) sentinel schedule autoStart postRestoreScript;
          composeServices = groupMeta.${groupName}.serviceNames;
          postgres = groupMeta.${groupName}.postgres;
          paths = groupMeta.${groupName}.paths;
          customRestores = groupMeta.${groupName}.customRestores;
        }) backupGroups;
      };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "restore-backup" ''
        exec ${hlRestoreScript} "$@"
      '')
    ];
  };
}
