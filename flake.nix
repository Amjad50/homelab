{
  description = "Simple NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs =
    { self, nixpkgs }:
    {
      nixosConfigurations = {
        myserver = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./common/configuration.nix
            ./machines/myserver/configuration.nix
          ];
        };
        
        # Example for additional machines:
        # server2 = nixpkgs.lib.nixosSystem {
        #   system = "x86_64-linux";
        #   modules = [
        #     ./common/configuration.nix
        #     ./machines/server2/configuration.nix
        #   ];
        # };
      };
    };
}
