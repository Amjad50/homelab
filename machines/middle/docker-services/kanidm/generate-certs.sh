#!/bin/sh

# Generate self-signed certificates for Kanidm
# Runs in Alpine container before Kanidm starts

set -e

# Install OpenSSL
apk add --no-cache openssl

CERT_DIR="/data"
DOMAIN="${DOMAIN:-idm.home.alsharafi.dev}"

if [ -f "$CERT_DIR/chain.pem" ] && [ -f "$CERT_DIR/key.pem" ]; then
    echo "Certificates already exist, skipping generation."
    exit 0
fi

echo "Generating self-signed certificates for $DOMAIN..."

# Generate private key
openssl genrsa -out "$CERT_DIR/key.pem" 2048

# Generate certificate signing request
openssl req -new -key "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.csr" -subj "/CN=$DOMAIN"

# Generate self-signed certificate (valid for 365 days)
openssl x509 -req -in "$CERT_DIR/cert.csr" -signkey "$CERT_DIR/key.pem" -out "$CERT_DIR/chain.pem" -days 365

# Clean up CSR
rm "$CERT_DIR/cert.csr"

# Set proper permissions
chmod 600 "$CERT_DIR/key.pem"
chmod 644 "$CERT_DIR/chain.pem"

echo "Certificates generated successfully!"
echo "- $CERT_DIR/key.pem"
echo "- $CERT_DIR/chain.pem"