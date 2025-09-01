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
    if [ -n "$2" ]; then
      echo -e "${BLUE}Starting${NC} $2..."
      systemctl start "docker-compose-$2"
    else
      echo "Usage: compose-manage start <service-name>"
      exit 1
    fi
    ;;
  stop)
    if [ -n "$2" ]; then
      echo -e "${BLUE}Stopping${NC} $2..."
      systemctl stop "docker-compose-$2"
    else
      echo "Usage: compose-manage stop <service-name>"
      exit 1
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
  *)
    echo -e "${BLUE}Docker Compose Services Manager${NC}"
    echo ""
    echo "Usage: $0 {command} [arguments]"
    echo ""
    echo -e "${YELLOW}Service Management:${NC}"
    echo "  list                     - List all available services"
    echo "  status [service]         - Show status of service(s)"
    echo "  start <service>          - Start a service"
    echo "  stop <service>           - Stop a service" 
    echo "  restart <service>        - Restart a service"
    echo "  enable <service>         - Enable auto-start on boot"
    echo "  disable <service>        - Disable auto-start on boot"
    echo ""
    echo -e "${YELLOW}Container Operations:${NC}"
    echo "  logs <service> [container] - Follow logs"
    echo "  exec <service> <container> <cmd> - Execute command in container"
    echo "  ps [service]             - Show running containers"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  compose-manage list"
    echo "  compose-manage start nginx"
    echo "  compose-manage logs postgres"
    echo "  compose-manage exec nginx web bash"
    ;;
esac