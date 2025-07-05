# NixOS Installation Guide

## Installation Script

The `install-nixos.sh` script provides automated NixOS installation with optimized Btrfs layout and SSH configuration.

## Prerequisites

- **NixOS ISO** booted on target system
- **UEFI system** (script is UEFI-only)
- **Internet connection** for package downloads
- **Root access** on installer

## Usage

### Basic Installation
```bash
# Download or copy script to NixOS ISO
chmod +x install-nixos.sh
sudo ./install-nixos.sh /dev/sda
```

### Custom Configuration
Edit the script variables before running:
```bash
DISK="${1:-/dev/sda}"           # Target disk
HOSTNAME="nixos-server"         # System hostname  
USERNAME="amjad"                # Primary user
TIMEZONE="Asia/Kuala_Lumpur"    # System timezone
SSH_KEY="ssh-ed25519 ..."       # Your SSH public key
```

## What the Script Does

### 1. Disk Partitioning
- **GPT partition table** for UEFI compatibility
- **512MB EFI partition** (`/boot/efi`)
- **Remaining space** for Btrfs root partition

### 2. Btrfs Subvolumes
Creates optimized subvolume layout:

| Subvolume | Mount Point | Compression | Purpose |
|-----------|-------------|-------------|---------|
| `root` | `/` | `zstd:3` | System root |
| `home` | `/home` | `zstd:1` | User data |
| `nix` | `/nix` | `zstd:3` | Nix store |
| `var` | `/var` | `zstd:1` | Variable data |
| `var-log` | `/var/log` | `zstd:6` | System logs |
| `var-cache` | `/var/cache` | `nodatacow` | Cache files |
| `var-tmp` | `/var/tmp` | `nodatacow` | Temp files |
| `var-lib` | `/var/lib` | `zstd:1` | Service data |
| `var-lib-docker` | `/var/lib/docker` | `zstd:1` | Docker data |
| `tmp` | `/tmp` | `nodatacow` | Temporary files |
| `srv` | `/srv` | `zstd:1` | Service data |
| `opt` | `/opt` | `zstd:1` | Optional software |
| `snapshots` | `/.snapshots` | `zstd:1` | Btrfs snapshots |

### 3. Base System Installation
- **Minimal NixOS** with essential packages
- **SSH daemon** with key-only authentication
- **User account** with sudo access
- **Flakes enabled** for modern Nix usage
- **Hardware configuration** auto-generated

## Post-Installation

### 1. Reboot System
```bash
reboot
```

### 2. Verify SSH Access
```bash
ssh amjad@<server-ip>
```

### 3. Deploy Configuration
```bash
# From your development machine
./deploy.sh myserver amjad@<server-ip>

# For additional machines, specify the machine name
./deploy.sh server2 amjad@<server-ip>
```

## Security Features

- **SSH key-only authentication** - No password login
- **Root SSH access** - For deployment purposes
- **Passwordless sudo** - For wheel group users
- **Firewall enabled** - Only SSH port open
- **Secure EFI mount** - Proper permission restrictions

## Customization

### Different Disk
```bash
sudo ./install-nixos.sh /dev/nvme0n1
```

### Custom Configuration
Edit these variables in the script:
- `HOSTNAME` - System hostname
- `USERNAME` - Primary user account
- `TIMEZONE` - System timezone
- `SSH_KEY` - Your SSH public key

### Advanced Options
The script can be modified for:
- Different partition sizes
- Additional subvolumes
- Custom compression settings
- Different package selections

## Troubleshooting

### Script Fails During Partitioning
- Ensure disk is not mounted
- Check disk path with `lsblk`
- Verify UEFI boot mode

### Installation Hangs
- Check internet connection
- Monitor with `journalctl -f`
- Increase timeouts if needed

### Boot Issues After Installation
- Verify UEFI settings in BIOS
- Check EFI partition mounting
- Ensure bootloader installation succeeded

### SSH Connection Fails
- Verify network configuration
- Check SSH key in script
- Confirm firewall settings

## What's Next

After successful installation:

1. **Test SSH connectivity**
2. **Deploy your configuration** with `./deploy.sh user@server myserver`
3. **Add machine to flake.nix** if using different machine name
4. **Set up Docker services** as needed
5. **Configure machine-specific settings**
6. **Set up monitoring and backups**

The installation creates a minimal but production-ready NixOS system optimized for your configuration deployment workflow.