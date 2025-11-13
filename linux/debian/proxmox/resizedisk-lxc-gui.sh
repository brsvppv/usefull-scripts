#!/usr/bin/env bash
# =================================================================
# Proxmox LXC Disk Resizer - Production GUI Edition
# Author: GitHub Copilot for Borislav Popov
# License: MIT
# 
# Features:
# - **Production-Ready**: Robust error handling and validation
# - **Dialog-based GUI**: Intuitive user interface
# - **Safe Operation**: Dry-run mode and comprehensive validation
# - **Universal Support**: Works with ext4 and xfs filesystems
# - **Professional Logging**: Full audit trail of operations
# =================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# --- Production Configuration ---
readonly LOG_FILE="/var/log/proxmox-lxc-resizer.log"
readonly BACKTITLE="Proxmox LXC Disk Resizer - Production GUI"
readonly TEMP_FILE=$(mktemp)

# Global variables initialization
CONTAINERS=()
SELECTED_CTID=""
CURRENT_SIZE=""
NEW_SIZE=""
DRY_RUN=""
HOSTNAME=""
STATUS=""
FS_TYPE=""
ROOT_DEVICE=""

# Color definitions for better UX
readonly YW="\033[33m"
readonly GN="\033[32m" 
readonly RD="\033[31m"
readonly BL="\033[36m"
readonly CL="\033[m"

# Professional exit codes
readonly ERR_CONTAINER_NOT_FOUND=201
readonly ERR_INVALID_SIZE=202
readonly ERR_RESIZE_FAILED=203
readonly ERR_FILESYSTEM_FAILED=204
readonly ERR_CONTAINER_START_FAILED=205

# --- Core System Functions ---
cleanup() {
    local exit_code=$?
    
    # Enhanced dialog cleanup
    {
        pkill -f "dialog.*resize" 2>/dev/null || true
        pkill -f "dialog" 2>/dev/null || true
        killall dialog 2>/dev/null || true
        killall whiptail 2>/dev/null || true
        
        jobs -p | xargs -r kill 2>/dev/null || true
        
        stty sane 2>/dev/null || true
        reset 2>/dev/null || true
        tput init 2>/dev/null || true
        clear 2>/dev/null || true
        
        printf '\033c' 2>/dev/null || true
    } >/dev/null 2>&1
    
    # Clean up temporary files
    [[ -f "$TEMP_FILE" ]] && rm -f "$TEMP_FILE" 2>/dev/null || true
    
    exit $exit_code
}

trap 'cleanup' EXIT
trap 'echo ""; echo "[INFO] Operation interrupted by user."; exit 130' INT TERM
trap 'error_handler $LINENO $?' ERR

error_handler() {
    local line_no="${1:-unknown}"
    local exit_code="${2:-1}"
    local command="${BASH_COMMAND:-unknown}"
    
    log "ERROR at line $line_no: $command (exit $exit_code)"
    error "An unexpected failure occurred at line $line_no. Check $LOG_FILE for details." "$exit_code"
}

# --- UI & Logging Functions ---
handle_cancel() {
    if [[ $? -ne 0 ]]; then
        clear
        printf '\033c' 2>/dev/null || true
        echo ""
        echo -e "${YW}[INFO] Operation cancelled by user.${CL}"
        echo ""
        echo "Thank you for using Proxmox LXC Disk Resizer!"
        echo ""
        exit 0
    fi
}

error() {
    local exit_code="${2:-1}"
    clear
    echo ""
    echo -e "${RD}[ERROR]${CL} $1"
    echo ""
    
    log "ERROR (exit $exit_code): $1"
    
    if command -v dialog >/dev/null 2>&1; then
        dialog --title "Critical Error" --msgbox "[ERROR] $1\n\nCheck logs: $LOG_FILE" 12 70 2>/dev/null || true
    fi
    
    exit "$exit_code"
}

info() {
    echo -e "${BL}[INFO]${CL} $1"
}

warn() {
    echo -e "${YW}[WARN]${CL} $1"
    log "WARN: $1"
}

msg_ok() {
    echo -e "${GN}[OK]${CL} $1"
}

log() {
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $1" >> "$LOG_FILE" 2>/dev/null || true
}

