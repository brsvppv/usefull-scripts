#!/usr/bin/env bash
# =================================================================
# Universal LXC Builder for Proxmox VE - v4
# Author: GPT-5 for Borislav Popov
# Style: Inspired by tteck's Proxmox scripts
#
# Features:
# - Interactive & Non-Interactive modes
# - Auto-suggests next available CTID
# - Auto-detects storage, templates, and bridges
# - Supports VLAN tagging
# - Supports SSH public key injection
# - Attempts to auto-detect OS from template name
#
# Usage (Interactive):
# ./create-lxc-v4.sh
#
# Usage (Non-Interactive):
# ./create-lxc-v4.sh \
#   --ctid 101 \
#   --hostname my-container \
#   --template debian-12-standard_12.2-1_amd64.tar.zst \
#   --storage local-lvm \
#   --cores 2 \
#   --ram 2048 \
#   --disk 10 \
#   --bridge vmbr0 \
#   --vlan 100 \
#   --ssh-key ~/.ssh/id_rsa.pub \
#   --unprivileged 1
# =================================================================

# --- Colors & UI ---
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
    echo -e "${GN}        🧱 Universal Proxmox LXC Builder v4${CL}"
    echo -e "${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}\n"
}

# --- Parse Command-Line Arguments ---
while [ "$#" -gt 0 ]; do
    case "$1" in
        --ctid) CTID="$2"; shift 2;;
        --hostname) HOSTNAME="$2"; shift 2;;
        --template) OVERRIDE_TEMPLATE="$2"; shift 2;;
        --storage) OVERRIDE_STORAGE="$2"; shift 2;;
        --cores) CORES="$2"; shift 2;;
        --ram) RAM="$2"; shift 2;;
        --disk) DISK="$2"; shift 2;;
        --swap) SWAP="$2"; shift 2;;
        --bridge) BRIDGE="$2"; shift 2;;
        --vlan) VLAN="$2"; shift 2;;
        --ip) IP="$2"; shift 2;;
        --ssh-key) SSH_KEY_FILE="$2"; shift 2;;
        --unprivileged) UNPRIV="$2"; shift 2;;
        *) echo "Unknown parameter: $1"; exit 1;;
    esac
done

# --- Pre-flight Checks ---
if ! command -v pveversion &>/dev/null; then
    echo -e "${RD}❌ This script must be run on a Proxmox host.${CL}"
    exit 1
fi

# --- Interactive Mode Logic ---
if [ -z "$CTID" ]; then
    INTERACTIVE=true
    header_info
fi

# --- Suggest Next CTID ---
function suggest_ctid() {
    local last_id
    last_id=$(pct list | awk 'NR>1 {print $1}' | sort -n | tail -1)
    if [ -z "$last_id" ]; then
        echo "100"
    else
        echo "$((last_id + 1))"
    fi
}

# --- Detect OS from Template ---
function detect_os() {
    local template_name
    template_name=$(basename "$1")
    case "$template_name" in
        *debian*) echo "debian" ;;
        *ubuntu*) echo "ubuntu" ;;
        *centos*) echo "centos" ;;
        *almalinux*) echo "almalinux" ;;
        *rocky*) echo "rocky" ;;
        *fedora*) echo "fedora" ;;
        *arch*) echo "archlinux" ;;
        *) echo "debian" ;; # Fallback
    esac
}

