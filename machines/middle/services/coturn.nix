# Native coturn TURN relay (public).
#
# Acts as a generic public TURN/STUN relay. A single shared static auth secret
# is used in TURN REST API mode (use-auth-secret): both mediamtx and a backend
# derive time-limited HMAC credentials from it out-of-band. coturn itself only
# stores the one secret.
#
# TLS (TURNS) is terminated by coturn on 5349 using a Let's Encrypt cert obtained
# natively via security.acme + Cloudflare DNS-01. This is independent of the
# Traefik container (which keeps port 443 and its own in-container ACME).
#
# See docs/superpowers/specs/2026-06-04-coturn-turn-relay-design.md
{ config, lib, pkgs, ... }:

let
  turnDomain = "turn.amsh.dev";
  # Public IPv4 of this host (ens18). Relay allocations are pinned to it so
  # coturn never advertises a private docker-bridge address as a relay candidate.
  publicIp = "62.146.239.217";
  # Relay UDP port range (each concurrent allocation uses one port).
  relayMinPort = 49152;
  relayMaxPort = 49999;
in
{
  # --- Secrets -------------------------------------------------------------

  # Shared static auth secret, read by coturn at runtime (kept out of the Nix
  # store). The coturn module substitutes it into /run/coturn/turnserver.cfg via
  # replace-secret in ExecStartPre, which runs as the turnserver user (the whole
  # unit is hardened with User=turnserver), so the secret must be owned by it.
  sops.secrets.coturn-static-auth-secret = {
    owner = "turnserver";
    group = "turnserver";
    mode = "0400";
  };

  # Cloudflare DNS token for the ACME DNS-01 challenge, rendered as an env file
  # the acme service consumes via environmentFile. Reuses the existing
  # cloudflare-dns-api-token secret value (same Cloudflare account).
  sops.templates."coturn-acme-cloudflare.env" = {
    owner = "acme";
    group = "acme";
    mode = "0400";
    path = "/var/lib/acme/cloudflare.env";
    content = ''
      CF_DNS_API_TOKEN=${config.sops.placeholder.cloudflare-dns-api-token}
    '';
  };

  # --- TLS certificate via ACME (Cloudflare DNS-01) ------------------------

  security.acme = {
    acceptTerms = true;
    defaults.email = "amjadsharafi10@gmail.com";
    certs.${turnDomain} = {
      dnsProvider = "cloudflare";
      environmentFile = config.sops.templates."coturn-acme-cloudflare.env".path;
      # coturn (turnserver user) must be able to read the cert/key.
      group = "turnserver";
      # Restart coturn so it picks up renewed certs.
      reloadServices = [ "coturn.service" ];
    };
  };

  # --- coturn --------------------------------------------------------------

  services.coturn = {
    enable = true;
    realm = turnDomain;

    # TURN REST API mode: time-limited HMAC credentials derived from the secret.
    # use-auth-secret rides on the long-term credential mechanism, so both are on.
    use-auth-secret = true;
    lt-cred-mech = true;
    static-auth-secret-file = config.sops.secrets.coturn-static-auth-secret.path;

    no-cli = true;

    # TLS (TURNS) on 5349 using the ACME cert.
    cert = "/var/lib/acme/${turnDomain}/fullchain.pem";
    pkey = "/var/lib/acme/${turnDomain}/key.pem";

    # Relay endpoint UDP port range.
    min-port = relayMinPort;
    max-port = relayMaxPort;

    # Pin relay allocations to the public IP only. Without this coturn
    # auto-discovers every interface (the host's docker bridges 172.x / 10.42.x
    # and IPv6) and hands clients relay candidates on those private addresses,
    # which are unroutable — ICE pairs then stall in `in-progress` and never
    # connect. ens18 holds the public 62.146.239.217.
    relay-ips = [ publicIp ];

    extraConfig = ''
      fingerprint
      no-tlsv1
      no-tlsv1_1
      external-ip=${publicIp}
    '';
  };

  # Ensure coturn starts after its cert exists.
  systemd.services.coturn = {
    after = [ "acme-${turnDomain}.service" ];
    wants = [ "acme-${turnDomain}.service" ];
  };

  # --- Firewall ------------------------------------------------------------

  # The coturn NixOS module does NOT open the firewall itself, so open the
  # listener ports (3478 plain, 5349 TLS) and the relay UDP range explicitly.
  networking.firewall.allowedTCPPorts = [
    3478 # TURN/STUN
    5349 # TURNS (TLS)
  ];
  networking.firewall.allowedUDPPorts = [
    3478 # TURN/STUN
    5349 # TURNS (DTLS)
  ];
  networking.firewall.allowedUDPPortRanges = [
    {
      from = relayMinPort;
      to = relayMaxPort;
    }
  ];
}
