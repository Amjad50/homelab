{ ... }:
{
  services.logrotate = {
    enable = true;
    settings.traefik = {
      files = "/var/log/traefik/*.log";
      frequency = "weekly";
      rotate = 4;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      # Traefik holds the file descriptor open; truncate in place rather than
      # renaming so we don't need a SIGUSR1/restart to reopen the log.
      copytruncate = true;
    };
  };
}
