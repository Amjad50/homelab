# coturn public TURN relay on `middle` — design

**Date:** 2026-06-04
**Machine:** `middle` (public VPS, `62.146.239.217` / `2407:3640:2270:5255::1`)
**Status:** approved design, pending implementation

## Goal

Run a native NixOS `services.coturn` daemon on the `middle` server as a **public TURN relay**.
It is a generic relay — it does not know or care who its clients are. Two consumers use it,
both deriving credentials from a **single shared static auth secret** (coturn TURN REST API mode):

1. **mediamtx** — holds the raw secret, mints its own (long-lived) HMAC credentials.
2. **A backend** — holds the same raw secret, mints short-lived, time-limited HMAC credentials
   for browsers.

coturn itself stores only the one secret. "Two points" refers to who generates credentials, not
two secrets in coturn — this is the standard RFC-style TURN REST API design.

### Credential scheme (informational — coturn side only)

With `use-auth-secret` + `lt-cred-mech`, a valid credential is:

```
username = "<unix-expiry-timestamp>"            # e.g. "1893456000"  (or "<ts>:<arbitrary>")
password = base64( HMAC_SHA1( static_secret, username ) )
```

- The **backend** sets `<expiry>` to `now + short_ttl` (e.g. 1h) → browser creds expire.
- **mediamtx** sets a far-future expiry (or uses mediamtx's own coturn integration with the raw
  secret) → effectively long-lived.

This document covers the coturn/NixOS side only. Generating credentials in mediamtx/backend is
out of scope (they just need the raw secret value, distributed out-of-band).

## Deployment model

Native NixOS service (`services.coturn`), **not** Docker. Rationale: TURN relays a wide UDP port
range; running that in Docker is slow (per-port userland proxy) and awkward. Native binds the
public interface directly and integrates with the firewall. Sits alongside the existing native
`rathole-server` systemd service on `middle`.

## Listeners & ports

| Purpose            | Port / proto        | Notes                                        |
|--------------------|---------------------|----------------------------------------------|
| Plain TURN/STUN    | 3478 UDP + TCP      | `listening-port = 3478`                      |
| TURNS (TLS/DTLS)   | 5349 UDP + TCP      | `tls-listening-port = 5349`, cert below      |
| Relay range        | 49152–49999 UDP     | `min-port`/`max-port`; ~850 concurrent allocations |

- The NixOS coturn module opens `listening-port` and `tls-listening-port` in the firewall
  automatically.
- The relay UDP range **must** be added explicitly to `networking.firewall.allowedUDPPorts`
  (range syntax `{ from = 49152; to = 49999; }`).
- 443 is **not** used — it is owned by the Traefik container. Traefik cannot proxy TURN (UDP relay
  + coturn must terminate its own TLS for realm auth), so coturn is fully independent of Traefik.

## TLS

