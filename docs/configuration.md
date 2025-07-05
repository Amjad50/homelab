# Configuration Guide

## Module Structure

- `system.nix` - Boot loader, timezone, locale, base packages
- `users.nix` - User accounts, SSH keys, sudo configuration  
- `services.nix` - SSH daemon, networking, fail2ban
- `btrfs.nix` - Snapper snapshots, automatic scrubbing
- `docker.nix` - Docker daemon with overlay2 storage
- `compose-services.nix` - Docker Compose services management

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

## Customization

Edit the appropriate module file and redeploy with `./deploy.sh amjad@server`.

Common changes:
- Add packages: Edit `system.nix`
- Change hostname: Edit `services.nix`
- Add SSH keys: Edit `users.nix`
- Modify firewall ports: Edit `services.nix`