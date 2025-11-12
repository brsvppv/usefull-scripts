#!/usr/bin/env bash
#
# install-yay.sh
# Installs yay AUR helper on Arch Linux
#
# Usage: ./install-yay.sh (run as regular user, not root)

set -euo pipefail

echo "=== Installing yay AUR Helper ==="

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "Error: Do not run this script as root!"
    exit 1
fi

# Install dependencies
echo "Installing dependencies..."
sudo pacman -S --needed --noconfirm git base-devel

# Clone yay repository
echo "Cloning yay repository..."
cd /tmp
rm -rf yay
git clone https://aur.archlinux.org/yay.git
cd yay

# Build and install yay
echo "Building and installing yay..."
makepkg -si --noconfirm

# Clean up
cd ~
rm -rf /tmp/yay

echo "=== yay Installation Complete ==="
echo "yay version:"
yay --version
