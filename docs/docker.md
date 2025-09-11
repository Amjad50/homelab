# Docker Compose Management

## Services

The system manages Docker Compose services in `/opt/docker-services/`. Each directory with a `docker-compose.yml` becomes a systemd service named `docker-compose-<directory-name>`.

## Active Services

### Home Machine
- **webapp** - Static website (nginx)
- **traefik** - Reverse proxy (internal port 8080)
- **fireflyiii** - Personal finance manager
- **blinko** - Note-taking app with PostgreSQL
- **memos** - Memo service with Telegram bot
- **minio** - S3-compatible object storage
- **n8n** - Workflow automation platform

### Middle Machine
- **traefik** - Reverse proxy with HTTPS (ports 80/443)
- **wg-easy** - WireGuard VPN management
- **ys-sitecore** - Django web application
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