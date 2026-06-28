# Docker Compose Services Management
# Declarative management of Docker Compose services
{ config, lib, pkgs, ... }:

let
  composeRoot = "/opt/docker-services";

  # List of services to manage
  services = config.services.compose-services.services;

  # Create systemd service for a compose service
  createComposeService = serviceName: {
    name = "docker-compose-${serviceName}";
    value = {
      description = "Docker Compose: ${serviceName}";
      after = [ "docker.service" "network.target" ];
      requires = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = "${composeRoot}/${serviceName}";
        ExecStartPre = [
          "${pkgs.coreutils}/bin/test -f docker-compose.yml"
        ];
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
        ExecReload = "${pkgs.docker-compose}/bin/docker-compose restart";
        TimeoutStartSec = 300;
        TimeoutStopSec = 60;
        Restart = "on-failure";
        RestartSec = "10s";
        User = "dock";
        Group = "docker";
      };
      wantedBy = [ "multi-user.target" ];
    };
  };

in
{
  # Module options
  options.services.compose-services = {
    services = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of Docker Compose services to manage";
    };
  };

  # Create systemd services for all listed compose services
  config.systemd.services = lib.listToAttrs (map createComposeService services);

  # Root + per-service dirs; the latter must exist before each unit's WorkingDirectory.
  # 2775 (setgid, group-writable) lets docker-group users upload/edit compose files
  # without sudo (deploy.sh --only-docker); new files inherit the docker group.
  config.systemd.tmpfiles.rules =
    [ "d ${composeRoot} 2775 dock docker - -" ]
    ++ map (s: "d ${composeRoot}/${s} 2775 dock docker - -") services;

  # Allow docker group to manage docker-compose services via polkit
  config.security.polkit.enable = true;
  config.security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit").indexOf("docker-compose-") == 0 &&
            subject.isInGroup("docker")) {
            return polkit.Result.YES;
        }
    });
  '';

  # Install shared library
  config.environment.etc."homelab/lib.sh" = {
    source = ../scripts/homelab-lib.sh;
    mode = "0444";
  };

  # Install management scripts
  config.environment.systemPackages = with pkgs; [
    # `compose-manage update` reads pinned-tag digests from registries.
    regclient

    # Main management script from external file
    (writeShellScriptBin "compose-manage" (builtins.readFile ../scripts/compose-manage.sh))

    # Quick status script
    (writeShellScriptBin "compose-status" ''
      #!/usr/bin/env bash
      compose-manage list
    '')
  ];
}