- coturn terminates TLS itself on 5349 for realm `turn.amsh.dev`.
- Certificate obtained **natively** via NixOS `security.acme` using the **Cloudflare DNS-01**
  challenge (the Traefik container's in-container ACME is unrelated and untouched).
- `security.acme.certs."turn.amsh.dev"` with `dnsProvider = "cloudflare"` and a
  `credentialsFile`/`environmentFile` containing the Cloudflare DNS API token.
- coturn points at:
  - `cert = "/var/lib/acme/turn.amsh.dev/fullchain.pem"`
  - `pkey = "/var/lib/acme/turn.amsh.dev/key.pem"`
- ACME renewal hook (`postRun`) restarts `coturn.service` so it picks up the renewed cert.
- The `acme` user must be able to read the certs; coturn (`turnserver` user) must be able to read
  them too — add `turnserver` to the `security.acme.certs."turn.amsh.dev".group` (or use the
  default `acme` group and grant coturn membership). Concretely: set the cert `group` and ensure
  `turnserver`'s supplementary groups include it. Verify exact mechanism at implementation time
  via `nix eval` of `security.acme.certs.<name>.group`.

## coturn configuration (`services.coturn`)

```nix
services.coturn = {
  enable                 = true;
  realm                  = "turn.amsh.dev";
  use-auth-secret        = true;
  lt-cred-mech           = true;                 # required: use-auth-secret rides on the long-term mech
  static-auth-secret-file = config.sops.secrets.coturn-static-auth-secret.path;
  no-cli                 = true;
  cert                   = "/var/lib/acme/turn.amsh.dev/fullchain.pem";
  pkey                   = "/var/lib/acme/turn.amsh.dev/key.pem";
  min-port               = 49152;
  max-port               = 49999;
  # listening-port = 3478; tls-listening-port = 5349;  # defaults, kept explicit if needed
  extraConfig = ''
    fingerprint
    no-tlsv1
    no-tlsv1_1
    # listening-ips left unset = listen on all interfaces (public v4 + v6)
  '';
};
```

- `static-auth-secret-file` keeps the secret out of the Nix store (reads at runtime from the
  sops-decrypted path).
- `no-auth` stays off; we explicitly want auth.

## Secrets (sops)

Add to `machines/middle/secrets.yaml`:

| Secret                          | Owner        | Consumer                              |
|---------------------------------|--------------|---------------------------------------|
| `coturn-static-auth-secret`     | `turnserver` | coturn `static-auth-secret-file`      |
| `coturn-cloudflare-dns-token`   | `acme`*      | `security.acme` DNS-01 environmentFile |

\* Or reuse the existing `cloudflare-dns-api-token` value — same Cloudflare account/token. Decision
at implementation: simplest is a dedicated `coturn-cloudflare-dns-token` (or a shared
`acme-cloudflare-env` template) owned so the acme service can read it. The acme service needs the
token as an env var (e.g. `CF_DNS_API_TOKEN=...`) via `environmentFile`, which a sops **template**
produces cleanly (mirrors the existing `restic-s3.env` / `ntfy.env` template pattern).

These coturn secrets are declared **directly under `sops.secrets`** in
`machines/middle/services/index.nix` (alongside `rathole-*`), **not** via `homelab.services`,
because coturn is a native systemd service, not a compose service. The `homelab.services` registry
only drives Docker Compose services + their secrets/templates/backups.

## Files to change

1. **`machines/middle/secrets.yaml`** — add `coturn-static-auth-secret` and the Cloudflare DNS
   token (or reuse existing). Generate the static secret with e.g. `openssl rand -hex 32`.
2. **`machines/middle/services/index.nix`** (or a new `machines/middle/services/coturn.nix`
   imported there) —
   - `services.coturn` block (above),
   - `security.acme` cert for `turn.amsh.dev`,
   - `sops.secrets` / `sops.templates` for the two secrets,
   - group wiring so `turnserver` can read the ACME cert,
   - relay UDP firewall range.
3. **`machines/middle/networking.nix`** — add the relay UDP range to
   `networking.firewall.allowedUDPPorts` (3478/5349 handled by the coturn module; confirm and avoid
   duplicates).
4. **`docs/`** — short note documenting the TURN endpoint + credential scheme (optional but nice).

Prefer a dedicated `machines/middle/services/coturn.nix` to keep `index.nix` focused, imported from
`index.nix` or `configuration.nix`.

## Prerequisites (done / external)

- **DNS:** `turn.amsh.dev` A → `62.146.239.217`, AAAA → `2407:3640:2270:5255::1`. ✅ Done by user.
- `security.acme.acceptTerms = true` and a contact email must be set (check whether already set on
  `middle`; if not, add `security.acme.defaults.email`).

## Verification

- `nix eval .#nixosConfigurations.middle.config.systemd.services.coturn` builds.
- After deploy: `systemctl status coturn`, `journalctl -u coturn`.
- ACME: `systemctl status acme-turn.amsh.dev`, cert present in `/var/lib/acme/turn.amsh.dev/`.
- TURN reachability test from an external host using the Trickle ICE / `turnutils_uclient` tool, or
  the WebRTC samples Trickle-ICE page, with a backend-minted credential — confirm a `relay`
  candidate appears for both `turn:turn.amsh.dev:3478` and `turns:turn.amsh.dev:5349`.
- Confirm UDP relay works end-to-end (a relay candidate that actually carries media), not just that
  the port is open.

## Out of scope

- mediamtx and backend credential-generation code (they consume the raw secret; distribution is
  manual/out-of-band).
- Traefik SNI-passthrough of 443 → coturn (rejected; can revisit if a restrictive-firewall client
  ever needs TURNS-on-443).
- Two cryptographically separate secrets (rejected in favour of one shared secret).
