# Homelab Mappings

This repository organizes machine-specific behavior through a small set of `homelab.*` mappings and machine-local secret files.

## Core Names

- `homelab.services` is the per-machine service registry.
- `homelab.backups` is the per-machine backup-group registry.
- `homelab.machineName` is the machine identifier used in restic tags, lock files, and restore metadata.

These values are set in the machine configs and consumed by `common/modules/service-registry.nix`.

## Service Registry

Each machine defines `homelab.services.<name>` entries in `machines/<machine>/services/index.nix`.

Typical fields:

- `tmpfiles` for directory creation
- `secrets` for `sops.secrets` entries
- `templates` for `sops.templates`
- `backup.group` to attach the service to a backup group
- `backup.paths` for filesystem paths included in the backup
- `backup.postgres` for PostgreSQL dump metadata
- `backup.customBackupScript` and `backup.customRestoreScript` for service-specific hooks

Example:

```nix
homelab.services.fireflyiii = {
  tmpfiles = [ "v /mnt/storage/firefly 0755 dock docker - -" ];
  secrets.firefly-db-password = {
    owner = "www-data";
    group = "www-data";
    mode = "0400";
  };
  backup = {
    group = config.homelab.backups.default;
    paths = [ "/mnt/storage/firefly/upload" ];
    postgres = [{
      composeService = "fireflyiii-db";
      database = "firefly";
      user = "firefly";
    }];
  };
};
```

## Backup Registry

Each machine defines `homelab.backups.<group>` entries in the same registry file.

Typical fields:

- `autoStart` to control whether the restore sentinel is expected on boot
- `schedule` to set the restic timer calendar
- `postRestoreScript` for group-level restore cleanup or setup

Example:

```nix
homelab.backups.default = {
  autoStart = true;
};

homelab.backups.immich = {
  autoStart = false;
  postRestoreScript = ''
    mkdir -p /mnt/storage/immich/upload
  '';
};
```

## Secrets Layout

Secrets are machine-local encrypted files:

- `machines/home/secrets.yaml`
- `machines/middle/secrets.yaml`
- `machines/home-vm/secrets.yaml`
- `machines/middle-vm/secrets.yaml`

These files are:

- generated or re-encrypted by `scripts/generate-secrets.sh`
- matched against `.sops.yaml` creation rules
- ignored by Git

## Runtime Flow

At evaluation time, the registry generates:

- `services.compose-services.services`
- `systemd.tmpfiles.rules`
- `sops.secrets`
- `sops.templates`
- `services.restic.backups.<group>`
- restore metadata in `/etc/homelab/services.json`

At runtime, the restore CLI is:

```bash
homelab-backup list
homelab-backup restore default
homelab-backup backup default
homelab-backup restore immich
```

## Where To Look

- [`common/modules/service-registry.nix`](../common/modules/service-registry.nix)
- [`machines/home/services/index.nix`](../machines/home/services/index.nix)
- [`machines/middle/services/index.nix`](../machines/middle/services/index.nix)
- [`docs/secrets.md`](secrets.md)
- [`docs/backup.md`](backup.md)
