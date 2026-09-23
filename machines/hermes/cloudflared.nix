{ pkgs, ... }:
{
  systemd.services.hermes-tunnel = {
    description = "Cloudflare Tunnel for Hermes webhooks";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate --metrics 127.0.0.1:20241 run --token-file %d/cloudflared-token";
      ImportCredential = "cloudflared-token";
      DynamicUser = true;
      Restart = "always";
      RestartSec = 5;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      CapabilityBoundingSet = "";
      MemoryMax = "256M";
    };
  };
}
