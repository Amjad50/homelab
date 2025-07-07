{ ... }:
{
  networking.hostName = "middle";

  networking.interfaces.ens3.ipv6.addresses = [
    {
      address = "2a03:4000:5:1ab::abcd";
      prefixLength = 64;
    }
  ];

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
