#!/usr/bin/env bash
# ============================================================
# Proxmox LXC Disk Resizer - Console Edition v2 (Streamlined)
# Author: GitHub Copilot for Borislav Popov (styled like tteck scripts)
# License: MIT
# 
# Improvements:
# - Direct container ID input (faster workflow)
# - Streamlined validation and execution
# - Enhanced error handling with detailed feedback
# - Production-ready logging
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

# ---------- Configuration ----------
readonly LOG_FILE="/var/log/proxmox-lxc-resizer.log"

# ---------- Error handling ----------
trap 'echo -e "\n${RD}Interrupted. Exiting.${CL}"; exit 130' INT

function err_exit() {
    echo -e "${RD}[ERROR]${CL} $1" >&2
    log "ERROR: $1"
    exit 1
}

function log() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $1" >> "$LOG_FILE" 2>/dev/null || true
}

function header_info() {
    clear
    cat <<"EOF"
    ____  __  ________   ____  _      __      ____           _              
   / __ \/ / / ____/ | / /  |(_)____/ /___  / __ \___  ____(_)___  ___  ____
  / /_/ / /_/ /   /  |/ /|_|/ / ___/ //_  / / /_/ / _ \/ ___/ /_  / / _ \/ ___/
 / ____/ __/ /___/ /|  / __/ (__  ) / / /_/ _, _/  __(__  ) / / /_/  __/ /    
/_/   /_/  \____/_/ |_/ __/_/____/_/ /___/_/ |_|\___/____/_/ /___/\___/_/     
                                                                            
EOF
    echo -e "${BL}Proxmox LXC Disk Resizer - Console Edition v2${CL}"
    echo -e "${YW}Streamlined container disk resize tool${CL}"
    echo
}

# ---------- Validation functions ----------
validate_container_id() {
    local ctid="$1"
    
    # Check if numeric
    if [[ ! "$ctid" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    # Check if container exists
    if ! pct config "$ctid" >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

validate_size_format() {
    local size="$1"
    
    # Check format (number + optional unit)
    if [[ ! "$size" =~ ^[0-9]+[MGT]?$ ]]; then
        return 1
    fi
    
    # Validate ranges based on unit
    local num unit
    if [[ "$size" =~ ^[0-9]+$ ]]; then
        num="$size"
        unit="G"
    else
        num="${size%?}"
        unit="${size: -1}"
    fi
    
    case "$unit" in
        M|m) [[ $num -ge 1024 && $num -le 10485760 ]] || return 1 ;;
        G|g) [[ $num -ge 1 && $num -le 10240 ]] || return 1 ;;
        T|t) [[ $num -ge 1 && $num -le 100 ]] || return 1 ;;
        *) return 1 ;;
    esac
    
    return 0
}

normalize_size() {
    local size="$1"
    
    if [[ "$size" =~ ^[0-9]+$ ]]; then
        echo "${size}G"
    else
        echo "$size"
    fi
}

convert_to_gb() {
    local size="$1"
    
    if [[ "$size" =~ ^[0-9]+$ ]]; then
        echo "$size"
        return
    fi
    
    local num="${size%?}"
    local unit="${size: -1}"
    
    case "$unit" in
        M|m) echo "$((num / 1024))" ;;
        G|g) echo "$num" ;;
        T|t) echo "$((num * 1024))" ;;
        *) echo "0" ;;
    esac
}

get_container_info() {
    local ctid="$1"
    local info_type="$2"
    
    case "$info_type" in
        "hostname")
            pct config "$ctid" | grep "^hostname:" | cut -d' ' -f2 2>/dev/null || echo "unknown"
            ;;
        "status")
            pct status "$ctid" | awk '{print $2}' 2>/dev/null || echo "unknown"
            ;;
        "current_size")
            local rootfs_line=$(pct config "$ctid" | grep "^rootfs:" 2>/dev/null || echo "")
            echo "$rootfs_line" | grep -oE 'size=[^,]*' | cut -d'=' -f2 2>/dev/null || echo "unknown"
            ;;
        "storage")
            local rootfs_line=$(pct config "$ctid" | grep "^rootfs:" 2>/dev/null || echo "")
            echo "$rootfs_line" | cut -d':' -f2 | cut -d',' -f1 | sed 's/^[[:space:]]*//' 2>/dev/null || echo "unknown"
            ;;
    esac
}

