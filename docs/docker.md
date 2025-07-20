# Docker Compose Management

## Services

The system manages Docker Compose services in `/opt/docker-services/`. Each directory with a `docker-compose.yml` becomes a systemd service named `docker-compose-<directory-name>`.

## Directory Structure

```
/opt/docker-services/
├── nginx/
│   └── docker-compose.yml
├── database/
│   └── docker-compose.yml
└── app/
    └── docker-compose.yml
```

## Management Commands

```bash
# Services
compose-manage list             # List all services with status

# Service control
compose-manage start nginx      # Start service
compose-manage stop nginx       # Stop service
compose-manage restart nginx    # Restart service
compose-manage enable nginx     # Auto-start on boot

# Monitoring
compose-manage status nginx     # Service status
compose-manage logs nginx       # Follow logs
compose-manage ps nginx         # Show containers

# Container operations
compose-manage exec nginx web bash  # Execute in container
```

## Adding New Services

1. Create directory: `mkdir /opt/docker-services/myapp`
2. Add `docker-compose.yml` file
3. Modify `configuration.nix` to include the new service
    ```nix
    services.compose-services.services = [
      "myapp"
      ...
    ]
    ```
4. Rebuild the system configuration: `sudo nixos-rebuild switch`
5. Run `compose-manage start myapp`

## Service Integration

- Services are managed as systemd units
- Automatic restart on failure
- Depends on docker.service
- Logs via journald with rotation
- User runs as `dock:docker`
- Docker group has polkit access to manage services