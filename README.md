# NixOS Server Configuration

Modular NixOS server configuration with Docker Compose services, Btrfs snapshots, and security features.

## Quick Start

```bash
# Deploy to server
./deploy.sh amjad@server

# Manage Docker Compose services
compose-manage list
compose-manage start nginx
```

## Architecture

```
nixos-config/
├── flake.nix                 # Flake configuration
├── configuration.nix         # Main entry point
├── hardware-configuration.nix # Hardware & filesystem config
├── modules/                  # Modular configurations
│   ├── system.nix           # Core system settings
│   ├── btrfs.nix            # Btrfs snapshots & scrubbing
│   ├── services.nix         # SSH, networking, fail2ban
│   ├── users.nix            # User accounts & SSH keys
│   ├── docker.nix           # Docker configuration
│   └── compose-services.nix # Docker Compose services
├── scripts/                 # External shell scripts
├── docs/                    # Detailed documentation
└── deploy.sh               # Deployment script
```

## Features

- Modular configuration with separate concerns
- Remote deployment via SSH
- Btrfs subvolumes with automatic snapshots
- Docker Compose service management and systemd integration
- Fail2ban with progressive banning
- SSH key-only authentication
- Firewall configuration

## Available Commands

### System Management
```bash
./deploy.sh amjad@server      # Deploy to remote server
./deploy.sh                   # Deploy locally (if on NixOS)
```

### Docker Compose Services
```bash
compose-manage list           # List all services and status
compose-manage start <service>    # Start a service
compose-manage stop <service>     # Stop a service
compose-manage restart <service>  # Restart a service
compose-manage logs <service>     # Follow service logs
compose-manage status [service]   # Show detailed status
compose-manage enable <service>   # Auto-start on boot
compose-manage disable <service>  # Disable auto-start
```

### Container Operations
```bash
compose-manage exec <service> <container> <command>  # Execute in container
compose-manage ps [service]                          # Show containers
```

### Quick Status
```bash
compose-status               # Quick service overview
```

## Configuration

### Adding Docker Compose Services

1. Create directory in `/opt/docker-services/`
2. Add `docker-compose.yml` file
3. Run `compose-manage start <service-name>`

### Module Structure

- `modules/system.nix` - Boot, locale, packages
- `modules/users.nix` - User accounts, SSH keys
- `modules/services.nix` - SSH, networking, fail2ban
- `modules/btrfs.nix` - Snapshots, scrubbing
- `modules/docker.nix` - Docker daemon configuration
- `modules/compose-services.nix` - Docker Compose services

## 📚 Documentation

Detailed documentation is available in the `docs/` directory:

- [Installation Guide](docs/installation.md) - Automated NixOS installation
- [Configuration Guide](docs/configuration.md) - Detailed module configuration
- [Docker Management](docs/docker.md) - Docker Compose service management
- [Btrfs & Snapshots](docs/btrfs.md) - Storage and backup configuration
- [Security](docs/security.md) - Security features and best practices
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions

## 🛠️ Requirements

- **Local**: Nix package manager (for remote deployment)
- **Server**: NixOS 25.05 with UEFI boot
- **Storage**: Btrfs filesystem with separate subvolumes
- **Network**: SSH access to target server

## 🔒 Security Features

- **SSH**: Key-only authentication, no password login
- **Fail2ban**: Automatic IP blocking with progressive timeouts
- **Firewall**: Minimal attack surface with essential ports only
- **User Security**: Non-root user with sudo access
- **Container Security**: Docker security options enabled

## 📊 Monitoring

- **Systemd**: All services integrated with systemd
- **Journald**: Centralized logging with rotation
- **Snapper**: Automatic snapshot monitoring
- **Btrfs**: Monthly filesystem scrubbing
