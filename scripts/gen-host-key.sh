#!/usr/bin/env bash
# scripts/gen-host-key.sh
# Generate an ed25519 SSH host key for a new machine and derive its sops/age recipient.
#
# On NixOS + sops-nix, a host's /etc/ssh/ssh_host_ed25519_key doubles as the age key
# that decrypts its secrets. This script generates that keypair and prints:
#   1. the key path  -> pass to `install.sh --host-key <path>`
#   2. a ready-to-paste `.sops.yaml` anchor line for the recipient
# It does NOT edit .sops.yaml (no YAML parsing) — you paste the line, add the anchor to
# the machine's creation_rule, then run `sops updatekeys <secrets.yaml>`.
#
# Usage:
#   ./scripts/gen-host-key.sh <anchor-name> [out-dir]
#
#   <anchor-name>  sops anchor for the line, e.g. `middle` -> `- &middle age1...`
#   [out-dir]      where to write the keypair (default: a kept mktemp dir). The PRIVATE
#                  key is a secret — move it somewhere safe and delete it after install.
set -euo pipefail

NAME="${1:-}"
[[ -n "$NAME" ]] || { sed -n '3,18p' "$0"; exit 1; }

OUT_DIR="${2:-$(mktemp -d -t hostkey-"$NAME"-XXXXXX)}"
mkdir -p "$OUT_DIR"; chmod 700 "$OUT_DIR"
KEY="$OUT_DIR/ssh_host_ed25519_key"

ssh-keygen -t ed25519 -N "" -C "$NAME" -f "$KEY" >/dev/null

# ssh-to-age: from nixpkgs if not on PATH.
if command -v ssh-to-age >/dev/null 2>&1; then
    AGE="$(ssh-to-age -i "$KEY.pub")"
else
    AGE="$(nix run nixpkgs#ssh-to-age -- -i "$KEY.pub")"
fi

cat <<EOF

==> Host key generated for '$NAME'
    private key : $KEY        (SECRET — move to safe storage, delete after install)
    public key  : $KEY.pub

==> Install with:
    ./scripts/install.sh <machine> <user@host> --host-key $KEY [--build-on-remote]

==> Add this line to the 'keys:' block in .sops.yaml, then reference &$NAME in the
    machine's creation_rule, and run: sops updatekeys machines/<m>/secrets.yaml

  - &$NAME $AGE
EOF
