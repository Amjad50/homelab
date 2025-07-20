# Deployment

## Overview

`./deploy.sh` provides compressed remote deployment with change detection and automatic service restarts.

## Usage

```bash
./deploy.sh myserver amjad@server    # Remote deployment
./deploy.sh myserver                 # Local deployment
```

## Process

1. **Archive creation** - XZ-compressed tar with exclusions
2. **File transfer** - SCP archive + remote deployment script  
3. **Change detection** - SHA256 checksums for docker-services
4. **Configuration deployment** - NixOS rebuild
5. **Service restarts** - Only changed docker services restart

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