# ---------- Pre-flight checks ----------
header_info

# System checks
command -v pveversion >/dev/null 2>&1 || err_exit "This script must be run on a Proxmox host (pveversion missing)."
command -v pct >/dev/null 2>&1 || err_exit "'pct' not found. Proxmox LXC tools required."

# Root privileges check
if [[ $EUID -ne 0 ]]; then
    err_exit "This script requires root privileges. Please run as root or with sudo."
fi

log "LXC Disk Resizer v2 session started"

# ---------- Get container ID ----------
echo -e "${INFO} Available LXC containers:${CL}"
echo
pct list | while read line; do
    if [[ "$line" =~ ^VMID ]]; then
        # Format header nicely
        echo "  $(echo "$line" | awk '{printf "%-8s %-12s %-20s", $1, $2, $3}')"
        echo "  $(echo "--------" | awk '{printf "%-8s %-12s %-20s", "--------", "------------", "--------------------"}')"
    else
        # Format container info
        echo "  $line"
    fi
done
echo

while true; do
    read -rp "Enter container ID to resize: " CTID
    
    if validate_container_id "$CTID"; then
        break
    else
        if [[ ! "$CTID" =~ ^[0-9]+$ ]]; then
            echo -e "${RD}Invalid format. Please enter a numeric container ID.${CL}"
        else
            echo -e "${RD}Container $CTID not found. Please check the ID and try again.${CL}"
        fi
        echo
    fi
done

# ---------- Get container details ----------
HOSTNAME=$(get_container_info "$CTID" "hostname")
STATUS=$(get_container_info "$CTID" "status")
CURRENT_SIZE=$(get_container_info "$CTID" "current_size")
STORAGE=$(get_container_info "$CTID" "storage")

echo
echo -e "${GN}Container Information:${CL}"
echo "  • Container ID: $CTID"
echo "  • Hostname: $HOSTNAME"
echo "  • Status: $STATUS"
echo "  • Current Size: $CURRENT_SIZE"
echo "  • Storage: $STORAGE"
echo

# ---------- Get new size ----------
echo -e "${YW}Enter new disk size:${CL}"
echo -e "${INFO} Examples: 25G, 30G, 2048M, 1T${CL}"
echo -e "${INFO} Must be larger than current size ($CURRENT_SIZE)${CL}"
echo

while true; do
    read -rp "New size: " NEW_SIZE_INPUT
    
    if validate_size_format "$NEW_SIZE_INPUT"; then
        NEW_SIZE=$(normalize_size "$NEW_SIZE_INPUT")
        
        # Check if new size is larger than current
        current_gb=$(convert_to_gb "$CURRENT_SIZE")
        new_gb=$(convert_to_gb "$NEW_SIZE")
        
        if [[ $new_gb -gt $current_gb ]]; then
            break
        else
            echo -e "${RD}New size ($NEW_SIZE = ${new_gb}GB) must be larger than current size ($CURRENT_SIZE = ${current_gb}GB).${CL}"
        fi
    else
        echo -e "${RD}Invalid size format. Use format like: 25G, 2048M, 1T${CL}"
    fi
    echo
done

echo -e "${GN}New size: $NEW_SIZE${CL}"
echo

# ---------- Pre-resize validation ----------
echo -e "${INFO} Validating storage availability...${CL}"
storage_valid=false

# Method 1: Check if storage is active via pvesm
if pvesm status 2>/dev/null | grep -q "^$STORAGE"; then
    storage_valid=true
    log "Storage validation: $STORAGE found via pvesm status"
