# Docker Compose Services Management
# Automatically discovers and manages all compose services in docker-services directory
{ config, lib, pkgs, ... }:

let
  composeRoot = "/home/amjad/docker-services";
  
  # Create the discovery script package
  discoveryScript = pkgs.writeShellScriptBin "compose-discovery" (builtins.readFile ../scripts/compose-discovery.sh);
  
in
{
  # Create a service discovery and management system
  systemd.services.compose-discovery = {
    description = "Docker Compose Service Discovery";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${discoveryScript}/bin/compose-discovery";
      User = "root";  # Need root to write to /etc/systemd/system
    };
    wantedBy = [ "multi-user.target" ];
  };
  
  # Create the docker-services directory if it doesn't exist
  systemd.tmpfiles.rules = [
    "d ${composeRoot} 0755 amjad docker - -"
  ];
  

  # Install management scripts
  environment.systemPackages = with pkgs; [
    # Main management script from external file
    (writeShellScriptBin "compose-manage" (builtins.readFile ../scripts/compose-manage.sh))

    # Discovery script
    (discoveryScript)
    
    # Quick status script
    (writeShellScriptBin "compose-status" ''
      #!/bin/bash
      compose-manage list
    '')
  ];
}