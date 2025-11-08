#!/bin/bash

set -e  # Exit on error

echo "=========================================="
echo "GitLab with Traefik SSL Setup"
echo "=========================================="
echo ""

# 1. Check if SSL certificates exist
if [ -f "./certs/gitlab.local.crt" ] && [ -f "./certs/gitlab.local.key" ]; then
  echo "✅ SSL certificates already exist in ./certs/"
  echo ""
  read -p "Do you want to regenerate the certificates? (y/N): " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Regenerating SSL certificates..."
    ./generate-ssl-cert.sh
  else
    echo "Using existing certificates"
  fi
else
  echo "📋 SSL certificates not found. Generating new ones..."
  ./generate-ssl-cert.sh
fi

echo ""
echo "=========================================="
echo "Starting services..."
echo "=========================================="
echo ""

# 2. Run the start script
bash ./start.sh

# 3. Deploy the SSL certificate
echo ""
echo "=========================================="
echo "Deploy the Self-Signed Certificate"
echo "=========================================="
echo ""
sudo mkdir -p /etc/gitlab-runner
sudo cp -rf ./certs /etc/gitlab-runner
sudo cp ./certs/gitlab.local.crt /usr/local/share/ca-certificates/
sudo sudo update-ca-certificates

echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "📍 Access GitLab at: https://gitlab.local"
echo "📍 Traefik Dashboard: http://localhost:8080"
echo ""
echo "⚠️  Important Notes:"
echo "1. Add '127.0.0.1 gitlab.local' to /etc/hosts if not already done"
echo "2. Your browser will show a security warning for the self-signed certificate"
echo "3. You can safely proceed past the warning (it's expected for self-signed certs)"
echo ""
echo "To stop services: bash ./stop.sh"
echo ""



