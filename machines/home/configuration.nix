{ ... }:
{
  imports = [
    ./services/index.nix
    ./networking.nix
    ./swap.nix
  ];

  homelab.machineName = "home";
}