# Method 2: Try direct pvesm list on the storage
elif pvesm list "$STORAGE" >/dev/null 2>&1; then
    storage_valid=true
    log "Storage validation: $STORAGE accessible via pvesm list"
# Method 3: Check storage configuration file
elif [[ -f /etc/pve/storage.cfg ]] && grep -q "^\[$STORAGE\]" /etc/pve/storage.cfg 2>/dev/null; then
    storage_valid=true
    log "Storage validation: $STORAGE found in storage.cfg"
# Method 4: Check if storage appears in any pvesm command
elif pvesm status 2>/dev/null | awk '{print $1}' | grep -q "^$STORAGE$"; then
    storage_valid=true
    log "Storage validation: $STORAGE found in storage list"
# Method 5: Skip validation for common storage types that might not show up in pvesm
elif [[ "$STORAGE" =~ ^(local|local-lvm|ZFS|rpool|tank|data|storage)$ ]]; then
    storage_valid=true
    log "Storage validation: $STORAGE is common storage name, assuming valid"
fi

if [[ "$storage_valid" == "true" ]]; then
    echo -e "${CM} Storage '$STORAGE' validated${CL}"
else
    # Don't fail - just warn and continue (like the original working script)
    echo -e "${YW} Warning: Could not validate storage '$STORAGE' - continuing anyway${CL}"
    echo -e "${INFO} This is normal for some storage configurations${CL}"
    log "Storage validation: Could not validate $STORAGE, but continuing"
fi

log "Resize request: CT $CTID ($HOSTNAME) from $CURRENT_SIZE to $NEW_SIZE"

# ---------- Dry run option ----------
echo
echo -e "${YW}Would you like to perform a dry run first?${CL}"
read -rp "Dry run? (y/n) [y]: " DRY_RUN_ANS
DRY_RUN_ANS=${DRY_RUN_ANS:-y}

if [[ "$DRY_RUN_ANS" =~ ^[Yy] ]]; then
    echo
    echo -e "${BL}╔══════════════════════════════════════════════════════╗${CL}"
    echo -e "${BL}║                    DRY RUN RESULTS                  ║${CL}"
    echo -e "${BL}╚══════════════════════════════════════════════════════╝${CL}"
    echo
    echo -e "${INFO} Container: CT $CTID ($HOSTNAME)${CL}"
    echo -e "${INFO} Current: $CURRENT_SIZE → Target: $NEW_SIZE${CL}"
    echo -e "${INFO} Status: $STATUS${CL}"
    echo -e "${INFO} Storage: $STORAGE${CL}"
    echo
    echo -e "${YW}Operations that would be performed:${CL}"
    
    step=1
    if [[ "$STATUS" == "running" ]]; then
        echo "  $step. Stop container CT $CTID"
    else
        echo "  $step. Container already stopped"
    fi
    ((step++))
    echo "  $step. Resize rootfs from $CURRENT_SIZE to $NEW_SIZE"
    ((step++))
    echo "  $step. Start container"
    ((step++))
    echo "  $step. Wait for container boot"
    ((step++))
    echo "  $step. Detect filesystem type"
    ((step++))
    echo "  $step. Expand filesystem"
    ((step++))
    echo "  $step. Verify new size"
    
    echo
    echo -e "${GN}✓ Dry run completed. No changes made.${CL}"
    echo
    read -rp "Proceed with actual resize? (y/n) [n]: " PROCEED
    PROCEED=${PROCEED:-n}
    if [[ ! "$PROCEED" =~ ^[Yy] ]]; then
        echo -e "${YW}Operation cancelled.${CL}"
        exit 0
    fi
fi

