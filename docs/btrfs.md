# Btrfs Storage and Snapshots

This guide covers the configured Btrfs filesystem with automatic snapshots and scrubbing.

## Table of Contents

- [Subvolume Layout](#subvolume-layout)
- [Mount Options](#mount-options)
- [Snapper Snapshots](#snapper-snapshots)
- [Automatic Maintenance](#automatic-maintenance)
- [Basic Usage](#basic-usage)

The system uses Btrfs with optimized subvolumes, automatic snapshots via Snapper, and monthly scrubbing for data integrity.

## Subvolume Layout

```
/dev/vda2 (btrfs root)
├── root/          → mounted at /
├── home/          → mounted at /home
├── nix/           → mounted at /nix
├── var/           → mounted at /var
├── var-log/       → mounted at /var/log
├── var-cache/     → mounted at /var/cache
├── var-tmp/       → mounted at /var/tmp
├── var-lib/       → mounted at /var/lib
├── var-lib-docker/ → mounted at /var/lib/docker
├── srv/           → mounted at /srv
├── opt/           → mounted at /opt
├── tmp/           → mounted at /tmp
└── snapshots/     → mounted at /.snapshots
```

### Subvolume Purposes

| Subvolume | Purpose | Optimization |
|-----------|---------|--------------|
| `root` | System files | High compression |
| `home` | User data | Light compression |
| `nix` | Nix store | High compression |
| `var` | System state | Light compression |
| `var-log` | Log files | Maximum compression |
| `var-cache` | Cache data | No compression, nodatacow |
| `var-tmp` | Temp files | No compression, nodatacow |
| `var-lib` | App data | Light compression |
| `var-lib-docker` | Docker data | Light compression |
| `srv` | Service data | Light compression |
| `opt` | Optional software | Light compression |
| `tmp` | System temp | No compression, nodatacow |
| `snapshots` | Snapper snapshots | Light compression |

## Mount Options

### Compression Strategy

**High Compression** (`zstd:3`):
- Root filesystem (`/`)
- Nix store (`/nix`)
- **Rationale**: System files don't change often, benefit from compression

**Light Compression** (`zstd:1`):
- Home directory (`/home`)
- Variable data (`/var`)
- Service data (`/srv`, `/opt`)
- **Rationale**: Good compression/speed balance for user data

**Maximum Compression** (`zstd:6`):
- Log files (`/var/log`)
- **Rationale**: Logs compress extremely well, accessed infrequently

**No Compression + nodatacow**:
- Temporary files (`/tmp`, `/var/tmp`)
- Cache data (`/var/cache`)
- **Rationale**: Frequently changing data, performance over space

### Common Options

All subvolumes use:
- `noatime`: Don't update access times (performance)
- `space_cache=v2`: Improved free space caching
- `compress=zstd:N`: Compression level as appropriate

### Example Mount Configuration

```nix
fileSystems."/" = {
  device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
  fsType = "btrfs";
  options = [
    "subvol=root"
    "compress=zstd:3"
    "noatime"
    "space_cache=v2"
  ];
};

fileSystems."/var/cache" = {
  device = "/dev/disk/by-uuid/6d4c7429-66ff-488f-a1d4-128d13a32aae";
  fsType = "btrfs";
  options = [
    "subvol=var-cache"
    "nodatacow"
    "noatime"
    "space_cache=v2"
  ];
};
```

## Snapper Snapshots

Automatic snapshots are configured for key subvolumes:

- **Root** (`/`): 10 hourly/daily/weekly/monthly/yearly snapshots
- **Home** (`/home`): 24 hourly, 7 daily, 4 weekly, 6 monthly, 2 yearly
- **Logs** (`/var/log`): 6 hourly, 7 daily, 4 weekly, 2 monthly, 1 yearly  
- **App data** (`/var/lib`): 3 daily, 2 weekly, 1 monthly

## Automatic Maintenance

**Monthly Scrubbing**: Automatic data integrity checks
```nix
services.btrfs.autoScrub = {
  enable = true;
  interval = "monthly";
  fileSystems = [ "/" ];
};
```

**Automatic Cleanup**: Old snapshots are automatically removed based on retention policies.

## Basic Usage

### Viewing Snapshots
```bash
# List snapshots
sudo snapper list

# Browse snapshot content
ls /.snapshots/42/snapshot/
```

### Manual Snapshots
```bash
# Create snapshot before major changes
sudo snapper create --description "Before system update"
```

### Restoring Files
```bash
# Copy file from snapshot
sudo cp /.snapshots/42/snapshot/etc/some-config /etc/some-config
```
