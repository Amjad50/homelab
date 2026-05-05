# Vault on Home

## Overview

Vault Community Edition runs on the `home` machine and is published at `https://vault.home.amsh.dev` through the existing middle-to-home rathole tunnel.

- Runtime: Docker Compose on `home`
- Storage: Integrated Raft storage in `/mnt/storage/vault`
- UI/API address: `https://vault.home.amsh.dev`
- Auth: Vault OIDC against Kanidm at `idm.home.amsh.dev`

## What This Deploys

- Vault service directory: `/opt/docker-services/vault`
- Vault config: `/opt/docker-services/vault/config/vault.hcl`
- Vault data: `/mnt/storage/vault`
- OIDC bootstrap sidecar: `vault-bootstrap`
- Bootstrap script: `/opt/docker-services/vault/bootstrap-oidc.sh`
- Bootstrap env file: `/var/lib/dock/vault-bootstrap.env`

## Why This Shape

- Vault stays on the `home` machine because that is where your private apps and local storage already live.
- Middle Traefik only terminates TLS and forwards traffic to home, matching the existing homelab pattern.
- The middle OAuth2 proxy is bypassed for `vault.home.amsh.dev` so Vault can own its own OIDC login flow.

## Required Secrets

Add these through `scripts/generate-secrets.sh`:

- `VAULT_KANIDM_CLIENT_SECRET` - the Kanidm OAuth2 basic secret for client `vault`
- `VAULT_BOOTSTRAP_TOKEN` - a Vault token with enough privilege to enable auth methods, write policies, configure `auth/oidc`, and manage identity groups

Vault initialization will generate additional material you must store safely:

- Unseal key

In a simple single-node homelab, the practical choice is to use the initial root token as `VAULT_BOOTSTRAP_TOKEN`.

## Kanidm Setup

Create the OIDC client on the `middle` machine. This uses the current Kanidm OAuth2/OIDC pattern documented by Kanidm.

```bash
kanidm system oauth2 create vault "Vault" https://vault.home.amsh.dev
kanidm system oauth2 add-redirect-url vault https://vault.home.amsh.dev/ui/vault/auth/oidc/oidc/callback
kanidm system oauth2 add-redirect-url vault http://localhost:8250/oidc/callback
kanidm system oauth2 update-scope-map vault vault-users openid profile email groups_name
kanidm system oauth2 show-basic-secret vault
```

Notes:

- `vault-users` is the baseline Kanidm group for anyone who should be allowed to log into Vault through OIDC.
- `vault-admins` is the default Kanidm group name expected by the bootstrap script.
- `vault-managers` is the default Kanidm group name for users who should manage secrets under `secret/` without full Vault administration.
- The bootstrap script hardcodes the OIDC client, discovery URL, default role, and group names. Change the script itself if you want different non-secret defaults.
- Kanidm documents its per-client discovery URL as `https://idm.home.amsh.dev/oauth2/openid/<client_id>/.well-known/openid-configuration`.

### Kanidm Group Setup

Create the groups if they do not already exist:

```bash
kanidm group create vault-users
kanidm group create vault-admins
kanidm group create vault-managers
```

Grant the OAuth2 scopes to the baseline login group:

```bash
kanidm system oauth2 update-scope-map vault vault-users openid profile email groups_name
```

Add users depending on the level of access they should have:

Normal user, read-only in Vault:

```bash
kanidm group add-members vault-users <username>
```

Secrets manager, can manage secrets under `secret/`:

```bash
kanidm group add-members vault-users <username>
kanidm group add-members vault-managers <username>
```

Vault admin, full Vault administration:

```bash
kanidm group add-members vault-users <username>
kanidm group add-members vault-admins <username>
```

Example:

```bash
kanidm group add-members vault-users alice
kanidm group add-members vault-users amjad
kanidm group add-members vault-managers alice
kanidm group add-members vault-admins amjad
```

Resulting access model:

- member of `vault-users`: `default` + `reader`
- member of `vault-users` + `vault-managers`: `default` + `reader` + `manager`
- member of `vault-users` + `vault-admins`: full `homelab-admin`

## Deploy Vault

```bash
./deploy.sh home <your-home-host>
```

After deployment, start or restart the service if needed:

```bash
compose-manage restart vault
compose-manage logs vault
```

## Initialize and Unseal

Run these on the `home` machine after the container is up:

```bash
docker exec -it vault vault operator init
docker exec -it vault vault operator unseal
docker exec -it vault vault status
```

Store the root token and unseal key outside this repo.

## Bootstrap OIDC

OIDC bootstrap is automatic.

After Vault is initialized and unsealed, the `vault-bootstrap` container waits for the API to become ready and then converges the OIDC configuration using the secrets rendered into `/var/lib/dock/vault-bootstrap.env`.

The helper does the following:

- Enables KV v2 at `secret/` if it is absent
- Writes an `homelab-admin` policy
- Enables the `oidc` auth method if it is absent
- Disables any extra auth mounts other than `token/` and `oidc/`
- Configures Vault to use Kanidm discovery for the `vault` client
- Configures Vault to accept Kanidm's `ES256` signed ID tokens
- Creates a Vault external identity group and group alias for the configured Kanidm admin group
- Creates a Vault external identity group and group alias for the configured Kanidm manager group
- Creates an OIDC role with `groups_claim=groups`; admin access is granted by the group alias instead of a brittle exact-match `bound_claims` gate

The process is idempotent:

- repeated `docker compose up`
- service restarts
- repeated `./deploy.sh`

will rerun the bootstrap container safely without duplicating mounts or breaking existing config.

### Temporary OIDC Claim Debugging

If you need to inspect the exact claims Vault receives from Kanidm, set:

```bash
VAULT_OIDC_VERBOSE_LOGGING=true
```

directly in the bootstrap script, redeploy, retry one OIDC login, inspect Vault logs, then set it back to `false`.

This maps to Vault's `verbose_oidc_logging` role option and should only be enabled temporarily because it logs received OIDC claim data.

## Login

UI login:

- Open `https://vault.home.amsh.dev/ui`
- Select OIDC
- Leave role blank unless you changed the default role

CLI login:

```bash
export VAULT_ADDR='https://vault.home.amsh.dev'
vault login -method=oidc
```

For CLI login, the localhost callback `http://localhost:8250/oidc/callback` must remain configured in Kanidm and Vault.

## Version

The stack is pinned to `hashicorp/vault:2.0.0`.

As of May 4, 2026:

- HashiCorp docs expose `v2.x` as the latest doc stream.
- Docker Hub shows `hashicorp/vault:2.0.0` and `latest`.
