#!/usr/bin/env bash

source /etc/homelab/lib.sh

# --- Commands ---

cmd_list() {
  # Resolve sablier set once up-front so children don't each curl Traefik.
  sablier_managed_set >/dev/null

  info "Registered services:"
  while read -r name; do
    print_stack_status "$name"
  done < <(registry_services | sort)

  echo ""
  info "Unregistered (on disk, not in registry):"
  local found=0
  for dir in "$COMPOSE_ROOT"/*/; do
    [[ -f "${dir}docker-compose.yml" ]] || continue
    local name
    name=$(basename "$dir")
    registry_has "$name" && continue
    print_status_line "$name"
    found=$((found + 1))
  done
  [[ $found -gt 0 ]] || echo "  (none)"
}

cmd_status() {
  if [[ -n "${1:-}" ]]; then
    require_service "$1"
    systemctl status "$(unit_name "$1")" --no-pager -l
  else
    info "Status of all compose services:"
    while read -r name; do
      echo -e "\n${YELLOW}=== $name ===${NC}"
      systemctl status "$(unit_name "$name")" --no-pager -l || true
    done < <(registry_services | sort)
  fi
}

cmd_start() {
  if [[ -n "${1:-}" ]]; then
    require_service "$1"
    info "Starting $1..."
    do_systemctl start "$1"
  else
    info "Starting all services in parallel..."
    parallel_from start registry_services
  fi
}

cmd_stop() {
  if [[ -n "${1:-}" ]]; then
    require_service "$1"
    info "Stopping $1..."
    do_systemctl stop "$1"
  else
    info "Stopping all services in parallel..."
    parallel_from stop registry_services
  fi
}

cmd_restart() {
  require_arg "${1:-}" "compose-manage restart <service>"
  require_service "$1"
  info "Restarting $1..."
  do_systemctl restart "$1"
}

cmd_start_group() {
  require_arg "${1:-}" "compose-manage start-group <backup-group>"
  require_group "$1"
  info "Starting all services in backup group $1..."
  parallel_from start group_services "$1"
}

cmd_stop_group() {
  require_arg "${1:-}" "compose-manage stop-group <backup-group>"
  require_group "$1"
  info "Stopping all services in backup group $1..."
  parallel_from stop group_services "$1"
}

cmd_start_container() {
  require_arg "${1:-}" "compose-manage start-container <service> <container>"
  require_arg "${2:-}" "compose-manage start-container <service> <container>"
  require_service "$1"
  info "Starting container $2 in $1..."
  cd "$COMPOSE_ROOT/$1" && docker-compose up -d "$2"
}

cmd_stop_container() {
  require_arg "${1:-}" "compose-manage stop-container <service> <container>"
  require_arg "${2:-}" "compose-manage stop-container <service> <container>"
  require_service "$1"
  info "Stopping container $2 in $1..."
  cd "$COMPOSE_ROOT/$1" && docker-compose stop "$2"
}

cmd_logs() {
  require_arg "${1:-}" "compose-manage logs <service> [container]"
  require_service "$1"
  local svc=$1; shift
  cd "$COMPOSE_ROOT/$svc" && docker-compose logs -f "$@"
}

cmd_exec() {
  local t_flag=""
  if [[ "${1:-}" == "-T" ]]; then
    t_flag="-T"
    shift
  fi
  require_arg "${1:-}" "compose-manage exec [-T] <service> <container> <cmd...>"
  require_arg "${2:-}" "compose-manage exec [-T] <service> <container> <cmd...>"
  local svc=$1 ctr=$2; shift 2
  cd "$COMPOSE_ROOT/$svc" && docker-compose exec $t_flag "$ctr" "$@"
}

cmd_ps() {
  if [[ -n "${1:-}" ]]; then
    require_service "$1"
    cd "$COMPOSE_ROOT/$1" && docker-compose ps
  else
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  fi
}

cmd_pull() {
  local do_up=false
  [[ "${1:-}" == "--up" ]] && { do_up=true; shift; }

  pull_one() {
    local name=$1
    info "=== $name ==="
    cd "$COMPOSE_ROOT/$name" && sudo -u dock docker compose pull
    if [[ $do_up == true ]] && is_running "$name"; then
      info "Bringing up $name..."
      sudo -u dock docker compose up -d --remove-orphans
    fi
  }

  if [[ $# -eq 0 ]]; then
    info "Pulling images for all services..."
    while read -r name; do pull_one "$name"; done < <(registry_services)
    success "All images updated"
  else
    for name in "$@"; do
      require_service "$name"
      pull_one "$name"
    done
  fi
}

# Stacks never touched by `update` (pinned on purpose, or updated by hand).
UPDATE_SKIP=(
  traefik
)

# Digest of the pinned tag from the registry. Manifest-only request — cheap and
# never resolves to a different tag, so postgres:15 can't surface as 18.
remote_digest() {
  regctl image digest --list "$1" 2>/dev/null
}

# RepoDigests of the locally-present image for the pinned tag.
local_digest() {
  docker image inspect "$1" --format '{{join .RepoDigests "\n"}}' 2>/dev/null
}

update_skipped() {
  local name=$1 s
  for s in "${UPDATE_SKIP[@]}"; do [[ "$name" == "$s" ]] && return 0; done
  return 1
}

# Unique images of a stack. Prefers running containers (exact, resolved tags,
# no env_file needed); falls back to the compose YAML when the stack is down.
stack_images() {
  local name=$1 imgs
  imgs=$(docker ps -a --filter "label=com.docker.compose.project=$name" \
    --format '{{.Image}}' 2>/dev/null | sed '/^$/d' | sort -u)
  if [[ -z "$imgs" ]]; then
    imgs=$(grep -hE '^\s*image:' "$COMPOSE_ROOT/$name/docker-compose.yml" 2>/dev/null |
      sed -E 's/^\s*image:\s*//; s/^["'\'']//; s/["'\'']\s*$//' |
      sed -E 's/\$\{[^:}]+:-([^}]+)\}/\1/g' | sed '/\$/d' | sort -u)
  fi
  printf '%s\n' "$imgs"
}

cmd_update() {
  local check_only=false
  [[ "${1:-}" == "--check" ]] && { check_only=true; shift; }

  local -a targets
  if [[ $# -gt 0 ]]; then
    for name in "$@"; do require_service "$name"; done
    targets=("$@")
  else
    mapfile -t targets < <(registry_services | sort)
  fi

  local -a updated=() report=()
  local name

  for name in "${targets[@]}"; do
    update_skipped "$name" && { info "[SKIP] $name (pinned)"; continue; }

    local -a outdated=()
    local image
    while read -r image; do
      [[ -z "$image" ]] && continue
      local remote have
      remote=$(remote_digest "$image")
      if [[ -z "$remote" ]]; then
        warn "[WARN] $name: no remote digest for $image"
        continue
      fi
      have=$(local_digest "$image")
      if [[ "$have" == *"$remote"* ]]; then
        echo -e "  ${GREEN}✓${NC} $name: $image"
      else
        warn "  ↑ $name: $image (update available)"
        outdated+=("$image")
      fi
    done < <(stack_images "$name")

    [[ ${#outdated[@]} -eq 0 ]] && continue
    $check_only && continue

    cd "$COMPOSE_ROOT/$name" || { err "$name: missing stack dir"; continue; }

    local pulled=true
    for image in "${outdated[@]}"; do
      info "[PULL] $name: $image"
      sudo -u dock docker pull "$image" || { err "$name: pull failed for $image"; pulled=false; }
    done
    $pulled || continue

    info "[RESTART] $name"
    if sudo -u dock docker compose up -d --remove-orphans; then
      updated+=("$name")
      local img
      for img in "${outdated[@]}"; do report+=("  $name: $(basename "$img")"); done
    else
      err "$name: up -d failed"
    fi
  done

  if [[ ${#updated[@]} -gt 0 ]]; then
    success "Updated: ${updated[*]}"
    update_notify "${report[@]}"
  else
    $check_only || success "Everything up to date"
  fi
}

# ntfy only on a committed update, reusing the homelab ntfy env.
update_notify() {
  local env_file=/var/lib/dock/ntfy-client.env
  [[ -r "$env_file" ]] || return 0
  # shellcheck disable=SC1090
  source "$env_file"
  [[ -n "${NTFY_TOKEN:-}" ]] || return 0
  local body; body=$(printf '%s\n' "$@")
  curl -fsS \
    -H "Authorization: Bearer ${NTFY_TOKEN}" \
    -H "Title: Containers updated on $(hostname)" \
    -H "Tags: arrow_up,whale" \
    -d "$body" \
    "${NTFY_URL%/}/${NTFY_TOPIC}" >/dev/null || true
}

cmd_help() {
  info "Docker Compose Services Manager"
  echo ""
  echo "Usage: compose-manage {command} [arguments]"
  echo ""
  warn "Service Management:"
  echo "  list                     - List all registered services and status"
  echo "  status [service]         - Show status of service(s)"
  echo "  start [service]          - Start a service, or all services in parallel"
  echo "  stop [service]           - Stop a service, or all services in parallel"
  echo "  restart <service>        - Restart a service"
  echo "  start-group <group>      - Start all services in a backup group"
  echo "  stop-group <group>       - Stop all services in a backup group"
  echo ""
  warn "Container Operations:"
  echo "  start-container <svc> <ctr> - Start a specific container"
  echo "  stop-container <svc> <ctr>  - Stop a specific container"
  echo "  logs <service> [container]  - Follow logs"
  echo "  exec <svc> <ctr> <cmd...>   - Execute command in container"
  echo "  ps [service]                - Show running containers"
  echo "  pull [--up] [services...]   - Pull images (--up to restart if running)"
  echo "  update [--check] [svc...]   - Digest-check pinned tags; pull+restart only changed (--check: console only, no pull/notify)"
}

# --- Main ---

require_meta

case "${1:-}" in
  list)            cmd_list ;;
  status)          cmd_status "${2:-}" ;;
  start)           cmd_start "${2:-}" ;;
  stop)            cmd_stop "${2:-}" ;;
  restart)         cmd_restart "${2:-}" ;;
  start-group)     cmd_start_group "${2:-}" ;;
  stop-group)      cmd_stop_group "${2:-}" ;;
  start-container) cmd_start_container "${2:-}" "${3:-}" ;;
  stop-container)  cmd_stop_container "${2:-}" "${3:-}" ;;
  logs)            shift; cmd_logs "$@" ;;
  exec)            shift; cmd_exec "$@" ;;
  ps)              cmd_ps "${2:-}" ;;
  pull)            shift; cmd_pull "$@" ;;
  update)          shift; cmd_update "$@" ;;
  unlock)          cmd_unlock ;;
  lock)            cmd_lock ;;
  *)               cmd_help ;;
esac
