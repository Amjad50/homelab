{ config, pkgs, ... }:
{
  services.netdata = {
    enable = true;
  };

  # Override some of the parameters for the systemd service
  systemd.services.netdata = {
    environment = {
      DISABLE_TELEMETRY = "1";
      NETDATA_LOG_LEVEL = "warn";
    };
  };
}
