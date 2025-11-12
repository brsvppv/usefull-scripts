#!/usr/bin/env bash
#
# setup-firewall.sh
# Configures firewalld on RHEL/CentOS/Fedora
#
# Usage: sudo ./setup-firewall.sh

set -euo pipefail

echo "=== Firewall Configuration for RHEL/CentOS/Fedora ==="

# Install firewalld if not present
if ! command -v firewall-cmd &> /dev/null; then
    echo "Installing firewalld..."
    dnf install -y firewalld
fi

# Start and enable firewalld
echo "Starting firewalld service..."
systemctl start firewalld
systemctl enable firewalld

# Configure common services
echo "Configuring firewall rules..."

# Allow SSH
firewall-cmd --permanent --add-service=ssh
echo "  - Allowed SSH (port 22)"

# Allow HTTP and HTTPS
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
echo "  - Allowed HTTP (port 80) and HTTPS (port 443)"

# Reload firewall
echo "Reloading firewall..."
firewall-cmd --reload

echo "=== Firewall Configuration Complete ==="
echo "Active zones:"
firewall-cmd --get-active-zones
echo ""
echo "Allowed services:"
firewall-cmd --list-services
