# Middle Server Configuration

## Services

- **Traefik**: Reverse proxy with HTTPS termination
- **WG-Easy**: WireGuard VPN management interface

## Domains

- `traefik.home.alsharafi.dev` - Traefik dashboard (VPN-only)
- `wg.home.alsharafi.dev` - WireGuard management UI (public)

## Ports

- `80/443` - HTTP/HTTPS (Traefik)
- `51820/udp` - WireGuard VPN

## Access

- **Traefik dashboard**: VPN required
- **WireGuard UI**: Public access
- **VPN subnet**: `10.8.0.0/24`

## Quick Commands

```bash
# Deploy to middle server
./deploy.sh middle user@server

# Check container health
docker ps
```