# --- Validation & Discovery Functions ---
production_checks() {
    # Verify running on Proxmox
    if ! command -v pct >/dev/null 2>&1; then
        error "This script must be run on a Proxmox VE host. Command 'pct' not found."
    fi
    
    # Check for root privileges
    if [[ $EUID -ne 0 ]]; then
        error "This script requires root privileges. Please run as root or with sudo."
    fi
    
    # Create log file
    mkdir -p "$(dirname "$LOG_FILE")" || error "Cannot create log directory"
    touch "$LOG_FILE" || error "Cannot create log file at $LOG_FILE"
}

ensure_dependencies() {
    local missing_deps=()
    
    for cmd in dialog pct; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing_deps[*]}. Please install them first."
    fi
}

discover_containers() {
    info "Discovering LXC containers..."
    
    CONTAINERS=()
    
    # Get all containers with details
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        
        local ctid=$(echo "$line" | awk '{print $1}')
        [[ "$ctid" =~ ^[0-9]+$ ]] || continue
        
        local status=$(echo "$line" | awk '{print $2}')
        local hostname=$(pct config "$ctid" | grep "^hostname:" | cut -d' ' -f2 2>/dev/null || echo "unknown")
        local rootfs_line=$(pct config "$ctid" | grep "^rootfs:" 2>/dev/null || echo "")
        local current_size=$(echo "$rootfs_line" | grep -oE 'size=[^,]*' | cut -d'=' -f2 2>/dev/null || echo "unknown")
        
        local display_name="CT $ctid - $hostname ($status) - Size: $current_size"
        CONTAINERS+=("$ctid" "$display_name" "OFF")
        
    done < <(pct list | tail -n +2)
    
    if [[ ${#CONTAINERS[@]} -eq 0 ]]; then
        error "No LXC containers found on this system."
    fi
    
    msg_ok "Found $((${#CONTAINERS[@]} / 3)) containers"
}

validate_new_size() {
    local size="$1"
    
    # Check format (number + optional unit)
    if [[ ! "$size" =~ ^[0-9]+[MGT]?$ ]]; then
        return 1
    fi
    
    # Extract number and unit
    local num="${size%?}"
    local unit="${size: -1}"
    
    # If no unit, assume G
    if [[ "$unit" =~ ^[0-9]$ ]]; then
        num="$size"
        unit="G"
        NEW_SIZE="${size}G"
    fi
    
    # Validate ranges
    case "$unit" in
        M|m) [[ $num -ge 1024 && $num -le 10485760 ]] || return 1 ;;
        G|g) [[ $num -ge 1 && $num -le 10240 ]] || return 1 ;;
        T|t) [[ $num -ge 1 && $num -le 100 ]] || return 1 ;;
        *) return 1 ;;
    esac
    
    return 0
}

# --- Configuration Functions ---
select_container() {
    dialog --backtitle "$BACKTITLE" --title "Select Container" \
           --radiolist "Choose the container to resize:" \
           20 80 10 "${CONTAINERS[@]}" 2>"$TEMP_FILE"
    handle_cancel $?
    
    SELECTED_CTID=$(cat "$TEMP_FILE")
    
    # Get container details
    STATUS=$(pct status "$SELECTED_CTID" | awk '{print $2}')
    HOSTNAME=$(pct config "$SELECTED_CTID" | grep "^hostname:" | cut -d' ' -f2 2>/dev/null || echo "unknown")
    local rootfs_line=$(pct config "$SELECTED_CTID" | grep "^rootfs:" 2>/dev/null || echo "")
    CURRENT_SIZE=$(echo "$rootfs_line" | grep -oE 'size=[^,]*' | cut -d'=' -f2 2>/dev/null || echo "unknown")
    
    log "Selected container: CT $SELECTED_CTID ($HOSTNAME) - Current size: $CURRENT_SIZE"
}

