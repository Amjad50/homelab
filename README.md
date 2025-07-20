# NixOS Server Configuration

Modular NixOS server configuration with Docker Compose services, Btrfs snapshots, and security features.

## Quick Start

```bash
# Deploy to server
./deploy.sh myserver amjad@server

# Manage Docker Compose services
compose-manage list
compose-manage start nginx
```

## Architecture

```
nixos-config/
├── flake.nix                 # Flake configuration with multiple machines
├── common/                   # Shared configuration
│   ├── configuration.nix    # Common base configuration  
│   ├── modules/              # Shared modules
│   │   ├── system.nix       # Core system settings
│   │   ├── btrfs.nix        # Btrfs snapshots & scrubbing
│   │   ├── services.nix     # SSH, networking, fail2ban
│   │   ├── users.nix        # User accounts & SSH keys
│   │   ├── docker.nix       # Docker configuration
│   │   └── compose-services.nix # Docker Compose services
│   └── scripts/             # Management scripts
├── machines/                # Machine-specific configurations
│   └── myserver/            # Individual machine config
│       ├── configuration.nix # Machine-specific settings
│       └── docker-services/ # Optional: machine-specific services
├── hardware/                # Hardware configuration references
│   ├── README.md            # Hardware configuration guide
│   └── vm-testing.nix       # Example configurations
├── docker-services/         # Global Docker Compose services
├── docs/                    # Detailed documentation
└── deploy.sh               # Multi-machine deployment script
```

## Features

- **Multi-machine support** - Common configuration with machine-specific overrides
- **Modular configuration** - Shared modules and machine-specific settings
- **Remote deployment** - Compressed transfers with change detection and automatic service restarts
- **Btrfs subvolumes** - Optimized layout with automatic snapshots
- **Docker Compose services** - Global and machine-specific service management with polkit integration
- **Security hardening** - SSH keys, fail2ban, firewall configuration
- **Declarative management** - Everything defined in Nix configuration

## Available Commands

### System Management
```bash
./deploy.sh myserver amjad@server1     # Deploy myserver config to server1
./deploy.sh server2 amjad@server2      # Deploy server2 config to server2
./deploy.sh myserver                   # Deploy myserver locally (if on NixOS)
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

### Adding New Machines

1. Create directory: `mkdir machines/newserver`
2. Add `machines/newserver/configuration.nix` with machine-specific settings
3. Add machine to `flake.nix` nixosConfigurations
4. Deploy: `./deploy.sh newserver user@newserver`

### Adding Docker Compose Services

**Global services (shared across machines):**
1. Add to `docker-services/` directory
2. Update `common/modules/compose-services.nix` services list
3. Deploy to update all machines

**Machine-specific services:**
1. Add to `machines/MACHINE/docker-services/` directory  
2. Deploy specific machine

### Module Structure

- `common/modules/system.nix` - Boot, locale, packages
- `common/modules/users.nix` - User accounts, SSH keys  
- `common/modules/services.nix` - SSH, networking, fail2ban
- `common/modules/btrfs.nix` - Snapshots, scrubbing
- `common/modules/docker.nix` - Docker daemon configuration
- `common/modules/compose-services.nix` - Docker Compose services

## 📚 Documentation

Detailed documentation is available in the `docs/` directory:

- [Installation Guide](docs/installation.md) - Automated NixOS installation
- [Deployment Guide](docs/deployment.md) - Remote deployment with change detection
- [Configuration Guide](docs/configuration.md) - Detailed module configuration
- [Docker Management](docs/docker.md) - Docker Compose service management
- [Btrfs & Snapshots](docs/btrfs.md) - Storage and backup configuration
- [Security](docs/security.md) - Security features and best practices
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions

## 🛠️ Requirements

- **Local**: Nix package manager (for remote deployment)
- **Server**: NixOS 25.05 with UEFI/BIOS boot support
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
