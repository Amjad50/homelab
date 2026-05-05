# Homelab Backup System

This document covers the backup system using NixOS-native restic configuration with Backblaze B2 storage.

## Overview

The homelab uses NixOS's built-in `services.restic.backups` with:
- **Storage**: Backblaze B2 (via S3 compatibility)
- **Schedule**: Daily backups at 02:00 AM
- **Strategy**: Database dumps + file-based data
- **Encryption**: Client-side encryption via restic
- **Compression**: Automatic compression and deduplication

## Architecture

### Data Types
1. **Database dumps**: PostgreSQL databases exported to SQL files  
2. **SQLite backups**: SQLite databases with proper backup commands
3. **Application data**: File-based storage (configs, uploads, user data)
4. **Media files**: Books and configuration files (movies/TV excluded)
5. **Service configurations**: Direct filesystem paths for simple configs

### Backup Flow
```
Daily (scheduled per server):
1. backup-prepare → Create database dumps and service-specific backups
2. restic backup → Upload dumps + application data + direct paths to B2
3. backup-cleanup → Remove temporary dump files
4. restic prune → Clean up old backup data (retention policy)
```

### Server Types
- **Home server**: PostgreSQL databases + application data (02:00 AM)
- **Middle server**: WireGuard + Kanidm + AdGuard configs (03:00 AM)

## Configuration

### Repository
```nix
repository = "s3:s3.<region>.backblazeb2.com/<bucket-name>/backups/<machine>-daily";
```

### Paths Backed Up
The backup includes:
- **Database dumps**: Temporary directory for PostgreSQL exports
- **Application data**: Service-specific data directories
- **Configuration files**: Application and system configurations  
- **User uploads**: Files uploaded through web interfaces
- **Media libraries**: Books, documents, and media files
- **Sync data**: Files synchronized between devices

Example configuration:
```nix
paths = [
  "/tmp/db-dumps-daily"        # Database dumps
  "/mnt/storage/*/data"        # Application data directories
  "/mnt/storage/*/config"      # Configuration directories
  "/mnt/storage/media/books"   # Media libraries
  # ... other service directories
];
```

### Database Handling
**PostgreSQL containers** are automatically discovered and dumped based on their environment variables. The backup script looks for containers with database credentials and exports them using `pg_dump`.

**SQLite databases** are copied from containers to the host, then backed up using the `sqlite3 .backup` command for proper database consistency.

**Hybrid approach**: Some services use direct filesystem backup, others require specialized scripts depending on their data complexity.

### Retention Policy
- **Daily**: 30 days
- **Weekly**: 8 weeks  
- **Monthly**: 12 months

## Backup Scripts

### Home Server Scripts

**backup-prepare.sh** - Generic PostgreSQL database dump script:
- Inspects container environments for DB credentials
- Exports PostgreSQL databases using `pg_dump`
- Creates backup manifest with metadata
- Fails fast on any errors

**Usage:**
```bash
backup-prepare <dump-directory> <container1> <container2> ...
```

**backup-cleanup.sh** - Cleanup script for temporary dump directories:
```bash
backup-cleanup <dump-directory>
```

### Middle Server Scripts

**backup-prepare-middle.sh** - Specialized backup for middle server services:
- **WireGuard Easy**: Copies SQLite DB and config from container, creates SQLite backup on host
- **Kanidm**: Extracts existing backups from container
- **AdGuard**: Backed up via direct filesystem paths (not handled by script)

**Usage:**
```bash
backup-prepare-middle <dump-directory>
```

**backup-cleanup-middle.sh** - Cleanup for middle server temporary files:
```bash
backup-cleanup-middle <dump-directory>
```

## Manual Operations

### Trigger Backup
```bash
# Run backup service manually
sudo systemctl start restic-backups-<backup-name>

# Check backup status
sudo systemctl status restic-backups-<backup-name>

# Follow backup logs
sudo journalctl -u restic-backups-<backup-name> -f
```

### Using Wrapper Script
NixOS generates wrapper scripts for each backup configuration:
```bash
# List backups
restic-<backup-name> snapshots

# Get repository statistics  
restic-<backup-name> stats

# Check repository integrity
restic-<backup-name> check
```

### Browse Backup Contents
```bash
# Mount backup for browsing
sudo mkdir -p /mnt/backup-browse
sudo restic-<backup-name> mount /mnt/backup-browse &

# Use ncdu to analyze disk usage
ncdu /mnt/backup-browse

# Unmount when done
sudo umount /mnt/backup-browse
```

### Restore Operations
```bash
# List snapshots to find restore target
restic-<backup-name> snapshots

# Restore specific snapshot
restic-<backup-name> restore SNAPSHOT_ID --target /tmp/restore

# Restore specific files only
restic-<backup-name> restore latest --target /tmp/restore --include "/path/to/files/*"
```

## Secrets Management

### Required Secrets
The backup system uses these sops-managed secrets:
- `restic-repository-password` - Repository encryption key
- `backup-aws-access-key-id` - B2 S3-compatible access key ID
- `backup-aws-secret-access-key` - B2 S3-compatible secret key