# --- Interactive Prompts ---
if [ "$INTERACTIVE" = true ]; then
    # Storage
    STORAGES=($(pvesm status -content rootdir | awk 'NR>1 {print $1}'))
    echo -e "${INFO} Available storages:${CL}"
    for i in "${!STORAGES[@]}"; do echo "  [$i] ${STORAGES[$i]}"; done
    read -rp "Select storage index [0]: " idx; STORAGE=${STORAGES[${idx:-0}]}
    echo -e "${GN}Selected: $STORAGE${CL}\n"

    # Template
    TEMPLATE_FILES=($(find /var/lib/vz/template/cache /mnt/pve/*/template/cache -maxdepth 1 -type f -name "*.tar.*" 2>/dev/null))
    echo -e "${INFO} Available templates:${CL}"
    for i in "${!TEMPLATE_FILES[@]}"; do echo "  [$i] $(basename "${TEMPLATE_FILES[$i]}")"; done
    read -rp "Select template index [0]: " idx; TEMPLATE="${TEMPLATE_FILES[${idx:-0}]}"
    echo -e "${GN}Selected: $(basename "$TEMPLATE")${CL}\n"

    # Bridge
    BRIDGES=($(brctl show | awk 'NR>1 {print $1}'))
    echo -e "${INFO} Available bridges:${CL}"
    for i in "${!BRIDGES[@]}"; do echo "  [$i] ${BRIDGES[$i]}"; done
    read -rp "Select bridge index [0]: " idx; BRIDGE="${BRIDGES[${idx:-0}]}"
    echo -e "${GN}Selected: $BRIDGE${CL}\n"

    # Basic Config
    SUGGESTED_CTID=$(suggest_ctid)
    read -rp "Enter CTID [$SUGGESTED_CTID]: " CTID; CTID=${CTID:-$SUGGESTED_CTID}
    read -rp "Enter Hostname: " HOSTNAME
    read -rp "CPU cores [2]: " CORES; CORES=${CORES:-2}
    read -rp "Memory (MB) [2048]: " RAM; RAM=${RAM:-2048}
    read -rp "Disk size (GB) [8]: " DISK; DISK=${DISK:-8}
    read -rp "Swap (MB) [512]: " SWAP; SWAP=${SWAP:-512}

    # Networking
    read -rp "VLAN tag (optional): " VLAN
    read -rp "Use DHCP? (y/n) [y]: " dhcp_choice
    if [[ "$dhcp_choice" =~ ^[Nn]$ ]]; then
        read -rp "Enter static IP (e.g., 192.168.1.50/24): " IP
    else
        IP="dhcp"
    fi

    # SSH Key
    read -rp "Path to public SSH key (optional, e.g., ~/.ssh/id_rsa.pub): " SSH_KEY_FILE

    # Unprivileged
    read -rp "Unprivileged container? (y/n) [y]: " unpriv_choice
    [[ "$unpriv_choice" =~ ^[Nn]$ ]] && UNPRIV=0 || UNPRIV=1
else
    # Non-interactive: Use provided args or defaults
    TEMPLATE=$(find /var/lib/vz/template/cache /mnt/pve/*/template/cache -maxdepth 1 -type f -name "*$OVERRIDE_TEMPLATE*" 2>/dev/null | head -n 1)
    STORAGE=${OVERRIDE_STORAGE}
    CORES=${CORES:-2}
    RAM=${RAM:-2048}
    DISK=${DISK:-8}
    SWAP=${SWAP:-512}
    IP=${IP:-dhcp}
    UNPRIV=${UNPRIV:-1}
fi

# --- Final Processing ---
OSTYPE=$(detect_os "$TEMPLATE")
NET_OPTS="name=eth0,bridge=${BRIDGE},ip=${IP}"
[ -n "$VLAN" ] && NET_OPTS+=",tag=${VLAN}"

SSH_KEY_ARG=""
if [ -n "$SSH_KEY_FILE" ] && [ -f "$SSH_KEY_FILE" ]; then
    SSH_KEY_ARG="--ssh-public-keys $SSH_KEY_FILE"
fi

# --- Summary ---
if [ "$INTERACTIVE" = true ]; then
    header_info
    echo -e "${YW}Summary:${CL}"
    cat <<EOF
CTID:          $CTID
Hostname:      $HOSTNAME
OS Type:       $OSTYPE (auto-detected)
Cores:         $CORES
RAM:           ${RAM}MB
Disk:          ${DISK}GB
Storage:       $STORAGE
Template:      $(basename "$TEMPLATE")
Unprivileged:  $UNPRIV
Network:       $NET_OPTS
SSH Key File:  ${SSH_KEY_FILE:-"None"}
EOF
    echo
    read -rp "Proceed with creation? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo -e "${RD}Aborted.${CL}"; exit 0; }
fi

# --- Build Container ---
echo -ne "${BFR}${HOLD} Creating container... "
pct create "$CTID" "$TEMPLATE" \
  --hostname "$HOSTNAME" \
  --arch amd64 \
  --cores "$CORES" \
  --memory "$RAM" \
  --swap "$SWAP" \
  --rootfs "${STORAGE}:${DISK}" \
  --net0 "$NET_OPTS" \
  --ostype "$OSTYPE" \
  --unprivileged "$UNPRIV" \
  --onboot 1 \
  --start 0 \
  $SSH_KEY_ARG &>/dev/null

if [ $? -ne 0 ]; then
    echo -e "${BFR}${CROSS} Container creation failed. Please check your parameters.${CL}"
    exit 1
fi

echo -e "${BFR}${CM} Container created successfully."

# --- Completion ---
echo
echo -e "${GN}✅ Done!${CL}"
echo -e "Container ${YW}$CTID${CL} (${GN}$HOSTNAME${CL}) has been created."
echo -e "To start it: ${YW}pct start $CTID${CL}\n"
