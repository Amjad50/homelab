# Middle Server Configuration

## Services

- **Traefik**: Reverse proxy with HTTPS termination
- **NetBird**: Mesh VPN management and routing

## Domains

- `traefik.home.amsh.dev` - Traefik dashboard (VPN-only)
- `netbird.home.amsh.dev` - NetBird dashboard

## Ports

- `80/443` - HTTP/HTTPS (Traefik)
- `51821/udp` - NetBird client
- `3480/udp` - NetBird STUN

## Access

- **Traefik dashboard**: VPN required
- **Mesh access**: NetBird

## Quick Commands

```bash
# Deploy to middle server
./deploy.sh middle user@server

# Check container health
docker ps
```
