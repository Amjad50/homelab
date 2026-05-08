#!/usr/bin/env bash
# scripts/vm-kill.sh
# Kills the running VM QEMU process.
# Usage: ./scripts/vm-kill.sh [home|middle]
set -euo pipefail

TARGET="${1:-home}"
if [[ "$TARGET" != "home" && "$TARGET" != "middle" ]]; then
  echo "Usage: $0 [home|middle]"
  exit 1
fi

if [[ -f /tmp/${TARGET}-vm.pid ]]; then
  PID=$(cat /tmp/${TARGET}-vm.pid)
  kill "$PID" 2>/dev/null && echo "VM killed (PID $PID)" || echo "VM already stopped"
  rm -f /tmp/${TARGET}-vm.pid
else
  echo "No VM PID file found — VM may not be running"
fi
