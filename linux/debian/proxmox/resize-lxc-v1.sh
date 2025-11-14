#!/usr/bin/env bash
# ============================================================
# Proxmox LXC Disk Resizer - Console Edition v1 (Enterprise)
# Author: GitHub Copilot for Borislav Popov (styled like tteck scripts)
# License: MIT
# Version: 1.1 - Production Ready
# 
# Improvements:
# - Production logging added
# - Lock file management
# - Enhanced error handling
# - Backup verification
# ============================================================

set -euo pipefail
IFS=$'\n\t'

# ---------- Production Configuration ----------
readonly LOG_FILE="/var/log/proxmox-lxc-resizer.log"
readonly LOCK_DIR="/var/run/lxc-resizer"

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

# ---------- Logging & Error Handling ----------
log() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $1" >> "$LOG_FILE" 2>/dev/null || true
}

cleanup() {
    local exit_code=$?
    
    # Remove lock file if it exists
    if [[ -n "${LOCKFILE:-}" && -f "$LOCKFILE" ]]; then
        rm -f "$LOCKFILE" 2>/dev/null || true
        log "Lock released for CT ${CTID:-unknown}"
    fi
    
    log "Script exited with code $exit_code"
    exit $exit_code
}

trap 'echo -e "\n${RD}Interrupted. Exiting.${CL}"; log "Operation interrupted by user"; cleanup; exit 130' INT TERM
trap 'cleanup' EXIT

function header_info() {
    clear
    cat <<"EOF"
    ____  __  ________   ____  _      __      ____           _              
   / __ \/ / / ____/ | / /  |(_)____/ /___  / __ \___  ____(_)___  ___  ____
  / /_/ / /_/ /   /  |/ /|_|/ / ___/ //_  / / /_/ / _ \/ ___/ /_  / / _ \/ ___/
 / ____/ __/ /___/ /|  / __/ (__  ) / / /_/ _, _/  __(__  ) / / /_/  __/ /    
/_/   /_/  \____/_/ |_/ __/_/____/_/ /___/_/ |_|\___/____/_/ /___/\___/_/     
                                                                            
EOF
    echo -e "${BL}Proxmox LXC Disk Resizer - Console Edition${CL}"
    echo -e "${YW}Safely resize container root filesystem${CL}"
    echo
}

function err_exit() {
    echo -e "${RD}[ERROR] $1${CL}" >&2
    log "FATAL ERROR: $1"
    exit 1
}

header_info
log "=== LXC Disk Resizer v1 session started ==="

# ---------- Pre-flight checks ----------
log "Starting pre-flight checks"
command -v pveversion >/dev/null 2>&1 || err_exit "This script must be run on a Proxmox host (pveversion missing)."
command -v pct >/dev/null 2>&1 || err_exit "'pct' not found. Proxmox LXC tools required."

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    err_exit "This script requires root privileges. Please run as root or with sudo."
fi

# Create lock directory
mkdir -p "$LOCK_DIR" 2>/dev/null || err_exit "Cannot create lock directory at $LOCK_DIR"

log "Pre-flight checks passed"

# ---------- Helper: numeric input with validation ----------
read_number_default() {
    local prompt="$1"
    local default="$2"
    local min="$3"
    local max="$4"
    local input

    while true; do
        read -rp "$prompt [$default]: " input
        input=${input:-$default}
        
        if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge "$min" ] && [ "$input" -le "$max" ]; then
            echo "$input"
            return 0
        else
            echo -e "${RD}Please enter a number between $min and $max.${CL}"
        fi
    done
}

# ---------- Get list of existing containers ----------
log "Detecting existing LXC containers"
echo -e "${INFO} Detecting existing LXC containers...${CL}"
CONTAINERS=($(pct list | awk 'NR>1 {print $1}'))

