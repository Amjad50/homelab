#!/usr/bin/env bash

# NixOS Installation Script with Btrfs and SSH
# Usage: ./install-nixos.sh /dev/sda [/dev/sdb]

set -e

# Configuration
DISK="${1:-/dev/nvme0n1}"
STORAGE_DISK="${2:-}"
HOSTNAME="home"
USERNAME="amjad"
TIMEZONE="Asia/Kuala_Lumpur"

# SSH public key (replace with your actual key)
SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGRGvFgz+AH8SllcU1ZRbVw5cyfzCOo5gRuxu+DLMLHn"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
fi

# Check if disks exist
if [[ ! -b "$DISK" ]]; then
    error "Main disk $DISK does not exist"
fi

# Check if storage disk exists (optional)
if [[ -n "$STORAGE_DISK" && ! -b "$STORAGE_DISK" ]]; then
    error "Storage disk $STORAGE_DISK does not exist"
fi

# Confirmation
if [[ -n "$STORAGE_DISK" ]]; then
    warn "This will DESTROY ALL DATA on $DISK and $STORAGE_DISK"
    echo "Main disk: $DISK"
    echo "Storage disk: $STORAGE_DISK"
else
    warn "This will DESTROY ALL DATA on $DISK"
    echo "Main disk: $DISK"
    echo "Storage disk: none (will use main disk)"
fi
echo "Hostname: $HOSTNAME"
echo "Username: $USERNAME"
echo "Timezone: $TIMEZONE"
echo ""
read -p "Are you sure? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    error "Installation cancelled"
fi

if [[ -n "$STORAGE_DISK" ]]; then
    log "Starting NixOS installation on $DISK with storage on $STORAGE_DISK"
else
    log "Starting NixOS installation on $DISK (single disk setup)"
fi

# 1. Partition the disk
log "Creating partitions..."
parted --script "$DISK" -- \
    mklabel gpt \
    mkpart primary 1MiB 3MiB \
    set 1 bios_grub on \
    mkpart primary fat32 3MiB 103MiB \
    set 2 boot on \
    mkpart primary 103MiB 1103MiB \
    mkpart primary 1103MiB 100%

# Wait for partitions to be created
sleep 2

# Set partition variables
if [[ "$DISK" == *"nvme"* ]]; then
    BIOS_PART="${DISK}p1"
    EFI_PART="${DISK}p2"
    BOOT_PART="${DISK}p3"
    ROOT_PART="${DISK}p4"
else
    BIOS_PART="${DISK}1"
    EFI_PART="${DISK}2"
    BOOT_PART="${DISK}3"
    ROOT_PART="${DISK}4"
fi

log "BIOS boot partition: $BIOS_PART"
log "EFI partition: $EFI_PART"
log "Boot partition: $BOOT_PART"
log "Root partition: $ROOT_PART"

# 2. Format partitions
log "Formatting EFI partition..."
mkfs.fat -F 32 -n efi "$EFI_PART"

log "Formatting boot partition..."
mkfs.ext4 -L boot "$BOOT_PART"

log "Formatting root partition with Btrfs..."
mkfs.btrfs -f -L nixos "$ROOT_PART"

# 3. Create Btrfs subvolumes
log "Creating Btrfs subvolumes..."
mount "$ROOT_PART" /mnt

# Create subvolumes
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@/.snapshots
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@home/.snapshots
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@var-log
btrfs subvolume create /mnt/@var-log/.snapshots
btrfs subvolume create /mnt/@var-cache
btrfs subvolume create /mnt/@var-tmp
btrfs subvolume create /mnt/@var-lib
btrfs subvolume create /mnt/@var-lib/.snapshots
btrfs subvolume create /mnt/@var-lib-docker
btrfs subvolume create /mnt/@srv
btrfs subvolume create /mnt/@opt
btrfs subvolume create /mnt/@tmp

umount /mnt

# Format storage disk with Btrfs (if provided)
if [[ -n "$STORAGE_DISK" ]]; then
    log "Formatting storage disk $STORAGE_DISK with Btrfs..."
    mkfs.btrfs -f -L storage "$STORAGE_DISK"

    # Create storage subvolume
    log "Creating storage subvolume..."
    mount "$STORAGE_DISK" /mnt
    btrfs subvolume create /mnt/@
    umount /mnt
fi

