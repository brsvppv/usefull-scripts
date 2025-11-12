#!/usr/bin/env bash
# ============================================================
# Universal LXC Creation Script for Proxmox VE 7/8
# Author: GPT-5 for Borislav Popov
# License: MIT
# ============================================================

set -e

# --- Dependencies ---
if ! command -v dialog &>/dev/null; then
  echo "Installing dialog..."
  apt update &>/dev/null
  apt install -y dialog &>/dev/null
fi

# --- Collect basic info ---
TITLE="Proxmox LXC Creator"
BACKTITLE="Universal LXC Setup Utility"

# Get available templates
TEMPLATES=$(find /var/lib/vz/template/cache /mnt/pve/*/template/cache -maxdepth 1 -type f -name "*.tar.*" 2>/dev/null | sed 's|/var/lib/vz/template/cache/||;s|/mnt/pve/||' | sort)
[ -z "$TEMPLATES" ] && { echo "No LXC templates found. Download one first via GUI or 'pveam update'."; exit 1; }

# Get available storages that support containers
STORAGES=$(pvesm status -content rootdir | awk 'NR>1 {print $1}')
[ -z "$STORAGES" ] && { echo "No container-capable storages found."; exit 1; }

# Select template
TEMPLATE=$(dialog --clear --backtitle "$BACKTITLE" --title "$TITLE" \
  --menu "Select LXC Template:" 20 60 12 $(for t in $TEMPLATES; do echo "$t" ""; done) 3>&1 1>&2 2>&3)

[ -z "$TEMPLATE" ] && exit 1

# Select storage
STORAGE=$(dialog --clear --backtitle "$BACKTITLE" --title "$TITLE" \
  --menu "Select Storage for Container RootFS:" 20 60 10 $(for s in $STORAGES; do echo "$s" ""; done) 3>&1 1>&2 2>&3)

[ -z "$STORAGE" ] && exit 1

# Basic parameters
CTID=$(dialog --inputbox "Enter Container ID (e.g. 108):" 8 50 "108" 3>&1 1>&2 2>&3)
HOSTNAME=$(dialog --inputbox "Enter Hostname:" 8 50 "my-lxc" 3>&1 1>&2 2>&3)
CPU=$(dialog --inputbox "CPU Cores:" 8 50 "2" 3>&1 1>&2 2>&3)
RAM=$(dialog --inputbox "Memory (MB):" 8 50 "2048" 3>&1 1>&2 2>&3)
DISK=$(dialog --inputbox "Disk Size (GB):" 8 50 "8" 3>&1 1>&2 2>&3)
SWAP=$(dialog --inputbox "Swap (MB):" 8 50 "512" 3>&1 1>&2 2>&3)

# Privilege and features
dialog --yesno "Should this container be UNPRIVILEGED?" 8 50
if [ $? -eq 0 ]; then
  UNPRIV="1"
else
  UNPRIV="0"
fi

dialog --checklist "Select container features:" 15 60 5 \
  1 "Enable nesting (for Docker etc.)" on \
  2 "Enable keyctl (for security tools)" on 2>features.tmp

FEATURES=""
while read -r choice; do
  case $choice in
    1) FEATURES="${FEATURES:+$FEATURES,}nesting=1" ;;
    2) FEATURES="${FEATURES:+$FEATURES,}keyctl=1" ;;
  esac
done < <(sed 's/"//g' features.tmp)
rm features.tmp

# Network configuration
NETMODE=$(dialog --menu "Select Network Mode:" 10 50 3 \
  "dhcp" "DHCP (auto)" \
  "static" "Static IP" 3>&1 1>&2 2>&3)

if [ "$NETMODE" = "static" ]; then
  IP=$(dialog --inputbox "Enter static IP (e.g. 192.168.1.50/24):" 8 50 "" 3>&1 1>&2 2>&3)
else
  IP="dhcp"
fi

# Bridge
BRIDGE=$(dialog --inputbox "Bridge Interface (default: vmbr0):" 8 50 "vmbr0" 3>&1 1>&2 2>&3)

# Confirm summary
SUMMARY="CTID: $CTID
Hostname: $HOSTNAME
CPU: $CPU cores
RAM: ${RAM}MB
Disk: ${DISK}GB
Swap: ${SWAP}MB
Storage: $STORAGE
Template: $TEMPLATE
Unprivileged: $UNPRIV
Features: $FEATURES
Network: $NETMODE ($IP)
Bridge: $BRIDGE"

dialog --msgbox "$SUMMARY" 20 60

# --- Execute container creation ---
echo "Creating LXC container..."
pct create "$CTID" "$STORAGE:vztmpl/$TEMPLATE" \
  --hostname "$HOSTNAME" \
  --arch amd64 \
  --cores "$CPU" \
  --memory "$RAM" \
  --swap "$SWAP" \
  --rootfs "${STORAGE}:${DISK}" \
  --net0 "name=eth0,bridge=${BRIDGE},ip=${IP}" \
  --ostype debian \
  --unprivileged "$UNPRIV" \
  --features "${FEATURES}" \
  --start 0 \
  --onboot 1

dialog --msgbox "Container $CTID ($HOSTNAME) created successfully!" 8 50

clear
echo "✅ LXC container $CTID ($HOSTNAME) created successfully."
echo "To start it, run: pct start $CTID"
