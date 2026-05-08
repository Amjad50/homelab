#!/usr/bin/env bash

COMPOSE_ROOT="/opt/docker-services"
META=/etc/homelab/services.json

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Read service list from registry. Exits if registry not available.
require_meta() {
  if [[ ! -f $META ]]; then
    echo -e "${RED}Error:${NC} $META not found — registry not deployed" >&2
    exit 1
  fi
}

# Print all registered service names, one per line.
registry_services() {
  jq -r '.services[]' "$META"
}

# Check a service is in the registry.
registry_has() {
  jq -e --arg n "$1" '.services | index($n) != null' "$META" >/dev/null
}

# Check a backup group exists.
group_exists() {
  jq -e --arg g "$1" '.backups[$g] != null' "$META" >/dev/null
}

# Print service names for a backup group, one per line.
group_services() {
  jq -r --arg g "$1" '.backups[$g].composeServices[]?' "$META"
}

case "$1" in
  list)
    require_meta
    echo -e "${BLUE}Registered services:${NC}"
    while read -r name; do
      status=$(systemctl is-active "docker-compose-$name" 2>/dev/null; true)
      case $status in
        active)   echo -e "  ${GREEN}✓${NC} $name (running)" ;;
        inactive) echo -e "  ${RED}✗${NC} $name (stopped)" ;;
        failed)   echo -e "  ${RED}!${NC} $name (failed)" ;;
        *)        echo -e "  ${YELLOW}?${NC} $name ($status)" ;;
      esac
    done < <(registry_services | sort)

    echo ""
    echo -e "${BLUE}Unregistered (on disk, not in registry):${NC}"
    found=0
    for dir in "$COMPOSE_ROOT"/*/; do
      [[ -f "${dir}docker-compose.yml" ]] || continue
      name=$(basename "$dir")
      registry_has "$name" && continue
      status=$(systemctl is-active "docker-compose-$name" 2>/dev/null; true)
      case $status in
        active)   echo -e "  ${GREEN}✓${NC} $name (running)" ;;
        inactive) echo -e "  ${RED}✗${NC} $name (stopped)" ;;
        failed)   echo -e "  ${RED}!${NC} $name (failed)" ;;
        *)        echo -e "  ${YELLOW}?${NC} $name ($status)" ;;
      esac
      found=$((found + 1))
    done
    [[ $found -eq 0 ]] && echo "  (none)"
    ;;

  status)
    require_meta
    if [[ -n "${2:-}" ]]; then
      registry_has "$2" || { echo -e "${RED}Error:${NC} '$2' not in registry" >&2; exit 1; }
      systemctl status "docker-compose-$2" --no-pager -l
    else
      echo -e "${BLUE}Status of all compose services:${NC}"
      while read -r name; do
        echo -e "\n${YELLOW}=== $name ===${NC}"
        systemctl status "docker-compose-$name" --no-pager -l || true
      done < <(registry_services | sort)
    fi
    ;;

  logs)
    require_meta
    [[ -n "${2:-}" ]] || { echo "Usage: compose-manage logs <service> [container]" >&2; exit 1; }
    registry_has "$2" || { echo -e "${RED}Error:${NC} '$2' not in registry" >&2; exit 1; }
    cd "$COMPOSE_ROOT/$2" && docker-compose logs -f "${@:3}"
    ;;

  start)
    require_meta
    if [[ -n "${2:-}" ]]; then
      registry_has "$2" || { echo -e "${RED}Error:${NC} '$2' not in registry" >&2; exit 1; }
      echo -e "${BLUE}Starting${NC} $2..."
      systemctl start "docker-compose-$2"
    else
      echo -e "${BLUE}Starting all services in parallel...${NC}"
      pids=(); names=()
      while read -r name; do
        systemctl start "docker-compose-$name" 2>/dev/null &
        pids+=($!); names+=("$name")
      done < <(registry_services)
      failed=0
      for i in "${!pids[@]}"; do
        if wait "${pids[$i]}" 2>/dev/null; then
          echo -e "  ${GREEN}✓${NC} ${names[$i]}"
        else
          echo -e "  ${RED}!${NC} ${names[$i]} (failed)"
          failed=$((failed + 1))
        fi
      done
      echo -e "${GREEN}Done.${NC} $failed service(s) failed to start."
    fi
    ;;

  stop)
    require_meta
    if [[ -n "${2:-}" ]]; then
      registry_has "$2" || { echo -e "${RED}Error:${NC} '$2' not in registry" >&2; exit 1; }
      echo -e "${BLUE}Stopping${NC} $2..."
      systemctl stop "docker-compose-$2"
    else
      echo -e "${BLUE}Stopping all services in parallel...${NC}"
      pids=(); names=()
      while read -r name; do
        systemctl stop "docker-compose-$name" 2>/dev/null &
        pids+=($!); names+=("$name")
      done < <(registry_services)
      failed=0
      for i in "${!pids[@]}"; do
        if wait "${pids[$i]}" 2>/dev/null; then
          echo -e "  ${GREEN}✓${NC} ${names[$i]}"
        else
          echo -e "  ${YELLOW}!${NC} ${names[$i]} (already stopped or failed)"
          failed=$((failed + 1))
        fi
      done
      echo -e "${GREEN}Done.${NC} $failed service(s) were already stopped or failed."
    fi
    ;;

  restart)
    require_meta
    [[ -n "${2:-}" ]] || { echo "Usage: compose-manage restart <service>" >&2; exit 1; }
    registry_has "$2" || { echo -e "${RED}Error:${NC} '$2' not in registry" >&2; exit 1; }
    echo -e "${BLUE}Restarting${NC} $2..."
    systemctl restart "docker-compose-$2"
    ;;

  start-group)
    require_meta
    [[ -n "${2:-}" ]] || { echo "Usage: compose-manage start-group <backup-group>" >&2; exit 1; }
    group_exists "$2" || { echo -e "${RED}Error:${NC} backup group '$2' not found in registry" >&2; exit 1; }
    echo -e "${BLUE}Starting all services in backup group${NC} $2..."
    failed=0
    while read -r name; do
      echo -e "${BLUE}Starting${NC} $name..."
      systemctl start "docker-compose-$name" || { echo -e "  ${RED}!${NC} $name (failed)"; failed=$((failed + 1)); }
    done < <(group_services "$2")
    [[ $failed -eq 0 ]] && echo -e "${GREEN}Done.${NC}" || echo -e "${RED}Done. $failed service(s) failed to start.${NC}"
    ;;

  stop-group)
    require_meta
    [[ -n "${2:-}" ]] || { echo "Usage: compose-manage stop-group <backup-group>" >&2; exit 1; }
    group_exists "$2" || { echo -e "${RED}Error:${NC} backup group '$2' not found in registry" >&2; exit 1; }
    echo -e "${BLUE}Stopping all services in backup group${NC} $2..."
    failed=0
    while read -r name; do
      echo -e "${BLUE}Stopping${NC} $name..."
      systemctl stop "docker-compose-$name" || { echo -e "  ${YELLOW}!${NC} $name (already stopped or failed)"; failed=$((failed + 1)); }
    done < <(group_services "$2")
    echo -e "${GREEN}Done.${NC}"
    ;;

  start-container)
    require_meta
    [[ -n "${2:-}" && -n "${3:-}" ]] || { echo "Usage: compose-manage start-container <service> <container>" >&2; exit 1; }
    registry_has "$2" || { echo -e "${RED}Error:${NC} '$2' not in registry" >&2; exit 1; }
    echo -e "${BLUE}Starting container${NC} $3 in $2..."
    cd "$COMPOSE_ROOT/$2" && docker-compose up -d "$3"
    ;;

  stop-container)
    require_meta
    [[ -n "${2:-}" && -n "${3:-}" ]] || { echo "Usage: compose-manage stop-container <service> <container>" >&2; exit 1; }
    registry_has "$2" || { echo -e "${RED}Error:${NC} '$2' not in registry" >&2; exit 1; }
    echo -e "${BLUE}Stopping container${NC} $3 in $2..."
    cd "$COMPOSE_ROOT/$2" && docker-compose stop "$3"
    ;;

  exec)
    require_meta
    [[ -n "${2:-}" && -n "${3:-}" ]] || { echo "Usage: compose-manage exec <service> <container> <cmd...>" >&2; exit 1; }
    registry_has "$2" || { echo -e "${RED}Error:${NC} '$2' not in registry" >&2; exit 1; }
    cd "$COMPOSE_ROOT/$2" && docker-compose exec "$3" "${@:4}"
    ;;

  ps)
    require_meta
    if [[ -n "${2:-}" ]]; then
      registry_has "$2" || { echo -e "${RED}Error:${NC} '$2' not in registry" >&2; exit 1; }
      cd "$COMPOSE_ROOT/$2" && docker-compose ps
    else
      docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    fi
    ;;

  pull)
    require_meta
    shift
    do_up=false
    if [[ "${1:-}" == "--up" ]]; then do_up=true; shift; fi

    if [[ $# -eq 0 ]]; then
      echo -e "${BLUE}Pulling images for all services...${NC}"
      while read -r name; do
        echo -e "${YELLOW}=== $name ===${NC}"
        cd "$COMPOSE_ROOT/$name" && sudo -u dock docker compose pull
        if [[ $do_up == true ]] && [[ $(systemctl is-active "docker-compose-$name" 2>/dev/null) == active ]]; then
          echo -e "${BLUE}Bringing up${NC} $name..."
          sudo -u dock docker compose up -d --remove-orphans
        fi
      done < <(registry_services)
      echo -e "${GREEN}All images updated${NC}"
    else
      for name in "$@"; do
        registry_has "$name" || { echo -e "${RED}Error:${NC} '$name' not in registry" >&2; exit 1; }
        echo -e "${BLUE}Pulling${NC} $name..."
        cd "$COMPOSE_ROOT/$name" && sudo -u dock docker compose pull
        if [[ $do_up == true ]] && [[ $(systemctl is-active "docker-compose-$name" 2>/dev/null) == active ]]; then
          echo -e "${BLUE}Bringing up${NC} $name..."
          sudo -u dock docker compose up -d --remove-orphans
        fi
      done
    fi
    ;;

  unlock)
    if [[ -f /etc/compose-unlocked ]]; then
      echo -e "${GREEN}Already unlocked.${NC}"
    else
      touch /etc/compose-unlocked
      systemctl start compose-unlocked.target
      echo -e "${GREEN}Unlocked. Services will now start.${NC}"
    fi
    ;;

  lock)
    rm -f /etc/compose-unlocked
    echo -e "${YELLOW}Locked. Services will not auto-start on next boot.${NC}"
    ;;

  *)
    echo -e "${BLUE}Docker Compose Services Manager${NC}"
    echo ""
    echo "Usage: $0 {command} [arguments]"
    echo ""
    echo -e "${YELLOW}Service Management:${NC}"
    echo "  list                     - List all registered services and status"
    echo "  status [service]         - Show status of service(s)"
    echo "  start [service]          - Start a service, or all services in parallel"
    echo "  stop [service]           - Stop a service, or all services in parallel"
    echo "  restart <service>        - Restart a service"
    echo "  start-group <group>      - Start all services in a backup group"
    echo "  stop-group <group>       - Stop all services in a backup group"
    echo ""
    echo -e "${YELLOW}Container Operations:${NC}"
    echo "  start-container <service> <container> - Start a specific container"
    echo "  stop-container <service> <container>  - Stop a specific container"
    echo "  logs <service> [container] - Follow logs"
    echo "  exec <service> <container> <cmd...>   - Execute command in container"
    echo "  ps [service]             - Show running containers"
    echo "  pull [--up] [services...]  - Pull images (--up to restart if running)"
    echo ""
    echo -e "${YELLOW}Boot Control:${NC}"
    echo "  unlock                   - Create unlock file so services start on boot"
    echo "  lock                     - Remove unlock file (services won't auto-start)"
    ;;
esac
