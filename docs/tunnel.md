# Rathole Tunnel Architecture

## Overview

Secure proxy tunnel using rathole to expose home services through a public middle server.

## Architecture

```
Internet → Middle Server (Public IP) → Rathole Tunnel → Home Server (Private/NAT)
```

### Traffic Flow

1. **User** requests `*.home.alsharafi.dev`
2. **DNS** resolves to middle server public IP
3. **Traefik** (middle) receives HTTPS request on port 443
4. **Traefik** routes to rathole server on localhost:8080
5. **Rathole server** forwards through encrypted tunnel
6. **Rathole client** (home) receives and forwards to localhost:8080
7. **Traefik** (home) receives request and routes to appropriate service
8. **Docker service** (home) processes request and responds back

## Components

### Middle Server (Public)
- **Traefik**: HTTPS termination, reverse proxy
- **Rathole server**: Tunnel endpoint (port 2333)
- **Services**: VPN management, proxy routing

### Home Server (Private)
- **Rathole client**: Connects to middle server
- **Traefik**: Internal routing (no TLS)
- **Docker services**: Web apps, APIs
- **Local ports**: 8080 (traefik tunnel)

### Tunnel Details
- **Protocol**: TCP with noise encryption
- **Authentication**: Shared token + noise keys
- **Ports**: 2333 (tunnel), 8080 (proxy endpoint)

## Configuration

### Adding Services to Tunnel

To route a new service through the tunnel:

1. **Middle Server** [machines/middle/docker-services/traefik/config/dynamic.yml](../machines/middle/docker-services/traefik/config/dynamic.yml)

2. **Home Server**: Configure service normally with Traefik labels:
```yaml
# In docker-compose.yml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`myapp.home.alsharafi.dev`)"
  - "traefik.http.services.myapp.loadbalancer.server.port=3000"
```

