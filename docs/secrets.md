# Secrets Management

This repository uses `sops-nix` and SSH host keys to decrypt secrets on the target machine. The encrypted files are kept as machine-specific `secrets.yaml` files under `machines/<machine>/`, and those paths are ignored by Git.

## How It Works

- `.sops.yaml` defines which age recipients may decrypt each machine file.
- `machines/home/secrets.yaml`, `machines/middle/secrets.yaml`, `machines/home-vm/secrets.yaml`, and `machines/middle-vm/secrets.yaml` are the machine-specific encrypted payloads.
- `scripts/generate-secrets.sh` can generate or re-encrypt those files from environment variables.
- `scripts/install-pre-commit-hook.sh` installs a local hook that refuses commits if a `secrets.yaml` file is staged.

## Current Pattern

Most services consume secrets through NixOS templates:

```nix
sops = {
  defaultSopsFile = ../secrets.yaml;
  age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
};

sops.templates."myapp.env" = {
  owner = "dock";
  group = "docker";
  mode = "0400";
  path = "/var/lib/dock/myapp.env";
  content = ''
    DB_PASSWORD=${config.sops.placeholder.myapp-db-password}
    API_KEY=${config.sops.placeholder.myapp-api-key}
  '';
};
```

The current repo uses this pattern for:

- Docker environment files under `/var/lib/dock/`
- Tunnel config files such as `rathole-client.toml`
- Backup credentials such as `restic-repository-password`

## Adding A Secret

1. Add the secret name to `.sops.yaml` if it needs a new recipient rule.
2. Add the secret entry to the appropriate machine config with `sops.secrets.<name>`.
3. Reference it through `config.sops.placeholder.<name>` in a template or service config.
4. Generate or update the encrypted file with `scripts/generate-secrets.sh` or `sops <path>`.

Example:

```bash
./scripts/generate-secrets.sh
```

## Editing And Verifying

```bash
sops machines/home/secrets.yaml
sops machines/middle/secrets.yaml
sops --decrypt machines/home/secrets.yaml
```

If you are working on the VM configs, keep in mind that `machines/home-vm/configuration.nix` and `machines/middle-vm/configuration.nix` each point at their own local `secrets.yaml` file.

## Notes

- Do not commit `secrets.yaml` files.
- If you stage one by mistake, the local pre-commit hook will stop the commit.
- The repo intentionally keeps the generated encrypted files local so they can be recreated, rotated, or re-encrypted without storing them in Git history.
