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

group_restore_autostart() {
  jq -e --arg g "$1" '.backups[$g].restoreAutoStart == true' "$META" >/dev/null
}

group_postgres() {
  jq -c --arg g "$1" '.backups[$g].postgres // []' "$META"
}

group_custom_restores() {
  jq -c --arg g "$1" '.backups[$g].customRestores // []' "$META"
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

# Renders one stack: header line + (optional) per-container sub-list.
# Sub-list is shown when the stack is sablier-managed or when any container
# is in a problem state. The header is escalated to "degraded" if any
# container is missing or unhealthy.
print_stack_status() {
  local name=$1
  local unit_status; unit_status=$(get_status "$name")

  # Collect container states
  local -a containers states
  mapfile -t containers < <(stack_containers "$name")

  local has_sablier=false problems=0 missing=0 unhealthy=0
  local c state
  for c in "${containers[@]}"; do
    state=$(container_state "$c")
    states+=("$state")
    is_sablier_managed "$c" && has_sablier=true
    case "$state" in
      missing)   missing=$((missing + 1));   problems=$((problems + 1)) ;;
      unhealthy) unhealthy=$((unhealthy + 1)); problems=$((problems + 1)) ;;
    esac
  done

  # --- Header ---
  local tag=""
  $has_sablier && tag=", sablier"

  if [[ $problems -gt 0 && $unit_status == active ]]; then
    local parts=()
    [[ $missing -gt 0 ]]   && parts+=("$missing missing")
    [[ $unhealthy -gt 0 ]] && parts+=("$unhealthy unhealthy")
    local summary; summary=$(IFS=', '; echo "${parts[*]}")
    echo -e "  ${YELLOW}⚠${NC} $name (degraded — $summary$tag)"
  else
    case "$unit_status" in
      active)   echo -e "  ${GREEN}✓${NC} $name (running$tag)" ;;
      inactive) echo -e "  ${RED}✗${NC} $name (stopped)" ;;
      failed)   echo -e "  ${RED}!${NC} $name (failed)" ;;
      *)        echo -e "  ${YELLOW}?${NC} $name ($unit_status)" ;;
    esac
  fi

  # --- Sub-list ---
  if $has_sablier || [[ $problems -gt 0 ]]; then
    local i
    for i in "${!containers[@]}"; do
      format_container_line "${containers[$i]}" "${states[$i]}"
    done
  fi
}

# --- Sablier awareness ---

