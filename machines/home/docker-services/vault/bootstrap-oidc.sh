#!/usr/bin/env sh

set -eu

VAULT_PUBLIC_ADDR="https://vault.home.amsh.dev"
VAULT_OIDC_DISCOVERY_URL="https://idm.home.amsh.dev/oauth2/openid/vault"
VAULT_OIDC_CLIENT_ID="vault"
VAULT_OIDC_ROLE="reader"
VAULT_OIDC_ADMIN_GROUP="vault-admins"
VAULT_OIDC_MANAGER_GROUP="vault-managers"
VAULT_OIDC_VERBOSE_LOGGING="true"
VAULT_BOOTSTRAP_WAIT_SECONDS="600"
VAULT_BOOTSTRAP_POLL_SECONDS="5"

require_env() {
  var_name="$1"
  eval "value=\${$var_name:-}"
  if [ -z "$value" ]; then
    echo "Missing required environment variable: $var_name" >&2
    exit 1
  fi
}

run_vault() {
  vault "$@"
}

oidc_accessor() {
  run_vault auth list \
    | awk '$1 == "oidc/" {print $3}'
}

ensure_group_alias() {
  GROUP_NAME="$1"
  POLICY_NAME="$2"
  ALIAS_OUTPUT=""
  OIDC_ACCESSOR="$(oidc_accessor)"
  if [ -z "$OIDC_ACCESSOR" ]; then
    echo "Failed to determine oidc auth accessor." >&2
    return 1
  fi

  GROUP_ID="$(run_vault read -field=id "identity/group/name/$GROUP_NAME" 2>/dev/null || true)"
  if [ -z "$GROUP_ID" ]; then
    GROUP_ID="$(run_vault write -field=id identity/group \
      name="$GROUP_NAME" \
      type="external" \
      policies="$POLICY_NAME")"
  else
    run_vault write identity/group/id/"$GROUP_ID" \
      name="$GROUP_NAME" \
      type="external" \
      policies="$POLICY_NAME" >/dev/null
  fi

  ALIAS_OUTPUT="$(run_vault write identity/group-alias \
    name="$GROUP_NAME" \
    mount_accessor="$OIDC_ACCESSOR" \
    canonical_id="$GROUP_ID" 2>&1)" || {
      printf '%s\n' "$ALIAS_OUTPUT" | grep -q 'combination of mount and group alias name is already in use' && return 0
      printf '%s\n' "$ALIAS_OUTPUT" >&2
      return 1
    }
}

disable_unwanted_auth_methods() {
  run_vault auth list \
    | awk 'NR > 2 {print $1}' \
    | while read -r auth_path; do
        case "$auth_path" in
          token/|oidc/)
            ;;
          *)
            run_vault auth disable "$auth_path"
            ;;
        esac
      done
}

status_json() {
  status_output=""
  status_code=0
  status_output="$(vault status -format=json 2>/dev/null)" && status_code=0 || status_code=$?

  if [ "$status_code" -eq 0 ] || [ "$status_code" -eq 2 ]; then
    printf '%s\n' "$status_output"
    return 0
  fi

  return 1
}

wait_for_unsealed_vault() {
  deadline=0
  now=0
  status=""
  initialized=""
  sealed=""
  deadline=$(( $(date +%s) + VAULT_BOOTSTRAP_WAIT_SECONDS ))

  while true; do
    now="$(date +%s)"
    if [ "$now" -ge "$deadline" ]; then
      echo "Timed out waiting for Vault to become initialized and unsealed." >&2
      return 1
    fi

    if status="$(status_json)"; then
      initialized="$(printf '%s\n' "$status" | sed -n 's/.*"initialized":[[:space:]]*\(true\|false\).*/\1/p' | head -n1)"
      sealed="$(printf '%s\n' "$status" | sed -n 's/.*"sealed":[[:space:]]*\(true\|false\).*/\1/p' | head -n1)"

      if [ "$initialized" = "true" ] && [ "$sealed" = "false" ]; then
        return 0
      fi
    fi

    sleep "$VAULT_BOOTSTRAP_POLL_SECONDS"
  done
}

require_env VAULT_TOKEN
require_env VAULT_OIDC_CLIENT_SECRET

wait_for_unsealed_vault

if ! run_vault secrets list -format=json | grep -q '"secret/"'; then
  run_vault secrets enable -path=secret kv-v2
fi

cat <<'EOF' | run_vault policy write homelab-admin -
# Full control over the KV v2 secret mount used in this homelab.
path "secret/data/*" {
  capabilities = ["create", "read", "update", "delete", "list", "patch", "sudo"]
}

path "secret/metadata/*" {
  capabilities = ["create", "read", "update", "delete", "list", "patch", "sudo"]
}

# Auth methods and login configuration.
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "patch", "sudo"]
}

path "sys/auth" {
  capabilities = ["read"]
}

path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "patch", "sudo"]
}

# Policies and ACL management.
path "sys/policies/acl" {
  capabilities = ["read", "list"]
}

path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list", "patch", "sudo"]
}

# Identity entities, groups, and aliases.
path "identity/*" {
  capabilities = ["create", "read", "update", "delete", "list", "patch", "sudo"]
}

# Secrets engines and general system administration.
path "sys/mounts" {
  capabilities = ["read"]
}

path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "patch", "sudo"]
}

path "sys/*" {
  capabilities = ["create", "read", "update", "delete", "list", "patch", "sudo"]
}
EOF

cat <<'EOF' | run_vault policy write reader -
path "secret/data/*" {
  capabilities = ["read"]
}

path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
EOF

cat <<'EOF' | run_vault policy write manager -
path "secret/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

if ! run_vault auth list | grep -q '^oidc/'; then
  run_vault auth enable oidc
fi

run_vault auth tune -listing-visibility=unauth oidc/

disable_unwanted_auth_methods
ensure_group_alias "$VAULT_OIDC_ADMIN_GROUP" "homelab-admin"
ensure_group_alias "$VAULT_OIDC_MANAGER_GROUP" "manager"

run_vault write auth/oidc/config \
  oidc_discovery_url="$VAULT_OIDC_DISCOVERY_URL" \
  oidc_client_id="$VAULT_OIDC_CLIENT_ID" \
  oidc_client_secret="$VAULT_OIDC_CLIENT_SECRET" \
  jwt_supported_algs="ES256" \
  default_role="$VAULT_OIDC_ROLE"

run_vault delete auth/oidc/role/homelab-admin >/dev/null 2>&1 || true
run_vault delete auth/oidc/role/"$VAULT_OIDC_ROLE" >/dev/null 2>&1 || true

cat <<EOF | run_vault write auth/oidc/role/"$VAULT_OIDC_ROLE" -
{
  "role_type": "oidc",
  "user_claim": "preferred_username",
  "bound_audiences": ["$VAULT_OIDC_CLIENT_ID"],
  "allowed_redirect_uris": [
    "$VAULT_PUBLIC_ADDR/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ],
  "verbose_oidc_logging": $VAULT_OIDC_VERBOSE_LOGGING,
  "oidc_scopes": ["openid", "profile", "email", "groups_name"],
  "groups_claim": "groups",
  "token_policies": ["default", "reader"]
}
EOF

echo "Vault OIDC bootstrap complete."
echo "Role: $VAULT_OIDC_ROLE"
echo "Admin group claim: $VAULT_OIDC_ADMIN_GROUP"
echo "Manager group claim: $VAULT_OIDC_MANAGER_GROUP"
