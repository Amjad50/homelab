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
    
    # Automatically prune unused data.
    # Do NOT pass --all: Sablier scales idle containers to "stopped" state, and
    # `docker system prune --all` removes stopped containers + their images.
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };
}
