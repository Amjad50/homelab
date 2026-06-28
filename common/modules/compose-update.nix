# Nightly digest-check + auto-update of compose stacks.
# Runs at 04:00, after the backups (02:00 + up to 1h jitter, historically done by ~03:00).
# Gated on the ntfy setup (same condition as notifications.nix) so machines
# without backups/ntfy don't reference a missing sops template.
{ config, lib, pkgs, ... }:

let
  enabled = config.homelab.backupJobs.enable
    && lib.attrNames config.homelab.backups != [];
in
{
  config = lib.mkIf enabled {
    systemd.services.compose-update = {
      description = "Digest-check pinned tags and update changed compose stacks";
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = config.sops.templates."ntfy-client.env".path;
      };
      path = with pkgs; [
        config.virtualisation.docker.package
        docker-compose
        regclient
        jq
        curl
        nettools          # hostname
        systemd           # systemctl
        "/run/wrappers"   # sudo (script uses `sudo -u dock`)
      ];
      # compose-manage is installed via compose-services.nix into systemPackages.
      script = "/run/current-system/sw/bin/compose-manage update";
    };

    systemd.timers.compose-update = {
      description = "Nightly compose stack update";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 04:00:00";
        Persistent = true;
      };
    };
  };
}
