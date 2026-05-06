{ lib, ... }:
{
  networking.hostName = "home-vm";
  networking.useDHCP = lib.mkForce true;
  networking.firewall.allowedTCPPorts = [ 5055 8096 8090 ];
}
