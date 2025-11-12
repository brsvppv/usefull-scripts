#!/usr/bin/env bash
#
# setup-dev-environment.sh
# Sets up a basic development environment on Debian-based systems
#
# Usage: sudo ./setup-dev-environment.sh

set -euo pipefail

echo "=== Debian Development Environment Setup ==="

# Update package lists
echo "Updating package lists..."
apt-get update

# Install essential development tools
echo "Installing development tools..."
apt-get install -y \
    build-essential \
    git \
    curl \
    wget \
    vim \
    htop \
    net-tools

# Install Python development tools
echo "Installing Python tools..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv

# Install Node.js (using NodeSource repository)
echo "Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

echo "=== Setup Complete ==="
echo "Installed packages:"
echo "  - Build tools (gcc, make, etc.)"
echo "  - Git, curl, wget"
echo "  - Python 3 with pip and venv"
echo "  - Node.js with npm"
echo ""
echo "Versions:"
python3 --version
node --version
npm --version
