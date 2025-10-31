#!/bin/bash

# Script to generate self-signed SSL certificate for gitlab.local

CERT_DIR="./certs"
DOMAIN="gitlab.local"
DAYS_VALID=365

# Create certs directory if it doesn't exist
mkdir -p "$CERT_DIR"

echo "🔐 Generating self-signed SSL certificate for $DOMAIN..."

# Generate private key (2048-bit RSA)
openssl genrsa -out "$CERT_DIR/${DOMAIN}.key" 2048

# Generate certificate signing request (CSR) with CN=gitlab.local
openssl req -new -key "$CERT_DIR/${DOMAIN}.key" \
  -out "$CERT_DIR/${DOMAIN}.csr" \
  -subj "/C=CN/ST=Shanghai/L=Shanghai/O=Local/OU=IT/CN=${DOMAIN}"

# Generate self-signed certificate valid for 365 days
openssl x509 -req -days $DAYS_VALID \
  -in "$CERT_DIR/${DOMAIN}.csr" \
  -signkey "$CERT_DIR/${DOMAIN}.key" \
  -out "$CERT_DIR/${DOMAIN}.crt" \
  -extfile <(printf "subjectAltName=DNS:${DOMAIN},DNS:*.${DOMAIN}")

# Set appropriate permissions
chmod 600 "$CERT_DIR/${DOMAIN}.key"
chmod 644 "$CERT_DIR/${DOMAIN}.crt"

echo "✅ SSL certificate generated successfully!"
echo ""
echo "Certificate files:"
echo "  - Private key: $CERT_DIR/${DOMAIN}.key"
echo "  - Certificate: $CERT_DIR/${DOMAIN}.crt"
echo "  - CSR: $CERT_DIR/${DOMAIN}.csr"
echo ""
echo "Certificate details:"
openssl x509 -in "$CERT_DIR/${DOMAIN}.crt" -text -noout | grep -A2 "Subject:"
echo ""
echo "Valid until:"
openssl x509 -in "$CERT_DIR/${DOMAIN}.crt" -text -noout | grep "Not After"
