# Troubleshooting Guide

## Deployment Issues

### SSH Connection Failed
```bash
# Test connection
ssh -v amjad@server

# Check SSH keys
ssh-copy-id amjad@server
```

### Build Failures
```bash
# Check syntax
nix flake check

# Test build locally
nixos-rebuild dry-build --flake .#myserver

# Clear cache if needed
sudo nix-collect-garbage -d
```

## System Issues

### Boot Problems
- Select previous generation in GRUB
- Boot from NixOS installer and run `nixos-rebuild switch --rollback`

### Service Failures
```bash
# Check service status
systemctl status service-name

# View logs
journalctl -u service-name -n 50

# Restart service
sudo systemctl restart service-name
```

### Disk Space Issues
```bash
# Check usage
df -h

# Clean up
sudo nix-collect-garbage -d
docker system prune -a
sudo journalctl --vacuum-size=100M
```

## Docker Issues

### Service Discovery Problems
```bash
# Check directory structure
ls -la /home/amjad/docker-services/

# Rediscover services
compose-manage discover

# Check permissions
sudo chown -R amjad:docker /home/amjad/docker-services/
```

### Container Issues
```bash
# Check compose file
cd /home/amjad/docker-services/service-name
docker-compose config

# View container logs
compose-manage logs service-name

# Test manually
docker-compose up
```

## Btrfs Issues

### Snapshot Problems
```bash
# Check snapshots
sudo snapper list

# Clean old snapshots
sudo snapper cleanup timeline

# Check disk space
sudo btrfs filesystem usage /
```

## Network Issues

### Firewall Blocking
```bash
# Check firewall
sudo systemctl status firewall

# Test connectivity
nmap -p 22,80,443 server

# Temporarily disable (testing only)
sudo systemctl stop firewall
```

### DNS Issues
```bash
# Test DNS
nslookup google.com

# Check resolv.conf
cat /etc/resolv.conf
```

## Security Issues

### Fail2ban Not Working
```bash
# Check status
sudo fail2ban-client status sshd

# Restart service
sudo systemctl restart fail2ban

# Check logs
sudo journalctl -u fail2ban -n 50
```

### Locked Out
- Use console access if available
- Boot from recovery mode
- Use different SSH key or user

## Log Analysis

```bash
# System logs
sudo journalctl -b

# Service logs
sudo journalctl -u service-name

# Authentication logs
sudo journalctl -u sshd | grep "Failed"

# Docker logs
sudo journalctl -u docker
```