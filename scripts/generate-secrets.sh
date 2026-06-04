#!/usr/bin/env bash

# Secrets Generator
# Generates and encrypts secrets for middle, home, and home-vm machines
#
# Requires .sops.yaml to be present in the repo root — keys are read from there.
# No AGE_KEY env vars needed; sops auto-selects recipients based on output file path.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are available
check_dependencies() {
    local missing_tools=()

    if ! command -v sops &>/dev/null; then
        missing_tools+=("sops")
    fi

    if ! command -v openssl &>/dev/null; then
        missing_tools+=("openssl")
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install with: nix-shell -p sops openssl"
        exit 1
    fi
}

# Load environment variables from .env file
# Supports unquoted, single-quoted, double-quoted, and multiline double-quoted values
dotenv() {
    if [ -f "$1" ]; then
        # Extract key names defined in the file (skip comments and blank lines)
        local keys
        mapfile -t keys < <(grep -E '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "$1" | sed 's/=.*//')

        # Build a script file for the child bash to avoid quoting issues in print_cmd
        local tmp_script
        tmp_script=$(mktemp)
        {
            echo "set -a; source \"$1\"; set +a"
            for key in "${keys[@]}"; do
                # Use a here-doc per key to avoid outer-shell expansion of \n
                cat <<EOF
v="\${${key}}"
v="\${v//$'\n'/NEWLINE_PLACEHOLDER}"
printf '%s=%s\n' "${key}" "\$v"
EOF
            done
        } > "$tmp_script"

        while IFS= read -r line; do
            local k="${line%%=*}"
            local v="${line#*=}"
            export "$k"="${v//NEWLINE_PLACEHOLDER/$'\n'}"
        done < <(bash "$tmp_script" 2>/dev/null)

        rm -f "$tmp_script"

        log_info "Loaded environment variables from $1"
    else
        log_warn "No .env file found, using existing environment variables"
    fi
}

# Define secrets (VAR_NAME|TYPE|TARGET|YAML_KEY|GENERATOR)
# TYPE: req (required), gen (generatable)
# TARGET: middle, home, both, none
# GENERATOR: bash command to generate value
SECRETS=(
    # Connection tokens
    "RATHOLE_TOKEN|gen|both|rathole-token|openssl rand -hex 32"
    "RATHOLE_NOISE_PRIVATE|req|middle|rathole-noise-private|"
    "RATHOLE_NOISE_PUBLIC|req|home|rathole-noise-public|"

    # OAuth and Auth
    "OAUTH2_PROXY_CLIENT_SECRET|req|middle|oauth2-proxy-client-secret|"
    "OAUTH2_PROXY_COOKIE_SECRET|gen|middle|oauth2-proxy-cookie-secret|openssl rand -base64 32 | tr -d '=+/' | cut -c1-32"

    # coturn TURN relay (shared static auth secret for TURN REST API)
    "COTURN_STATIC_AUTH_SECRET|gen|middle|coturn-static-auth-secret|openssl rand -hex 32"

    # Services - Home
    "FIREFLY_APP_KEY|gen|home|firefly-app-key|echo \"base64:\$(openssl rand -base64 32)\""
    "FIREFLY_DB_PASSWORD|gen|home|firefly-db-password|openssl rand -base64 32"
    "BLINKO_NEXTAUTH_SECRET|gen|home|blinko-nextauth-secret|openssl rand -base64 32"
    "BLINKO_DB_PASSWORD|gen|home|blinko-db-password|openssl rand -base64 32 | tr -d '/+=' | cut -c1-32"
    "MEMOS_TELEGRAM_BOT_TOKEN|req|home|memos-telegram-bot-token|"
    "MINIO_ROOT_PASSWORD|req|home|minio-root-password|"
    "N8N_DB_PASSWORD|gen|home|n8n-db-password|openssl rand -base64 32 | tr -d '/+=' | cut -c1-32"
    "N8N_ENCRYPTION_KEY|gen|home|n8n-encryption-key|openssl rand -base64 32 | tr -d '/+=' | cut -c1-32"
    "WUD_OPENID_CLIENT_SECRET|req|home|wud-openid-client-secret|"
    "SOLIDTIME_APP_KEY|req|home|solidtime-app-key|"
    "SOLIDTIME_PASSPORT_PRIVATE_KEY|req|home|solidtime-passport-private-key|"
    "SOLIDTIME_PASSPORT_PUBLIC_KEY|req|home|solidtime-passport-public-key|"
    "SOLIDTIME_SUPER_ADMINS|req|home|solidtime-super-admins|"
    "SOLIDTIME_DB_PASSWORD|gen|home|solidtime-db-password|openssl rand -base64 32 | tr -d '/+=' | cut -c1-32"
    "OPENAI_API_KEY|req|home|openai-api-key|"
    "LINKWARDEN_NEXTAUTH_SECRET|gen|home|linkwarden-nextauth-secret|openssl rand -base64 32 | tr -d '/+=' | cut -c1-32"
    "LINKWARDEN_DB_PASSWORD|gen|home|linkwarden-db-password|openssl rand -base64 32 | tr -d '/+=' | cut -c1-32"
    "LINKWARDEN_KANIDM_CLIENT_SECRET|req|home|linkwarden-kanidm-client-secret|"
    "FRESHRSS_KANIDM_CLIENT_SECRET|req|home|freshrss-kanidm-client-secret|"
    "FRESHRSS_CRYPTO_SECRET|gen|home|freshrss-crypto-secret|openssl rand -base64 32 | tr -d '\n/+=' | cut -c1-32"
    "IMMICH_DB_PASSWORD|gen|home|immich-db-password|openssl rand -base64 32 | tr -d '/+=' | cut -c1-32"
    "INFISICAL_DB_PASSWORD|gen|home|infisical-db-password|openssl rand -base64 32 | tr -d '/+=' | cut -c1-32"
    "INFISICAL_AUTH_SECRET|gen|home|infisical-auth-secret|openssl rand -base64 32"
    "INFISICAL_ENCRYPTION_KEY|gen|home|infisical-encryption-key|openssl rand -hex 16"
    "INFISICAL_GITHUB_OAUTH_CLIENT_ID|req|home|infisical-github-oauth-client-id|"
    "INFISICAL_GITHUB_OAUTH_CLIENT_SECRET|req|home|infisical-github-oauth-client-secret|"
    "INFISICAL_GITHUB_APP_CLIENT_ID|req|home|infisical-github-app-client-id|"
    "INFISICAL_GITHUB_APP_CLIENT_SECRET|req|home|infisical-github-app-client-secret|"
    "INFISICAL_GITHUB_APP_SLUG|req|home|infisical-github-app-slug|"
    "INFISICAL_GITHUB_APP_ID|req|home|infisical-github-app-id|"
    "INFISICAL_GITHUB_APP_PRIVATE_KEY|req|home|infisical-github-app-private-key|"
    "OPENCLOUD_ONLYOFFICE_TOKEN|gen|home|opencloud-onlyoffice-token|openssl rand -hex 32"
    "NORISH_DB_PASSWORD|gen|home|norish-db-password|openssl rand -base64 32 | tr -d '/+=' | cut -c1-32"
    "NORISH_MASTER_KEY|gen|home|norish-master-key|openssl rand -base64 32"
    "NORISH_KANIDM_CLIENT_SECRET|req|home|norish-kanidm-client-secret|"
    "PLANE_DB_PASSWORD|gen|home|plane-db-password|openssl rand -hex 32"
    "PLANE_SECRET_KEY|gen|home|plane-secret-key|openssl rand -base64 48 | tr -d '\n/+=' | cut -c1-50"
    "PLANE_LIVE_SERVER_SECRET|gen|home|plane-live-server-secret|openssl rand -hex 32"
    "PLANE_RABBITMQ_USER|gen|home|plane-rabbitmq-user|openssl rand -hex 8"
    "PLANE_RABBITMQ_PASSWORD|gen|home|plane-rabbitmq-password|openssl rand -hex 32"
    "PLANE_MINIO_ACCESS_KEY|gen|home|plane-minio-access-key|openssl rand -hex 10"
    "PLANE_MINIO_SECRET_KEY|gen|home|plane-minio-secret-key|openssl rand -hex 20"
    "PLANE_GITHUB_CLIENT_ID|req|home|plane-github-client-id|"
    "PLANE_GITHUB_CLIENT_SECRET|req|home|plane-github-client-secret|"

    # Shared SMTP credentials (host/port/user/pass shared; from-address/name set per service)
    "SMTP_HOST|req|home|smtp-host|"
    "SMTP_PORT|req|home|smtp-port|"
    "SMTP_USERNAME|req|home|smtp-username|"
    "SMTP_PASSWORD|req|home|smtp-password|"

    # Infrastructure and Backup
    "RESTIC_REPOSITORY_PASSWORD|gen|both|restic-repository-password|openssl rand -base64 64 | tr -d '\n/+=' | cut -c1-64"
    "BACKUP_AWS_ACCESS_KEY_ID|req|both|backup-aws-access-key-id|"
    "BACKUP_AWS_SECRET_ACCESS_KEY|req|both|backup-aws-secret-access-key|"
    "CLOUDFLARE_EMAIL|req|middle|cloudflare-email|"
    "CLOUDFLARE_DNS_API_TOKEN|req|middle|cloudflare-dns-api-token|"
    "CLOUDFLARE_ZONE_API_TOKEN|req|middle|cloudflare-zone-api-token|"

    # Beszel monitoring
    "BESZEL_HUB_PUBLIC_KEY|req|both|beszel-hub-public-key|"
    "BESZEL_HOME_AGENT_TOKEN|req|home|beszel-home-agent-token|"
    "BESZEL_MIDDLE_AGENT_TOKEN|req|middle|beszel-middle-agent-token|"

    # Ntfy
    "NTFY_TOKEN|req|both|ntfy-token|"
    "NTFY_FIRST_PROVISIONED_USERS|req|middle|ntfy-first-provisioned-users|"
)

# Process secrets: check required and generate missing
process_secrets() {
    local missing_vars=()
    GENERATED_COUNT=0
    GENERATED_VARS=()

    for secret in "${SECRETS[@]}"; do
        IFS='|' read -r var_name type target yaml_key generator <<<"$secret"

        local current_val="${!var_name:-}"

        if [ "$type" = "req" ]; then
            if [ -z "$current_val" ]; then
                missing_vars+=("$var_name")
            fi
        elif [ "$type" = "gen" ]; then
            if [ -z "$current_val" ]; then
                log_info "Generating new $var_name"
                # Execute generator and capture value
                local new_val
                new_val=$(eval "$generator")
                export "$var_name"="$new_val"
                GENERATED_COUNT=$((GENERATED_COUNT + 1))
                GENERATED_VARS+=("$var_name")
            else
                log_info "Using provided $var_name"
            fi
        fi
    done

    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        echo
        log_info "Set them in .env or export them before running this script."
        exit 1
    fi
}

# Create secrets YAML content for a machine
generate_machine_yaml() {
    local machine="$1"

    for secret in "${SECRETS[@]}"; do
        IFS='|' read -r var_name type target yaml_key generator <<<"$secret"

        if [[ "$target" == "$machine" || "$target" == "both" ]]; then
            local val="${!var_name}"

            if [[ "$val" == *$'\n'* ]]; then
                # Multiline: use YAML literal block scalar (strip trailing newline first)
                val="${val%$'\n'}"
                echo "$yaml_key: |"
                while IFS= read -r l; do
                    echo "  $l"
                done <<< "$val"
            else
                echo "$yaml_key: \"$val\""
            fi
        fi
    done
}

# Encrypt secrets for a machine
# Recipients are determined automatically from .sops.yaml based on output_file path.
encrypt_secrets() {
    local machine="$1"
    # home-vm shares the same secret values as home (it's a replica)
    local source_machine="${2:-$machine}"
    local output_file="machines/$machine/secrets.yaml"

    log_info "Encrypting secrets for $machine..."

    mkdir -p "machines/$machine"

    # sops matches the INPUT file path against .sops.yaml creation_rules.
    # Pipe through process substitution isn't supported, so use a named pipe
    # trick: generate plaintext, pipe to sops encrypt with config path override.
    generate_machine_yaml "$source_machine" | \
        sops --encrypt --input-type yaml \
             --config "$(pwd)/.sops.yaml" \
             --filename-override "$output_file" \
             /dev/stdin >"$output_file"

    if [ $? -eq 0 ]; then
        log_info "✓ Created $output_file"
    else
        log_error "✗ Failed to create $output_file"
        return 1
    fi
}

# Verify encrypted files can be decrypted
verify_secrets() {
    local machine="$1"
    local secrets_file="machines/$machine/secrets.yaml"

    log_info "Verifying $machine secrets..."

    if [ ! -f "$secrets_file" ]; then
        log_error "Secrets file not found: $secrets_file"
        return 1
    fi

    if sops --decrypt "$secrets_file" >/dev/null 2>&1; then
        log_info "✓ $machine secrets are valid"
    else
        log_warn "⚠ Cannot verify $machine secrets (age key not available locally)"
    fi
}

# Main function
main() {
    echo "=== Secrets Generator ==="
    echo

    check_dependencies
    dotenv .env
    process_secrets

    echo
    log_info "Status of secrets:"
    for secret in "${SECRETS[@]}"; do
        IFS='|' read -r var_name type target yaml_key generator <<<"$secret"
        local val="${!var_name}"
        echo "  - $var_name: ${val:0:16}..."
    done
    echo

    # Encrypt for all machines
    # VMs use the same secret values as their physical counterparts (they are replicas),
    # but encrypted with the VM host key (as defined in .sops.yaml creation_rules)
    encrypt_secrets "middle"
    encrypt_secrets "home"
    encrypt_secrets "home-vm" "home"
    encrypt_secrets "middle-vm" "middle"

    echo
    log_info "Verifying encrypted files..."
    verify_secrets "middle"
    verify_secrets "home"
    verify_secrets "home-vm"
    verify_secrets "middle-vm"

    echo
    if [ "$GENERATED_COUNT" -gt 0 ]; then
        log_info "✅ Secrets generation complete! ($GENERATED_COUNT new secrets generated)"
    else
        log_info "✅ Secrets generation complete! (No new secrets generated)"
    fi
    echo
    log_info "Generated files:"
    echo "  - machines/middle/secrets.yaml"
    echo "  - machines/home/secrets.yaml"
    echo "  - machines/home-vm/secrets.yaml"
    echo "  - machines/middle-vm/secrets.yaml"

    # Print only secrets generated this run in .env format for easy copy-paste
    if [ "$GENERATED_COUNT" -gt 0 ]; then
        echo
        log_info "Newly generated secrets (add to .env to reuse next run):"
        echo "---"
        for var_name in "${GENERATED_VARS[@]}"; do
            echo "$var_name=${!var_name}"
        done
        echo "---"
    fi

    # Show all secrets (optional)
    if [ "${SHOW_SECRETS:-false}" = "true" ]; then
        echo
        log_warn "All secrets (SHOW_SECRETS=true):"
        for secret in "${SECRETS[@]}"; do
            IFS='|' read -r var_name type target yaml_key generator <<<"$secret"
            echo "$var_name=${!var_name}"
        done
    fi
}

# Run main function
main "$@"
