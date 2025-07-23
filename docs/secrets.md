# Secrets Management

## Overview

Uses sops-nix with SSH host key encryption for secure secrets management. Secrets are encrypted in git, automatically decrypted on target machines using existing SSH infrastructure.

## Current Secrets

### Rathole Secrets (Tunnel)
- **rathole-token**: Authentication token (shared between server/client)
- **rathole-noise-private**: Noise transport private key (middle server only)
- **rathole-noise-public**: Noise transport public key (both machines)

### Application Secrets (Home Machine)
- **firefly-app-key**: Firefly III application encryption key
- **firefly-db-password**: Firefly III database password
- **blinko-nextauth-secret**: Blinko NextAuth session secret
- **blinko-db-password**: Blinko PostgreSQL password
- **memos-telegram-bot-token**: Memos Telegram bot API token
- **minio-root-password**: MinIO admin password
- **n8n-db-password**: n8n PostgreSQL password
- **n8n-encryption-key**: n8n workflow encryption key

### Authentication Secrets (Middle Machine)
- **oauth2-proxy-client-secret**: OAuth2 proxy client secret
- **oauth2-proxy-cookie-secret**: OAuth2 proxy cookie signing secret

### Secret Distribution
- **Middle server**: Rathole server keys + OAuth2 secrets
- **Home server**: Rathole client keys + application secrets

## Setup

### 1. Automated Script

```bash
# Create .env file with required variables
cat > .env << EOF
MIDDLE_AGE_KEY=age1abc123...  # Get from: ssh user@middle "cat /etc/ssh/ssh_host_ed25519_key.pub" | ssh-to-age
HOME_AGE_KEY=age1def456...    # Get from: ssh user@home "cat /etc/ssh/ssh_host_ed25519_key.pub" | ssh-to-age
RATHOLE_NOISE_PRIVATE=your-private-key
RATHOLE_NOISE_PUBLIC=your-public-key
EOF

# Generate and encrypt secrets
./scripts/generate-rathole-secrets.sh
```

### 2. Deploy and Verify

```bash
# Deploy configurations
./deploy.sh middle user@middle-server
./deploy.sh home user@home-server

# Check rathole services
systemctl status rathole-server  # middle
systemctl status rathole-client  # home

# Test connectivity
curl https://app.home.alsharafi.dev
```

## Configuration Patterns

### Environment File Template (Most Common)
```nix
sops = {
  defaultSopsFile = ./secrets.yaml;
  age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  secrets = {
    myapp-db-password = { owner = "dock"; group = "docker"; mode = "0400"; };
    myapp-api-key = { owner = "dock"; group = "docker"; mode = "0400"; };
  };
};

# Environment file template for Docker services
sops.templates."myapp.env" = {
  owner = "dock";
  group = "docker";
  mode = "0400";
  path = "/var/lib/dock/myapp.env";
  content = ''
    DB_PASSWORD=${config.sops.placeholder.myapp-db-password}
    API_KEY=${config.sops.placeholder.myapp-api-key}
  '';
};
```

### Configuration File Template (Advanced)
```nix
# For services requiring TOML/YAML config files
sops.templates."rathole-server.toml" = {
  owner = "rathole";
  group = "rathole"; 
  mode = "0400";
  path = "/var/lib/rathole/rathole-server.toml";
  restartUnits = [ "rathole-server.service" ];
  content = ''
    [server]
    default_token = "${config.sops.placeholder.rathole-token}"
    [server.transport.noise]
    local_private_key = "${config.sops.placeholder.rathole-noise-private}"
  '';
};
```

### Service User Ownership
- **dock:docker** - Docker service environment files
- **www-data:www-data** - Web service configs (Firefly III)
- **rathole:rathole** - Tunnel service configs
- **nobody:nobody** - System service secrets

## Adding New Secrets

### 1. Add to secrets.yaml

```bash
sops machines/middle/secrets.yaml
# Add: new-secret: "value"
```

### 2. Add to NixOS config

```nix
sops = {
  age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  secrets = {
    rathole-token = { /* existing */ };
    ...
    new-secret = {
      owner = "service-user";
      group = "service-group";
      mode = "0400";
    };
  };
};
```

### 3. Use in Docker services

```nix
# Most common: Environment file
sops.templates."myservice.env" = {
  owner = "dock";
  group = "docker";
  path = "/var/lib/dock/myservice.env";
  content = ''SECRET=${config.sops.placeholder.new-secret}'';
};
```

```yaml
# docker-compose.yml
services:
  myservice:
    env_file:
      - path: /var/lib/dock/myservice.env
        required: true
```

## Daily Operations

### View Secrets
```bash
# View decrypted secrets (requires age key locally)
sops --decrypt machines/middle/secrets.yaml
sops --decrypt machines/home/secrets.yaml

# View encrypted files
cat machines/middle/secrets.yaml
cat machines/home/secrets.yaml
```

### Edit Secrets
```bash
# Edit existing secrets manually
sops machines/middle/secrets.yaml  # Edit token + private key
sops machines/home/secrets.yaml    # Edit token + public key

# Or regenerate with script (updates .env file)
./scripts/generate-rathole-secrets.sh
```

### Rotate Secrets
```bash
# Update .env and regenerate
vim .env  # Update RATHOLE_NOISE_PRIVATE and RATHOLE_NOISE_PUBLIC
./scripts/generate-rathole-secrets.sh

# Deploy updates to both machines
./deploy.sh middle user@middle-server
./deploy.sh home user@home-server
```
