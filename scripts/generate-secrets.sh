#!/bin/bash

# Secrets Generator
# Generates and encrypts secrets for both middle and home machines
#
# Required environment variables:
# - MIDDLE_AGE_KEY: Age public key for middle server
# - HOME_AGE_KEY: Age public key for home server

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
    
    if ! command -v sops &> /dev/null; then
        missing_tools+=("sops")
    fi
    
    if ! command -v openssl &> /dev/null; then
        missing_tools+=("openssl")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install with: nix-shell -p sops openssl"
        exit 1
    fi
}

# Load environment variables from .env file
dotenv() {
    if [ -f "$1" ]; then
        while IFS='=' read -r key value || [ -n "$key" ]; do
            # Skip comments and empty lines
            if [[ -z "$key" || "$key" =~ ^# ]]; then
                continue
            fi
            # Export variable
            export "$key"="$value"
        done < "$1"
        log_info "Loaded environment variables from $1"
    else
        log_warn "No .env file found, using existing environment variables"
    fi
}

# Check required environment variables
check_env_vars() {
    local missing_vars=()
    
    if [ -z "${MIDDLE_AGE_KEY:-}" ]; then
        missing_vars+=("MIDDLE_AGE_KEY")
    fi
    
    if [ -z "${HOME_AGE_KEY:-}" ]; then
        missing_vars+=("HOME_AGE_KEY")
    fi

    if [ -z "${RATHOLE_NOISE_PRIVATE:-}" ]; then
        missing_vars+=("RATHOLE_NOISE_PRIVATE")
    fi

    if [ -z "${RATHOLE_NOISE_PUBLIC:-}" ]; then
        missing_vars+=("RATHOLE_NOISE_PUBLIC")
    fi

    if [ -z "${OAUTH2_PROXY_CLIENT_SECRET:-}" ]; then
        missing_vars+=("OAUTH2_PROXY_CLIENT_SECRET")
    fi
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        echo
        log_info "Example usage:"
        echo "  export MIDDLE_AGE_KEY=\"age1abc123...\""
        echo "  export HOME_AGE_KEY=\"age1def456...\""
        echo "  $0"
        echo
        log_info "To get age keys from SSH host keys:"
        echo "  ssh user@middle-server \"cat /etc/ssh/ssh_host_ed25519_key.pub\" | ssh-to-age"
        echo "  ssh user@home-server \"cat /etc/ssh/ssh_host_ed25519_key.pub\" | ssh-to-age"
        exit 1
    fi
}

# Generate secrets if not provided
generate_secrets() {
    # Generate rathole token if not provided
    if [ -z "${RATHOLE_TOKEN:-}" ]; then
        RATHOLE_TOKEN=$(openssl rand -hex 32)
        log_info "Generated new rathole token"
    else
        log_info "Using provided rathole token"
    fi
    
    # Generate OAuth2 Proxy cookie secret if not provided (client secret must be from Kanidm)
    if [ -z "${OAUTH2_PROXY_COOKIE_SECRET:-}" ]; then
        OAUTH2_PROXY_COOKIE_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
        log_info "Generated new OAuth2 Proxy cookie secret"
    else
        log_info "Using provided OAuth2 Proxy cookie secret"
    fi
    
    # Generate FireflyIII app key if not provided
    if [ -z "${FIREFLY_APP_KEY:-}" ]; then
        FIREFLY_APP_KEY="base64:$(openssl rand -base64 32)"
        log_info "Generated new FireflyIII app key"
    else
        log_info "Using provided FireflyIII app key"
    fi
    
    # Generate FireflyIII database password if not provided
    if [ -z "${FIREFLY_DB_PASSWORD:-}" ]; then
        FIREFLY_DB_PASSWORD=$(openssl rand -base64 32)
        log_info "Generated new FireflyIII database password"
    else
        log_info "Using provided FireflyIII database password"
    fi
}

# Create secrets YAML content for middle server
create_middle_secrets_yaml() {
    cat << EOF
rathole-token: "$RATHOLE_TOKEN"
rathole-noise-private: "$RATHOLE_NOISE_PRIVATE"
oauth2-proxy-client-secret: "$OAUTH2_PROXY_CLIENT_SECRET"
oauth2-proxy-cookie-secret: "$OAUTH2_PROXY_COOKIE_SECRET"
EOF
}

# Create secrets YAML content for home server
create_home_secrets_yaml() {
    cat << EOF
rathole-token: "$RATHOLE_TOKEN"
rathole-noise-public: "$RATHOLE_NOISE_PUBLIC"
firefly-app-key: "$FIREFLY_APP_KEY"
firefly-db-password: "$FIREFLY_DB_PASSWORD"
EOF
}

# Encrypt secrets for a machine
encrypt_secrets() {
    local machine="$1"
    local age_key="$2"
    local output_file="machines/$machine/secrets.yaml"
    
    log_info "Encrypting secrets for $machine..."
    
    # Create machine directory if it doesn't exist
    mkdir -p "machines/$machine"
    
    # Create and encrypt secrets based on machine type
    if [ "$machine" = "middle" ]; then
        create_middle_secrets_yaml | sops --encrypt --input-type yaml --age "$age_key" /dev/stdin > "$output_file"
    elif [ "$machine" = "home" ]; then
        create_home_secrets_yaml | sops --encrypt --input-type yaml --age "$age_key" /dev/stdin > "$output_file"
    else
        log_error "Unknown machine type: $machine"
        return 1
    fi
    
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
    
    if sops --decrypt "$secrets_file" > /dev/null 2>&1; then
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
    check_env_vars
    generate_secrets
    
    echo
    log_info "Generating secrets with:"
    echo "  - Rathole Token: ${RATHOLE_TOKEN:0:16}..."
    echo "  - Noise Private: ${RATHOLE_NOISE_PRIVATE:0:16}..."
    echo "  - Noise Public: ${RATHOLE_NOISE_PUBLIC:0:16}..."
    echo "  - OAuth2 Proxy Client Secret: ${OAUTH2_PROXY_CLIENT_SECRET:0:16}..."
    echo "  - OAuth2 Proxy Cookie Secret: ${OAUTH2_PROXY_COOKIE_SECRET:0:16}..."
    echo "  - FireflyIII App Key: ${FIREFLY_APP_KEY:0:16}..."
    echo "  - FireflyIII DB Password: ${FIREFLY_DB_PASSWORD:0:16}..."
    echo
    
    # Encrypt for both machines
    encrypt_secrets "middle" "$MIDDLE_AGE_KEY"
    encrypt_secrets "home" "$HOME_AGE_KEY"
    
    echo
    log_info "Verifying encrypted files..."
    verify_secrets "middle"
    verify_secrets "home"
    
    echo
    log_info "✅ Secrets generation complete!"
    echo
    log_info "Generated files:"
    echo "  - machines/middle/secrets.yaml"
    echo "  - machines/home/secrets.yaml"
    echo
    log_info "Next steps:"
    echo "  1. Deploy configurations: ./deploy.sh middle user@middle-server"
    echo "  2. Deploy configurations: ./deploy.sh home user@home-server"
    echo "  3. Verify services: systemctl status rathole-server"
    
    # Show generated values for reference (optional)
    if [ "${SHOW_SECRETS:-false}" = "true" ]; then
        echo
        log_warn "Generated secrets (SHOW_SECRETS=true):"
        echo "RATHOLE_TOKEN=$RATHOLE_TOKEN"
        echo "RATHOLE_NOISE_PRIVATE=$RATHOLE_NOISE_PRIVATE"
        echo "RATHOLE_NOISE_PUBLIC=$RATHOLE_NOISE_PUBLIC"
        echo "OAUTH2_PROXY_CLIENT_SECRET=$OAUTH2_PROXY_CLIENT_SECRET"
        echo "OAUTH2_PROXY_COOKIE_SECRET=$OAUTH2_PROXY_COOKIE_SECRET"
        echo "FIREFLY_APP_KEY=$FIREFLY_APP_KEY"
        echo "FIREFLY_DB_PASSWORD=$FIREFLY_DB_PASSWORD"
    fi
}

# Run main function
main "$@"