{ config, lib, pkgs, ... }:

let
  notifyScript = builtins.readFile ../scripts/homelab-notify.sh;
  backupGroups = lib.attrNames config.homelab.backups;
  enabled = config.homelab.backupJobs.enable && backupGroups != [];
in
{
  config = lib.mkIf enabled {
    sops.secrets.ntfy-token = {
      owner = "root";
      group = "root";
      mode = "0400";
    };

    sops.templates."ntfy-client.env" = {
      owner = "dock";
      group = "docker";
      mode = "0400";
      path = "/var/lib/dock/ntfy-client.env";
      content = ''
        NTFY_TOKEN=${config.sops.placeholder.ntfy-token}
        NTFY_URL=https://ntfy.home.amsh.dev
        NTFY_TOPIC=homelab
      '';
    };

    environment.systemPackages = with pkgs; [
      curl
      (writeShellScriptBin "homelab-notify" notifyScript)
    ];

    environment.etc."homelab-scripts/homelab-notify.sh" = {
      text = notifyScript;
      mode = "0755";
    };

    systemd.services = lib.mkMerge [
      {
        "homelab-backup-notify-success@" = {
          description = "Notify successful homelab backup for %i";
          path = with pkgs; [ coreutils curl gawk gnugrep gnused jq systemd ];
          serviceConfig = {
            Type = "oneshot";
            EnvironmentFile = config.sops.templates."ntfy-client.env".path;
            ExecStart = "${pkgs.writeShellScriptBin "homelab-notify" notifyScript}/bin/homelab-notify backup-success %i";
          };
        };

        "homelab-backup-notify-failure@" = {
          description = "Notify failed homelab backup for %i";
          path = with pkgs; [ coreutils curl gawk gnugrep gnused jq systemd ];
          serviceConfig = {
            Type = "oneshot";
            EnvironmentFile = config.sops.templates."ntfy-client.env".path;
            ExecStart = "${pkgs.writeShellScriptBin "homelab-notify" notifyScript}/bin/homelab-notify backup-failure %i";
          };
        };
      }
      (builtins.listToAttrs (map (group: {
        name = "restic-backups-${group}";
        value.unitConfig = {
          OnSuccess = [ "homelab-backup-notify-success@${group}.service" ];
          OnFailure = [ "homelab-backup-notify-failure@${group}.service" ];
        };
      }) backupGroups))
    ];
  };
}
