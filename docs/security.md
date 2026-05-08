# Security Configuration

## SSH Security

- Key-only authentication (no passwords)
- No root login via SSH
- No X11 forwarding
- SSH keys managed in `users.nix`

## Fail2ban Protection

Progressive banning for SSH attacks:
- 3 failed attempts = 1 hour ban
- Repeat offenses: 2h, 4h, 8h, 16h, 32h, 64h
- Maximum ban: 1 week
- Whitelists localhost and can be configured for local networks

## Firewall

- Only SSH port (22) open by default
- Additional ports can be added in `services.nix`
- Managed via NixOS firewall module

## User Security

- Main user (`amjad`) in wheel group with sudo access
- Passwordless sudo configured
- Docker group membership for container management
- Local pre-commit hook blocks staged `secrets.yaml` files from being committed

## Container Security

- Docker runs with security options enabled
- `no-new-privileges` prevents privilege escalation
- Journald logging for centralized log management
- Auto-pruning prevents disk space issues

## Monitoring

Check security status:
```bash
# SSH attempts
sudo journalctl -u sshd | grep "Failed"

# Fail2ban status
sudo fail2ban-client status sshd

# Firewall status
sudo systemctl status firewall

# System logs
sudo journalctl -k | grep -i security
```
