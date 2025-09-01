#!/usr/bin/env bash
set -e

CONFIG_PATH=${CONFIG_PATH:-/config/AdGuardHome.yaml}
SERVER_NAME=${SERVER_NAME:?You must set SERVER_NAME env}
ADGUARD_CONTAINER_NAME=${ADGUARD_CONTAINER_NAME:-adguard}

echo "Waiting for AdGuardHome.yaml to appear..."
while [ ! -f "$CONFIG_PATH" ]; do
  sleep 1
done

echo "Modifying AdGuardHome.yaml..."

# enable unencrypted DoH
sed -i 's/allow_unencrypted_doh: false/allow_unencrypted_doh: true/' "$CONFIG_PATH"

# replace or insert server_name
if grep -qE '^\s*server_name:' "$CONFIG_PATH"; then
  sed -i "s/^\s*server_name:.*/  server_name: \"$SERVER_NAME\"/" "$CONFIG_PATH"
else
  echo "  server_name: \"$SERVER_NAME\"" >> "$CONFIG_PATH"
fi

# enable TLS by replacing 'enabled: false' under the 'tls:' block
sed -i '/^tls:/,/^[^[:space:]]/ s/enabled: false/enabled: true/' "$CONFIG_PATH"

echo "Restarting AdGuard container: $ADGUARD_CONTAINER_NAME..."
docker restart "$ADGUARD_CONTAINER_NAME"

echo "Done."
