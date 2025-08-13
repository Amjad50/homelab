{ ... }:
{
  networking.hostName = "middle";

  systemd.network.links."10-net-main" = {
    matchConfig.Path = "pci-0000:00:12.0";
    linkConfig.Name = "ens18";
  };
  networking.interfaces.ens18 = {
    useDHCP = true; 
    ipv6.addresses = [
      { address = "2407:3640:2270:5255::1"; prefixLength = 64; }
    ];
  };
  networking.defaultGateway6 = {
    address = "fe80::1";   # common link-local gw in VPS hosts
    interface = "ens18";   # must specify interface for fe80::
  };

  # IPv6 NAT support for WireGuard
  boot.kernelModules = [ "ip6table_nat" ];

  # Firewall - allow web traffic, VPN, and rathole
  networking.firewall.allowedTCPPorts = [
    80
    443
    2333
  ];
  networking.firewall.allowedUDPPorts = [ 51820 ];

  # Sadly no way to do this in NixOS firewall
  # Allow port 8080 only from Docker networks (dynamically detect all Docker networks)
  networking.firewall.extraCommands = ''
    # Allow from all Docker bridge networks (172.16.0.0/12 covers docker0 and custom networks)
    iptables -A INPUT -p tcp --dport 8080 -s 172.16.0.0/12 -j ACCEPT
    # Allow from localhost
    iptables -A INPUT -p tcp --dport 8080 -s 127.0.0.1 -j ACCEPT
    # Drop everything else
    iptables -A INPUT -p tcp --dport 8080 -j DROP
  '';

  networking.firewall.extraStopCommands = ''
    iptables -D INPUT -p tcp --dport 8080 -s 172.16.0.0/12 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 8080 -s 127.0.0.1 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 8080 -j DROP 2>/dev/null || true
  '';
}
