# System services configuration
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Add snapper to system packages
  environment.systemPackages = with pkgs; [
    fail2ban
  ];

  # Enable the OpenSSH daemon
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
    };
  };

  # Networking configuration
  networking = {
    hostName = lib.mkDefault "server";
    networkmanager.enable = true;
    usePredictableInterfaceNames = true;
    enableIPv6 = true;
    nat.enableIPv6 = true;

    # Firewall configuration
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };

  # Fail2ban intrusion prevention
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "24h";
    bantime-increment = {
      enable = true;
      multipliers = "1 2 4 8 16 32 64";
      maxtime = "168h"; # 1 week
    };
  };

}
