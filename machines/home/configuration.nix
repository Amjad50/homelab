{ ... }:
{
  imports = [
    ./hermes-vm.nix
    ./services/index.nix
    ./networking.nix
    ./swap.nix
    ./logrotate.nix
  ];

  homelab.machineName = "home";
}
