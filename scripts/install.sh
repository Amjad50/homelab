#!/usr/bin/env bash
# scripts/install.sh
# Install ANY flake machine onto ANY ssh target via nixos-anywhere.
#
# Usage:
#   ./scripts/install.sh <machine> <user@host> [--host-key PATH] [--build-on-remote]
#
#   <machine>          flake nixosConfiguration name (home, middle-arm, ...)
#   <user@host>        ssh target (must reach it as root, or a sudo user)
#   --host-key PATH    inject this ed25519 host key as /etc/ssh/ssh_host_ed25519_key
#                      (PATH and PATH.pub). Use when the machine's sops secrets are
#                      encrypted to this key — see scripts/gen-host-key.sh. If omitted,
#                      NixOS generates a fresh host key on first boot (sops-encrypted
#                      secrets will NOT decrypt unless a recipient was pre-added).
#   --build-on-remote  build on the target instead of locally (needed for cross-arch,
#                      e.g. installing an aarch64 machine from an x86 laptop).
#
# WARNING: nixos-anywhere runs disko, which WIPES the target disk.
#
# Prereqs: `nix develop` (provides nixos-anywhere).
set -euo pipefail

MACHINE=""
TARGET=""
HOST_KEY=""
BUILD_ON_REMOTE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host-key)        HOST_KEY="$2"; shift 2 ;;
        --build-on-remote) BUILD_ON_REMOTE=true; shift ;;
        -h|--help)         sed -n '3,20p' "$0"; exit 0 ;;
        -*)                echo "ERROR: unknown flag: $1" >&2; exit 1 ;;
        *)
            if   [[ -z "$MACHINE" ]]; then MACHINE="$1"
            elif [[ -z "$TARGET" ]];  then TARGET="$1"
            else echo "ERROR: unexpected argument: $1" >&2; exit 1
            fi
            shift ;;
    esac
done

[[ -n "$MACHINE" && -n "$TARGET" ]] || { sed -n '3,20p' "$0"; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v nixos-anywhere >/dev/null 2>&1 || { echo "ERROR: nixos-anywhere missing — run: nix develop" >&2; exit 1; }

ANYWHERE_ARGS=(--flake "$REPO_ROOT#$MACHINE" --target-host "$TARGET")
$BUILD_ON_REMOTE && ANYWHERE_ARGS+=(--build-on-remote)

EXTRA_FILES=""
if [[ -n "$HOST_KEY" ]]; then
    [[ -f "$HOST_KEY"     ]] || { echo "ERROR: $HOST_KEY not found" >&2; exit 1; }
    [[ -f "$HOST_KEY.pub" ]] || { echo "ERROR: $HOST_KEY.pub not found (need the matching public key)" >&2; exit 1; }
    EXTRA_FILES="$(mktemp -d)"
    trap 'rm -rf "$EXTRA_FILES"' EXIT
    mkdir -p "$EXTRA_FILES/etc/ssh"
    cp "$HOST_KEY"     "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key"
    cp "$HOST_KEY.pub" "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key.pub"
    chmod 600 "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key"
    ANYWHERE_ARGS+=(--extra-files "$EXTRA_FILES")
    echo "==> Injecting host key $HOST_KEY (sops decryption identity for $MACHINE)."
fi

echo "==> Installing '$MACHINE' onto '$TARGET'"
$BUILD_ON_REMOTE && echo "    (building on the remote box)"
echo "    nixos-anywhere runs disko and WIPES the target disk."
nixos-anywhere "${ANYWHERE_ARGS[@]}"

echo ""
echo "==> Done. '$MACHINE' installed on '$TARGET'; it will reboot into NixOS."
