# Docker containerization platform
{ config, lib, pkgs, ... }:

{
  # Add Docker Compose
  environment.systemPackages = with pkgs; [
    docker
    docker-compose
    docker-buildx
  ];

  # Enable Docker service
  virtualisation.docker = {
    enable = true;
    
    # Enable on boot
    enableOnBoot = true;

    # Storage driver (overlay2, simplest and best for most cases)
    storageDriver = "overlay2";
    
    logDriver = "journald";

    # Docker daemon settings
    daemon.settings = {
      # Security options
      no-new-privileges = true;
    };
    
    # Pruning is handled by the custom docker-prune timer below, NOT autoPrune.
    # `docker system prune` (which autoPrune runs) ALWAYS removes every stopped
    # container — with or without --all. Sablier scales idle services to a
    # stopped state, so any system-prune deletes those containers and breaks the
    # service until the next `compose up`. We only ever want to reclaim images
    # and build cache, never containers, so we drive prune ourselves.
    autoPrune.enable = false;
  };

  # Container-safe weekly prune. Reclaims dangling images + build cache only.
  # Deliberately does NOT run `container prune` or `network prune`:
  #   - container prune would delete Sablier-stopped service containers
  #   - network prune would delete networks of fully-idle stacks (churn on wake)
  # Named *-safe to avoid colliding with the NixOS docker module's own
  # docker-prune.service, which still gets defined even when autoPrune is off.
  systemd.services.docker-prune-safe = {
    description = "Prune docker images and build cache (container-safe)";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    serviceConfig.Type = "oneshot";
    path = [ config.virtualisation.docker.package ];
    script = ''
      docker image prune --force
      docker builder prune --force
    '';
  };

  systemd.timers.docker-prune-safe = {
    description = "Weekly container-safe docker prune";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };
}
