{ ... }:
{
  services.resolved.enable = false;
  networking = {
    useDHCP = false;
    useNetworkd = true;
    enableIPv6 = false;
    nameservers = [ "1.1.1.1" "9.9.9.9" ];
    firewall = {
      enable = true;
      checkReversePath = "loose";
      # Administration uses ssh -J home amjad@192.168.250.2. The host also
      # rejects unsolicited forwarded traffic to this interface/subnet.
      extraInputRules = ''ip saddr 192.168.250.1 tcp dport 22 accept'';
    };
    nftables.enable = true;
  };
  systemd.network.networks."10-eth" = {
    matchConfig.MACAddress = "02:00:00:fa:00:02";
    address = [ "192.168.250.2/30" ];
    routes = [{ Gateway = "192.168.250.1"; }];
    networkConfig = { DHCP = "no"; IPv6AcceptRA = false; LinkLocalAddressing = "no"; };
  };
}