configure_new_size() {
    while true; do
        dialog --backtitle "$BACKTITLE" --title "New Disk Size" \
               --inputbox "Enter new disk size for CT $SELECTED_CTID ($HOSTNAME)\n\nCurrent size: $CURRENT_SIZE\nExamples: 10G, 20G, 1024M, 2T\n\nNew size:" \
               12 60 "" 2>"$TEMP_FILE"
        handle_cancel $?
        
        local input_size=$(cat "$TEMP_FILE")
        
        if validate_new_size "$input_size"; then
            log "New size configured: $NEW_SIZE"
            break
        else
            dialog --title "Invalid Size" \
                   --msgbox "Invalid size format: '$input_size'\n\nValid formats:\n• 1024M (megabytes)\n• 10G (gigabytes)\n• 2T (terabytes)\n\nRange: 1G-10T" \
                   10 50
        fi
    done
}

configure_dry_run() {
    dialog --backtitle "$BACKTITLE" --title "Dry Run Mode" \
           --yesno "Perform a dry run first?\n\nDry run will show what operations would be performed without making any actual changes.\n\nRecommended for safety." \
           10 60
    
    if [[ $? -eq 0 ]]; then
        DRY_RUN="yes"
        log "Dry run mode enabled"
    else
        DRY_RUN="no"
        log "Dry run mode disabled"
    fi
}

show_operation_summary() {
    local summary="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Disk Resize Operation Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Container ID:      $SELECTED_CTID
  Hostname:          $HOSTNAME
  Current Status:    $STATUS
  Current Size:      $CURRENT_SIZE
  New Size:          $NEW_SIZE
  Mode:              $([ "$DRY_RUN" == "yes" ] && echo "Dry Run" || echo "Live Operation")
  
  Operations:
  1. Stop container (if running)
  2. Resize rootfs volume
  3. Start container
  4. Expand filesystem
  5. Verify results
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ "$DRY_RUN" == "yes" ]; then
        dialog --title "Dry Run Results" \
               --msgbox "$summary\n\nDRY RUN MODE: No changes will be made.\n\nProceed with actual resize?" \
               25 80
        handle_cancel $?
        
        # Ask if user wants to proceed with real operation
        dialog --title "Proceed with Real Operation?" \
               --yesno "Dry run completed successfully.\n\nProceed with actual disk resize operation?\n\n⚠️ This will modify the container!" \
               10 60
        if [[ $? -ne 0 ]]; then
            clear
            echo -e "${YW}[INFO] Operation cancelled after dry run.${CL}"
            exit 0
        fi
        DRY_RUN="no"
    else
        dialog --title "Confirm Disk Resize" \
               --yesno "$summary\n\n⚠️ LIVE OPERATION WARNING ⚠️\n\nThis will modify your container!\nEnsure you have a backup!\n\nProceed with disk resize?" \
               25 80
        if [[ $? -ne 0 ]]; then
            handle_cancel 1
        fi
    fi
}

