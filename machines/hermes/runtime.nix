{ config, pkgs, lib, ... }:
let
  cfg = config.services.hermes-agent;
  hermesCli = pkgs.writeShellScriptBin "hermes" ''
    if [ "$(${pkgs.coreutils}/bin/id -un)" != ${lib.escapeShellArg cfg.user} ]; then
      exec /run/wrappers/bin/sudo -u ${lib.escapeShellArg cfg.user} -H "$0" "$@"
    fi
    export HERMES_HOME=${lib.escapeShellArg "${cfg.stateDir}/.hermes"}
    exec ${cfg.package}/bin/hermes "$@"
  '';
  terminalImage = "hermes-exec:local";
  organizerPython = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  organizerCli = pkgs.writeShellScriptBin "organizer" ''
    exec ${organizerPython}/bin/python3 ${./organizer/organizer.py} "$@"
  '';
  prayerScheduleCli = pkgs.writeShellScriptBin "hermes-prayer-schedule" ''
    if [ "$(${pkgs.coreutils}/bin/id -un)" != ${lib.escapeShellArg cfg.user} ]; then
      exec /run/wrappers/bin/sudo -u ${lib.escapeShellArg cfg.user} -H "$0" "$@"
    fi
    export HERMES_HOME=${lib.escapeShellArg "${cfg.stateDir}/.hermes"}
    exec ${cfg.package.hermesVenv}/bin/python3 ${cfg.stateDir}/.hermes/scripts/schedule.py "$@"
  '';
  bindCli = pkgs.writeShellScriptBin "hermes-secretary-bind" ''
    if [ "$(${pkgs.coreutils}/bin/id -un)" != ${lib.escapeShellArg cfg.user} ]; then
      exec /run/wrappers/bin/sudo -u ${lib.escapeShellArg cfg.user} -H "$0" "$@"
    fi
    export HERMES_HOME=${lib.escapeShellArg "${cfg.stateDir}/.hermes"}
    exec ${cfg.package.hermesVenv}/bin/python3 ${cfg.stateDir}/.hermes/scripts/bind.py "$@"
  '';
in {
  # Shared with hermes.nix, which contains only services.hermes-agent settings.
  _module.args.hermesRuntime = { inherit terminalImage; };

  # The gateway uses its package directly; interactive users get this wrapper.
  environment.systemPackages = [ (lib.hiPrio hermesCli) organizerCli prayerScheduleCli bindCli pkgs.chromium pkgs.curl ];

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
    daemon.settings = {
      log-driver = "local";
      data-root = "/var/lib/hermes-execution/docker";
      default-address-pools = [{ base = "172.30.0.0/16"; size = 24; }];
    };
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/hermes-execution 0755 root root - -"
    "d /var/lib/hermes-execution/sandboxes 0700 hermes hermes - -"
    "d /var/lib/hermes-organizer 0700 hermes hermes - -"
    "d /var/lib/hermes-organizer/data 0700 hermes hermes - -"
  ];
  users.users.hermes.extraGroups = [ "docker" ];

  systemd.services.hermes-terminal-image = {
    requires = [ "docker.service" ];
    after = [ "docker.service" ];
    before = [ "hermes-agent.service" ];
    path = [ pkgs.docker pkgs.systemd ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash ${./terminal-image.sh} ${./Dockerfile} ${lib.escapeShellArg terminalImage}";
    };
  };
  systemd.services.hermes-agent = {
    requires = [ "hermes-terminal-image.service" ];
    after = [ "hermes-terminal-image.service" ];
    environment = {
      AGENT_BROWSER_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
      STT_GROQ_MODEL = "whisper-large-v3";
      # systemd services do not inherit nix-ld's interactive-session variables.
      NIX_LD = "/run/current-system/sw/share/nix-ld/lib/ld.so";
      NIX_LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
    };
    serviceConfig = {
      ImportCredential = "hermes.env";
      UMask = lib.mkForce "0077";
      MemoryMax = "1536M";
      TasksMax = 256;
      ReadWritePaths = [ "/var/lib/hermes-execution/sandboxes" "/var/lib/hermes-organizer/data" ];
    };
    preStart = lib.mkBefore ''
      install -m 0600 "$CREDENTIALS_DIRECTORY/hermes.env" /var/lib/hermes/.hermes/.env
    '';
  };
  # Desk delivery identity is read from the gateway's own authenticated session
  # records, never from model text or a topic title, so no configuration carries
  # it. Nothing binds until the owner sends an explicit bind request in the
  # target topic; the consumed request is recorded so an old one cannot
  # re-point delivery later.
  systemd.services.hermes-secretary-bind = {
    description = "Bind the Hermes secretary Desk destination from an owner request";
    wantedBy = [ "hermes-agent.service" ];
    after = [ "hermes-agent.service" ];
    before = [ "hermes-prayer-refresh.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = cfg.user;
      Environment = "HERMES_HOME=${cfg.stateDir}/.hermes";
      ExecStart = "${cfg.package.hermesVenv}/bin/python3 ${cfg.stateDir}/.hermes/scripts/bind.py";
    };
  };
  # Cheap poll for an unclaimed request. It never guesses a destination and does
  # nothing at all unless the owner has asked to bind.
  systemd.timers.hermes-secretary-bind = {
    description = "Poll for an unclaimed Hermes Desk bind request";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "1min";
      Persistent = false;
    };
  };
  # A restart reconciles an overdue weekly refresh. With no control file or
  # enabled routines this is a no-op; failures stay in this separate unit.
  systemd.services.hermes-prayer-refresh = {
    description = "Reconcile enabled Hermes prayer routines after gateway start";
    wantedBy = [ "hermes-agent.service" ];
    after = [ "hermes-agent.service" "hermes-secretary-bind.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "hermes";
      Environment = "HERMES_HOME=${cfg.stateDir}/.hermes";
      ExecStart = "${cfg.package.hermesVenv}/bin/python3 /var/lib/hermes/.hermes/scripts/prayer-refresh.py";
    };
  };
  # Declarative replacement for the interactive `hermes cron create` step: a
  # weekly host-side reconcile needs no native job, so a rebuilt machine
  # reschedules itself. Persistent catches up a run missed while powered off.
  systemd.timers.hermes-prayer-refresh = {
    description = "Weekly Hermes prayer routine reconcile";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon 00:05";
      Persistent = true;
    };
  };
}
