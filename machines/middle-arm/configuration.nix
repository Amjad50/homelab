{ lib, ... }:
{
  imports = [
    # Pull in the real middle config: services, networking, fail2ban, coturn,
    # sops (defaultSopsFile = ../middle/secrets.yaml), everything.
    ../middle/configuration.nix
  ];

  # --- Oracle networking: use DHCP, drop middle's hardcoded static IPs ---
  networking.useDHCP = lib.mkForce true;
  # Clear the static interface config from ../middle/networking.nix
  # (it pins ens18 to the OLD middle's public IPs, which are wrong here).
  networking.interfaces = lib.mkForce { };
  networking.defaultGateway = lib.mkForce null;
  networking.defaultGateway6 = lib.mkForce null;
}
