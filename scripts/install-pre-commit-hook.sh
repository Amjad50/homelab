#!/usr/bin/env bash
# Installs the local pre-commit hook that blocks committing secrets.yaml files.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_SRC="$REPO_ROOT/scripts/pre-commit"
HOOK_DST="$REPO_ROOT/.git/hooks/pre-commit"

usage() {
  cat <<EOF
Usage: $0

Installs the repository's local pre-commit hook into .git/hooks/pre-commit.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 0 ]]; then
  echo "ERROR: Unknown argument: $1" >&2
  usage >&2
  exit 2
fi

if [[ ! -d "$REPO_ROOT/.git" ]]; then
  echo "ERROR: $REPO_ROOT is not a Git repository." >&2
  exit 1
fi

if [[ ! -f "$HOOK_SRC" ]]; then
  echo "ERROR: Missing hook source: $HOOK_SRC" >&2
  exit 1
fi

mkdir -p "$REPO_ROOT/.git/hooks"
cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"

echo "Installed pre-commit hook to $HOOK_DST"