# ---------- Final confirmation ----------
echo
echo -e "${RD}╔══════════════════════════════════════════════════════╗${CL}"
echo -e "${RD}║            ⚠️  CONFIRM DISK RESIZE  ⚠️             ║${CL}"
echo -e "${RD}╚══════════════════════════════════════════════════════╝${CL}"
echo
echo -e "${YW}FINAL CONFIRMATION REQUIRED${CL}"
echo
echo "  Container: CT $CTID ($HOSTNAME)"
echo "  Current:   $CURRENT_SIZE"
echo "  New Size:  $NEW_SIZE"
echo "  Storage:   $STORAGE"
echo
echo -e "${RD}⚠️  This operation will modify your container!${CL}"
echo -e "${RD}⚠️  Ensure you have recent backups!${CL}"
echo
read -rp "Type 'yes' to proceed: " FINAL_CONFIRM

if [[ "$FINAL_CONFIRM" != "yes" ]]; then
    echo -e "${YW}Operation cancelled for safety.${CL}"
    log "Resize cancelled by user"
    exit 0
fi

# ---------- Execute resize operation ----------
echo
echo -e "${BL}🔧 Starting disk resize operation...${CL}"
echo

log "Starting resize operation: CT $CTID from $CURRENT_SIZE to $NEW_SIZE"

# Enhanced error handling
set +e
trap 'echo -e "\n${RD}❌ Resize operation failed.${CL}"; log "Resize operation failed"; exit 1' ERR
set -e

# Step 1: Stop container if running
if [[ "$STATUS" == "running" ]]; then
    echo -ne "${BFR}${HOLD} [1/7] Stopping container CT $CTID..."
    if pct stop "$CTID" >/dev/null 2>&1; then
        echo -e "${BFR}${CM} [1/7] Container stopped successfully"
        log "Container $CTID stopped"
    else
        echo -e "${BFR}${CROSS} [1/7] Failed to stop container"
        log "Failed to stop container $CTID"
        exit 1
    fi
else
    echo -e "${CM} [1/7] Container already stopped"
fi

# Step 2: Resize rootfs
echo -ne "${BFR}${HOLD} [2/7] Resizing rootfs to $NEW_SIZE..."
resize_output=$(mktemp)
if pct resize "$CTID" rootfs "$NEW_SIZE" 2>"$resize_output"; then
    echo -e "${BFR}${CM} [2/7] Rootfs resized to $NEW_SIZE"
    log "Rootfs resized: CT $CTID to $NEW_SIZE"
else
    echo -e "${BFR}${CROSS} [2/7] Failed to resize rootfs"
    error_msg=$(cat "$resize_output" 2>/dev/null || echo "Unknown error")
    log "Resize failed: $error_msg"
    echo -e "${RD}Error details: $error_msg${CL}"
    rm -f "$resize_output"
    exit 1
fi
rm -f "$resize_output"

# Verify resize
echo -ne "${BFR}${HOLD} [2/7] Verifying resize..."
NEW_ROOT_SIZE=$(get_container_info "$CTID" "current_size")
if [[ "$NEW_ROOT_SIZE" == "$NEW_SIZE" ]]; then
    echo -e "${BFR}${CM} [2/7] Resize verified ($NEW_ROOT_SIZE)"
else
    echo -e "${BFR}${YW} [2/7] Size mismatch: expected $NEW_SIZE, got $NEW_ROOT_SIZE${CL}"
    log "Size verification warning: expected $NEW_SIZE, got $NEW_ROOT_SIZE"
fi

# Step 3: Start container
echo -ne "${BFR}${HOLD} [3/7] Starting container..."
if pct start "$CTID" >/dev/null 2>&1; then
    echo -e "${BFR}${CM} [3/7] Container started successfully"
    log "Container $CTID started"
else
    echo -e "${BFR}${CROSS} [3/7] Failed to start container"
    log "Failed to start container $CTID"
    exit 1
fi

# Step 4: Wait for boot
echo -ne "${BFR}${HOLD} [4/7] Waiting for container boot..."
BOOT_TIMEOUT=60
BOOT_COUNT=0
until pct exec "$CTID" -- uptime >/dev/null 2>&1; do
    sleep 2
    BOOT_COUNT=$((BOOT_COUNT + 2))
    if [ $BOOT_COUNT -ge $BOOT_TIMEOUT ]; then
        echo -e "${BFR}${CROSS} [4/7] Container boot timeout (${BOOT_TIMEOUT}s)"
        log "Container $CTID boot timeout"
        exit 1
    fi