### Environment Template
```nix
sops.templates."restic-s3.env" = {
  content = ''
    AWS_ACCESS_KEY_ID=${config.sops.placeholder.backup-aws-access-key-id}
    AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.backup-aws-secret-access-key}
  '';
};
```

## Backblaze B2 Setup

### S3 Compatibility Requirements
- Use **S3-compatible credentials**, not native B2 API keys
- Get S3 endpoint URL for your region (e.g., `s3.eu-central-003.backblazeb2.com`)
- Create bucket with **no server-side encryption** (restic handles encryption)

### Application Key Permissions
Required permissions for B2 application key:
- ✅ **Read Files**
- ✅ **Write Files**  
- ✅ **Delete Files** (needed for pruning)
- ✅ **List Files**

## Monitoring

### Service Health
```bash
# Check timer status
systemctl status restic-backups-<backup-name>.timer

# See next scheduled run
systemctl list-timers restic-backups-<backup-name>.timer

# Check recent backup logs
journalctl -u restic-backups-<backup-name> --since "24 hours ago"
```

### Repository Health
```bash
# Check repository integrity (5% sample)
restic-<backup-name> check --read-data-subset=5%

# Full integrity check (slower)
restic-<backup-name> check --read-data

# Unlock repository if stuck
restic-<backup-name> unlock
```

### Storage Usage
```bash
# Repository statistics
restic-<backup-name> stats --mode repo

# Latest snapshot size
restic-<backup-name> stats latest

# Files by size in latest snapshot  
restic-<backup-name> ls latest --long | sort -k5 -nr | head -20
```

## Troubleshooting

### Common Issues

**Backup fails with "command not found":**
- Scripts run in restricted systemd environment
- Solution: PATH is configured with required binaries in NixOS config
- Required packages: `docker`, `sqlite`, `coreutils`, `hostname`, `grep`, `sed`, `gawk`

**S3 authentication errors:**
- Verify you're using S3-compatible credentials, not native B2 keys
- Check bucket region matches endpoint URL
- Ensure application key has required permissions

**Large backup sizes:**
- Use `ncdu /mnt/backup-browse` to identify large files
- Consider excluding cache directories or temporary files
- Example: Application archives or cache directories can be excluded
- Use `restic rewrite --exclude` to remove files from existing snapshots

**SQLite database issues:**
- Ensure `sqlite3` is available in PATH during backup
- SQLite backup creates consistent point-in-time snapshots
- Fallback: Raw database file is still copied if `sqlite3` unavailable

**Container access issues:**
- Ensure Docker containers are running during backup
- Scripts fail fast if containers are not accessible
- Check container names match configuration

**Repository locked errors:**
```bash
# Unlock stuck repository
restic-<backup-name> unlock
```

### Maintenance Commands

**Cleanup old data:**
```bash
# Aggressive prune to remove all unused data
restic-<backup-name> prune --max-unused 0

# Rewrite snapshots to remove files
restic-<backup-name> rewrite --exclude "pattern"
```

**Fresh start (if needed):**
```bash
# Initialize new repository (destructive!)
restic-<backup-name> init
```

## Security Notes

- **Encryption**: All data encrypted client-side before upload
- **Zero-knowledge**: Backblaze cannot decrypt your data
- **Key management**: Repository password managed via sops-nix
- **Access control**: B2 credentials scoped to specific bucket only

## Server-Specific Examples

### Home Server Configuration
```nix
services.restic.backups.homelab-daily = {
  repository = "s3:s3.eu-central-003.backblazeb2.com/bucket/backups/home-daily";
  paths = [
    "/tmp/db-dumps-daily"        # PostgreSQL dumps
    "/mnt/storage/*/data"        # Application data
    "/mnt/storage/media/books"   # Media files
  ];
  timerConfig.OnCalendar = "02:00";
  extraBackupArgs = ["--tag" "home-server"];
};
```

### Middle Server Configuration  
```nix
services.restic.backups.middle-daily = {
  repository = "s3:s3.eu-central-003.backblazeb2.com/bucket/backups/middle-daily";  
  paths = [
    "/tmp/middle-backups-daily"  # Service-specific backups
    "/storage/adguard/conf"      # Direct filesystem backup
  ];
  timerConfig.OnCalendar = "03:00";
  extraBackupArgs = ["--tag" "middle-server"];
};
```

## Future Improvements

- **Cross-region replication**: Consider multiple B2 regions
- **Backup verification**: Automated restore testing
- **Alerting**: Notification system for backup failures  
- **Additional servers**: Template system for new machines
- **Monitoring dashboard**: Grafana integration for backup metrics
- **Backup rotation**: Automated old backup cleanup policies

## Migration Notes

This configuration replaces any manual backup scripts with NixOS-native `services.restic.backups`. Benefits:
- **Declarative**: Everything in configuration.nix
- **Automatic service generation**: No manual systemd units
- **Built-in error handling**: Robust service management
- **Wrapper scripts**: Easy manual operations
- **Integration**: Works seamlessly with NixOS ecosystem
