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
    systemd
  ];

  # Enable the OpenSSH daemon
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      ChallengeResponseAuthentication = false;
      PermitRootLogin = "no";
      PubkeyAuthentication = true;
      X11Forwarding = false;
    };
  };
  
  programs.mosh = {
    enable = true;
    openFirewall = true;
  };

  # Networking configuration
  networking = {
    hostName = lib.mkDefault "server";
    networkmanager.enable = false;
    useNetworkd = true;
    usePredictableInterfaceNames = true;
    enableIPv6 = true;
    nat.enableIPv6 = true;

    # Firewall configuration
    firewall = {
      enable = true;
    };
    nameservers = [ "1.1.1.1" "1.0.0.1" "2606:4700:4700::1111" "2606:4700:4700::1001" "8.8.8.8" "8.8.4.4" ];
  };
  services.resolved.enable = false;

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