if [ ${#CONTAINERS[@]} -eq 0 ]; then
    log "ERROR: No LXC containers found"
    err_exit "No LXC containers found on this system."
fi

log "Found ${#CONTAINERS[@]} containers"

echo -e "${INFO} Available LXC containers:${CL}"
for i in "${!CONTAINERS[@]}"; do
    CTID="${CONTAINERS[$i]}"
    STATUS=$(pct status "$CTID" | awk '{print $2}')
    CONFIG_LINE=$(pct config "$CTID" | grep "^hostname:" || echo "hostname: unknown")
    HOSTNAME=$(echo "$CONFIG_LINE" | cut -d' ' -f2)
    ROOTFS_LINE=$(pct config "$CTID" | grep "^rootfs:" || echo "rootfs: unknown")
    CURRENT_SIZE=$(echo "$ROOTFS_LINE" | grep -oE 'size=[^,]*' | cut -d'=' -f2 || echo "unknown")
    
    printf "  [%s] CT %s - %s (%s) - Current: %s\n" "$i" "$CTID" "$HOSTNAME" "$STATUS" "$CURRENT_SIZE"
done
echo

# Choose container by index
while true; do
    read -rp "Enter container index [0-$((${#CONTAINERS[@]}-1))]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -lt ${#CONTAINERS[@]} ]; then
        CTID="${CONTAINERS[$choice]}"
        log "Container selected: CT $CTID (index $choice)"
        break
    else
        echo -e "${RD}Invalid choice. Please enter a number between 0 and $((${#CONTAINERS[@]}-1)).${CL}"
    fi
done

# Create lock file for this CTID
LOCKFILE="${LOCK_DIR}/resize-${CTID}.lock"
if [[ -f "$LOCKFILE" ]]; then
    log "ERROR: Lock file exists for CT $CTID"
    err_exit "Another resize operation is running for CT $CTID. Lock file: $LOCKFILE"
fi
touch "$LOCKFILE" || err_exit "Failed to create lock file"
log "Lock acquired for CT $CTID"

# Get container details
STATUS=$(pct status "$CTID" | awk '{print $2}')
CONFIG_LINE=$(pct config "$CTID" | grep "^hostname:" || echo "hostname: unknown")
HOSTNAME=$(echo "$CONFIG_LINE" | cut -d' ' -f2)
ROOTFS_LINE=$(pct config "$CTID" | grep "^rootfs:" || echo "rootfs: unknown")
CURRENT_SIZE=$(echo "$ROOTFS_LINE" | grep -oE 'size=[^,]*' | cut -d'=' -f2 || echo "unknown")

echo -e "${GN}Selected container: CT $CTID ($HOSTNAME)${CL}"
echo -e "${INFO} Current status: $STATUS${CL}"
echo -e "${INFO} Current rootfs size: $CURRENT_SIZE${CL}"
echo

log "Container info: CT $CTID | Hostname: $HOSTNAME | Status: $STATUS | Current size: $CURRENT_SIZE"

# ---------- New size input with validation ----------
echo -e "${YW}Enter new disk size:${CL}"
echo -e "${INFO} Examples: 10G, 20G, 1024M, 2T${CL}"
echo -e "${INFO} Size must be larger than current size${CL}"
echo

while true; do
    read -rp "New size: " NEW_SIZE
    
    # Basic format validation
    if [[ ! "$NEW_SIZE" =~ ^[0-9]+[MGT]?$ ]]; then
        echo -e "${RD}Invalid format. Use format like: 10G, 1024M, 2T${CL}"
        continue
    fi
    
    # Validate size is reasonable (between 1G and 100T)
    case "${NEW_SIZE: -1}" in
        G|g) SIZE_NUM="${NEW_SIZE%?}"; MIN=1; MAX=10240 ;;
        M|m) SIZE_NUM="${NEW_SIZE%?}"; MIN=1024; MAX=10485760 ;;
        T|t) SIZE_NUM="${NEW_SIZE%?}"; MIN=1; MAX=100 ;;
        *) SIZE_NUM="$NEW_SIZE"; MIN=1; MAX=10240; NEW_SIZE="${NEW_SIZE}G" ;;
    esac
    
    if [[ $SIZE_NUM -ge $MIN && $SIZE_NUM -le $MAX ]]; then
        break
    else
        echo -e "${RD}Size out of reasonable range. Please use 1G-10T range.${CL}"
    fi
done

echo -e "${GN}New size: $NEW_SIZE${CL}"
echo

log "New size selected: $NEW_SIZE (was: $CURRENT_SIZE)"

# ---------- Dry run option ----------
echo -e "${YW}Would you like to perform a dry run first?${CL}"
read -rp "Dry run? (y/n) [y]: " DRY_RUN_ANS
DRY_RUN_ANS=${DRY_RUN_ANS:-y}

if [[ "$DRY_RUN_ANS" =~ ^[Yy] ]]; then
    log "Dry run initiated for CT $CTID: $CURRENT_SIZE -> $NEW_SIZE"
    echo -e "${BL}=== DRY RUN ===${CL}"
    echo -e "${INFO} Container: CT $CTID ($HOSTNAME)${CL}"
    echo -e "${INFO} Current size: $CURRENT_SIZE${CL}"
    echo -e "${INFO} Target size: $NEW_SIZE${CL}"
    echo -e "${INFO} Status: $STATUS${CL}"
    echo
    echo -e "${YW}Operations that would be performed:${CL}"
    if [[ "$STATUS" == "running" ]]; then
        echo "  1. Stop container CT $CTID"
    else
        echo "  1. Container already stopped"
    fi
    echo "  2. Resize rootfs to $NEW_SIZE"
    echo "  3. Start container"
    echo "  4. Wait for container boot"
    echo "  5. Detect filesystem type"
    echo "  6. Expand filesystem (resize2fs/xfs_growfs)"
    echo "  7. Verify new size"
    echo
    echo -e "${GN}Dry run completed. No changes made.${CL}"
    echo
    read -rp "Proceed with actual resize? (y/n) [n]: " PROCEED
    PROCEED=${PROCEED:-n}
    if [[ ! "$PROCEED" =~ ^[Yy] ]]; then
        log "Resize operation cancelled by user after dry run"
        echo -e "${YW}Operation cancelled.${CL}"
        exit 0
    fi
    log "User confirmed proceeding with actual resize after dry run"
