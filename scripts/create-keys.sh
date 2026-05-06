#!/usr/bin/env bash
# Generates keys needed for VM testing. Idempotent — safe to run multiple times.
set -euo pipefail

KEYS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/machines/tests/keys"
mkdir -p "$KEYS_DIR"

if [[ ! -f "$KEYS_DIR/vm_ed25519_key" ]]; then
  echo "==> Generating VM SSH host key..."
  ssh-keygen -t ed25519 -N "" -f "$KEYS_DIR/vm_ed25519_key"
else
  echo "==> VM SSH host key already exists, skipping"
fi
