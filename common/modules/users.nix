# User account configuration
{
  config,
  lib,
  pkgs,
  ...
}:

let
  adminSshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGRGvFgz+AH8SllcU1ZRbVw5cyfzCOo5gRuxu+DLMLHn"
  ];
in
{
  # Define user accounts
  users.users.amjad = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    # Uncomment and add your SSH public key here
    openssh.authorizedKeys.keys = adminSshKeys;
  };

  users.users.dock = {
    isNormalUser = true;
    extraGroups = [ "docker" ];
    description = "Docker services management user";
    home = "/var/lib/dock";
    createHome = true;
  };

  users.users.root = {
    openssh.authorizedKeys.keys = adminSshKeys;
  };

  security.sudo.wheelNeedsPassword = false;
}
