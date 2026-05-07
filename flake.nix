{
  description = "Multi-machine NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixvim.url = "github:nix-community/nixvim/nixos-25.05";
    nixvim.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, nixpkgs, home-manager, nixvim, sops-nix, disko }:
    let
      lib = nixpkgs.lib;
      productionHardwareModules =
        if builtins.pathExists ./hardware-configuration.nix then
          [ ./hardware-configuration.nix ]
        else
          [
            # Evaluation fallback for this repo checkout. Real deployed machines
            # should keep their generated /etc/nixos/hardware-configuration.nix,
            # which overrides these mkDefault filesystem settings.
            {
              fileSystems."/" = lib.mkDefault {
                device = "none";
                fsType = "tmpfs";
              };
            }
          ];
    in
    {
      nixosConfigurations = {
        middle = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = productionHardwareModules ++ [
            ./common/configuration.nix
            ./machines/middle/configuration.nix
            sops-nix.nixosModules.sops
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
        home = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = productionHardwareModules ++ [
            ./common/configuration.nix
            ./machines/home/configuration.nix
            sops-nix.nixosModules.sops
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
        home-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            disko.nixosModules.disko
            ./hardware/home-vm.nix
            ./common/configuration.nix
            ./machines/home-vm/configuration.nix
            sops-nix.nixosModules.sops
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
      };
      packages.x86_64-linux.installer-iso = (nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          {
            users.users.root.initialHashedPassword = lib.mkForce null;
            users.users.root.initialPassword = "nixos";
            users.users.root.openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKMsaYI7HF5cnWT+y+C1CDMlQSETGyJPWWOx617sFhE+ amjad@amjad-fed"
            ];
            services.openssh.enable = true;
            services.openssh.settings.PermitRootLogin = "yes";
          }
        ];
      }).config.system.build.isoImage;

      devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
        packages = with nixpkgs.legacyPackages.x86_64-linux; [
          nixos-anywhere
          OVMF
          # qemu intentionally omitted — use system qemu-system-x86_64 (avoids SDL3 issues)
        ];
      };
    };
}