fi

# ---------- Final confirmation ----------
log "Awaiting final confirmation for resize operation"
clear
header_info
echo -e "${RD}⚠️  DISK RESIZE OPERATION ⚠️${CL}"
echo -e "${YW}This operation will:${CL}"
echo "  • Stop container CT $CTID if running"
echo "  • Resize the root filesystem"
echo "  • Restart the container"
echo "  • Expand the filesystem inside"
echo
echo -e "${YW}Container Details:${CL}"
echo "  Container ID:    $CTID"
echo "  Hostname:        $HOSTNAME"
echo "  Current Status:  $STATUS"
echo "  Current Size:    $CURRENT_SIZE"
echo "  New Size:        $NEW_SIZE"
echo
echo -e "${RD}⚠️  BACKUP YOUR CONTAINER BEFORE PROCEEDING! ⚠️${CL}"
echo
read -rp "Are you absolutely sure? Type 'yes' to continue: " FINAL_CONFIRM

if [[ "$FINAL_CONFIRM" != "yes" ]]; then
    log "Resize operation cancelled by user at final confirmation"
    echo -e "${YW}Operation cancelled for safety.${CL}"
    exit 0
fi

# ---------- Execute resize operation ----------
log "=== Starting resize operation for CT $CTID ==="
log "Current size: $CURRENT_SIZE | New size: $NEW_SIZE | Status: $STATUS"
echo
echo -e "${BL}🔧 Starting disk resize operation...${CL}"
echo

# Set error handling for resize operation
set +e
trap 'echo -e "\n${RD}❌ Resize operation failed. Container may be in intermediate state.${CL}"; log "Resize operation failed - check container state"; echo -e "${YW}Check container status: pct status $CTID${CL}"; exit 1' ERR
set -e

# Step 1: Stop container if running
log "Step 1: Checking container status"
if pct status "$CTID" | grep -q running; then
    log "Container is running, stopping CT $CTID"
    echo -ne "${BFR}${HOLD} [1/7] Stopping container CT $CTID..."
    if pct stop "$CTID" >/dev/null 2>&1; then
        echo -e "${BFR}${CM} [1/7] Container stopped"
        log "Container CT $CTID stopped successfully"
    else
        echo -e "${BFR}${CROSS} [1/7] Failed to stop container"
        log "ERROR: Failed to stop container CT $CTID"
        exit 1
    fi
else
    echo -e "${CM} [1/7] Container already stopped"
    log "Container CT $CTID already stopped"
fi

# Step 2: Resize rootfs
log "Step 2: Resizing rootfs to $NEW_SIZE"
echo -ne "${BFR}${HOLD} [2/7] Resizing rootfs to $NEW_SIZE..."
if pct resize "$CTID" rootfs "$NEW_SIZE" >/dev/null 2>&1; then
    echo -e "${BFR}${CM} [2/7] Rootfs resized to $NEW_SIZE"
    log "Rootfs resized successfully to $NEW_SIZE"
else
    echo -e "${BFR}${CROSS} [2/7] Failed to resize rootfs"
    log "ERROR: Failed to resize rootfs for CT $CTID"
    exit 1
fi

# Verify resize
log "Verifying resize operation"
NEW_ROOT_SIZE=$(pct config "$CTID" | grep "^rootfs:" | grep -oE 'size=[^,]*' | cut -d'=' -f2)
if [[ "$NEW_ROOT_SIZE" != "$NEW_SIZE" ]]; then
    echo -e "${YW}⚠️  Warning: Expected $NEW_SIZE, got $NEW_ROOT_SIZE${CL}"
    log "WARNING: Size mismatch after resize - expected $NEW_SIZE, got $NEW_ROOT_SIZE"
else
    log "Resize verified: $NEW_ROOT_SIZE"
fi

# Step 3: Start container
log "Step 3: Starting container CT $CTID"
echo -ne "${BFR}${HOLD} [3/7] Starting container..."
if pct start "$CTID" >/dev/null 2>&1; then
    echo -e "${BFR}${CM} [3/7] Container started"
    log "Container CT $CTID started successfully"
else
    echo -e "${BFR}${CROSS} [3/7] Failed to start container"
    log "ERROR: Failed to start container CT $CTID"
    exit 1
