# System services configuration
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Enable the OpenSSH daemon
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
    };
  };

  # Networking configuration
  networking = {
    hostName = "server";
    networkmanager.enable = true;
    usePredictableInterfaceNames = true;

    # Firewall configuration
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };
}
