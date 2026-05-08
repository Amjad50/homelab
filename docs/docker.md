# Docker Compose Management

## Services

The system manages Docker Compose services in `/opt/docker-services/`. Each directory with a `docker-compose.yml` becomes a systemd service named `docker-compose-<directory-name>`.

## Active Services

### Home Machine
- **traefik** - Reverse proxy (internal port 8080)
- **fireflyiii** - Personal finance manager
- **blinko** - Note-taking app with PostgreSQL
- **memos** - Memo service with Telegram bot
- **minio** - S3-compatible object storage
- **n8n** - Workflow automation platform

### Middle Machine
- **traefik** - Reverse proxy with HTTPS (ports 80/443)
- **wg-easy** - WireGuard VPN management
- **kanidm** - Identity management server
- **oauth2-proxy** - Authentication proxy

## Directory Structure

```
/opt/docker-services/
├── traefik/
│   ├── config/
│   │   ├── traefik.yml
│   │   └── dynamic.yml
│   └── docker-compose.yml
├── fireflyiii/
│   └── docker-compose.yml
└── ... (other services)
```

## Management Commands

```bash
# Services
compose-manage list             # List all services with status

# Service control
compose-manage start traefik    # Start service
compose-manage stop traefik     # Stop service
compose-manage restart traefik  # Restart service
compose-manage enable traefik   # Auto-start on boot

# Monitoring
compose-manage status traefik   # Service status
compose-manage logs traefik     # Follow logs
compose-manage ps traefik       # Show containers

# Container operations
compose-manage exec traefik <container> bash  # Execute in container
```

## Service Patterns

### Basic Service
```yaml
networks:
  traefik:
    external: true

services:
  myapp:
    image: myapp:latest
    container_name: myapp
    restart: unless-stopped
    networks:
      - traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.home.amsh.dev`)"
      - "traefik.http.services.myapp.loadbalancer.server.port=3000"
```

### Service with Database
```yaml
networks:
  traefik:
    external: true
  myapp:
    internal: true

services:
  myapp-db:
    image: postgres:17-alpine
    restart: unless-stopped
    networks:
      - myapp
    env_file:
      - path: /var/lib/dock/myapp.env
        required: true
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U myapp"]
      interval: 5s

  myapp:
    depends_on:
      myapp-db:
        condition: service_healthy
    networks:
      - traefik
      - myapp
    env_file:
      - path: /var/lib/dock/myapp.env
        required: true
```

### Environment Integration
Services use environment files from sops templates:
- **Path**: `/var/lib/dock/servicename.env`
- **Owner**: `dock:docker` (mode 0400)
- **Generated**: From sops secrets via NixOS templates

In this repo, most service secrets and templates are declared through `common/modules/service-registry.nix`, then merged into the machine config.

## Adding New Services

1. Create directory: `mkdir /opt/docker-services/myapp`
2. Add `docker-compose.yml` file
3. Add secrets to `machines/MACHINE/configuration.nix`:
    ```nix
    sops.secrets.myapp-secret = { owner = "dock"; group = "docker"; mode = "0400"; };
    sops.templates."myapp.env" = {
      path = "/var/lib/dock/myapp.env";
      content = ''SECRET=${config.sops.placeholder.myapp-secret}'';
    };
    ```
4. Include service in configuration:
    ```nix
    services.compose-services.services = [ "myapp" ... ];
    ```
5. Deploy: `./deploy.sh machine user@server`

## Service Integration

- Services are managed as systemd units
- Automatic restart on failure
- Depends on docker.service
- Logs via journald with rotation
- User runs as `dock:docker`
- Docker group has polkit access to manage services
