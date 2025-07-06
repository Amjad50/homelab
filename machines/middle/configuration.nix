# Middle Server - Traefik + WireGuard VPN
{ config, pkgs, ... }:
{
  networking.hostName = "middle";
  
  # Firewall - allow web traffic and VPN
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 51820 ];
  networking.firewall.trustedInterfaces = [ "wg0" ];
  
  # IPv6 NAT support for WireGuard
  boot.kernelModules = [ "ip6table_nat" ];
  
  # Docker Compose services
  services.compose-services.services = [
    "traefik"   # Reverse proxy with HTTPS
    "wg-easy"   # WireGuard VPN management
  ];
}