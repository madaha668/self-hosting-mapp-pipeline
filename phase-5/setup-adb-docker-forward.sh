#!/bin/bash
set -e

echo "Setting up ADB server with Docker bridge forwarding..."

# Kill existing adb and socat processes
echo "Cleaning up existing adb and socat processes..."
pkill -9 adb socat 2>/dev/null || true
sleep 1

# Remove adb cache
rm -rf ~/.android/adb_usb.ini 2>/dev/null || true

# Set ANDROID_HOME if not already set
ANDROID_HOME=${ANDROID_HOME:-/opt/android-sdk-linux}
export ANDROID_HOME

# Start adb server
echo "Starting adb server..."
$ANDROID_HOME/platform-tools/adb start-server

# Start socat forwarding
echo "Starting socat on 172.17.0.1:5037..."
socat TCP-LISTEN:5037,bind=172.17.0.1,fork,reuseaddr TCP:127.0.0.1:5037 &
SOCAT_PID=$!
sleep 1

echo "socat running with PID: $SOCAT_PID"

# Check if UFW is enabled
echo "Checking UFW status..."
if sudo ufw status | grep -q "Status: active"; then
    echo "UFW is enabled. Adding firewall rules..."
    sudo ufw allow in on docker0 to 172.17.0.1 port 5037
    echo "UFW rule added successfully"
else
    echo "UFW is inactive. Skipping firewall configuration."
fi

# Verify socat is listening
echo ""
echo "Verifying socat is listening on 172.17.0.1:5037..."
if netstat -tlnp 2>/dev/null | grep -q "172.17.0.1:5037"; then
    echo "✓ Successfully listening on 172.17.0.1:5037"
else
    echo "✗ Warning: socat may not be listening correctly"
    netstat -tlnp | grep 5037 || echo "  (no processes found on port 5037)"
fi

echo ""
echo "Setup complete. ADB is accessible to Docker containers via:"
echo "  ADB_SERVER_SOCKET=tcp:host.docker.internal:5037"
