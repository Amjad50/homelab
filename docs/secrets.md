# Secrets Management

## Overview

Uses sops-nix with SSH host key encryption for secure secrets management. Secrets are encrypted in git, automatically decrypted on target machines using existing SSH infrastructure.

## Current Secrets

### Rathole Secrets
- **rathole-token**: Authentication token (shared between server/client)
- **rathole-noise-private**: Noise transport private key (middle server only)
- **rathole-noise-public**: Noise transport public key (both machines)

### Secret Distribution
- **Middle server**: Gets token + noise private key
- **Home server**: Gets token + noise public key only (security best practice)

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

## Configuration Pattern

### Middle Server (Server + Private Key)
```nix
sops = {
  defaultSopsFile = ./secrets.yaml;
  age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  secrets = {
    rathole-token = { owner = "rathole"; group = "rathole"; mode = "0400"; };
    rathole-noise-private = { owner = "rathole"; group = "rathole"; mode = "0400"; };
  };
};

# Server configuration template
sops.templates."rathole-server.toml" = {
  content = ''
    [server]
    default_token = "${config.sops.placeholder.rathole-token}"
    [server.transport.noise]
    local_private_key = "${config.sops.placeholder.rathole-noise-private}"
  '';
};
```

### Home Server (Client + Public Key Only)
```nix
sops = {
  defaultSopsFile = ./secrets.yaml;
  age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  secrets = {
    rathole-token = { owner = "rathole"; group = "rathole"; mode = "0400"; };
    rathole-noise-public = { owner = "rathole"; group = "rathole"; mode = "0400"; };
  };
};

# Client configuration template
sops.templates."rathole-client.toml" = {
  content = ''
    [client]
    default_token = "${config.sops.placeholder.rathole-token}"
    [client.transport.noise]
    remote_public_key = "${config.sops.placeholder.rathole-noise-public}"
  '';
};
```

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

### 3. Use in services

```nix
systemd.services.myservice = {
  serviceConfig = {
    EnvironmentFile = config.sops.secrets.new-secret.path;
  };
};
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
