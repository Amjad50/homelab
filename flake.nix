{
  description = "Multi-machine NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, nixpkgs, sops-nix, disko }:
    let
      lib = nixpkgs.lib;
    in
    {
      nixosConfigurations = {
        middle = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            disko.nixosModules.disko
            ./hardware/middle.nix
            ./common/configuration.nix
            ./machines/middle/configuration.nix
            sops-nix.nixosModules.sops
          ];
        };
        home = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            disko.nixosModules.disko
            ./hardware/home.nix
            ./common/configuration.nix
            ./machines/home/configuration.nix
            sops-nix.nixosModules.sops
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
          ];
        };
        middle-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            disko.nixosModules.disko
            ./hardware/middle-vm.nix
            ./common/configuration.nix
            ./machines/middle-vm/configuration.nix
            sops-nix.nixosModules.sops
          ];
        };
      };
      packages.x86_64-linux.installer-iso =
        let
          installerAuthorizedKey = builtins.getEnv "VM_INSTALLER_AUTHORIZED_KEY";
          checkedInstallerAuthorizedKey =
            if installerAuthorizedKey == "" then
              throw "Set VM_INSTALLER_AUTHORIZED_KEY and build installer-iso with --impure"
            else
              installerAuthorizedKey;
        in
        (nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            {
              isoImage.isoName = "home-vm-installer-${builtins.substring 0 8 (builtins.hashString "sha256" checkedInstallerAuthorizedKey)}.iso";
              users.users.root.initialHashedPassword = lib.mkForce null;
              users.users.root.initialPassword = "nixos";
              users.users.root.openssh.authorizedKeys.keys = [
                checkedInstallerAuthorizedKey
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
