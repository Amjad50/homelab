#!/usr/bin/env bash
# scripts/vm-start.sh
# Starts the VM from its installed disk (no ISO).
# Run after vm-create.sh has completed installation.
# Usage: ./scripts/vm-start.sh [home|middle]
set -euo pipefail

TARGET="${1:-home}"
if [[ "$TARGET" != "home" && "$TARGET" != "middle" ]]; then
  echo "Usage: $0 [home|middle]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VM_DIR="$REPO_ROOT/machines/tests/disks"
OS_DISK="$VM_DIR/${TARGET}-vm-os.qcow2"
STORAGE_DISK="$VM_DIR/${TARGET}-vm-storage.qcow2"
OVMF_VARS="$VM_DIR/${TARGET}-vm-ovmf-vars.fd"

SSH_PORT=2222
if [[ "$TARGET" == "middle" ]]; then
  SSH_PORT=2223
fi

[[ -f "$OS_DISK" ]]   || { echo "ERROR: OS disk not found: $OS_DISK — run vm-create.sh first"; exit 1; }
[[ -f "$OVMF_VARS" ]] || { echo "ERROR: OVMF_VARS not found: $OVMF_VARS — run vm-create.sh first"; exit 1; }

OVMF_CODE=$(find /nix/store -maxdepth 3 -name "OVMF_CODE.fd" 2>/dev/null | head -1 || true)
[[ -n "$OVMF_CODE" ]] || { echo "ERROR: OVMF_CODE.fd not found — run: nix develop"; exit 1; }

# Kill any existing VM on this port
if [[ -f /tmp/${TARGET}-vm.pid ]]; then
  OLD_PID=$(cat /tmp/${TARGET}-vm.pid)
  kill "$OLD_PID" 2>/dev/null || true
  rm -f /tmp/${TARGET}-vm.pid
fi

echo "==> Starting ${TARGET}-vm from disk..."
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
  -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
  -device virtio-net-pci,netdev=net0 \
  -vga virtio \
  -display none \
  -daemonize \
  -pidfile /tmp/${TARGET}-vm.pid

echo "==> Waiting for SSH (up to 2 minutes)..."
for i in $(seq 1 24); do
  if nc -z localhost "$SSH_PORT" 2>/dev/null; then
    echo "==> SSH is up!"
    echo ""
    echo "    Connect: ssh -p $SSH_PORT amjad@localhost"
    echo "    Kill:    kill \$(cat /tmp/${TARGET}-vm.pid)"
    exit 0
  fi
  echo -n "."
  sleep 5
done
echo ""
echo "WARNING: SSH not reachable after 2 minutes — VM may still be booting."
echo "    Try: ssh -p $SSH_PORT amjad@localhost"
