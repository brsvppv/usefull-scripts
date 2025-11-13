#!/usr/bin/env bash
# ============================================================
# Universal LXC Builder for Proxmox VE (Production-ready)
# Author: GPT-5 for Borislav Popov (styled like tteck scripts)
# License: MIT
# ============================================================

set -euo pipefail
IFS=$'\n\t'

# ---------- Colors & UI ----------
YW="\033[33m"
GN="\033[32m"
RD="\033[31m"
BL="\033[36m"
CL="\033[m"
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
INFO="${BL}i${CL}"

trap 'echo -e "\n${RD}Interrupted. Exiting.${CL}"; exit 130' INT

function header_info() {
    clear
    echo -e "${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
    echo -e "${GN}        Universal Proxmox LXC Builder (Production)${CL}"
    echo -e "${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}\n"
}

function err_exit() {
    echo -e "${RD}ERROR: $*${CL}" >&2
    exit 1
}

header_info

# ---------- Pre-flight checks ----------
command -v pveversion >/dev/null 2>&1 || err_exit "This script must be run on a Proxmox host (pveversion missing)."
command -v pvesm >/dev/null 2>&1 || err_exit "'pvesm' not found. Is this a full Proxmox install?"
command -v pct >/dev/null 2>&1 || err_exit "'pct' not found. Proxmox LXC tools required."

# ---------- Helper: numeric input with default ----------
read_number_default() {
  local prompt="$1"; local def="$2"; local min="${3:-0}"; local max="${4:-}"
  local val
  while true; do
    read -rp "$prompt [$def]: " val
    val=${val:-$def}
    if [[ ! "$val" =~ ^[0-9]+$ ]]; then
      echo -e "${RD}Please enter a numeric value.${CL}"
      continue
    fi
    if [[ -n "$max" && "$val" -lt "$min" || -n "$max" && "$val" -gt "$max" ]]; then
      echo -e "${RD}Value must be between $min and $max.${CL}"
      continue
    fi
    echo "$val"
    return 0
  done
}

