#!/usr/bin/env bash

COMPOSE_ROOT="/opt/docker-services"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

case "$1" in
  list)
    echo -e "${BLUE}Available services in $COMPOSE_ROOT:${NC}"
    if [ -d "$COMPOSE_ROOT" ]; then
      for service in "$COMPOSE_ROOT"/*; do
        if [ -d "$service" ] && [ -f "$service/docker-compose.yml" ]; then
          name=$(basename "$service")
          status=$(systemctl is-active "docker-compose-$name" 2>/dev/null || echo "not-configured")
          case $status in
            active) echo -e "  ${GREEN}✓${NC} $name (running)" ;;
            inactive) echo -e "  ${RED}✗${NC} $name (stopped)" ;;
            failed) echo -e "  ${RED}!${NC} $name (failed)" ;;
            *) echo -e "  ${YELLOW}?${NC} $name (not configured)" ;;
          esac
        fi
      done
    else
      echo "  Directory $COMPOSE_ROOT does not exist"
    fi
    ;;
  status)
    if [ -n "$2" ]; then
      # Status for specific service
      systemctl status "docker-compose-$2" --no-pager -l
    else
      # Status for all services
      echo -e "${BLUE}Status of all compose services:${NC}"
      for service in "$COMPOSE_ROOT"/*; do
        if [ -d "$service" ] && [ -f "$service/docker-compose.yml" ]; then
          name=$(basename "$service")
          echo -e "\n${YELLOW}=== $name ===${NC}"
          systemctl status "docker-compose-$name" --no-pager -l || echo "Not configured"
        fi
      done
    fi
    ;;
  logs)
    if [ -n "$2" ]; then
      if [ -d "$COMPOSE_ROOT/$2" ]; then
        cd "$COMPOSE_ROOT/$2" && docker-compose logs -f "${@:3}"
      else
        echo -e "${RED}Error:${NC} Service '$2' not found in $COMPOSE_ROOT"
        exit 1
      fi
    else
      echo "Usage: compose-manage logs <service-name> [container-name]"
      exit 1
    fi
    ;;
  start)
    if [ -n "${2:-}" ]; then
      echo -e "${BLUE}Starting${NC} $2..."
      systemctl start "docker-compose-$2"
    else
      echo -e "${BLUE}Starting all services in parallel...${NC}"
      pids=()
      names=()
      for service in "$COMPOSE_ROOT"/*; do
        if [ -d "$service" ] && [ -f "$service/docker-compose.yml" ]; then
          name=$(basename "$service")
          systemctl start "docker-compose-$name" 2>/dev/null &
          pids+=($!)
          names+=("$name")
        fi
      done
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
    if [ -n "${2:-}" ]; then
      echo -e "${BLUE}Stopping${NC} $2..."
      systemctl stop "docker-compose-$2"
    else
      # Stop all services in parallel
      echo -e "${BLUE}Stopping all services in parallel...${NC}"
      pids=()
      names=()
      for service in "$COMPOSE_ROOT"/*; do
        if [ -d "$service" ] && [ -f "$service/docker-compose.yml" ]; then
          name=$(basename "$service")
          systemctl stop "docker-compose-$name" 2>/dev/null &
          pids+=($!)
          names+=("$name")
        fi
      done
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
    if [ -n "$2" ]; then
      echo -e "${BLUE}Restarting${NC} $2..."
      systemctl restart "docker-compose-$2"
    else
      echo "Usage: compose-manage restart <service-name>"
      exit 1
    fi
    ;;
  enable)
    if [ -n "$2" ]; then
      echo -e "${BLUE}Enabling${NC} $2 (auto-start on boot)..."
      systemctl enable "docker-compose-$2"
    else
      echo "Usage: compose-manage enable <service-name>"
      exit 1
    fi
    ;;
  disable)
    if [ -n "$2" ]; then
      echo -e "${BLUE}Disabling${NC} $2 (no auto-start on boot)..."
      systemctl disable "docker-compose-$2"
    else
      echo "Usage: compose-manage disable <service-name>"
      exit 1
    fi
    ;;
  start-container)
    if [ -n "${2:-}" ] && [ -n "${3:-}" ]; then
      if [ -d "$COMPOSE_ROOT/$2" ]; then
        echo -e "${BLUE}Starting container${NC} $3 in $2..."
        cd "$COMPOSE_ROOT/$2" && docker-compose up -d "$3"
      else
        echo -e "${RED}Error:${NC} Service '$2' not found in $COMPOSE_ROOT"
        exit 1
      fi
    else
      echo "Usage: compose-manage start-container <service-name> <container-name>"
      exit 1
    fi
    ;;
  stop-container)
    if [ -n "${2:-}" ] && [ -n "${3:-}" ]; then
      if [ -d "$COMPOSE_ROOT/$2" ]; then
        echo -e "${BLUE}Stopping container${NC} $3 in $2..."
        cd "$COMPOSE_ROOT/$2" && docker-compose stop "$3"
      else
        echo -e "${RED}Error:${NC} Service '$2' not found in $COMPOSE_ROOT"
        exit 1
      fi
    else
      echo "Usage: compose-manage stop-container <service-name> <container-name>"
      exit 1
    fi
    ;;
  exec)
    if [ -n "$2" ] && [ -n "$3" ]; then
      if [ -d "$COMPOSE_ROOT/$2" ]; then
        cd "$COMPOSE_ROOT/$2" && docker-compose exec "$3" "${@:4}"
      else
        echo -e "${RED}Error:${NC} Service '$2' not found in $COMPOSE_ROOT"
        exit 1
      fi
    else
      echo "Usage: compose-manage exec <service-name> <container-name> <command>"
      exit 1
    fi
    ;;
  ps)
    if [ -n "$2" ]; then
      if [ -d "$COMPOSE_ROOT/$2" ]; then
        cd "$COMPOSE_ROOT/$2" && docker-compose ps
      else
        echo -e "${RED}Error:${NC} Service '$2' not found in $COMPOSE_ROOT"
        exit 1
      fi
    else
      # Show all containers
      docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    fi
    ;;
  pull)
    shift  # Remove 'pull' from arguments
    # Check if first argument is '--up' flag
    do_up=false
    if [ "$1" = "--up" ]; then
      do_up=true
      shift
    fi

    if [ $# -eq 0 ]; then
      # Pull images for all services
      echo -e "${BLUE}Pulling images for all services...${NC}"
      for service in "$COMPOSE_ROOT"/*; do
        if [ -d "$service" ] && [ -f "$service/docker-compose.yml" ]; then
          name=$(basename "$service")
          echo -e "${YELLOW}=== $name ===${NC}"
          cd "$service" && sudo -u dock docker compose pull

          # If 'up' flag is set and service is active, bring containers up
          if [ "$do_up" = true ]; then
            status=$(systemctl is-active "docker-compose-$name" 2>/dev/null)
            if [ "$status" = "active" ]; then
              echo -e "${BLUE}Bringing up containers for${NC} $name..."
              sudo -u dock docker compose up -d --remove-orphans
            fi
          fi
        fi
      done
      echo -e "${GREEN}All images updated${NC}"
    else
      # Pull images for specified services
      for service in "$@"; do
        if [ -d "$COMPOSE_ROOT/$service" ]; then
          echo -e "${BLUE}Pulling images for${NC} $service..."
          cd "$COMPOSE_ROOT/$service" && sudo -u dock docker compose pull

          # If 'up' flag is set and service is active, bring containers up
          if [ "$do_up" = true ]; then
            status=$(systemctl is-active "docker-compose-$service" 2>/dev/null)
            if [ "$status" = "active" ]; then
              echo -e "${BLUE}Bringing up containers for${NC} $service..."
              sudo -u dock docker compose up -d --remove-orphans
            fi
          fi
        else
          echo -e "${RED}Error:${NC} Service '$service' not found in $COMPOSE_ROOT"
          exit 1
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
    echo "  list                     - List all available services"
    echo "  status [service]         - Show status of service(s)"
    echo "  start [service]          - Start a service, or all services in parallel if none specified"
    echo "  stop [service]           - Stop a service, or all services in parallel if none specified"
    echo "  restart <service>        - Restart a service"
    echo "  enable <service>         - Enable auto-start on boot"
    echo "  disable <service>        - Disable auto-start on boot"
    echo ""
    echo -e "${YELLOW}Container Operations:${NC}"
    echo "  start-container <service> <container> - Start a specific container within a service"
    echo "  stop-container <service> <container>  - Stop a specific container within a service"
    echo "  logs <service> [container] - Follow logs"
    echo "  exec <service> <container> <cmd> - Execute command in container"
    echo "  ps [service]             - Show running containers"
    echo "  pull [--up] [services...]  - Pull images (add --up to bring up if running)"
    echo "  unlock                   - Create unlock file so services start on boot"
    echo "  lock                     - Remove unlock file (services won't auto-start)"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  compose-manage list"
    echo "  compose-manage start nginx"
    echo "  compose-manage logs postgres"
    echo "  compose-manage exec nginx web bash"
    echo "  compose-manage pull                     # Pull all services"
    echo "  compose-manage pull nginx postgres      # Pull specific services"
    echo "  compose-manage pull --up nginx postgres # Pull and bring up if running"
    ;;
esac
