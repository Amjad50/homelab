# Deployment

## Overview

`./deploy.sh` provides compressed remote deployment with change detection and automatic service restarts.

## Usage

```bash
./deploy.sh home amjad@server        # Remote deployment
./deploy.sh middle                   # Local deployment
./deploy.sh home amjad@server --no-docker
./deploy.sh home amjad@server --only-docker
./deploy.sh home amjad@server --update
```

## Process

1. **Archive creation** - XZ-compressed tar with exclusions
2. **File transfer** - SCP archive + remote deployment script  
3. **Change detection** - SHA256 checksums for docker-services
4. **Configuration deployment** - NixOS rebuild
5. **Service restarts** - Only changed docker services restart

On remote hosts, the helper script runs `nixos-rebuild switch --fast` after copying `/etc/nixos/{flake.nix,common,machines}` into place.

## Features

- **Compression** - XZ compression for minimal transfer
- **Change detection** - Content + filename checksums
- **Atomic operations** - Temporary directories with cleanup
- **Colored logging** - Step visibility with log levels
- **Service preservation** - Only restart changed services

## Output

- `[INFO]` - General information
- `[STEP]` - Major deployment phases
- `[DOCKER]` - Docker service operations
- `[SUCCESS]` - Completion status
- `[WARN]` - Non-fatal issues
