# Machine-specific configuration for myserver
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Machine-specific settings
  networking.hostName = "myserver";
  
  # Override or extend common configuration here
  # Example: Add machine-specific packages
  # environment.systemPackages = with pkgs; [
  #   # machine-specific packages
  # ];
  
  # Example: Machine-specific services
  # services.someService.enable = true;
}