# Headscale mesh node + split-horizon DNS for middle.
{ config, pkgs, ... }:
{
  sops.secrets.headscale-middle-authkey = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets.headscale-middle-authkey.path;
    extraUpFlags = [ "--login-server=https://vpn.home.amsh.dev" ];
  };

  systemd.services.coredns =
    let
      corefileTemplate = pkgs.writeText "Corefile.tmpl" ''
        . {
            bind tailscale0
            template IN A home.amsh.dev {
                match "^([^.]+\.)*home\.amsh\.dev\.$"
                answer "{{ .Name }} 60 IN A @MESH_V4@"
                fallthrough
            }
            template IN AAAA home.amsh.dev {
                match "^([^.]+\.)*home\.amsh\.dev\.$"
                answer "{{ .Name }} 60 IN AAAA @MESH_V6@"
                fallthrough
            }
            forward . 127.0.0.1:5300 1.1.1.1 {
                policy sequential
            }
            cache 30
            errors
        }
      '';
      renderCorefile = pkgs.writeShellScript "coredns-render-corefile" ''
        set -euo pipefail
        v4="$(${pkgs.tailscale}/bin/tailscale ip -4)"
        v6="$(${pkgs.tailscale}/bin/tailscale ip -6)"
        ${pkgs.gnused}/bin/sed \
          -e "s|@MESH_V4@|$v4|g" \
          -e "s|@MESH_V6@|$v6|g" \
          ${corefileTemplate} > /run/coredns/Corefile
      '';
    in {
      description = "CoreDNS mesh-only split-horizon resolver";
      after = [ "tailscaled.service" "sys-subsystem-net-devices-tailscale0.device" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        LimitNPROC = 512;
        LimitNOFILE = 1048576;
        CapabilityBoundingSet = "cap_net_bind_service";
        AmbientCapabilities = "cap_net_bind_service";
        NoNewPrivileges = true;
        DynamicUser = true;
        RuntimeDirectory = "coredns";
        ExecStartPre = renderCorefile;
        ExecStart = "${pkgs.coredns}/bin/coredns -conf=/run/coredns/Corefile";
        ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR1 $MAINPID";
        Restart = "on-failure";
      };
    };
}
