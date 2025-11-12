#!/usr/bin/env bash
#
# install-docker.sh
# Installs Docker Engine on Ubuntu
#
# Usage: sudo ./install-docker.sh

set -euo pipefail

echo "=== Docker Installation for Ubuntu ==="

# Remove old versions
echo "Removing old Docker versions..."
apt-get remove -y docker docker-engine docker.io containerd runc || true

# Update apt and install prerequisites
echo "Installing prerequisites..."
apt-get update
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
echo "Adding Docker GPG key..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up the repository
echo "Setting up Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
echo "Installing Docker Engine..."
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add current user to docker group (if not root)
if [ "$SUDO_USER" ]; then
    echo "Adding $SUDO_USER to docker group..."
    usermod -aG docker "$SUDO_USER"
fi

echo "=== Docker Installation Complete ==="
echo "Docker version:"
docker --version
echo ""
echo "Note: Log out and back in for group membership to take effect."
