#!/usr/bin/env bash
# homelab-lib.sh — shared helpers for homelab scripts
# Source this file: source /etc/homelab/lib.sh

META=/etc/homelab/services.json
COMPOSE_ROOT=/opt/docker-services

# --- Colors ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Output ---

info()    { echo -e "${BLUE}$*${NC}"; }
success() { echo -e "${GREEN}$*${NC}"; }
warn()    { echo -e "${YELLOW}$*${NC}"; }
err()     { echo -e "${RED}Error:${NC} $*" >&2; }
die()     { err "$@"; exit 1; }

log()     { echo -e "${BLUE}[$(date -Iseconds)]${NC} $*"; }
log_ok()  { echo -e "${GREEN}✓${NC} $*"; }
log_err() { echo -e "${RED}✗${NC} $*" >&2; }
log_warn(){ echo -e "${YELLOW}!${NC} $*"; }

# --- Registry ---

require_meta() {
  [[ -f $META ]] || die "$META not found — registry not deployed"
}

registry_services() {
  jq -r '.services[]' "$META"
}

registry_has() {
  jq -e --arg n "$1" '.services | index($n) != null' "$META" >/dev/null
}

group_names() {
  jq -r '.backups | keys[]' "$META"
}

group_exists() {
  jq -e --arg g "$1" '.backups[$g] != null' "$META" >/dev/null
}

group_services() {
  jq -r --arg g "$1" '.backups[$g].composeServices[]?' "$META"
}

group_sentinel() {
  jq -r --arg g "$1" '.backups[$g].sentinel' "$META"
}

group_postscript() {
  jq -r --arg g "$1" '.backups[$g].postRestoreScript // ""' "$META"
}

group_autostart() {
  jq -e --arg g "$1" '.backups[$g].autoStart == true' "$META" >/dev/null
}

group_postgres() {
  jq -c --arg g "$1" '.backups[$g].postgres // []' "$META"
}

# --- Validation ---

require_service() {
  registry_has "$1" || die "'$1' not in registry"
}

require_group() {
  group_exists "$1" || die "backup group '$1' not found in registry"
}

require_arg() {
  [[ -n "${1:-}" ]] || { echo "Usage: $2" >&2; exit 1; }
}

require_env() {
  local name=$1
  [[ -n "${!name:-}" ]] || die "$name not set"
}

# --- Systemd helpers ---

unit_name() { echo "docker-compose-$1"; }

get_status() {
  systemctl is-active "$(unit_name "$1")" 2>/dev/null || true
}

is_running() {
  [[ $(get_status "$1") == active ]]
}

print_status_line() {
  local name=$1
  case $(get_status "$name") in
    active)   echo -e "  ${GREEN}✓${NC} $name (running)" ;;
    inactive) echo -e "  ${RED}✗${NC} $name (stopped)" ;;
    failed)   echo -e "  ${RED}!${NC} $name (failed)" ;;
    *)        echo -e "  ${YELLOW}?${NC} $name ($(get_status "$name"))" ;;
  esac
}

do_systemctl() {
  local action=$1 name=$2
  systemctl "$action" "$(unit_name "$name")"
}

# --- Parallel execution ---

# parallel_systemctl ACTION [name ...]
parallel_systemctl() {
  local action=$1; shift
  local -a names=("$@")
  local -a pids=()

  for name in "${names[@]}"; do
    systemctl "$action" "$(unit_name "$name")" 2>/dev/null &
    pids+=($!)
  done

  local failed=0
  for i in "${!pids[@]}"; do
    if wait "${pids[$i]}" 2>/dev/null; then
      echo -e "  ${GREEN}✓${NC} ${names[$i]}"
    else
      echo -e "  ${RED}!${NC} ${names[$i]} (failed)"
      failed=$((failed + 1))
    fi
  done

  echo -e "${GREEN}Done.${NC} $failed service(s) failed."
  return $failed
}

# Collect names from a generator command, then run parallel_systemctl.
parallel_from() {
  local action=$1; shift
  local -a names
  mapfile -t names < <("$@")
  [[ ${#names[@]} -gt 0 ]] || { warn "No services found."; return 0; }
  parallel_systemctl "$action" "${names[@]}"
}

# --- JSON helpers ---

# jq_field ENTRY FIELD — extract a field from a JSON object string
jq_field() {
  echo "$1" | jq -r ".$2"
}
