#!/usr/bin/env bash
# scripts/vm-kill.sh
# Kills the running home-vm QEMU process.
set -euo pipefail

if [[ -f /tmp/home-vm.pid ]]; then
  PID=$(cat /tmp/home-vm.pid)
  kill "$PID" 2>/dev/null && echo "VM killed (PID $PID)" || echo "VM already stopped"
  rm -f /tmp/home-vm.pid
else
  echo "No VM PID file found — VM may not be running"
fi