# 4. Mount subvolumes
log "Mounting subvolumes..."
mount -o subvol=@,compress=zstd:3,noatime,space_cache=v2 "$ROOT_PART" /mnt

mkdir -p /mnt/{boot,boot,home,nix,var,tmp,srv,opt}
mount "$BOOT_PART" /mnt/boot
mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi
mount -o subvol=@home,compress=zstd:1,noatime,space_cache=v2 "$ROOT_PART" /mnt/home
mount -o subvol=@nix,compress=zstd:3,noatime,space_cache=v2 "$ROOT_PART" /mnt/nix
mount -o subvol=@var,compress=zstd:1,noatime,space_cache=v2 "$ROOT_PART" /mnt/var
mount -o subvol=@tmp,nodatacow,noatime,space_cache=v2 "$ROOT_PART" /mnt/tmp
mount -o subvol=@srv,compress=zstd:1,noatime,space_cache=v2 "$ROOT_PART" /mnt/srv
mount -o subvol=@opt,compress=zstd:1,noatime,space_cache=v2 "$ROOT_PART" /mnt/opt

mkdir -p /mnt/var/{log,cache,tmp,lib}
mount -o subvol=@var-log,compress=zstd:6,noatime,space_cache=v2 "$ROOT_PART" /mnt/var/log
mount -o subvol=@var-cache,nodatacow,noatime,space_cache=v2 "$ROOT_PART" /mnt/var/cache
mount -o subvol=@var-tmp,nodatacow,noatime,space_cache=v2 "$ROOT_PART" /mnt/var/tmp
mount -o subvol=@var-lib,compress=zstd:1,noatime,space_cache=v2 "$ROOT_PART" /mnt/var/lib

mkdir -p /mnt/var/lib/docker
mount -o subvol=@var-lib-docker,compress=zstd:1,noatime,space_cache=v2 "$ROOT_PART" /mnt/var/lib/docker

# Mount storage disk (only if provided)
if [[ -n "$STORAGE_DISK" ]]; then
    log "Mounting storage disk..."
    mkdir -p /mnt/mnt/storage
    mount -o subvol=@,compress=zstd:3,noatime,space_cache=v2 "$STORAGE_DISK" /mnt/mnt/storage
fi

# 5. Generate hardware configuration
log "Generating hardware configuration..."
nixos-generate-config --root /mnt

# Add grub device to hardware configuration
log "Adding grub device to hardware configuration..."
sed -i "/^}$/i\\  # Boot device for GRUB\\n  boot.loader.grub.device = \"$DISK\";" /mnt/etc/nixos/hardware-configuration.nix

# 6. Create basic configuration
log "Creating NixOS configuration..."
cat > /mnt/etc/nixos/configuration.nix << EOF
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Boot loader (device set in hardware-configuration.nix)
  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.efi.efiSysMountPoint = "/boot/efi";

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Network
  networking.hostName = "$HOSTNAME";
  networking.networkmanager.enable = true;

  # Time zone
  time.timeZone = "$TIMEZONE";

  # Localization
  i18n.defaultLocale = "en_US.UTF-8";

  # Users
  users.users.$USERNAME = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = [
      "$SSH_KEY"
    ];
  };

  users.users.root = {
    openssh.authorizedKeys.keys = [
      "$SSH_KEY"
    ];
  };

  # Enable passwordless sudo
  security.sudo.wheelNeedsPassword = false;

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "yes";
      X11Forwarding = false;
    };
  };

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # System packages
  environment.systemPackages = with pkgs; [
    neovim
    wget
    curl
    git
    htop
    tree
    unzip
    rsync
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  system.stateVersion = "25.05";
}
EOF

# 7. Install NixOS
log "Installing NixOS..."
nixos-install --no-root-passwd

# 8. Final steps
success "NixOS installation completed!"
log "Next steps:"
log "1. Reboot: reboot"
log "2. SSH into the system: ssh $USERNAME@<ip-address>"
log "3. Deploy your configuration: ./deploy.sh $USERNAME@<ip-address>"
log ""
log "The system is configured with:"
log "- Hostname: $HOSTNAME"
log "- User: $USERNAME (with sudo access)"
log "- SSH key authentication enabled"
log "- Root SSH access enabled"
log "- Btrfs with optimized subvolumes"
log "- Flakes enabled"

warn "Remember to:"
warn "1. Change the SSH key in the script before running"
warn "2. Configure your network after reboot"
warn "3. Test SSH connectivity before proceeding"