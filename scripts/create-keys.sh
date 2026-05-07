#!/usr/bin/env bash
# Generates keys needed for VM testing. Idempotent — safe to run multiple times.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYS_DIR="$REPO_ROOT/machines/tests/keys"
VM_HOST_KEY="$KEYS_DIR/vm_ed25519_key"
VM_CLIENT_KEY="$KEYS_DIR/vm_client_ed25519_key"
SOPS_CONFIG="$REPO_ROOT/.sops.yaml"
VM_SECRETS="$REPO_ROOT/machines/home-vm/secrets.yaml"
HOME_SECRETS="$REPO_ROOT/machines/home/secrets.yaml"
mkdir -p "$KEYS_DIR"

usage() {
  cat <<EOF
Usage: $0 [--rotate]

Without arguments, validate the existing VM host key and ensure the VM client
key exists.

Options:
  --rotate    Generate a new VM host key, update .sops.yaml home_vm recipient,
              and rekey machines/home-vm/secrets.yaml when sops can decrypt it.
  -h, --help  Show this help.
EOF
}

ROTATE=false
case "${1:-}" in
  "")
    ;;
  --rotate)
    ROTATE=true
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "ERROR: Unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ $# -gt 1 ]]; then
  echo "ERROR: Too many arguments." >&2
  usage >&2
  exit 2
fi

ssh_to_age() {
  if command -v ssh-to-age >/dev/null 2>&1; then
    ssh-to-age
    return
  fi

  if command -v nix >/dev/null 2>&1; then
    nix shell --inputs-from "$REPO_ROOT" nixpkgs#ssh-to-age -c ssh-to-age
    return
  fi

  echo "ERROR: ssh-to-age not found, and nix is unavailable to run nixpkgs#ssh-to-age." >&2
  return 1
}

expected_home_vm_recipient="$(
  awk '$2 == "&home_vm" { print $3 }' "$SOPS_CONFIG"
)"

if [[ -z "$expected_home_vm_recipient" ]]; then
  echo "ERROR: Could not find the .sops.yaml home_vm age recipient." >&2
  exit 1
fi

replace_home_vm_recipient() {
  local new_recipient="$1"
  local tmp
  tmp="$(mktemp)"
  awk -v new_recipient="$new_recipient" '
    /^[[:space:]]*-[[:space:]]*&home_vm[[:space:]]+/ {
      sub(/age1[0-9a-z]+/, new_recipient)
    }
    { print }
  ' "$SOPS_CONFIG" > "$tmp"
  mv "$tmp" "$SOPS_CONFIG"
}

if [[ "$ROTATE" == true ]]; then
  timestamp="$(date +%Y%m%d%H%M%S)"
  if [[ -f "$VM_HOST_KEY" ]]; then
    mv "$VM_HOST_KEY" "${VM_HOST_KEY}.bak-${timestamp}"
  fi
  if [[ -f "${VM_HOST_KEY}.pub" ]]; then
    mv "${VM_HOST_KEY}.pub" "${VM_HOST_KEY}.pub.bak-${timestamp}"
  fi

  echo "==> Rotating VM SSH host/decryption key..."
  ssh-keygen -t ed25519 -N "" -C "home-vm-host" -f "$VM_HOST_KEY"

  if ! new_home_vm_recipient="$(ssh_to_age < "${VM_HOST_KEY}.pub")"; then
    echo "ERROR: Could not convert ${VM_HOST_KEY}.pub to an age recipient with ssh-to-age." >&2
    echo "Install ssh-to-age or make nixpkgs#ssh-to-age available, then rerun this script." >&2
    exit 1
  fi

  replace_home_vm_recipient "$new_home_vm_recipient"
  expected_home_vm_recipient="$new_home_vm_recipient"

  echo "==> Updated .sops.yaml home_vm recipient:"
  echo "    $new_home_vm_recipient"

  if command -v sops >/dev/null 2>&1; then
    echo "==> Rekeying machines/home-vm/secrets.yaml..."
    if ! sops updatekeys -y "$VM_SECRETS"; then
      echo "==> Could not rekey existing VM secrets; recreating them from home secrets..."
      tmp_plain="$(mktemp)"
      trap 'rm -f "$tmp_plain"' EXIT
      if ! sops --decrypt "$HOME_SECRETS" > "$tmp_plain"; then
        echo "ERROR: Could not decrypt $HOME_SECRETS to recreate VM secrets." >&2
        exit 1
      fi
      if ! sops --encrypt "$tmp_plain" > "$VM_SECRETS"; then
        echo "ERROR: Could not encrypt recreated VM secrets to $VM_SECRETS." >&2
        exit 1
      fi
      rm -f "$tmp_plain"
      trap - EXIT
    fi
  else
    cat <<EOF
==> sops not found; VM host key and .sops.yaml were rotated.
    Rekey or recreate $VM_SECRETS before building home-vm.
EOF
  fi
fi

if [[ ! -f "$VM_HOST_KEY" ]]; then
  cat >&2 <<EOF
ERROR: Missing VM host/decryption key: $VM_HOST_KEY

This key must already match the .sops.yaml home_vm recipient:
  $expected_home_vm_recipient

Do not generate a random replacement; machines/home-vm/secrets.yaml will not decrypt.
Restore the matching VM host key to $VM_HOST_KEY, or intentionally update
.sops.yaml and re-encrypt machines/home-vm/secrets.yaml for the new recipient.
EOF
  exit 1
fi

if [[ ! -f "${VM_HOST_KEY}.pub" ]]; then
  echo "==> Reconstructing missing VM SSH host public key..."
  ssh-keygen -y -f "$VM_HOST_KEY" > "${VM_HOST_KEY}.pub"
fi

if ! actual_home_vm_recipient="$(ssh_to_age < "${VM_HOST_KEY}.pub")"; then
  echo "ERROR: Could not convert ${VM_HOST_KEY}.pub to an age recipient with ssh-to-age." >&2
  echo "Install ssh-to-age or make nixpkgs#ssh-to-age available, then rerun this script." >&2
  exit 1
fi
if [[ "$actual_home_vm_recipient" != "$expected_home_vm_recipient" ]]; then
  cat >&2 <<EOF
ERROR: VM host key does not match .sops.yaml home_vm recipient.

Expected: $expected_home_vm_recipient
Actual:   $actual_home_vm_recipient

Replace $VM_HOST_KEY with the host key matching .sops.yaml, or intentionally
update .sops.yaml and re-encrypt machines/home-vm/secrets.yaml.
EOF
  exit 1
fi
echo "==> VM SSH host key matches .sops.yaml home_vm recipient"

if [[ ! -f "$VM_CLIENT_KEY" ]]; then
  echo "==> Generating VM SSH client key..."
  ssh-keygen -t ed25519 -N "" -C "home-vm-client" -f "$VM_CLIENT_KEY"
else
  echo "==> VM SSH client key already exists, skipping"
fi

if [[ ! -f "${VM_CLIENT_KEY}.pub" ]]; then
  ssh-keygen -y -f "$VM_CLIENT_KEY" > "${VM_CLIENT_KEY}.pub"
fi
