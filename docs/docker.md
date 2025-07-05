# Docker Compose Management

## Auto-Discovery System

The system automatically discovers Docker Compose services in `/home/amjad/docker-services/`. Each directory with a `docker-compose.yml` becomes a systemd service named `docker-compose-<directory-name>`.

## Directory Structure

```
/home/amjad/docker-services/
├── nginx/
│   └── docker-compose.yml
├── database/
│   └── docker-compose.yml
└── app/
    └── docker-compose.yml
```

## Management Commands

```bash
# Discovery
compose-manage discover          # Scan for new services
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

1. Create directory: `mkdir /home/amjad/docker-services/myapp`
2. Add `docker-compose.yml` file
3. Run `compose-manage discover`
4. Start: `compose-manage start myapp`

## Service Integration

- Services are managed as systemd units
- Automatic restart on failure
- Depends on docker.service
- Logs via journald with rotation
- User runs as `amjad:docker`