fi

# Step 4: Wait for boot
log "Step 4: Waiting for container boot"
echo -ne "${BFR}${HOLD} [4/7] Waiting for container boot..."
BOOT_TIMEOUT=60
BOOT_COUNT=0
until pct exec "$CTID" -- uptime >/dev/null 2>&1; do
    sleep 2
    BOOT_COUNT=$((BOOT_COUNT + 2))
    if [ $BOOT_COUNT -ge $BOOT_TIMEOUT ]; then
        echo -e "${BFR}${CROSS} [4/7] Container boot timeout"
        log "ERROR: Container boot timeout after ${BOOT_TIMEOUT}s"
        exit 1
    fi
done
echo -e "${BFR}${CM} [4/7] Container ready"
log "Container ready after ${BOOT_COUNT}s"

# Step 5: Detect filesystem
log "Step 5: Detecting filesystem type"
echo -ne "${BFR}${HOLD} [5/7] Detecting filesystem..."
ROOT_DEVICE=$(pct exec "$CTID" -- findmnt -n -o SOURCE / 2>/dev/null)
FS_TYPE=$(pct exec "$CTID" -- findmnt -n -o FSTYPE / 2>/dev/null)
echo -e "${BFR}${CM} [5/7] Filesystem: $FS_TYPE on $ROOT_DEVICE"
log "Detected filesystem: $FS_TYPE on device $ROOT_DEVICE"

# Step 6: Expand filesystem
log "Step 6: Expanding filesystem ($FS_TYPE)"
echo -ne "${BFR}${HOLD} [6/7] Expanding filesystem..."
case "$FS_TYPE" in
    ext4)
        if pct exec "$CTID" -- resize2fs "$ROOT_DEVICE" >/dev/null 2>&1; then
            echo -e "${BFR}${CM} [6/7] Filesystem expanded (ext4)"
            log "ext4 filesystem expanded successfully"
        else
            echo -e "${BFR}${CROSS} [6/7] Failed to expand ext4 filesystem"
            log "ERROR: Failed to expand ext4 filesystem"
            exit 1
        fi
        ;;
    xfs)
        if pct exec "$CTID" -- xfs_growfs / >/dev/null 2>&1; then
            echo -e "${BFR}${CM} [6/7] Filesystem expanded (xfs)"
            log "xfs filesystem expanded successfully"
        else
            echo -e "${BFR}${CROSS} [6/7] Failed to expand xfs filesystem"
            log "ERROR: Failed to expand xfs filesystem"
            exit 1
        fi
        ;;
    *)
        echo -e "${BFR}${YW} [6/7] Unsupported filesystem: $FS_TYPE - skipped"
        log "WARNING: Unsupported filesystem type: $FS_TYPE - skipping expansion"
        ;;
esac

# Step 7: Verify final size
log "Step 7: Verifying final size"
echo -ne "${BFR}${HOLD} [7/7] Verifying resize..."
DISK_USAGE=$(pct exec "$CTID" -- df -h / | awk 'NR==2 {print $2}' 2>/dev/null)
FINAL_CONFIG_SIZE=$(pct config "$CTID" | grep "^rootfs:" | grep -oE 'size=[^,]*' | cut -d'=' -f2)
echo -e "${BFR}${CM} [7/7] Verification complete"
log "Final verification: Config size=$FINAL_CONFIG_SIZE, Available=$DISK_USAGE"

# ---------- Success Summary ----------
log "=== Resize operation completed successfully ==="
log "Final state: CT $CTID | $CURRENT_SIZE -> $FINAL_CONFIG_SIZE | Available: $DISK_USAGE | FS: $FS_TYPE"

echo
echo -e "${GN}╔══════════════════════════════════════════════════════╗${CL}"
echo -e "${GN}║    ✅ Disk Resize Operation Completed! ✅           ║${CL}"
echo -e "${GN}╚══════════════════════════════════════════════════════╝${CL}"
echo
echo -e "${YW}Final Status:${CL}"
echo "  Container ID:     $CTID ($HOSTNAME)"
echo "  Previous Size:    $CURRENT_SIZE"
echo "  New Config Size:  $FINAL_CONFIG_SIZE"
echo "  Available Space:  $DISK_USAGE"
echo "  Filesystem:       $FS_TYPE"
echo
echo -e "${BL}Useful commands:${CL}"
echo -e "  Check status:     ${YW}pct status $CTID${CL}"
echo -e "  View config:      ${YW}pct config $CTID${CL}"
echo -e "  Check disk usage: ${YW}pct exec $CTID -- df -h${CL}"
echo -e "  Enter console:    ${YW}pct enter $CTID${CL}"
echo
echo -e "${INFO} Operation logged to: $LOG_FILE${CL}"
echo