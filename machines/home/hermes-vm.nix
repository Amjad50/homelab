{ config, lib, pkgs, hermes-agent, ... }:
let
  runtime = "/run/hermes-vm";
  secret = config.sops.secrets;
in {
  microvm.vms.hermes = {
    autostart = true;
    restartIfChanged = true;
    specialArgs = {
      inherit hermes-agent;
      adminKeys = config.users.users.amjad.openssh.authorizedKeys.keys;
    };
    config = { imports = [ ../hermes/configuration.nix ]; };
  };
  sops.secrets = {
    hermes-env = { restartUnits = [ "microvm@hermes.service" ]; };
    hermes-provision = { restartUnits = [ "hermes-provision.service" "microvm@hermes.service" ]; };
  };
  systemd.services.hermes-provision = {
    description = "Provision Hermes Cloudflare tunnel and DNS";
    wants = [ "network-online.target" ];
    after = [ "sops-install-secrets.service" "network-online.target" ];
    before = [ "microvm@hermes.service" ];
    restartTriggers = [ ../hermes/provision.py ];
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 30;
      LoadCredential = "provision.json:${secret.hermes-provision.path}";
      StateDirectory = "hermes-provision";
      StateDirectoryMode = "0700";
      RuntimeDirectory = "hermes-vm";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
      TimeoutStartSec = 180;
      ExecStart = "${pkgs.python3}/bin/python3 ${../hermes/provision.py}";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };
  systemd.services."microvm@hermes" = {
    requires = [ "nftables.service" ];
    # Missing credentials fail QEMU's service setup. Wants + Restart allows
    # recovery after an Internet/API outage without an extra deploy or timer.
    wants = [ "hermes-provision.service" ];
    after = [ "hermes-provision.service" "nftables.service" "systemd-networkd.service" ];
    serviceConfig = {
      LoadCredential = [
        "hermes.env:${secret.hermes-env.path}"
        "cloudflared-token:${runtime}/cloudflared-token"
      ];
      MemoryMax = "5G";
      CPUQuota = "200%";
      TasksMax = 256;
      TimeoutStopSec = 180;
    };
  };
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  systemd.network.networks."30-hermes" = {
    matchConfig.Name = "hermes-tap";
    address = [ "192.168.250.1/30" ];
    networkConfig = { DHCP = "no"; IPv6AcceptRA = false; LinkLocalAddressing = "no"; ConfigureWithoutCarrier = true; };
  };
  # Separate nft hooks run before Docker/NixOS filter chains. No guest root can
  # remove these host rules. An ACCEPT here cannot bypass later host rules.
  networking.nftables = {
    enable = true;
    tables.hermes = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority -50; policy accept;
          iifname "hermes-tap" meta nfproto ipv6 drop
          iifname "hermes-tap" ip saddr != 192.168.250.2 drop
          iifname "hermes-tap" ct state established,related accept
          iifname "hermes-tap" drop
        }
        chain forward {
          type filter hook forward priority -50; policy accept;
          iifname "hermes-tap" meta nfproto ipv6 drop
          oifname "hermes-tap" meta nfproto ipv6 drop
          iifname "hermes-tap" ip saddr != 192.168.250.2 drop
          iifname "hermes-tap" ip daddr {
            0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8,
            169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.168.0.0/16,
            198.18.0.0/15, 224.0.0.0/4, 240.0.0.0/4
          } drop
          iifname "hermes-tap" oifname != "eno2" drop
          oifname "hermes-tap" ct state established,related accept
          oifname "hermes-tap" drop
        }
        chain nat {
          type nat hook postrouting priority srcnat; policy accept;
          ip saddr 192.168.250.2 oifname "eno2" masquerade
        }
      '';
    };
  };
  # Keep the existing host/Docker firewall backend; the dedicated early nft
  # hooks above enforce VM isolation independently of Docker's ACCEPT rules.
  networking.firewall.backend = "iptables";
  networking.firewall.package = pkgs.iptables;
  networking.firewall.extraCommands = ''
    iptables -w -C FORWARD -i hermes-tap -o eno2 -j ACCEPT 2>/dev/null || iptables -w -I FORWARD -i hermes-tap -o eno2 -j ACCEPT
    iptables -w -C FORWARD -i eno2 -o hermes-tap -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -w -I FORWARD -i eno2 -o hermes-tap -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  '';
  networking.firewall.extraStopCommands = ''
    iptables -w -D FORWARD -i hermes-tap -o eno2 -j ACCEPT 2>/dev/null || true
    iptables -w -D FORWARD -i eno2 -o hermes-tap -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
  '';
}
