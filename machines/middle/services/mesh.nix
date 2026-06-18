# Mesh nodes for middle: headscale (tailscale) + netbird clients, plus a single
# CoreDNS forwarder bound to both mesh interfaces.
{ config, pkgs, nixpkgs-unstable, ... }:
let
  nbIface = "nb-default";
  mgmtUrl = "https://netbird.home.amsh.dev";

  unstablePkgs = import nixpkgs-unstable { inherit (pkgs.stdenv.hostPlatform) system; };

  # 25.05's netbird is 0.43.3, too old for the 0.72.4 server; pin unstable's 0.72.x (keep 25.05's module, unstable's needs services.firewalld).
  netbird-pinned = unstablePkgs.netbird;

  nb = "${config.services.netbird.clients.default.wrapper}/bin/netbird-default";

  # Forwarder to AdGuard (answers *.home.amsh.dev), falling back to 1.1.1.1.
  corefile = pkgs.writeText "Corefile" ''
    . {
        bind tailscale0 ${nbIface}
        forward . 127.0.0.1:5300 1.1.1.1 {
            policy sequential
        }
        cache 30
        errors
    }
  '';
in
{
  ## Headscale (tailscale) ----------------------------------------------------
  sops.secrets.headscale-middle-authkey = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets.headscale-middle-authkey.path;
    extraUpFlags = [ "--login-server=https://vpn.home.amsh.dev --accept-dns=false" ];
  };

  ## NetBird ------------------------------------------------------------------
  sops.secrets.netbird-middle-setup-key = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  services.netbird.package = netbird-pinned;

  services.netbird.clients.default = {
    autoStart = true;
    openFirewall = true;
    interface = nbIface;
    # 51820/udp is taken by the netbird-server container on this host.
    port = 51821;
    # Don't set ManagementURL here: `config` writes it as a string but the daemon needs a url.URL (string = crash); passed via `netbird up --management-url` in netbird-enroll instead.
    config.DisableDNS = true;
  };

  # 25.05's module has no `login.setupKeyFile`, so enroll once via `netbird up`.
  systemd.services.netbird-enroll = {
    description = "Enroll middle into the NetBird mesh with a setup key";
    after = [ "netbird-default.service" "netbird-server.service" ];
    wants = [ "netbird-default.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      LoadCredential = [ "setup-key:${config.sops.secrets.netbird-middle-setup-key.path}" ];
    };
    script = ''
      set -euo pipefail
      for i in $(seq 1 30); do
        if ${nb} status >/dev/null 2>&1; then break; fi
        sleep 2
      done
      if ${nb} status 2>/dev/null | grep -q ": Connected"; then
        echo "netbird already connected; nothing to do"
        exit 0
      fi
      ${nb} up \
        --management-url "${mgmtUrl}" \
        --setup-key "$(cat "$CREDENTIALS_DIRECTORY/setup-key")"
    '';
  };

  ## CoreDNS (shared by both meshes) ------------------------------------------
  systemd.services.coredns = {
    description = "CoreDNS mesh forwarder (tailscale + netbird)";
    after = [ "tailscaled.service" "netbird-default.service" ];
    wants = [ "tailscaled.service" "netbird-default.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      LimitNPROC = 512;
      LimitNOFILE = 1048576;
      CapabilityBoundingSet = "cap_net_bind_service";
      AmbientCapabilities = "cap_net_bind_service";
      NoNewPrivileges = true;
      DynamicUser = true;
      ExecStart = "${pkgs.coredns}/bin/coredns -conf=${corefile}";
      ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR1 $MAINPID";
      Restart = "on-failure";
      # Interfaces may appear slightly after the services; retry binding.
      RestartSec = "3";
    };
  };
}