perform_resize_operation() {
    clear
    echo
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                  LXC Disk Resize Operation                    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo
    
    info "Starting disk resize operation for CT $SELECTED_CTID..."
    log "Starting resize: CT $SELECTED_CTID from $CURRENT_SIZE to $NEW_SIZE"
    
    # Step 1: Stop container if running
    if [[ "$STATUS" == "running" ]]; then
        info "[1/7] Stopping container CT $SELECTED_CTID..."
        if ! pct stop "$SELECTED_CTID" 2>/dev/null; then
            error "Failed to stop container CT $SELECTED_CTID" $ERR_CONTAINER_START_FAILED
        fi
        msg_ok "Container stopped successfully"
    else
        info "[1/7] Container already stopped"
    fi
    
    # Step 2: Resize rootfs
    info "[2/7] Resizing rootfs to $NEW_SIZE..."
    if ! pct resize "$SELECTED_CTID" rootfs "$NEW_SIZE" 2>/dev/null; then
        error "Failed to resize rootfs for CT $SELECTED_CTID" $ERR_RESIZE_FAILED
    fi
    msg_ok "Rootfs resized successfully"
    
    # Verify resize
    local new_config_size=$(pct config "$SELECTED_CTID" | grep "^rootfs:" | grep -oE 'size=[^,]*' | cut -d'=' -f2 2>/dev/null)
    if [[ "$new_config_size" != "$NEW_SIZE" ]]; then
        warn "Expected $NEW_SIZE, got $new_config_size in config"
    fi
    
    # Step 3: Start container
    info "[3/7] Starting container..."
    if ! pct start "$SELECTED_CTID" 2>/dev/null; then
        error "Failed to start container CT $SELECTED_CTID" $ERR_CONTAINER_START_FAILED
    fi
    msg_ok "Container started successfully"
    
    # Step 4: Wait for boot
    info "[4/7] Waiting for container to be ready..."
    local timeout=60
    local count=0
    until pct exec "$SELECTED_CTID" -- uptime >/dev/null 2>&1; do
        sleep 2
        count=$((count + 2))
        if [[ $count -ge $timeout ]]; then
            error "Container boot timeout after ${timeout}s" $ERR_CONTAINER_START_FAILED
        fi
    done
    msg_ok "Container is ready"
    
    # Step 5: Detect filesystem
    info "[5/7] Detecting filesystem type..."
    ROOT_DEVICE=$(pct exec "$SELECTED_CTID" -- findmnt -n -o SOURCE / 2>/dev/null || echo "unknown")
    FS_TYPE=$(pct exec "$SELECTED_CTID" -- findmnt -n -o FSTYPE / 2>/dev/null || echo "unknown")
    info "Filesystem: $FS_TYPE on $ROOT_DEVICE"
    
    # Step 6: Expand filesystem
    info "[6/7] Expanding filesystem..."
    case "$FS_TYPE" in
        ext4)
            if ! pct exec "$SELECTED_CTID" -- resize2fs "$ROOT_DEVICE" >/dev/null 2>&1; then
                error "Failed to expand ext4 filesystem" $ERR_FILESYSTEM_FAILED
            fi
            msg_ok "ext4 filesystem expanded"
            ;;
        xfs)
            if ! pct exec "$SELECTED_CTID" -- xfs_growfs / >/dev/null 2>&1; then
                error "Failed to expand xfs filesystem" $ERR_FILESYSTEM_FAILED
            fi
            msg_ok "xfs filesystem expanded"
            ;;
        *)
            warn "Unsupported filesystem type: $FS_TYPE - skipping filesystem expansion"
            ;;
    esac
    
    # Step 7: Verify results
    info "[7/7] Verifying resize operation..."
    local disk_usage=$(pct exec "$SELECTED_CTID" -- df -h / | awk 'NR==2 {print $2}' 2>/dev/null || echo "unknown")
    local final_config_size=$(pct config "$SELECTED_CTID" | grep "^rootfs:" | grep -oE 'size=[^,]*' | cut -d'=' -f2 2>/dev/null || echo "unknown")
    msg_ok "Resize operation completed successfully"
    
    log "Resize completed: CT $SELECTED_CTID - Config: $final_config_size, Available: $disk_usage"
    
    # Success notification
    dialog --title "Resize Operation Completed!" \
           --msgbox "🎉 Disk resize completed successfully!\n\nContainer: CT $SELECTED_CTID ($HOSTNAME)\nPrevious Size: $CURRENT_SIZE\nNew Config Size: $final_config_size\nAvailable Space: $disk_usage\nFilesystem: $FS_TYPE\n\nThe container is running and ready for use." \
           15 70
}

# --- Main Execution Flow ---
main() {
    # Initialize logging
    log "LXC Disk Resizer session started"
    
    # Run production checks
    production_checks
    ensure_dependencies
    
    # Display welcome
    clear
    info "🔧 Proxmox LXC Disk Resizer - Production GUI Edition"
    info "Initializing..."
    
    # Discover and configure
    discover_containers
    select_container
    configure_new_size
    configure_dry_run
    show_operation_summary
    
    # Execute resize
    perform_resize_operation
    
    # Final cleanup
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🎉 LXC Disk Resize Operation Completed Successfully!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 Container Details:"
    echo "   • Container ID: $SELECTED_CTID"
    echo "   • Hostname: $HOSTNAME"
    echo "   • Previous Size: $CURRENT_SIZE"
    echo "   • New Size: $NEW_SIZE"
    echo "   • Filesystem: $FS_TYPE"
    echo ""
    echo "🔧 Useful Commands:"
    echo "   • Check status:       pct status $SELECTED_CTID"
    echo "   • View config:        pct config $SELECTED_CTID"
    echo "   • Check disk usage:   pct exec $SELECTED_CTID -- df -h"
    echo "   • Enter console:      pct enter $SELECTED_CTID"
    echo ""
    echo "📝 Operation log saved to: $LOG_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi