#!/usr/bin/env bash

source /etc/homelab/lib.sh

# --- Commands ---

cmd_list() {
  info "Registered services:"
  while read -r name; do
    print_status_line "$name"
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

cmd_unlock() {
  if [[ -f /etc/compose-unlocked ]]; then
    success "Already unlocked."
  else
    touch /etc/compose-unlocked
    systemctl start compose-unlocked.target
    success "Unlocked. Services will now start."
  fi
}

cmd_lock() {
  rm -f /etc/compose-unlocked
  warn "Locked. Services will not auto-start on next boot."
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
  echo ""
  warn "Boot Control:"
  echo "  unlock                   - Create unlock file so services start on boot"
  echo "  lock                     - Remove unlock file (services won't auto-start)"
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
  unlock)          cmd_unlock ;;
  lock)            cmd_lock ;;
  *)               cmd_help ;;
esac
