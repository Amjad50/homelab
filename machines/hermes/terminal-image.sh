#!/usr/bin/env bash
set -euo pipefail

dockerfile=$1
image=$2

if systemctl is-active --quiet hermes-agent.service; then
  echo "Stop hermes-agent before rebuilding its terminal image" >&2
  exit 1
fi

# Prefer fresh base images, but allow an already built image when offline.
if docker build --pull --tag "$image" - < "$dockerfile"; then
  current_id=$(docker image inspect --format '{{.Id}}' "$image")
  for cid in $(docker ps -aq --filter label=hermes-agent=1); do
    image_ref=$(docker inspect --format '{{.Config.Image}}' "$cid")
    case "$image_ref" in
      hermes-exec:*)
        container_image_id=$(docker inspect --format '{{.Image}}' "$cid")
        if [ "$container_image_id" != "$current_id" ]; then
          docker rm -f "$cid"
        fi
        ;;
    esac
  done
elif ! docker image inspect "$image" >/dev/null 2>&1; then
  echo "Terminal image build failed and no cached image is available" >&2
  exit 1
else
  echo "Terminal image build failed; using the existing image" >&2
fi
