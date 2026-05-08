#!/usr/bin/env bash
# homelab-restore — per-service Restic restore CLI
# Reads /etc/homelab/services.json for service metadata.
# Machine-specific values (HOMELAB_MACHINE, HOMELAB_LOCK, HOMELAB_REPO) are
# injected by the NixOS module via `--prefix` env vars in the writeShellScriptBin wrapper.

set -euo pipefail

META=/etc/homelab/services.json
[[ -f $META ]] || { echo "ERROR: $META not found" >&2; exit 1; }

# Required injected env vars
: "${HOMELAB_MACHINE:?HOMELAB_MACHINE not set}"
: "${HOMELAB_LOCK:?HOMELAB_LOCK not set}"
: "${HOMELAB_REPO:?HOMELAB_REPO not set}"
: "${HOMELAB_RESTIC_PASSWORD_FILE:?HOMELAB_RESTIC_PASSWORD_FILE not set}"
: "${HOMELAB_RESTIC_S3_ENV:?HOMELAB_RESTIC_S3_ENV not set}"

export RESTIC_REPOSITORY="$HOMELAB_REPO"
export RESTIC_PASSWORD_FILE="$HOMELAB_RESTIC_PASSWORD_FILE"
# shellcheck disable=SC1090
set -a; . "$HOMELAB_RESTIC_S3_ENV"; set +a

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[$(date -Iseconds)]${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; }

services_all()      { jq -r '.services | keys[]'                                    "$META"; }
services_normal()   { jq -r '.services | to_entries[] | select(.value.large|not) | .key' "$META"; }
service_exists()    { jq -e --arg n "$1" '.services[$n] != null'                    "$META" >/dev/null; }
service_is_large()  { jq -e --arg n "$1" '.services[$n].large == true'              "$META" >/dev/null; }
service_postscript(){ jq -r --arg n "$1" '.services[$n].postScript // ""'           "$META"; }

cmd_list() {
  echo "Restore-enabled services on machine '${HOMELAB_MACHINE}':"
  while read -r svc; do
    large=""
    service_is_large "$svc" && large=" [large]"
    last=$(restic snapshots --json --tag "service-${svc}" --tag backup-v2 --tag "machine-${HOMELAB_MACHINE}" 2>/dev/null \
      | jq -r '.[-1].time // "never"' 2>/dev/null || echo "unknown")
    printf "  %-25s last=%s%s\n" "$svc" "$last" "$large"
  done < <(services_all)
}

# Restore a single service. Returns 0 on success, non-zero on failure.
restore_one() {
  local svc="$1"
  log "[$svc] stopping service"
  if ! compose-manage stop "$svc" 2>&1 | sed "s/^/  [$svc] /"; then
    warn "[$svc] compose-manage stop reported a non-zero status (continuing)"
  fi

  log "[$svc] acquiring lock and running restic restore"
  if ! flock "$HOMELAB_LOCK" restic restore latest \
        --tag "service-${svc}" \
        --tag backup-v2 \
        --tag "machine-${HOMELAB_MACHINE}" \
        --target / 2>&1 | sed "s/^/  [$svc] /"; then
    err "[$svc] restic restore failed"
    return 1
  fi

  local script
  script=$(service_postscript "$svc")
  if [[ -n $script ]]; then
    log "[$svc] running postScript"
    local tmp
    tmp=$(mktemp)
    printf '%s\n' "$script" > "$tmp"
    if ! bash "$tmp" 2>&1 | sed "s/^/  [$svc] /"; then
      err "[$svc] postScript failed"
      rm -f "$tmp"
      return 1
    fi
    rm -f "$tmp"
  fi

  log "[$svc] starting service"
  if ! compose-manage start "$svc" 2>&1 | sed "s/^/  [$svc] /"; then
    err "[$svc] compose-manage start failed"
    return 1
  fi

  ok "[$svc] restore complete"
  return 0
}

cmd_service() {
  local svc="${1:-}"
  [[ -n $svc ]] || { err "Usage: homelab-restore service <name>"; exit 2; }
  service_exists "$svc" || { err "Service '$svc' not in $META"; exit 2; }
  restore_one "$svc"
}

cmd_all() {
  local parallel=1
  if [[ "${1:-}" == "--parallel" ]]; then
    parallel="${2:-1}"; shift 2 || true
  fi

  local -a services
  mapfile -t services < <(services_normal)
  log "Restoring ${#services[@]} non-large service(s) with parallel=${parallel}"

  local -a succeeded=() failed=()
  local -a pids=() names=()

  flush_batch() {
    local i
    for i in "${!pids[@]}"; do
      if wait "${pids[$i]}"; then
        succeeded+=("${names[$i]}")
      else
        failed+=("${names[$i]}")
      fi
    done
    pids=(); names=()
  }

  for svc in "${services[@]}"; do
    restore_one "$svc" &
    pids+=($!); names+=("$svc")
    if (( ${#pids[@]} >= parallel )); then
      flush_batch
    fi
  done
  flush_batch

  local -a skipped=()
  while read -r svc; do
    service_is_large "$svc" && skipped+=("$svc")
  done < <(services_all)

  echo
  log "=== Restore summary ==="
  ok      "Succeeded (${#succeeded[@]}): ${succeeded[*]:-<none>}"
  warn    "Skipped large (${#skipped[@]}): ${skipped[*]:-<none>}"
  if (( ${#failed[@]} > 0 )); then
    err   "Failed (${#failed[@]}): ${failed[*]}"
    exit 1
  fi
}

case "${1:-}" in
  list)            shift; cmd_list "$@" ;;
  service)         shift; cmd_service "$@" ;;
  all)             shift; cmd_all "$@" ;;
  ""|-h|--help|*)
    cat <<EOF
homelab-restore — per-service Restic restore

Usage:
  homelab-restore list
      List restore-enabled services and last snapshot date.

  homelab-restore service <name>
      Restore one service (works on large services too).

  homelab-restore all [--parallel <n>]
      Restore every non-large restore-enabled service.
      Failures are isolated; large services are skipped (use 'service' for those).
EOF
    ;;
esac
