# Configuration Guide

## Architecture Overview

The configuration uses a **common + machine-specific** approach:

- **`common/`** - Shared configuration across all machines
- **`machines/`** - Machine-specific overrides and additions
- **`flake.nix`** - Defines all machine configurations

## Common Module Structure

Located in `common/modules/`:

- `system.nix` - Boot loader, timezone, locale, base packages
- `users.nix` - User accounts, SSH keys, sudo configuration  
- `services.nix` - SSH daemon, networking, fail2ban
- `btrfs.nix` - Snapper snapshots, automatic scrubbing
- `docker.nix` - Docker daemon with overlay2 storage
- `compose-services.nix` - Docker Compose services management

## Machine-Specific Configuration

Each machine has its own directory in `machines/MACHINE_NAME/`:

- `configuration.nix` - Machine-specific settings and overrides
- `docker-services/` - Machine-specific Docker services
- `secrets.yaml` - Machine-specific encrypted secrets

### Home Machine (`machines/home/`)
Services: traefik, fireflyiii, blinko, memos, minio, n8n
- Internal traefik (port 8080 only)
- Rathole client configuration
- Application-specific users (www-data for web services)

### Middle Machine (`machines/middle/`)
Services: traefik, wg-easy, kanidm, oauth2-proxy
- Public traefik (ports 80/443)
- Rathole server configuration
- OAuth2 proxy integration

## Hardware Configuration

Hardware configurations are **not included in deployments** for safety:

- Each system maintains its own `/etc/nixos/hardware-configuration.nix`
- Generated automatically during installation with `nixos-generate-config`
- Reference configurations available in `hardware/` directory
- See `hardware/README.md` for detailed information

## Key Configurations

### SSH Keys
SSH keys are centralized in `users.nix` using the `adminSshKeys` variable. Same keys are used for both user and root accounts.

### Fail2ban
Progressive banning: 1h → 2h → 4h → 8h → 16h → 32h → 64h (max 1 week).

### Docker
Uses overlay2 storage driver with journald logging and weekly auto-pruning.

### Service Users
- **dock:docker** - Runs all Docker Compose services
- **www-data:www-data** - Web service (some docker services needs this account) secrets (uid/gid 33)
- **rathole:rathole** - Tunnel service and secrets

### Environment Templates
Sops secrets are converted to environment files via templates:
```nix
sops.templates."service.env" = {
  owner = "dock";
  group = "docker"; 
  mode = "0400";
  path = "/var/lib/dock/service.env";
  content = ''SECRET=${config.sops.placeholder.secret-name}'';
};
```

## Customization

### Global Changes (All Machines)
Edit files in `common/modules/` and redeploy all machines:

- Add packages: Edit `common/modules/system.nix`
- Add SSH keys: Edit `common/modules/users.nix`
- Modify security: Edit `common/modules/services.nix`
- Add Docker services: Edit `common/modules/compose-services.nix`

### Machine-Specific Changes
Edit files in `machines/MACHINE/` and redeploy specific machine:

- Set hostname: Edit `machines/MACHINE/configuration.nix`
- Add machine-specific packages: Add to `machines/MACHINE/configuration.nix`
- Add machine-specific services: Create `machines/MACHINE/docker-services/`

### Deployment Commands
```bash
# Deploy specific machine
./deploy.sh myserver user@server1

# Deploy different machine
./deploy.sh server2 user@server2