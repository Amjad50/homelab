{ ... }:
{
  imports = [
    ./services/index.nix
    ./networking.nix
    ./swap.nix
    ./logrotate.nix
  ];

  homelab.machineName = "home";
}
