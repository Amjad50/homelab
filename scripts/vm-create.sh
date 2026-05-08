#!/usr/bin/env bash
# scripts/vm-create.sh
# Creates a QEMU VM and deploys the home-vm NixOS config via nixos-anywhere.
# Run from the repo root: ./scripts/vm-create.sh [home|middle]
# Prerequisites: nix shell (provides nixos-anywhere, OVMF)
set -euo pipefail

TARGET="${1:-home}"
if [[ "$TARGET" != "home" && "$TARGET" != "middle" ]]; then
  echo "Usage: $0 [home|middle]"
  exit 1
fi

exec > >(tee /tmp/vm-create-${TARGET}.log) 2>&1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VM_DIR="$REPO_ROOT/machines/tests/disks"
VM_HOST_KEY="$REPO_ROOT/machines/tests/keys/vm_ed25519_key"
VM_CLIENT_KEY="$REPO_ROOT/machines/tests/keys/vm_client_ed25519_key"
OS_DISK="$VM_DIR/${TARGET}-vm-os.qcow2"
STORAGE_DISK="$VM_DIR/${TARGET}-vm-storage.qcow2"

SSH_PORT=2222
if [[ "$TARGET" == "middle" ]]; then
  SSH_PORT=2223
fi

# Prevent GUI SSH password popups (ksshaskpass etc)
unset SSH_ASKPASS
unset SSH_ASKPASS_REQUIRE

echo "==> Checking dependencies..."
for cmd in nixos-anywhere ssh; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: Missing: $cmd — run: nix develop"; exit 1; }
done
for cmd in qemu-system-x86_64 qemu-img; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: Missing: $cmd — install with: sudo dnf install qemu-kvm"; exit 1; }
done

echo "==> Ensuring keys exist..."
"$SCRIPT_DIR/create-keys.sh"
VM_CLIENT_PUBLIC_KEY="$(< "${VM_CLIENT_KEY}.pub")"  # used for installer ISO

echo "==> Creating VM disks..."
mkdir -p "$VM_DIR"
if [[ ! -f "$OS_DISK" ]]; then
  qemu-img create -f qcow2 "$OS_DISK" 60G
  echo "    Created $OS_DISK (60G)"
fi
if [[ ! -f "$STORAGE_DISK" ]]; then
  qemu-img create -f qcow2 "$STORAGE_DISK" 200G
  echo "    Created $STORAGE_DISK (200G)"
fi

echo "==> Building custom NixOS installer ISO (with SSH key pre-authorized)..."
VM_INSTALLER_AUTHORIZED_KEY="$VM_CLIENT_PUBLIC_KEY" \
  nix build --impure "$REPO_ROOT#installer-iso" --out-link "$VM_DIR/installer-iso-result" --log-format bar-with-logs
ISO_SRC=$(find -L "$VM_DIR/installer-iso-result" -name "*.iso" -type f | head -1 || true)
[[ -n "$ISO_SRC" ]] || { echo "ERROR: ISO not found after build"; exit 1; }
ISO_PATH="$VM_DIR/installer.iso"
echo "    Copying ISO to $ISO_PATH ..."
cp "$ISO_SRC" "$ISO_PATH"
chmod 644 "$ISO_PATH"
echo "    ISO: $ISO_PATH"

OVMF_CODE=$(find /nix/store -maxdepth 3 -name "OVMF_CODE.fd" 2>/dev/null | head -1 || true)
OVMF_VARS_SRC=$(find /nix/store -maxdepth 3 -name "OVMF_VARS.fd" 2>/dev/null | head -1 || true)
[[ -n "$OVMF_CODE" ]] || { echo "ERROR: OVMF_CODE.fd not found. Run: nix develop"; exit 1; }
[[ -n "$OVMF_VARS_SRC" ]] || { echo "ERROR: OVMF_VARS.fd not found. Run: nix develop"; exit 1; }

OVMF_VARS="$VM_DIR/${TARGET}-vm-ovmf-vars.fd"
[[ -f "$OVMF_VARS" ]] || { cp "$OVMF_VARS_SRC" "$OVMF_VARS"; chmod 644 "$OVMF_VARS"; }
echo "    Using OVMF_CODE: $OVMF_CODE"
echo "    Using OVMF_VARS: $OVMF_VARS"

echo "==> Booting VM from ISO for nixos-anywhere installation..."
echo "    SSH will be forwarded on localhost:$SSH_PORT"

if [[ -f /tmp/${TARGET}-vm.pid ]]; then
  kill "$(cat /tmp/${TARGET}-vm.pid)" 2>/dev/null || true
  rm -f /tmp/${TARGET}-vm.pid
fi

qemu-system-x86_64 \
  -name ${TARGET}-vm \
  -machine type=q35,accel=kvm \
  -cpu host \
  -m 8192 \
  -smp 4 \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$OVMF_VARS" \
  -drive file="$OS_DISK",if=virtio,cache=writeback,discard=unmap \
  -drive file="$STORAGE_DISK",if=virtio,cache=writeback,discard=unmap \
  -cdrom "$ISO_PATH" \
  -boot once=d,order=c \
  -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
  -device virtio-net-pci,netdev=net0 \
  -vga virtio \
  -display none \
  -daemonize \
  -pidfile /tmp/${TARGET}-vm.pid

echo "==> Waiting for VM SSH to become available (up to 5 minutes)..."
ssh-keygen -R "[localhost]:$SSH_PORT" 2>/dev/null || true
CONNECTED=false
for i in $(seq 1 60); do
  if ssh -p "$SSH_PORT" -i "$VM_CLIENT_KEY" \
       -o StrictHostKeyChecking=no \
       -o ConnectTimeout=5 \
       -o PasswordAuthentication=no \
       -o BatchMode=yes \
       root@localhost true 2>/dev/null; then
    CONNECTED=true
    break
  fi
  echo -n "."
  sleep 5
done
echo ""
$CONNECTED || { echo "ERROR: VM SSH not reachable after 5 minutes"; exit 1; }
echo "    VM SSH is up."

echo "==> Injecting VM host key via extra-files..."
EXTRA_FILES="$REPO_ROOT/machines/tests/extra-files"
mkdir -p "$EXTRA_FILES/etc/ssh"
cp "$VM_HOST_KEY" "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key"
cp "${VM_HOST_KEY}.pub" "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key.pub"
chmod 600 "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key"

echo "==> Running nixos-anywhere to install ${TARGET}-vm config..."
nixos-anywhere \
  --flake "$REPO_ROOT#${TARGET}-vm" \
  --target-host "root@localhost" \
  --ssh-port "$SSH_PORT" \
  -i "$VM_CLIENT_KEY" \
  --ssh-option "StrictHostKeyChecking=no" \
  --no-substitute-on-destination \
  --ssh-store-setting "compress true" \
  --disk-encryption-keys "/etc/ssh/ssh_host_ed25519_key $VM_HOST_KEY" \
  --extra-files "$EXTRA_FILES"

# Cleanup the known_hosts entry for the installer VM (which had a different host key)
ssh-keygen -R "[localhost]:$SSH_PORT"

echo ""
echo "==> nixos-anywhere complete. Restarting VM from installed disk..."

# Restart without iso
"$SCRIPT_DIR/vm-start.sh" "$TARGET"