# ---------- Detect Storages (that can hold rootfs) ----------
STORAGES=($(pvesm status -content rootdir | awk 'NR>1 {print $1}'))
if [ ${#STORAGES[@]} -eq 0 ]; then
    err_exit "No valid container-capable storages found (pvesm status -content rootdir)."
fi

echo -e "${INFO} Available storages that support containers:${CL}"
for i in "${!STORAGES[@]}"; do
    printf "  [%s] %s\n" "$i" "${STORAGES[$i]}"
done
echo

# choose storage by index
while true; do
    read -rp "Select storage index [default: 0]: " STORAGE_INDEX
    STORAGE_INDEX=${STORAGE_INDEX:-0}
    if [[ "$STORAGE_INDEX" =~ ^[0-9]+$ ]] && [ "$STORAGE_INDEX" -ge 0 ] && [ "$STORAGE_INDEX" -lt "${#STORAGES[@]}" ]; then
        STORAGE=${STORAGES[$STORAGE_INDEX]}
        break
    else
        echo -e "${RD}Invalid. Enter number between 0 and $(( ${#STORAGES[@]} - 1 )).${CL}"
    fi
done
echo -e "${GN}Selected storage: $STORAGE${CL}\n"

# ---------- Detect Templates ----------
# look in /var/lib/vz/template/cache and /mnt/pve/*/template/cache
TEMPLATE_FILES=()
while IFS= read -r -d $'\0' f; do TEMPLATE_FILES+=("$f"); done < <(find /var/lib/vz/template/cache /mnt/pve/*/template/cache -maxdepth 1 -type f -name "*.tar.*" -print0 2>/dev/null || true)

if [ ${#TEMPLATE_FILES[@]} -eq 0 ]; then
    echo -e "${RD}No LXC templates found in /var/lib/vz/template/cache or /mnt/pve/*/template/cache.${CL}"
    echo -e "Download templates with: ${YW}pveam update && pveam available && pveam download local <template>${CL}"
    exit 1
fi

echo -e "${INFO} Available LXC templates:${CL}"
for i in "${!TEMPLATE_FILES[@]}"; do
    printf "  [%s] %s\n" "$i" "$(basename "${TEMPLATE_FILES[$i]}")"
done
echo

# choose template by index
while true; do
    read -rp "Select template index [default: 0]: " TEMPLATE_INDEX
    TEMPLATE_INDEX=${TEMPLATE_INDEX:-0}
    if [[ "$TEMPLATE_INDEX" =~ ^[0-9]+$ ]] && [ "$TEMPLATE_INDEX" -ge 0 ] && [ "$TEMPLATE_INDEX" -lt "${#TEMPLATE_FILES[@]}" ]; then
        TEMPLATE_PATH="${TEMPLATE_FILES[$TEMPLATE_INDEX]}"
        TEMPLATE_BASENAME="$(basename "$TEMPLATE_PATH")"
        break
    else
        echo -e "${RD}Invalid. Enter number between 0 and $(( ${#TEMPLATE_FILES[@]} - 1 )).${CL}"
    fi
done
echo -e "${GN}Selected template: ${TEMPLATE_BASENAME}${CL}\n"

# If template is on a different storage than chosen STORAGE, detect its storage
TEMPLATE_STORAGE="local"
if [[ "$TEMPLATE_PATH" =~ ^/mnt/pve/([^/]+)/template/cache/ ]]; then
    TEMPLATE_STORAGE="${BASH_REMATCH[1]}"
elif [[ "$TEMPLATE_PATH" =~ ^/var/lib/vz/template/cache/ ]]; then
    TEMPLATE_STORAGE="local"
fi

# warn if template storage differs from chosen rootfs storage
if [ "$TEMPLATE_STORAGE" != "$STORAGE" ]; then
    echo -e "${YW}Note:${CL} The chosen template resides on storage: ${YW}$TEMPLATE_STORAGE${CL}"
    echo -e "The container rootfs will be created on: ${YW}$STORAGE${CL}"
    echo -e "Proxmox will copy template data as needed. This is normal."
fi

# ---------- Detect Valid Bridges (only vmbr*) ----------
BRIDGES=()
# prefer reading /etc/network/interfaces for configured vmbr entries
while IFS= read -r br; do BRIDGES+=("$br"); done < <(grep -oP '^auto\s+\Kvmbr[0-9]+' /etc/network/interfaces 2>/dev/null || true)

# if not found, fallback to listing all bridges from ip link but filter vmbrX
if [ ${#BRIDGES[@]} -eq 0 ]; then
    while IFS= read -r br; do
        if [[ "$br" =~ ^vmbr[0-9]+$ ]]; then BRIDGES+=("$br"); fi
    done < <(ip -o link show | awk -F': ' '{print $2}')
fi

# final fallback: vmbr0
if [ ${#BRIDGES[@]} -eq 0 ]; then
    BRIDGES=("vmbr0")
fi

echo -e "${INFO} Available network bridges (vmbr* only):${CL}"
for i in "${!BRIDGES[@]}"; do
    printf "  [%s] %s\n" "$i" "${BRIDGES[$i]}"
done
echo

while true; do
    read -rp "Select bridge index [default: 0]: " BRIDGE_INDEX
    BRIDGE_INDEX=${BRIDGE_INDEX:-0}
    if [[ "$BRIDGE_INDEX" =~ ^[0-9]+$ ]] && [ "$BRIDGE_INDEX" -ge 0 ] && [ "$BRIDGE_INDEX" -lt "${#BRIDGES[@]}" ]; then
        BRIDGE="${BRIDGES[$BRIDGE_INDEX]}"
        break
    else
        echo -e "${RD}Invalid. Enter number between 0 and $(( ${#BRIDGES[@]} - 1 )).${CL}"
    fi
done
echo -e "${GN}Selected bridge: $BRIDGE${CL}\n"

# ---------- Basic Config ----------
while true; do
    read -rp "Enter Container ID (CTID, numeric, e.g. 109): " CTID
    if [[ "$CTID" =~ ^[0-9]+$ ]]; then break; fi
    echo -e "${RD}CTID must be numeric.${CL}"
done

read -rp "Enter Hostname: " HOSTNAME
HOSTNAME=${HOSTNAME:-lxc-$CTID}

CORES=$(read_number_default "CPU cores" "2" 1 64)
RAM=$(read_number_default "Memory (MB)" "2048" 128 262144)
DISK=$(read_number_default "Disk size (GB)" "8" 1 8192)
SWAP=$(read_number_default "Swap (MB)" "512" 0 262144)

# ---------- Privileged / Unprivileged ----------
echo -e "\nShould this container be ${YW}unprivileged${CL}?"
echo "  [1] Yes (recommended — root inside container is mapped to unprivileged host uid)"
echo "  [2] No  (privileged container)"
while true; do
    read -rp "#? " PRIV_CHOICE
    PRIV_CHOICE=${PRIV_CHOICE:-1}
    if [[ "$PRIV_CHOICE" == "1" ]]; then UNPRIV=1; break
    elif [[ "$PRIV_CHOICE" == "2" ]]; then UNPRIV=0; break
    else echo -e "${RD}Choose 1 or 2.${CL}"; fi
done
echo -e "${GN}Unprivileged: $UNPRIV${CL}\n"

# ---------- Features explanation & selection ----------
cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ⚙️  Container Feature Options — explanation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  🧩 Nesting:
    - Allows "containers inside this container" (e.g. Docker running inside an LXC).
    - Required if you want to install Docker or run nested containers.
    - Slightly reduces isolation/security compared to no nesting.
    - Enable only if you need nested container runtimes.

  🔑 Keyctl:
    - Provides Linux keyring support inside the container (Linux kernel key management).
    - Used by some software for secure credential/key storage.
    - Safe to enable if required by apps.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

read -rp "Enable Nesting? (y/n) [y]: " NESTING_ANS
NESTING_ANS=${NESTING_ANS:-y}
read -rp "Enable Keyctl? (y/n) [y]: " KEYCTL_ANS
KEYCTL_ANS=${KEYCTL_ANS:-y}

FEATURES=()
[[ "$NESTING_ANS" =~ ^[Yy] ]] && FEATURES+=("nesting=1")
[[ "$KEYCTL_ANS" =~ ^[Yy] ]] && FEATURES+=("keyctl=1")
FEATURES_ARG=$(IFS=,; echo "${FEATURES[*]}")

# ---------- Network (DHCP or static) ----------
echo
read -rp "Use DHCP? (y/n) [y]: " DHCP_ANS
DHCP_ANS=${DHCP_ANS:-y}
if [[ "$DHCP_ANS" =~ ^[Yy] ]]; then
    IP="dhcp"
else
    while true; do
        read -rp "Enter static IP (CIDR) (example 192.168.1.50/24): " IP
        # basic validation for IPv4/CIDR
        if [[ "$IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then break; fi
        echo -e "${RD}Invalid format. Use xxx.xxx.xxx.xxx/YY${CL}"
    done
fi

# ---------- Confirm Summary ----------
clear
header_info
echo -e "${YW}Summary:${CL}"
cat <<EOF
CTID:          $CTID
Hostname:      $HOSTNAME
CPU Cores:     $CORES
RAM:           ${RAM} MB
Disk:          ${DISK} GB
Swap:          ${SWAP} MB
Storage:       $STORAGE
Template:      ${TEMPLATE_BASENAME} (${TEMPLATE_STORAGE})
Unprivileged:  $UNPRIV
Features:      ${FEATURES_ARG:-none}
Network:       $BRIDGE ($IP)
EOF

echo
read -rp "Proceed with container creation? (y/n): " CONFIRM
CONFIRM=${CONFIRM:-n}
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
    echo -e "${RD}Aborted by user.${CL}"
    exit 0
fi

# ---------- Build Container ----------
echo -ne "${BFR}${HOLD} Creating container... "

# If template is not on selected storage, we still reference the template by its storage
# For pct create, templates are referenced as <storage>:vztmpl/<basename>
# Determine the storage that holds the template (TEMPLATE_STORAGE already deduced)
TEMPLATE_REF="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_BASENAME}"

# If TEMPLATE_STORAGE isn't present in pvesm list, fallback to local reference:
if ! pvesm status -content rootdir | awk 'NR>1 {print $1}' | grep -qx "$TEMPLATE_STORAGE"; then
    TEMPLATE_REF="local:vztmpl/${TEMPLATE_BASENAME}"
fi

# Compose pct create command
PCT_CMD=(pct create "$CTID" "$TEMPLATE_REF" \
  --hostname "$HOSTNAME" \
  --arch amd64 \
  --cores "$CORES" \
  --memory "$RAM" \
  --swap "$SWAP" \
  --rootfs "${STORAGE}:${DISK}" \
  --net0 "name=eth0,bridge=${BRIDGE},ip=${IP}" \
  --ostype debian \
  --unprivileged "$UNPRIV" \
  --onboot 1 \
  --start 0)

# Add features if any
if [ -n "${FEATURES_ARG}" ]; then
    PCT_CMD+=(--features "${FEATURES_ARG}")
fi

# Run creation, capture output/errors
if "${PCT_CMD[@]}" &>/dev/null; then
    echo -e "${BFR}${CM} Container created successfully."
else
    echo -e "${BFR}${CROSS} Container creation command failed."
    echo -e "${RD}Running the creation command again with output to show error:${CL}"
    "${PCT_CMD[@]}" || err_exit "pct create failed. See output above."
fi

# ---------- Completion ----------
echo
echo -e "${GN}✅ Done!${CL}"
echo -e "Container ${YW}$CTID${CL} (${GN}$HOSTNAME${CL}) has been created."
echo -e "To start it: ${YW}pct start $CTID${CL}"
echo -e "To view config: ${YW}cat /etc/pve/lxc/$CTID.conf${CL}"
echo
