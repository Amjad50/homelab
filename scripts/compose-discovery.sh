#!/bin/bash

COMPOSE_ROOT="/home/amjad/docker-services"
SYSTEMD_DIR="/etc/systemd/system"

# Create base directory if it doesn't exist
mkdir -p "$COMPOSE_ROOT"

# Remove old auto-generated service files
rm -f "$SYSTEMD_DIR"/docker-compose-*.service

# Discover and create service files for each compose project
if [ -d "$COMPOSE_ROOT" ]; then
  for service_dir in "$COMPOSE_ROOT"/*; do
    if [ -d "$service_dir" ] && [ -f "$service_dir/docker-compose.yml" ]; then
      service_name=$(basename "$service_dir")
      service_file="$SYSTEMD_DIR/docker-compose-$service_name.service"
      
      echo "Creating systemd service for: $service_name"
      
      # Create systemd service file
      cat > "$service_file" << EOF
[Unit]
Description=Docker Compose: $service_name
After=docker.service network.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=$service_dir
ExecStartPre=/run/current-system/sw/bin/test -f docker-compose.yml
ExecStartPre=/run/current-system/sw/bin/docker-compose pull --ignore-pull-failures
ExecStart=/run/current-system/sw/bin/docker-compose up -d --remove-orphans
ExecStop=/run/current-system/sw/bin/docker-compose down --remove-orphans
ExecReload=/run/current-system/sw/bin/docker-compose restart
TimeoutStartSec=300
TimeoutStopSec=60
Restart=on-failure
RestartSec=10s
User=amjad
Group=docker

[Install]
WantedBy=multi-user.target
EOF
      
      echo "Created service file: $service_file"
    fi
  done
fi

# Reload systemd to pick up new services
systemctl daemon-reload

echo "Service discovery complete. Found $(ls -1 "$SYSTEMD_DIR"/docker-compose-*.service 2>/dev/null | wc -l) compose services."