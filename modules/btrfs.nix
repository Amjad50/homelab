# Btrfs filesystem configuration
# Includes snapper snapshots and automatic scrubbing
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Add snapper to system packages
  environment.systemPackages = with pkgs; [
    snapper
  ];

  # Btrfs automatic scrubbing
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  # Snapper configuration for automatic snapshots
  services.snapper = {
    configs = {
      # Root filesystem snapshots
      root = {
        SUBVOLUME = "/";
        ALLOW_USERS = [ "amjad" ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = "10";
        TIMELINE_LIMIT_DAILY = "10";
        TIMELINE_LIMIT_WEEKLY = "10";
        TIMELINE_LIMIT_MONTHLY = "10";
        TIMELINE_LIMIT_YEARLY = "10";
      };

      # Home directory snapshots
      home = {
        SUBVOLUME = "/home";
        ALLOW_USERS = [ "amjad" ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = "24";
        TIMELINE_LIMIT_DAILY = "7";
        TIMELINE_LIMIT_WEEKLY = "4";
        TIMELINE_LIMIT_MONTHLY = "6";
        TIMELINE_LIMIT_YEARLY = "2";
      };

      # Log snapshots (important for debugging)
      var-log = {
        SUBVOLUME = "/var/log";
        ALLOW_USERS = [ "amjad" ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = "6";
        TIMELINE_LIMIT_DAILY = "7";
        TIMELINE_LIMIT_WEEKLY = "4";
        TIMELINE_LIMIT_MONTHLY = "2";
        TIMELINE_LIMIT_YEARLY = "1";
      };

      # Application data snapshots
      var-lib = {
        SUBVOLUME = "/var/lib";
        ALLOW_USERS = [ "amjad" ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = "0";
        TIMELINE_LIMIT_DAILY = "3";
        TIMELINE_LIMIT_WEEKLY = "2";
        TIMELINE_LIMIT_MONTHLY = "1";
        TIMELINE_LIMIT_YEARLY = "0";
      };
    };
  };
}
