{
  description = "Simple NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixvim.url = "github:nix-community/nixvim/nixos-25.05";
    nixvim.inputs.nixpkgs.follows = "nixpkgs";

  };

  outputs =
    { self, nixpkgs, home-manager, nixvim }:
    {
      nixosConfigurations = {
        vm-testing = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./common/configuration.nix
            ./machines/vm-testing/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.amjad = import ./common/home.nix;
              home-manager.sharedModules = [
                nixvim.homeManagerModules.nixvim
              ];
            }
          ];
        };
        middle = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./common/configuration.nix
            ./machines/middle/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.amjad = import ./common/home.nix;
              home-manager.sharedModules = [
                nixvim.homeManagerModules.nixvim
              ];
            }
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