# Returns the set of container names that are sablier-managed, newline-separated.
# Sourced from Traefik's middleware API; falls back to scanning docker labels.
# Cached per-process via __SABLIER_SET (set on first call).
sablier_managed_set() {
  if [[ -n "${__SABLIER_SET+x}" ]]; then
    [[ ${#__SABLIER_SET[@]} -gt 0 ]] && printf '%s\n' "${__SABLIER_SET[@]}"
    return
  fi

  local -a names=()
  local json
  json=$(curl -fsS --max-time 2 \
    -H "Host: traefik-internal.home.amsh.dev" \
    http://127.0.0.1:8080/api/http/middlewares 2>/dev/null) || true

  if [[ -n "$json" ]]; then
    mapfile -t names < <(echo "$json" | jq -r '
      .[]
      | select(.type == "sablier")
      | (.plugin.sablier.names // "")
      | split(",")
      | .[]
      | select(length > 0)
    ' 2>/dev/null | sort -u)
  fi

  # Fallback: scrape labels from docker if traefik query failed or empty.
  # Look for any label matching `*sablier*.plugin.sablier.names` and split its value.
  if [[ ${#names[@]} -eq 0 ]]; then
    mapfile -t names < <(
      docker ps -a --format '{{.Names}}' 2>/dev/null | while read -r c; do
        docker inspect "$c" --format \
          '{{range $k,$v := .Config.Labels}}{{$k}}={{$v}}{{"\n"}}{{end}}' 2>/dev/null \
          | grep -E '^traefik\.http\.middlewares\.[^.]+\.plugin\.sablier\.names=' \
          | sed 's/^[^=]*=//' \
          | tr ',' '\n'
      done | sed '/^$/d' | sort -u
    )
  fi

  # Per-process cache (arrays can't be exported across processes; the cache
  # benefit only applies within the current shell, which is enough for cmd_list).
  __SABLIER_SET=("${names[@]}")
  [[ ${#names[@]} -gt 0 ]] && printf '%s\n' "${names[@]}"
}

# True if a container name is in the sablier-managed set.
# Uses associative array __SABLIER_LOOKUP populated lazily.
is_sablier_managed() {
  local target=$1
  if [[ -z "${__SABLIER_LOOKUP_BUILT:-}" ]]; then
    declare -gA __SABLIER_LOOKUP=()
    local c
    while read -r c; do
      [[ -n "$c" ]] && __SABLIER_LOOKUP[$c]=1
    done < <(sablier_managed_set)
    __SABLIER_LOOKUP_BUILT=1
  fi
  [[ -n "${__SABLIER_LOOKUP[$target]:-}" ]]
}

# Echoes one of: running | idle | stopped | missing | unhealthy | notcreated
# Requires the sablier set to have been resolved (call sablier_managed_set first
# in callers that batch many lookups; otherwise this works fine but re-checks).
container_state() {
  local name=$1
  local status health
  status=$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null) || status=""

  if [[ -z "$status" ]]; then
    is_sablier_managed "$name" && echo missing || echo notcreated
    return
  fi

  if [[ "$status" == "running" ]]; then
    health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$name" 2>/dev/null)
    case "$health" in
      ""|healthy|starting) echo running ;;
      unhealthy)           echo unhealthy ;;
      *)                   echo running ;;
    esac
    return
  fi

  # status is exited/created/restarting/paused/dead/etc.
  if is_sablier_managed "$name"; then
    echo idle
  else
    echo stopped
  fi
}

# Echoes the expected container names for a compose stack (one per line).
# Uses `container_name:` from compose config; falls back to standard
# `${project}-${service}-1` naming when container_name is unset.
stack_containers() {
  local stack=$1
  local dir="$COMPOSE_ROOT/$stack"
  [[ -d "$dir" ]] || return 0

  # sudo because some stacks have root-owned env_file references
  sudo bash -c "cd '$dir' && docker compose config --format json 2>/dev/null" |
    jq -r --arg p "$stack" '
      .services
      | to_entries[]
      | .value.container_name // ($p + "-" + .key + "-1")
    ' 2>/dev/null
}

# Formats one indented container line for the list view.
# Args: <name> <state>
format_container_line() {
  local name=$1 state=$2
  case "$state" in
    running)    echo -e "    ${GREEN}✓${NC} $name (running)" ;;
    idle)       echo -e "    ${BLUE}⏻${NC} $name (idle)" ;;
    unhealthy)  echo -e "    ${YELLOW}⚠${NC} $name (unhealthy)" ;;
    missing)    echo -e "    ${RED}✗${NC} $name (missing!)" ;;
    stopped)    echo -e "    ${YELLOW}○${NC} $name (stopped)" ;;
    notcreated) echo -e "    ${YELLOW}○${NC} $name (not created)" ;;
    *)          echo -e "    ${YELLOW}?${NC} $name ($state)" ;;
  esac
}

systemd_unit_active_state() {
  systemctl show -p ActiveState --value "$1" 2>/dev/null || echo unknown
}

systemd_unit_sub_state() {
  systemctl show -p SubState --value "$1" 2>/dev/null || echo unknown
}

systemd_unit_runtime_state() {
  local active sub
  active=$(systemd_unit_active_state "$1")
  sub=$(systemd_unit_sub_state "$1")

  case "$active/$sub" in
    activating/*)
      echo running
      ;;
    active/exited|inactive/*)
      echo idle
      ;;
    failed/*)
      echo failed
      ;;
    unknown/unknown)
      echo unknown
      ;;
    *)
      echo "${active}${sub:+/$sub}"
      ;;
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