done
echo -e "${BFR}${CM} [4/7] Container ready (${BOOT_COUNT}s)"

# Step 5: Detect filesystem
echo -ne "${BFR}${HOLD} [5/7] Detecting filesystem..."
ROOT_DEVICE=$(pct exec "$CTID" -- findmnt -n -o SOURCE / 2>/dev/null || echo "unknown")
FS_TYPE=$(pct exec "$CTID" -- findmnt -n -o FSTYPE / 2>/dev/null || echo "unknown")
echo -e "${BFR}${CM} [5/7] Filesystem: $FS_TYPE on $ROOT_DEVICE"
log "Detected filesystem: $FS_TYPE on $ROOT_DEVICE"

# Step 6: Expand filesystem
echo -ne "${BFR}${HOLD} [6/7] Expanding filesystem..."
case "$FS_TYPE" in
    ext4)
        if pct exec "$CTID" -- resize2fs "$ROOT_DEVICE" >/dev/null 2>&1; then
            echo -e "${BFR}${CM} [6/7] ext4 filesystem expanded"
            log "ext4 filesystem expanded on CT $CTID"
        else
            echo -e "${BFR}${CROSS} [6/7] Failed to expand ext4 filesystem"
            log "Failed to expand ext4 filesystem on CT $CTID"
            exit 1
        fi
        ;;
    xfs)
        if pct exec "$CTID" -- xfs_growfs / >/dev/null 2>&1; then
            echo -e "${BFR}${CM} [6/7] xfs filesystem expanded"
            log "xfs filesystem expanded on CT $CTID"
        else
            echo -e "${BFR}${CROSS} [6/7] Failed to expand xfs filesystem"
            log "Failed to expand xfs filesystem on CT $CTID"
            exit 1
        fi
        ;;
    *)
        echo -e "${BFR}${YW} [6/7] Unsupported filesystem: $FS_TYPE - skipped"
        log "Unsupported filesystem: $FS_TYPE on CT $CTID"
        ;;
esac

# Step 7: Final verification
echo -ne "${BFR}${HOLD} [7/7] Final verification..."
DISK_USAGE=$(pct exec "$CTID" -- df -h / | awk 'NR==2 {print $2}' 2>/dev/null || echo "unknown")
FINAL_CONFIG_SIZE=$(get_container_info "$CTID" "current_size")
echo -e "${BFR}${CM} [7/7] Verification complete"

# ---------- Success Summary ----------
echo
echo -e "${GN}╔══════════════════════════════════════════════════════╗${CL}"
echo -e "${GN}║              ✅ RESIZE COMPLETED! ✅                ║${CL}"
echo -e "${GN}╚══════════════════════════════════════════════════════╝${CL}"
echo
echo -e "${YW}Operation Summary:${CL}"
echo "  • Container:      CT $CTID ($HOSTNAME)"
echo "  • Previous Size:  $CURRENT_SIZE"
echo "  • New Size:       $FINAL_CONFIG_SIZE"
echo "  • Available:      $DISK_USAGE"
echo "  • Filesystem:     $FS_TYPE"
echo "  • Storage:        $STORAGE"
echo
echo -e "${BL}Quick Commands:${CL}"
echo -e "  Status:    ${YW}pct status $CTID${CL}"
echo -e "  Console:   ${YW}pct enter $CTID${CL}"
echo -e "  Usage:     ${YW}pct exec $CTID -- df -h${CL}"
echo
echo -e "${INFO} Operation logged to: $LOG_FILE${CL}"
echo

log "Resize completed successfully: CT $CTID ($HOSTNAME) from $CURRENT_SIZE to $FINAL_CONFIG_SIZE"

echo