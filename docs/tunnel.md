# Rathole Tunnel Architecture

## Overview

Secure proxy tunnel using rathole to expose home services through a public middle server.

## Architecture

```
Internet → Middle Server (Public IP) → Rathole Tunnel → Home Server (Private/NAT)
```

### Traffic Flow

1. **User** requests `app.home.alsharafi.dev`
2. **DNS** resolves to middle server public IP
3. **Traefik** (middle) receives HTTPS request on port 443
4. **Traefik** routes to rathole server on localhost:8080
5. **Rathole server** forwards through encrypted tunnel
6. **Rathole client** (home) receives and forwards to localhost:3000
7. **Docker service** (home) processes request and responds back

## Components

### Middle Server (Public)
- **Traefik**: HTTPS termination, reverse proxy
- **Rathole server**: Tunnel endpoint (port 2333)
- **Services**: VPN management, proxy routing

### Home Server (Private)
- **Rathole client**: Connects to middle server
- **Docker services**: Web apps, APIs
- **Local ports**: 3000 (webapp), 3001 (api)

### Tunnel Details
- **Protocol**: TCP with noise encryption
- **Authentication**: Shared token + noise keys
- **Ports**: 2333 (tunnel), 8080/8081 (proxy endpoints)

## Tunnel Service Mapping

| Domain | Middle Port | Home Port | Service |
|--------|-------------|-----------|---------|
| `app.home.alsharafi.dev` | 8080 | 3000 | Web App |
| `api.home.alsharafi.dev` | 8081 | 3001 | API |
