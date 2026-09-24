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
in {
  # Shared with hermes.nix, which contains only services.hermes-agent settings.
  _module.args.hermesRuntime = { inherit terminalImage; };

  # The gateway uses its package directly; interactive users get this wrapper.
  environment.systemPackages = [ (lib.hiPrio hermesCli) pkgs.chromium ];

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
      # systemd services do not inherit nix-ld's interactive-session variables.
      NIX_LD = "/run/current-system/sw/share/nix-ld/lib/ld.so";
      NIX_LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
    };
    serviceConfig = {
      ImportCredential = "hermes.env";
      UMask = lib.mkForce "0077";
      MemoryMax = "1536M";
      TasksMax = 256;
      ReadWritePaths = [ "/var/lib/hermes-execution/sandboxes" ];
    };
    preStart = lib.mkBefore ''
      install -m 0600 "$CREDENTIALS_DIRECTORY/hermes.env" /var/lib/hermes/.hermes/.env
    '';
  };
}
