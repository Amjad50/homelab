#!/usr/bin/env bash
# scripts/vm-create.sh
# Creates a QEMU VM and deploys the home-vm NixOS config via nixos-anywhere.
# Run from the repo root: ./scripts/vm-create.sh
# Prerequisites: nix shell (provides nixos-anywhere, OVMF)
set -euo pipefail
exec > >(tee /tmp/vm-create.log) 2>&1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VM_DIR="$REPO_ROOT/machines/tests/disks"
VM_KEY="$REPO_ROOT/machines/tests/keys/vm_ed25519_key"
OS_DISK="$VM_DIR/home-vm-os.qcow2"
STORAGE_DISK="$VM_DIR/home-vm-storage.qcow2"

SSH_PORT=2222

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
nix build "$REPO_ROOT#installer-iso" --out-link "$VM_DIR/installer-iso-result" --log-format bar-with-logs
ISO_SRC=$(find -L "$VM_DIR/installer-iso-result" -name "*.iso" -type f | head -1 || true)
[[ -n "$ISO_SRC" ]] || { echo "ERROR: ISO not found after build"; exit 1; }
ISO_PATH="$VM_DIR/installer.iso"
if [[ ! -f "$ISO_PATH" ]] || [[ "$ISO_SRC" -nt "$ISO_PATH" ]]; then
  echo "    Copying ISO to $ISO_PATH ..."
  cp "$ISO_SRC" "$ISO_PATH"
  chmod 644 "$ISO_PATH"
fi
echo "    ISO: $ISO_PATH"

OVMF_CODE=$(find /nix/store -maxdepth 3 -name "OVMF_CODE.fd" 2>/dev/null | head -1 || true)
OVMF_VARS_SRC=$(find /nix/store -maxdepth 3 -name "OVMF_VARS.fd" 2>/dev/null | head -1 || true)
[[ -n "$OVMF_CODE" ]] || { echo "ERROR: OVMF_CODE.fd not found. Run: nix develop"; exit 1; }
[[ -n "$OVMF_VARS_SRC" ]] || { echo "ERROR: OVMF_VARS.fd not found. Run: nix develop"; exit 1; }

OVMF_VARS="$VM_DIR/home-vm-ovmf-vars.fd"
[[ -f "$OVMF_VARS" ]] || { cp "$OVMF_VARS_SRC" "$OVMF_VARS"; chmod 644 "$OVMF_VARS"; }
echo "    Using OVMF_CODE: $OVMF_CODE"
echo "    Using OVMF_VARS: $OVMF_VARS"

echo "==> Booting VM from ISO for nixos-anywhere installation..."
echo "    SSH will be forwarded on localhost:$SSH_PORT"

if [[ -f /tmp/home-vm.pid ]]; then
  kill "$(cat /tmp/home-vm.pid)" 2>/dev/null || true
  rm -f /tmp/home-vm.pid
fi

qemu-system-x86_64 \
  -name home-vm \
  -machine type=q35,accel=kvm \
  -cpu host \
  -m 8192 \
  -smp 4 \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$OVMF_VARS" \
  -drive file="$OS_DISK",if=virtio,cache=writeback,discard=unmap \
  -drive file="$STORAGE_DISK",if=virtio,cache=writeback,discard=unmap \
  -cdrom "$ISO_PATH" \
  -boot order=d \
  -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
  -device virtio-net-pci,netdev=net0 \
  -vga virtio \
  -display none \
  -daemonize \
  -pidfile /tmp/home-vm.pid

echo "==> Waiting for VM SSH to become available (up to 5 minutes)..."
ssh-keygen -R "[localhost]:$SSH_PORT" 2>/dev/null || true
CONNECTED=false
for i in $(seq 1 60); do
  if ssh -p "$SSH_PORT" -i "$VM_KEY" \
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
cp "$VM_KEY" "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key"
cp "${VM_KEY}.pub" "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key.pub"
chmod 600 "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key"

SSH_OPTS="-p $SSH_PORT -i $VM_KEY -o StrictHostKeyChecking=no"

echo "==> Running nixos-anywhere to install home-vm config..."
nixos-anywhere \
  --flake "$REPO_ROOT#home-vm" \
  --target-host "root@localhost" \
  --ssh-port "$SSH_PORT" \
  -i "$VM_KEY" \
  --ssh-option "StrictHostKeyChecking=no" \
  --extra-files "$EXTRA_FILES"

echo ""
echo "==> nixos-anywhere complete! VM is rebooting into NixOS home-vm..."
echo ""
echo "    Wait ~30 seconds for reboot, then:"
echo "      ssh -p $SSH_PORT -i $VM_KEY amjad@localhost"
echo ""
echo "    Run the full data restore (as root):"
echo "      ssh -p $SSH_PORT -i $VM_KEY root@localhost 'bash /etc/homelab-scripts/vm-restore.sh'"
echo ""
echo "    Kill the VM when done:"
echo "      ./scripts/vm-kill.sh"
