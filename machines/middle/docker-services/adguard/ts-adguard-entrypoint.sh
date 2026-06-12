#!/bin/sh
set -eu

API_KEY_FILE="${HEADSCALE_API_KEY_FILE:-/run/secrets/headplane-headscale-api-key}"
HEADSCALE_URL="${HEADSCALE_URL:-http://headscale:8080}"

API_KEY="$(cat "$API_KEY_FILE")"

EXPIRATION="$(date -u -d "@$(( $(date +%s) + 3600 ))" '+%Y-%m-%dT%H:%M:%SZ')"

RESPONSE="$(curl -fsSL -X POST "${HEADSCALE_URL}/api/v1/preauthkey" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"reusable\":true,\"ephemeral\":false,\"aclTags\":[\"tag:dns\"],\"expiration\":\"${EXPIRATION}\"}")"

TS_AUTHKEY="$(printf '%s' "$RESPONSE" | jq -er '.preAuthKey.key')"
export TS_AUTHKEY

exec /usr/local/bin/containerboot
