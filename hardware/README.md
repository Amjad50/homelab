# Hardware Configurations

This directory contains hardware-specific configurations for reference and documentation purposes.

## Important Notes

⚠️ **These files are NOT deployed to target systems**

- Hardware configurations are system-specific and auto-generated on each machine
- Deploying wrong hardware config can brick the system
- Each system maintains its own `/etc/nixos/hardware-configuration.nix`

## Purpose

These files serve as:
- **Documentation** - Show expected hardware configuration structure
- **Reference** - Examples for different system types
- **Templates** - Starting point for manual configuration if needed

## Available Configurations

### vm-testing.nix
- **Type**: QEMU/KVM Virtual Machine
- **Boot**: UEFI with GRUB
- **Storage**: Single disk with Btrfs subvolumes
- **Features**: Optimized compression settings per subvolume type

## How Hardware Configs Work

1. **Fresh Installation**: 
   - `install-nixos.sh` automatically generates hardware config with `nixos-generate-config`
   - File is created at `/etc/nixos/hardware-configuration.nix`

2. **Deployment**:
   - `deploy.sh` excludes hardware configs to prevent overwriting
   - Each system keeps its own generated configuration

3. **Adding New Systems**:
   - Run installation script on new hardware
   - Hardware config is automatically detected and generated
   - Deploy your modular configuration safely

## Usage

### For New Installations
```bash
# On target system - generates hardware-configuration.nix automatically
sudo ./install-nixos.sh /dev/sda

# Deploy your configuration (excludes hardware config)
./deploy.sh server user@new-system
```

### For Existing Systems
```bash
# Generate new hardware config if needed
sudo nixos-generate-config --force

# Deploy configuration updates
./deploy.sh server user@existing-system
```

## Adding New Hardware Profiles

When setting up new systems, you can:

1. **Save the generated config** for reference:
   ```bash
   # After installation
   scp user@new-system:/etc/nixos/hardware-configuration.nix hardware/new-system.nix
   ```

2. **Document any special requirements** in comments

3. **Update this README** with system details

## Btrfs Subvolume Layout

All hardware configs should follow this standard layout:

- `/` (root) - `compress=zstd:3`
- `/home` - `compress=zstd:1` 
- `/nix` - `compress=zstd:3`
- `/var` - `compress=zstd:1`
- `/var/log` - `compress=zstd:6`
- `/var/cache` - `nodatacow`
- `/var/tmp` - `nodatacow`
- `/var/lib` - `compress=zstd:1`
- `/var/lib/docker` - `compress=zstd:1`
- `/tmp` - `nodatacow`
- `/srv` - `compress=zstd:1`
- `/opt` - `compress=zstd:1`
- `/.snapshots` - `compress=zstd:1`

## Boot Configuration

All systems use UEFI boot with:
- **Boot loader**: GRUB with EFI support
- **EFI mount**: `/boot/efi`
- **Security**: `efiInstallAsRemovable = true`, `canTouchEfiVariables = false`