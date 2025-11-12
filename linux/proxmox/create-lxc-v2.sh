#!/usr/bin/env bash
# ============================================================
# Universal LXC Builder for Proxmox VE 7/8
# Author: GPT-5 for Borislav Popov
# Style: Inspired by tteck's Proxmox scripts
# ============================================================

# ---------- Colors & UI ----------
YW=$(echo "\033[33m")
GN=$(echo "\033[32m")
RD=$(echo "\033[31m")
BL=$(echo "\033[36m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
INFO="${BL}i${CL}"

function header_info() {
    clear
    echo -e "${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
    echo -e "${GN}        🧱 Universal Proxmox LXC Builder${CL}"
    echo -e "${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}\n"
}

function pause() {
    read -rp "Press Enter to continue..."
}

header_info

# ---------- Pre-flight ----------
if ! command -v pveversion &>/dev/null; then
    echo -e "${RD}❌ This script must be run on a Proxmox host.${CL}"
    exit 1
fi

if ! command -v pvesm &>/dev/null; then
    echo -e "${RD}❌ 'pvesm' not found. Is this a full Proxmox install?${CL}"
    exit 1
fi

# ---------- Detect Storages ----------
STORAGES=($(pvesm status -content rootdir | awk 'NR>1 {print $1}'))
if [ ${#STORAGES[@]} -eq 0 ]; then
    echo -e "${RD}❌ No valid container storages found!${CL}"
    exit 1
fi

echo -e "${INFO} Available storages that support containers:${CL}"
for s in "${STORAGES[@]}"; do echo " - $s"; done
echo
read -rp "Select storage [default: ${STORAGES[0]}]: " STORAGE
STORAGE=${STORAGE:-${STORAGES[0]}}

# ---------- Detect Templates ----------
TEMPLATES=$(find /var/lib/vz/template/cache /mnt/pve/*/template/cache -maxdepth 1 -type f -name "*.tar.*" 2>/dev/null)
if [ -z "$TEMPLATES" ]; then
    echo -e "${RD}❌ No LXC templates found.${CL}"
    echo -e "Use: ${YW}pveam update && pveam available && pveam download local debian-13-standard_13.1-2_amd64.tar.zst${CL}"
    exit 1
fi

echo -e "\n${INFO} Available templates:${CL}"
select TEMPLATE in $TEMPLATES; do
    [[ -n "$TEMPLATE" ]] && break
done

# ---------- Basic Config ----------
read -rp "Enter Container ID (CTID): " CTID
read -rp "Enter Hostname: " HOSTNAME
read -rp "CPU cores [2]: " CORES
read -rp "Memory (MB) [2048]: " RAM
read -rp "Disk size (GB) [8]: " DISK
read -rp "Swap (MB) [512]: " SWAP

CORES=${CORES:-2}
RAM=${RAM:-2048}
DISK=${DISK:-8}
SWAP=${SWAP:-512}

# ---------- Privileged / Unprivileged ----------
echo -e "\nShould this container be unprivileged?"
select PRIV in "Yes (recommended)" "No"; do
    case $PRIV in
        "Yes (recommended)") UNPRIV=1; break ;;
        "No") UNPRIV=0; break ;;
    esac
done

# ---------- Features ----------
echo -e "\nSelect features to enable:"
FEATURES=()
read -rp "Enable Nesting? (y/n) [y]: " NESTING
[[ "$NESTING" =~ ^[Yy]$|^$ ]] && FEATURES+=("nesting=1")
read -rp "Enable Keyctl? (y/n) [y]: " KEYCTL
[[ "$KEYCTL" =~ ^[Yy]$|^$ ]] && FEATURES+=("keyctl=1")
FEATURES_ARG=$(IFS=,; echo "${FEATURES[*]}")

# ---------- Networking ----------
echo -e "\nNetwork configuration:"
read -rp "Bridge (default vmbr0): " BRIDGE
BRIDGE=${BRIDGE:-vmbr0}
read -rp "Use DHCP? (y/n) [y]: " DHCP
if [[ "$DHCP" =~ ^[Yy]$|^$ ]]; then
    IP="dhcp"
else
    read -rp "Enter static IP (e.g. 192.168.1.50/24): " IP
fi

# ---------- Confirm Summary ----------
clear
header_info
echo -e "${YW}Summary:${CL}"
cat <<EOF
CTID:          $CTID
Hostname:      $HOSTNAME
CPU Cores:     $CORES
RAM:           ${RAM}MB
Disk:          ${DISK}GB
Swap:          ${SWAP}MB
Storage:       $STORAGE
Template:      $(basename "$TEMPLATE")
Unprivileged:  $UNPRIV
Features:      $FEATURES_ARG
Network:       $BRIDGE ($IP)
EOF

echo
read -rp "Proceed with container creation? (y/n): " CONFIRM
[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && { echo -e "${RD}Aborted.${CL}"; exit 0; }

# ---------- Build Container ----------
echo -ne "${BFR}${HOLD} Creating container... "

pct create "$CTID" "$STORAGE:vztmpl/$(basename "$TEMPLATE")" \
  --hostname "$HOSTNAME" \
  --arch amd64 \
  --cores "$CORES" \
  --memory "$RAM" \
  --swap "$SWAP" \
  --rootfs "${STORAGE}:${DISK}" \
  --net0 "name=eth0,bridge=${BRIDGE},ip=${IP}" \
  --ostype debian \
  --unprivileged "$UNPRIV" \
  --features "$FEATURES_ARG" \
  --onboot 1 \
  --start 0 &>/dev/null

echo -e "${BFR}${CM} Container created successfully."

# ---------- Completion ----------
echo
echo -e "${GN}✅ Done!${CL}"
echo -e "Container ${YW}$CTID${CL} (${GN}$HOSTNAME${CL}) has been created."
echo -e "To start it: ${YW}pct start $CTID${CL}\n"
